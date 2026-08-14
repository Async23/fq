import AppKit
import Darwin
import FQCore
import Foundation

@MainActor
protocol ApplicationManaging: AnyObject {
  func runningApplications() -> [ApplicationCandidate]
  func requestExit(
    _ application: ApplicationCandidate,
    action: ApplicationExitAction
  ) throws -> ApplicationExitOutcome
}

enum ApplicationManagerError: LocalizedError, Equatable {
  case noLongerRunning(String)
  case identityChanged(String)
  case requestRejected(String)

  var errorDescription: String? {
    switch self {
    case .noLongerRunning(let name):
      "“\(name)” 已经不在运行。"
    case .identityChanged(let name):
      "“\(name)” 的进程身份已变化；为避免退出错误的应用，操作已取消。"
    case .requestRejected(let name):
      "macOS 拒绝了对 “\(name)” 的退出请求。"
    }
  }
}

@MainActor
final class WorkspaceApplicationManager: ApplicationManaging {
  private let workspace: NSWorkspace
  private var applicationsByIdentity: [ApplicationIdentity: NSRunningApplication] = [:]

  init(workspace: NSWorkspace = .shared) {
    self.workspace = workspace
  }

  func runningApplications() -> [ApplicationCandidate] {
    var nextApplicationsByIdentity: [ApplicationIdentity: NSRunningApplication] = [:]

    let candidates = workspace.runningApplications.compactMap { application in
      guard application.activationPolicy == .regular, !application.isTerminated else {
        return nil
      }

      let identity = identity(for: application)
      nextApplicationsByIdentity[identity] = application

      return ApplicationCandidate(
        id: identity,
        name: displayName(for: application),
        isActive: application.isActive,
        isHidden: application.isHidden
      )
    }.sorted(by: applicationOrdering)

    applicationsByIdentity = nextApplicationsByIdentity
    return candidates
  }

  func requestExit(
    _ application: ApplicationCandidate,
    action: ApplicationExitAction
  ) throws -> ApplicationExitOutcome {
    let runningApplication =
      applicationsByIdentity[application.id]
      ?? NSRunningApplication(processIdentifier: application.processIdentifier)

    guard let runningApplication, !runningApplication.isTerminated else {
      throw ApplicationManagerError.noLongerRunning(application.name)
    }
    guard identity(for: runningApplication) == application.id else {
      throw ApplicationManagerError.identityChanged(application.name)
    }

    let accepted: Bool
    switch action {
    case .forceQuit:
      accepted = runningApplication.forceTerminate()
    case .quit:
      accepted = runningApplication.terminate()
    }

    guard accepted else {
      throw ApplicationManagerError.requestRejected(application.name)
    }

    let waitInterval: TimeInterval = action == .forceQuit ? 1.0 : 0.15
    let deadline = Date().addingTimeInterval(waitInterval)
    repeat {
      if runningApplication.isTerminated || processIsGone(application.processIdentifier) {
        applicationsByIdentity.removeValue(forKey: application.id)
        return .terminated
      }
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    } while Date() < deadline

    return .requested
  }

  private func identity(for application: NSRunningApplication) -> ApplicationIdentity {
    ApplicationIdentity(
      processIdentifier: application.processIdentifier,
      bundleIdentifier: application.bundleIdentifier,
      launchDate: application.launchDate
    )
  }

  private func displayName(for application: NSRunningApplication) -> String {
    if let name = application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty
    {
      return name
    }
    if let bundleIdentifier = application.bundleIdentifier, !bundleIdentifier.isEmpty {
      return bundleIdentifier
    }
    return "PID \(application.processIdentifier)"
  }

  private func applicationOrdering(
    _ lhs: ApplicationCandidate,
    _ rhs: ApplicationCandidate
  ) -> Bool {
    if lhs.isActive != rhs.isActive {
      return lhs.isActive
    }

    let comparison = lhs.name.localizedStandardCompare(rhs.name)
    if comparison != .orderedSame {
      return comparison == .orderedAscending
    }
    return lhs.processIdentifier < rhs.processIdentifier
  }

  private func processIsGone(_ processIdentifier: Int32) -> Bool {
    if kill(processIdentifier, 0) == 0 {
      return false
    }
    return errno == ESRCH
  }
}
