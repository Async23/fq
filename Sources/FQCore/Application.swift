import Foundation

public struct ApplicationIdentity: Hashable, Codable, Sendable {
  public let processIdentifier: Int32
  public let bundleIdentifier: String?
  public let launchDate: Date?

  public init(
    processIdentifier: Int32,
    bundleIdentifier: String?,
    launchDate: Date?
  ) {
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
    self.launchDate = launchDate
  }
}

public struct ApplicationCandidate: Identifiable, Equatable, Codable, Sendable {
  public let id: ApplicationIdentity
  public let name: String
  public let isActive: Bool
  public let isHidden: Bool

  public init(
    id: ApplicationIdentity,
    name: String,
    isActive: Bool = false,
    isHidden: Bool = false
  ) {
    self.id = id
    self.name = name
    self.isActive = isActive
    self.isHidden = isHidden
  }

  public var processIdentifier: Int32 {
    id.processIdentifier
  }

  public var bundleIdentifier: String? {
    id.bundleIdentifier
  }

  public var isFinder: Bool {
    bundleIdentifier == "com.apple.finder"
  }
}

public enum ApplicationExitAction: String, Equatable, Codable, Sendable {
  case forceQuit
  case quit
}

public enum ApplicationExitOutcome: Equatable, Sendable {
  case terminated
  case requested
}
