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
  ) throws -> ApplicationExitSelection?
}

enum TerminalPickerError: LocalizedError {
  case notATerminal
  case terminalSetupFailed(Int32)
  case terminalReadFailed(Int32)

  var errorDescription: String? {
    switch self {
    case .notATerminal:
      "交互选择器需要连接到终端。"
    case .terminalSetupFailed(let code):
      "无法切换终端输入模式（errno \(code)）。"
    case .terminalReadFailed(let code):
      "无法读取终端输入（errno \(code)）。"
    }
  }
}

@MainActor
final class TerminalPicker: ApplicationPicking {
  private let inputFileDescriptor: Int32
  private let outputFileDescriptor: Int32
  private let colorEnabled: Bool
  private let refreshInterval: TimeInterval
  private var bufferedByte: UInt8?

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
  ) throws -> ApplicationExitSelection? {
    guard isatty(inputFileDescriptor) == 1, isatty(outputFileDescriptor) == 1 else {
      throw TerminalPickerError.notATerminal
    }

    bufferedByte = nil
    var original = termios()
    guard tcgetattr(inputFileDescriptor, &original) == 0 else {
      throw TerminalPickerError.terminalSetupFailed(errno)
    }

    var raw = original
    cfmakeraw(&raw)
    raw.c_cc.16 = 0  // VMIN
    raw.c_cc.17 = 1  // VTIME, one tenth of a second
    guard tcsetattr(inputFileDescriptor, TCSAFLUSH, &raw) == 0 else {
      throw TerminalPickerError.terminalSetupFailed(errno)
    }

    write("\u{001B}[?1049h\u{001B}[?25l")
    defer {
      _ = tcsetattr(inputFileDescriptor, TCSAFLUSH, &original)
      write("\u{001B}[0m\u{001B}[?25h\u{001B}[?1049l")
    }

    var session = PickerSession(
      applications: applications,
      initialQuery: initialQuery,
      defaultAction: action
    )
    var dimensions = terminalDimensions()
    var nextRefresh = ProcessInfo.processInfo.systemUptime + refreshInterval
    render(session: session, dimensions: dimensions, clearScreen: true)

    while true {
      guard let event = try readEvent() else {
        var redraw = false
        var clearScreen = false
        let nextDimensions = terminalDimensions()
        if nextDimensions != dimensions {
          dimensions = nextDimensions
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
      case .stay(let redraw):
        if redraw {
          dimensions = terminalDimensions()
          render(session: session, dimensions: dimensions, clearScreen: false)
        }
      }
    }
  }

  private func readEvent() throws -> PickerEvent? {
    guard let first = try readByte() else {
      return nil
    }

    switch first {
    case 3, 4:
      return .interrupt
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
      return try readEscapeSequence()
    case 32...126:
      return .text(String(UnicodeScalar(first)))
    case 194...244:
      return try readUTF8Sequence(startingWith: first).map(PickerEvent.text)
    default:
      return nil
    }
  }

  private func readEscapeSequence() throws -> PickerEvent? {
    guard let second = try readByte() else {
      return .escape
    }
    guard second == 91 else {
      bufferedByte = second
      return .escape
    }
    guard let third = try readByte() else {
      return .escape
    }

    switch third {
    case 65:
      return .move(-1)
    case 66:
      return .move(1)
    case 67:
      return .moveHorizontal(1)
    case 68:
      return .moveHorizontal(-1)
    case 72:
      return .first
    case 70:
      return .last
    case 90:
      return .cycleFocus
    case 49, 55:
      guard try readByte() == 126 else {
        return nil
      }
      return .first
    case 52, 56:
      guard try readByte() == 126 else {
        return nil
      }
      return .last
    case 51:
      guard try readByte() == 126 else {
        return nil
      }
      return .clear
    case 53:
      guard try readByte() == 126 else {
        return nil
      }
      return .move(-pageSize())
    case 54:
      guard try readByte() == 126 else {
        return nil
      }
      return .move(pageSize())
    default:
      return nil
    }
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

  private func pageSize() -> Int {
    max(1, terminalDimensions().rows - 4)
  }

  private func render(
    session: PickerSession,
    dimensions: TerminalDimensions,
    clearScreen: Bool
  ) {
    write(
      TerminalPickerRenderer.render(
        session: session,
        dimensions: dimensions,
        colorEnabled: colorEnabled,
        clearScreen: clearScreen
      )
    )
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
