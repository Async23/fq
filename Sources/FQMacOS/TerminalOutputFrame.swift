enum TerminalOutputFrame {
  static let beginSynchronizedUpdate = "\u{001B}[?2026h"
  static let endSynchronizedUpdate = "\u{001B}[?2026l"

  static func synchronized(_ content: String) -> String {
    beginSynchronizedUpdate + content + endSynchronizedUpdate
  }
}
