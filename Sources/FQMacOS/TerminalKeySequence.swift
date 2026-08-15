enum TerminalSpecialKey: Equatable {
  case up
  case down
  case left
  case right
  case home
  case end
  case pageUp
  case pageDown
  case deleteForward
  case backTab
  case help
}

enum TerminalKeySequence {
  static func isBracketedPasteStart(
    parameters: String,
    intermediates: String = "",
    final: UInt8
  ) -> Bool {
    intermediates.isEmpty && parameters == "200" && final == 126
  }

  static func ss3(final: UInt8) -> TerminalSpecialKey? {
    switch final {
    case 65:
      .up
    case 66:
      .down
    case 67:
      .right
    case 68:
      .left
    case 70:
      .end
    case 72:
      .home
    case 80:
      .help
    default:
      nil
    }
  }

  static func csi(
    parameters: String,
    intermediates: String = "",
    final: UInt8
  ) -> TerminalSpecialKey? {
    guard intermediates.isEmpty, hasKeyboardParameters(parameters) else {
      return nil
    }

    switch final {
    case 65:
      return .up
    case 66:
      return .down
    case 67:
      return .right
    case 68:
      return .left
    case 70:
      return .end
    case 72:
      return .home
    case 80:
      return parameters.hasPrefix("1;") ? .help : .deleteForward
    case 90:
      return .backTab
    case 126:
      switch primaryParameter(in: parameters) {
      case 1, 7:
        return .home
      case 3:
        return .deleteForward
      case 4, 8:
        return .end
      case 5:
        return .pageUp
      case 6:
        return .pageDown
      case 11:
        return .help
      default:
        return nil
      }
    default:
      return nil
    }
  }

  private static func hasKeyboardParameters(_ parameters: String) -> Bool {
    parameters.allSatisfy { character in
      character == ";" || character.isNumber
    }
  }

  private static func primaryParameter(in parameters: String) -> Int? {
    let primary = parameters.split(separator: ";", omittingEmptySubsequences: false).first
    return primary.flatMap { Int($0) }
  }
}
