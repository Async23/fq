import Darwin
import Foundation

protocol Console: AnyObject {
  var isInputTerminal: Bool { get }
  var isOutputTerminal: Bool { get }

  func write(_ text: String)
  func writeError(_ text: String)
}

final class StandardConsole: Console {
  var isInputTerminal: Bool {
    isatty(STDIN_FILENO) == 1
  }

  var isOutputTerminal: Bool {
    isatty(STDOUT_FILENO) == 1
  }

  func write(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
  }

  func writeError(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
  }
}
