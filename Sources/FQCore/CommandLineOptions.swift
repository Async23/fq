import Foundation

public enum ApplicationListFormat: Equatable, Sendable {
  case text
  case json
}

public enum FQCommandMode: Equatable, Sendable {
  case interactive(action: ApplicationExitAction, query: String)
  case list(format: ApplicationListFormat, query: String)
  case help
  case version
}

public enum CommandLineOptionsError: LocalizedError, Equatable {
  case conflictingActions
  case incompatibleOption(String)
  case unexpectedArgument(String)

  public var errorDescription: String? {
    switch self {
    case .conflictingActions:
      "不能同时使用 --force 和 --quit。"
    case .incompatibleOption(let option):
      "选项 \(option) 不能与当前模式组合使用。"
    case .unexpectedArgument(let argument):
      "无法识别的选项：\(argument)"
    }
  }
}

public enum CommandLineOptions {
  public static func parse(_ arguments: [String]) throws -> FQCommandMode {
    var explicitAction: ApplicationExitAction?
    var listFormat: ApplicationListFormat?
    var queryParts: [String] = []
    var specialMode: FQCommandMode?
    var parsesOptions = true

    for argument in arguments {
      if parsesOptions, argument == "--" {
        parsesOptions = false
        continue
      }

      guard parsesOptions, argument.hasPrefix("-") else {
        queryParts.append(argument)
        continue
      }

      switch argument {
      case "-h", "--help":
        try setSpecialMode(.help, current: &specialMode)
      case "-V", "--version":
        try setSpecialMode(.version, current: &specialMode)
      case "-l", "--list":
        listFormat = listFormat ?? .text
      case "--json":
        listFormat = .json
      case "-f", "--force":
        try setAction(.forceQuit, current: &explicitAction)
      case "-q", "--quit":
        try setAction(.quit, current: &explicitAction)
      default:
        throw CommandLineOptionsError.unexpectedArgument(argument)
      }
    }

    if let specialMode {
      guard queryParts.isEmpty, explicitAction == nil, listFormat == nil else {
        throw CommandLineOptionsError.incompatibleOption(
          specialMode == .help ? "--help" : "--version"
        )
      }
      return specialMode
    }

    let query = queryParts.joined(separator: " ")
    if let listFormat {
      guard explicitAction == nil else {
        throw CommandLineOptionsError.incompatibleOption("--list")
      }
      return .list(format: listFormat, query: query)
    }

    return .interactive(action: explicitAction ?? .forceQuit, query: query)
  }

  private static func setAction(
    _ action: ApplicationExitAction,
    current: inout ApplicationExitAction?
  ) throws {
    if let current, current != action {
      throw CommandLineOptionsError.conflictingActions
    }
    current = action
  }

  private static func setSpecialMode(
    _ mode: FQCommandMode,
    current: inout FQCommandMode?
  ) throws {
    if let current, current != mode {
      throw CommandLineOptionsError.incompatibleOption("--help/--version")
    }
    current = mode
  }
}
