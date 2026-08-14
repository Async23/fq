import Darwin
import Foundation

protocol Console: AnyObject {
  var isInputTerminal: Bool { get }
  var isOutputTerminal: Bool { get }

  func write(_ text: String)
  func writeError(_ text: String)
  func readLine(prompt: String) -> String?
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

  func readLine(prompt: String) -> String? {
    write(prompt)
    return Swift.readLine()
  }
}
