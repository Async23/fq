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

  static func displayWidth(_ text: String) -> Int {
    text.reduce(into: 0) { width, character in
      width += characterDisplayWidth(character)
    }
  }

  static func clipped(_ text: String, to maximumWidth: Int) -> String {
    guard maximumWidth > 0 else {
      return ""
    }
    guard displayWidth(text) > maximumWidth else {
      return text
    }
    guard maximumWidth > 1 else {
      return "…"
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

  static func prefixFitting(_ text: String, in maximumWidth: Int) -> String {
    guard maximumWidth > 0 else {
      return ""
    }

    var result = ""
    var width = 0
    for character in text {
      let characterWidth = displayWidth(String(character))
      guard width + characterWidth <= maximumWidth else {
        break
      }
      result.append(character)
      width += characterWidth
    }
    return result
  }

  static func suffixFitting(_ text: String, in maximumWidth: Int) -> String {
    guard maximumWidth > 0 else {
      return ""
    }

    var characters: [Character] = []
    var width = 0
    for character in text.reversed() {
      let characterWidth = displayWidth(String(character))
      guard width + characterWidth <= maximumWidth else {
        break
      }
      characters.append(character)
      width += characterWidth
    }
    return String(characters.reversed())
  }

  static func padded(_ text: String, to targetWidth: Int) -> String {
    let clippedText = clipped(text, to: targetWidth)
    return clippedText
      + String(repeating: " ", count: max(0, targetWidth - displayWidth(clippedText)))
  }

  static func leftPadded(_ text: String, to targetWidth: Int) -> String {
    let clippedText = clipped(text, to: targetWidth)
    return String(repeating: " ", count: max(0, targetWidth - displayWidth(clippedText)))
      + clippedText
  }

  static func centered(_ text: String, in targetWidth: Int) -> String {
    let clippedText = clipped(text, to: targetWidth)
    let remaining = max(0, targetWidth - displayWidth(clippedText))
    return String(repeating: " ", count: remaining / 2)
      + clippedText
      + String(repeating: " ", count: remaining - remaining / 2)
  }

  private static func isBidirectionalOverride(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x202A...0x202E, 0x2066...0x2069:
      return true
    default:
      return false
    }
  }

  private static func characterDisplayWidth(_ character: Character) -> Int {
    let scalars = character.unicodeScalars
    if scalars.contains(where: isEmojiScalar) {
      return 2
    }

    return scalars.reduce(into: 0) { width, scalar in
      guard !isZeroWidth(scalar) else {
        return
      }
      width += isWide(scalar.value) ? 2 : 1
    }
  }

  private static func isEmojiScalar(_ scalar: UnicodeScalar) -> Bool {
    scalar.properties.isEmojiPresentation
      || scalar.value == 0xFE0F
      || scalar.value == 0x200D
      || 0x1F1E6...0x1F1FF ~= scalar.value
  }

  private static func isZeroWidth(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .control, .format, .nonspacingMark, .spacingMark, .enclosingMark:
      return true
    default:
      return 0xFE00...0xFE0F ~= scalar.value
        || 0xE0100...0xE01EF ~= scalar.value
    }
  }

  private static func isWide(_ value: UInt32) -> Bool {
    switch value {
    case 0x1100...0x115F,
      0x231A...0x231B,
      0x2329...0x232A,
      0x23E9...0x23EC,
      0x23F0...0x23F0,
      0x23F3...0x23F3,
      0x25FD...0x25FE,
      0x2614...0x2615,
      0x2648...0x2653,
      0x267F...0x267F,
      0x2693...0x2693,
      0x26A1...0x26A1,
      0x26AA...0x26AB,
      0x26BD...0x26BE,
      0x26C4...0x26C5,
      0x26CE...0x26CE,
      0x26D4...0x26D4,
      0x26EA...0x26EA,
      0x26F2...0x26F3,
      0x26F5...0x26F5,
      0x26FA...0x26FA,
      0x26FD...0x26FD,
      0x2705...0x2705,
      0x270A...0x270B,
      0x2728...0x2728,
      0x274C...0x274C,
      0x274E...0x274E,
      0x2753...0x2755,
      0x2757...0x2757,
      0x2795...0x2797,
      0x27B0...0x27B0,
      0x27BF...0x27BF,
      0x2B1B...0x2B1C,
      0x2B50...0x2B50,
      0x2B55...0x2B55,
      0x2E80...0x303E,
      0x3040...0xA4CF,
      0xAC00...0xD7A3,
      0xF900...0xFAFF,
      0xFE10...0xFE19,
      0xFE30...0xFE6F,
      0xFF01...0xFF60,
      0xFFE0...0xFFE6,
      0x1F300...0x1FAFF,
      0x20000...0x3FFFD:
      return true
    default:
      return false
    }
  }
}
