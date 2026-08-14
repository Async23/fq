import Darwin
import FQCore
import Foundation

@MainActor
protocol ApplicationPicking: AnyObject {
  func choose(
    from applications: [ApplicationCandidate],
    initialQuery: String,
    action: ApplicationExitAction
  ) throws -> ApplicationCandidate?
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

  init(
    inputFileDescriptor: Int32 = STDIN_FILENO,
    outputFileDescriptor: Int32 = STDOUT_FILENO
  ) {
    self.inputFileDescriptor = inputFileDescriptor
    self.outputFileDescriptor = outputFileDescriptor
  }

  func choose(
    from applications: [ApplicationCandidate],
    initialQuery: String,
    action: ApplicationExitAction
  ) throws -> ApplicationCandidate? {
    guard isatty(inputFileDescriptor) == 1, isatty(outputFileDescriptor) == 1 else {
      throw TerminalPickerError.notATerminal
    }

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

    var state = PickerState(applications: applications, initialQuery: initialQuery)
    render(state: state, action: action)

    while true {
      guard let event = try readEvent() else {
        continue
      }

      switch event {
      case .accept:
        return state.selectedApplication
      case .cancel:
        return nil
      case .move(let offset):
        state.moveSelection(by: offset)
      case .first:
        state.moveToFirst()
      case .last:
        state.moveToLast()
      case .backspace:
        state.deleteLastQueryCharacter()
      case .clear:
        state.clearQuery()
      case .text(let text):
        state.appendToQuery(text)
      }

      render(state: state, action: action)
    }
  }

  private func readEvent() throws -> InputEvent? {
    guard let first = try readByte() else {
      return nil
    }

    switch first {
    case 3, 4:
      return .cancel
    case 10, 13:
      return .accept
    case 8, 127:
      return .backspace
    case 9, 14:
      return .move(1)
    case 16:
      return .move(-1)
    case 21:
      return .clear
    case 27:
      return try readEscapeSequence()
    case 32...126:
      return .text(String(UnicodeScalar(first)))
    case 194...244:
      return try readUTF8Sequence(startingWith: first).map(InputEvent.text)
    default:
      return nil
    }
  }

  private func readEscapeSequence() throws -> InputEvent {
    guard let second = try readByte(), second == 91 else {
      return .cancel
    }
    guard let third = try readByte() else {
      return .cancel
    }

    switch third {
    case 65:
      return .move(-1)
    case 66:
      return .move(1)
    case 72:
      return .first
    case 70:
      return .last
    case 49, 55:
      _ = try readByte()
      return .first
    case 52, 56:
      _ = try readByte()
      return .last
    case 53:
      _ = try readByte()
      return .move(-pageSize())
    case 54:
      _ = try readByte()
      return .move(pageSize())
    default:
      return .cancel
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

  private func render(state: PickerState, action: ApplicationExitAction) {
    let dimensions = terminalDimensions()
    let width = max(2, dimensions.columns)
    let listRows = max(1, dimensions.rows - 5)
    let visible = state.visibleApplications
    let selectedIndex = min(state.selectedIndex, max(0, visible.count - 1))
    let startIndex = max(0, selectedIndex - listRows + 1)
    let endIndex = min(visible.count, startIndex + listRows)

    let actionName = action == .forceQuit ? "强制退出" : "正常退出"
    var output = "\u{001B}[H\u{001B}[2J"
    output += clipped("fq  \(actionName)应用", to: width - 1) + "\r\n"
    output += clipped("输入筛选 · ↑↓ 移动 · Enter 选择 · Esc 取消", to: width - 1) + "\r\n"
    output += clipped("搜索 › \(TerminalText.sanitize(state.query))", to: width - 1) + "\r\n\r\n"

    if visible.isEmpty {
      output += "  没有匹配的应用\r\n"
    } else {
      for index in startIndex..<endIndex {
        let application = visible[index]
        let activeMarker = application.isActive ? "*" : " "
        let hiddenMarker = application.isHidden ? "隐藏" : ""
        let bundle = application.bundleIdentifier ?? "-"
        let line =
          "\(index == selectedIndex ? ">" : " ") \(activeMarker) "
          + "\(TerminalText.sanitize(application.name))  pid:\(application.processIdentifier) "
          + "\(TerminalText.sanitize(bundle)) \(hiddenMarker)"
        let renderedLine = padded(clipped(line, to: width - 1), to: width - 1)
        if index == selectedIndex {
          output += "\u{001B}[7m\(renderedLine)\u{001B}[0m\r\n"
        } else {
          output += renderedLine + "\r\n"
        }
      }
    }

    write(output)
  }

  private func terminalDimensions() -> (rows: Int, columns: Int) {
    var size = winsize()
    guard ioctl(outputFileDescriptor, TIOCGWINSZ, &size) == 0 else {
      return (24, 80)
    }
    return (
      size.ws_row > 0 ? Int(size.ws_row) : 24,
      size.ws_col > 0 ? Int(size.ws_col) : 80
    )
  }

  private func pageSize() -> Int {
    max(1, terminalDimensions().rows - 5)
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

  private func clipped(_ text: String, to maximumWidth: Int) -> String {
    guard displayWidth(text) > maximumWidth else {
      return text
    }
    guard maximumWidth > 1 else {
      return ""
    }

    var result = ""
    var width = 0
    for character in text {
      let characterWidth = displayWidth(String(character))
      if width + characterWidth > maximumWidth - 1 {
        break
      }
      result.append(character)
      width += characterWidth
    }
    return result + "…"
  }

  private func padded(_ text: String, to targetWidth: Int) -> String {
    text + String(repeating: " ", count: max(0, targetWidth - displayWidth(text)))
  }

  private func displayWidth(_ text: String) -> Int {
    text.unicodeScalars.reduce(into: 0) { width, scalar in
      let scalarWidth = wcwidth(wchar_t(scalar.value))
      width += scalarWidth > 0 ? Int(scalarWidth) : 0
    }
  }
}

private enum InputEvent {
  case accept
  case cancel
  case move(Int)
  case first
  case last
  case backspace
  case clear
  case text(String)
}
