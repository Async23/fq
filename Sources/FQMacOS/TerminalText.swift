import Foundation

enum TerminalText {
  static func sanitize(_ text: String) -> String {
    String(
      text.unicodeScalars.map { scalar in
        if CharacterSet.controlCharacters.contains(scalar) || isBidirectionalOverride(scalar) {
          return " "
        }
        return Character(scalar)
      }
    )
  }

  private static func isBidirectionalOverride(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x202A...0x202E, 0x2066...0x2069:
      return true
    default:
      return false
    }
  }
}
