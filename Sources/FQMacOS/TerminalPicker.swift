import Darwin
import FQCore
import Foundation

@MainActor
protocol ApplicationPicking: AnyObject {
  func choose(
    from applications: [ApplicationCandidate],
    initialQuery: String,
    action: ApplicationExitAction,
    refreshApplications: () -> [ApplicationCandidate]
  ) throws -> ApplicationExitPlan?
}

enum TerminalPickerError: LocalizedError {
  case notATerminal
  case terminalSetupFailed(Int32)
  case signalSetupFailed(Int32)
  case terminalReadFailed(Int32)
  case terminalPasteIncomplete
  case terminalPasteTooLarge

  var errorDescription: String? {
    switch self {
    case .notATerminal:
      "交互选择器需要连接到终端。"
    case .terminalSetupFailed(let code):
      "无法切换终端输入模式（errno \(code)）。"
    case .signalSetupFailed(let code):
      "无法安装终端信号监视（errno \(code)）。"
    case .terminalReadFailed(let code):
      "无法读取终端输入（errno \(code)）。"
    case .terminalPasteIncomplete:
      "终端粘贴数据不完整。"
    case .terminalPasteTooLarge:
      "终端粘贴数据超过 64 KiB 限制。"
    }
  }
}

enum TerminalMouseAction: Equatable {
  case leftPress
  case leftDrag
  case leftRelease
  case scrollUp
  case scrollDown
}

struct TerminalMouseEvent: Equatable {
  let action: TerminalMouseAction
  let column: Int
  let row: Int

  static func parse(sgrPayload: String, terminator: Character) -> TerminalMouseEvent? {
    let fields = sgrPayload.split(separator: ";", omittingEmptySubsequences: false)
    guard fields.count == 3,
      let buttonCode = Int(fields[0]),
      let column = Int(fields[1]),
      let row = Int(fields[2]),
      buttonCode >= 0,
      buttonCode <= 127,
      column > 0,
      row > 0
    else {
      return nil
    }

    let action: TerminalMouseAction
    if terminator == "m" {
      guard buttonCode & 96 == 0, buttonCode & 3 == 0 else {
        return nil
      }
      action = .leftRelease
    } else if terminator == "M", buttonCode & 64 != 0 {
      guard buttonCode & 32 == 0, buttonCode & 3 <= 1 else {
        return nil
      }
      action = buttonCode & 1 == 0 ? .scrollUp : .scrollDown
    } else if terminator == "M", buttonCode & 32 != 0 {
      guard buttonCode & 3 == 0 else {
        return nil
      }
      action = .leftDrag
    } else if terminator == "M" {
      guard buttonCode & 3 == 0 else {
        return nil
      }
      action = .leftPress
    } else {
      return nil
    }
    return TerminalMouseEvent(action: action, column: column, row: row)
  }
}

struct TerminalMouseInteraction {
  private(set) var isDraggingScrollbar = false

  mutating func reset() {
    isDraggingScrollbar = false
  }

  mutating func event(
    for mouseEvent: TerminalMouseEvent,
    session: PickerSession,
    dimensions: TerminalDimensions
  ) -> PickerEvent? {
    switch mouseEvent.action {
    case .scrollUp, .scrollDown:
      isDraggingScrollbar = false
      guard case .browse = session.phase else {
        return nil
      }
      let listRows = max(1, dimensions.rows - 4)
      let startIndex = session.visibleApplicationRange(listRows: listRows).lowerBound
      let offset = mouseEvent.action == .scrollUp ? -3 : 3
      return .positionViewport(startIndex: startIndex + offset, listRows: listRows)
    case .leftRelease:
      isDraggingScrollbar = false
      return nil
    case .leftDrag:
      guard isDraggingScrollbar else {
        return nil
      }
      guard
        let target = TerminalPickerRenderer.scrollbarDragTarget(
          session: session,
          dimensions: dimensions,
          row: mouseEvent.row
        ),
        case .command(let event) = target
      else {
        isDraggingScrollbar = false
        return nil
      }
      return event
    case .leftPress:
      isDraggingScrollbar = false
      if case .filtering = session.phase {
        return .escape
      }
      guard
        let target = TerminalPickerRenderer.mouseTarget(
          session: session,
          dimensions: dimensions,
          column: mouseEvent.column,
          row: mouseEvent.row
        )
      else {
        return nil
      }

      switch target {
      case .application(let index):
        return index == session.state.selectedIndex
          ? .enter
          : .move(index - session.state.selectedIndex)
      case .command(let event):
        return event
      case .scrollbarThumb:
        isDraggingScrollbar = true
        return nil
      case .confirmationExecute:
        return .chooseConfirmation(.execute)
      case .confirmationCancel:
        return .chooseConfirmation(.cancel)
      }
    }
  }
}

@MainActor
final class TerminalPicker: ApplicationPicking {
  private static let bracketedPasteTimeout: TimeInterval = 1
  private static let enterInterface =
    "\u{001B}[?1049h\u{001B}[?25l\u{001B}[?1002h\u{001B}[?1006h\u{001B}[?2004h"
  private static let leaveInterface =
    TerminalOutputFrame.endSynchronizedUpdate
    + "\u{001B}[?2004l\u{001B}[?1006l\u{001B}[?1002l\u{001B}[0m\u{001B}[?25h\u{001B}[?1049l"

  private let inputFileDescriptor: Int32
  private let outputFileDescriptor: Int32
  private let colorEnabled: Bool
  private let refreshInterval: TimeInterval
  private var bufferedByte: UInt8?
  private var bracketedPasteDecoder: TerminalBracketedPasteDecoder?
  private var bracketedPasteDeadline: TimeInterval?
  private var mouseInteraction = TerminalMouseInteraction()

  init(
    inputFileDescriptor: Int32 = STDIN_FILENO,
    outputFileDescriptor: Int32 = STDOUT_FILENO,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    refreshInterval: TimeInterval = 0.75
  ) {
    self.inputFileDescriptor = inputFileDescriptor
    self.outputFileDescriptor = outputFileDescriptor
    colorEnabled = environment["NO_COLOR"] == nil && environment["TERM"] != "dumb"
    self.refreshInterval = refreshInterval
  }

  func choose(
    from applications: [ApplicationCandidate],
    initialQuery: String,
    action: ApplicationExitAction,
    refreshApplications: () -> [ApplicationCandidate]
  ) throws -> ApplicationExitPlan? {
    guard isatty(inputFileDescriptor) == 1, isatty(outputFileDescriptor) == 1 else {
      throw TerminalPickerError.notATerminal
    }

    bufferedByte = nil
    resetBracketedPaste()
    mouseInteraction.reset()
    var original = termios()
    guard tcgetattr(inputFileDescriptor, &original) == 0 else {
      throw TerminalPickerError.terminalSetupFailed(errno)
    }

    var raw = original
    cfmakeraw(&raw)
    raw.c_cc.16 = 0  // VMIN
    raw.c_cc.17 = 1  // VTIME, one tenth of a second

    let signalMonitor: TerminalSignalMonitor
    do {
      signalMonitor = try TerminalSignalMonitor()
    } catch let error as TerminalSignalMonitorError {
      throw TerminalPickerError.signalSetupFailed(error.code)
    }
    defer { signalMonitor.stop() }

    try activateInterface(using: &raw)
    defer {
      restoreInterfaceBestEffort(using: &original)
    }

    var session = PickerSession(
      applications: applications,
      initialQuery: initialQuery,
      defaultAction: action
    )
    var dimensions = terminalDimensions()
    session.synchronizeViewport(listRows: listRows(for: dimensions))
    var nextRefresh = ProcessInfo.processInfo.systemUptime + refreshInterval
    render(session: session, dimensions: dimensions, clearScreen: true)

    while true {
      let event: PickerEvent
      if let signalEvent = signalMonitor.consumeNext() {
        switch signalEvent {
        case .terminate(let signal):
          terminate(
            for: signal,
            restoring: &original,
            signalMonitor: signalMonitor
          )
        case .suspend:
          event = .suspend
        }
      } else if let inputEvent = try readEvent(session: session, dimensions: dimensions) {
        event = inputEvent
      } else {
        if !isReadingBracketedPaste {
          _ = session.handle(.inputIdle)
        }
        var redraw = false
        var clearScreen = false
        let nextDimensions = terminalDimensions()
        if nextDimensions != dimensions {
          dimensions = nextDimensions
          session.synchronizeViewport(listRows: listRows(for: dimensions))
          redraw = true
          clearScreen = true
        }

        let now = ProcessInfo.processInfo.systemUptime
        if now >= nextRefresh {
          _ = RunLoop.current.run(mode: .default, before: Date())
          redraw = session.replaceApplications(refreshApplications()) || redraw
          nextRefresh = now + refreshInterval
        }

        if redraw {
          render(session: session, dimensions: dimensions, clearScreen: clearScreen)
        }
        continue
      }

      switch session.handle(event) {
      case .cancel:
        return nil
      case .select(let selection):
        return selection
      case .suspend:
        mouseInteraction.reset()
        resetBracketedPaste()
        try deactivateInterface(restoring: &original)
        _ = Darwin.raise(SIGSTOP)

        try activateInterface(using: &raw)
        _ = session.replaceApplications(refreshApplications())
        dimensions = terminalDimensions()
        session.synchronizeViewport(listRows: listRows(for: dimensions))
        nextRefresh = ProcessInfo.processInfo.systemUptime + refreshInterval
        render(session: session, dimensions: dimensions, clearScreen: true)
      case .stay(let redraw):
        if redraw {
          dimensions = terminalDimensions()
          session.synchronizeViewport(listRows: listRows(for: dimensions))
          render(session: session, dimensions: dimensions, clearScreen: false)
        }
      }
    }
  }

  private func activateInterface(using mode: inout termios) throws {
    guard tcsetattr(inputFileDescriptor, TCSAFLUSH, &mode) == 0 else {
      throw TerminalPickerError.terminalSetupFailed(errno)
    }
    write(Self.enterInterface)
  }

  private func deactivateInterface(restoring mode: inout termios) throws {
    let result = tcsetattr(inputFileDescriptor, TCSAFLUSH, &mode)
    let errorCode = errno
    write(Self.leaveInterface)
    guard result == 0 else {
      throw TerminalPickerError.terminalSetupFailed(errorCode)
    }
  }

  private func restoreInterfaceBestEffort(using mode: inout termios) {
    _ = tcsetattr(inputFileDescriptor, TCSAFLUSH, &mode)
    write(Self.leaveInterface)
  }

  private func terminate(
    for signal: Int32,
    restoring mode: inout termios,
    signalMonitor: TerminalSignalMonitor
  ) -> Never {
    mouseInteraction.reset()
    resetBracketedPaste()
    restoreInterfaceBestEffort(using: &mode)
    signalMonitor.stop()
    _ = Darwin.raise(signal)
    Darwin._exit(128 + signal)
  }

  private func readEvent(
    session: PickerSession,
    dimensions: TerminalDimensions
  ) throws -> PickerEvent? {
    if isReadingBracketedPaste {
      return try readBracketedPasteChunk()
    }

    guard let first = try readByte() else {
      return nil
    }

    switch first {
    case 3, 4:
      return .interrupt
    case 26:
      return .suspend
    case 10, 13:
      return .enter
    case 8, 127:
      return .backspace
    case 9:
      return .cycleFocus
    case 14:
      return .move(1)
    case 12:
      return .redraw
    case 16:
      return .move(-1)
    case 21:
      return .clear
    case 27:
      return try readEscapeSequence(session: session, dimensions: dimensions)
    case 32...126:
      return .text(String(UnicodeScalar(first)))
    case 194...244:
      return try readUTF8Sequence(startingWith: first).map(PickerEvent.text)
    default:
      return nil
    }
  }

  private func readEscapeSequence(
    session: PickerSession,
    dimensions: TerminalDimensions
  ) throws -> PickerEvent? {
    guard let second = try readByte() else {
      return .escape
    }
    if second == 79 {
      guard let final = try readByte() else {
        return .escape
      }
      return TerminalKeySequence.ss3(final: final).map {
        event(for: $0, session: session, dimensions: dimensions)
      }
    }
    guard second == 91 else {
      bufferedByte = second
      return .escape
    }
    guard let first = try readByte() else {
      return .escape
    }

    if first == 60 {
      return try readMouseEvent().flatMap {
        mouseInteraction.event(for: $0, session: session, dimensions: dimensions)
      }
    }
    if first == 91 {
      guard let legacyFinal = try readByte() else {
        return nil
      }
      return legacyFinal == 65 ? .help : nil
    }
    return try readCSIKey(startingWith: first, session: session, dimensions: dimensions)
  }

  private func readCSIKey(
    startingWith first: UInt8,
    session: PickerSession,
    dimensions: TerminalDimensions
  ) throws -> PickerEvent? {
    var parameters = ""
    var intermediates = ""
    var byte = first

    for _ in 0..<32 {
      switch byte {
      case 48...63:
        guard intermediates.isEmpty else {
          return nil
        }
        parameters.append(Character(UnicodeScalar(byte)))
      case 32...47:
        intermediates.append(Character(UnicodeScalar(byte)))
      case 64...126:
        if TerminalKeySequence.isBracketedPasteStart(
          parameters: parameters,
          intermediates: intermediates,
          final: byte
        ) {
          bracketedPasteDecoder = TerminalBracketedPasteDecoder()
          bracketedPasteDeadline =
            ProcessInfo.processInfo.systemUptime + Self.bracketedPasteTimeout
          return try readBracketedPasteChunk()
        }
        return TerminalKeySequence.csi(
          parameters: parameters,
          intermediates: intermediates,
          final: byte
        ).map {
          event(for: $0, session: session, dimensions: dimensions)
        }
      default:
        return nil
      }

      guard let next = try readByte() else {
        return nil
      }
      byte = next
    }
    return nil
  }

  private var isReadingBracketedPaste: Bool {
    bracketedPasteDecoder != nil
  }

  private func readBracketedPasteChunk() throws -> PickerEvent? {
    guard var decoder = bracketedPasteDecoder else {
      return nil
    }

    while true {
      if let deadline = bracketedPasteDeadline,
        ProcessInfo.processInfo.systemUptime >= deadline
      {
        resetBracketedPaste()
        throw TerminalPickerError.terminalPasteIncomplete
      }

      guard let byte = try readByte() else {
        bracketedPasteDecoder = decoder
        if let deadline = bracketedPasteDeadline,
          ProcessInfo.processInfo.systemUptime >= deadline
        {
          resetBracketedPaste()
          throw TerminalPickerError.terminalPasteIncomplete
        }
        return nil
      }

      bracketedPasteDeadline =
        ProcessInfo.processInfo.systemUptime + Self.bracketedPasteTimeout
      let isComplete = decoder.consume(byte)
      if decoder.isOverflowed {
        resetBracketedPaste()
        throw TerminalPickerError.terminalPasteTooLarge
      }
      if isComplete {
        let text = decoder.text
        resetBracketedPaste()
        return .paste(text)
      }
    }
  }

  private func resetBracketedPaste() {
    bracketedPasteDecoder = nil
    bracketedPasteDeadline = nil
  }

  private func event(
    for key: TerminalSpecialKey,
    session: PickerSession,
    dimensions: TerminalDimensions
  ) -> PickerEvent {
    switch key {
    case .up:
      .move(-1)
    case .down:
      .move(1)
    case .left:
      .moveHorizontal(-1)
    case .right:
      .moveHorizontal(1)
    case .home:
      .first
    case .end:
      .last
    case .pageUp:
      pageEvent(direction: -1, session: session, dimensions: dimensions)
    case .pageDown:
      pageEvent(direction: 1, session: session, dimensions: dimensions)
    case .deleteForward:
      .deleteForward
    case .backTab:
      .cycleFocus
    case .help:
      .help
    }
  }

  private func readMouseEvent() throws -> TerminalMouseEvent? {
    var payload = ""
    while payload.utf8.count < 32, let byte = try readByte() {
      if byte == 77 || byte == 109 {
        return TerminalMouseEvent.parse(
          sgrPayload: payload,
          terminator: Character(UnicodeScalar(byte))
        )
      }
      guard byte == 59 || 48...57 ~= byte else {
        return nil
      }
      payload.append(Character(UnicodeScalar(byte)))
    }
    return nil
  }

  private func readUTF8Sequence(startingWith first: UInt8) throws -> String? {
    let length: Int
    switch first {
    case 194...223:
      length = 2
    case 224...239:
      length = 3
    case 240...244:
      length = 4
    default:
      return nil
    }

    var bytes = [first]
    for _ in 1..<length {
      guard let byte = try readByte(), byte & 0b1100_0000 == 0b1000_0000 else {
        return nil
      }
      bytes.append(byte)
    }
    return String(bytes: bytes, encoding: .utf8)
  }

  private func readByte() throws -> UInt8? {
    if let bufferedByte {
      self.bufferedByte = nil
      return bufferedByte
    }

    var byte: UInt8 = 0
    while true {
      let count = Darwin.read(inputFileDescriptor, &byte, 1)
      if count == 1 {
        return byte
      }
      if count == 0 {
        return nil
      }
      if errno != EINTR {
        throw TerminalPickerError.terminalReadFailed(errno)
      }
    }
  }

  private func terminalDimensions() -> TerminalDimensions {
    var size = winsize()
    guard ioctl(outputFileDescriptor, TIOCGWINSZ, &size) == 0 else {
      return TerminalDimensions(rows: 24, columns: 80)
    }
    return TerminalDimensions(
      rows: size.ws_row > 0 ? Int(size.ws_row) : 24,
      columns: size.ws_col > 0 ? Int(size.ws_col) : 80
    )
  }

  private func listRows(for dimensions: TerminalDimensions) -> Int {
    max(1, dimensions.rows - 4)
  }

  private func pageEvent(
    direction: Int,
    session: PickerSession,
    dimensions: TerminalDimensions
  ) -> PickerEvent {
    let listRows = listRows(for: dimensions)
    let startIndex = session.visibleApplicationRange(listRows: listRows).lowerBound
    return .positionViewport(
      startIndex: startIndex + direction * listRows,
      listRows: listRows
    )
  }

  private func render(
    session: PickerSession,
    dimensions: TerminalDimensions,
    clearScreen: Bool
  ) {
    let content =
      TerminalPickerRenderer.render(
        session: session,
        dimensions: dimensions,
        colorEnabled: colorEnabled,
        clearScreen: clearScreen
      )
    write(TerminalOutputFrame.synchronized(content))
  }

  private func write(_ text: String) {
    let bytes = Array(text.utf8)
    bytes.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else {
        return
      }

      var offset = 0
      while offset < rawBuffer.count {
        let written = Darwin.write(
          outputFileDescriptor,
          baseAddress.advanced(by: offset),
          rawBuffer.count - offset
        )
        if written > 0 {
          offset += written
        } else if written < 0, errno == EINTR {
          continue
        } else {
          return
        }
      }
    }
  }
}
