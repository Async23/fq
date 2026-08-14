import Darwin
import Dispatch
import Foundation

enum TerminalSignalEvent: Equatable {
  case terminate(Int32)
  case suspend
}

final class TerminalSignalState: @unchecked Sendable {
  private let lock = NSLock()
  private var pendingTermination: Int32?
  private var isSuspendPending = false

  func record(_ signal: Int32) {
    lock.lock()
    defer { lock.unlock() }

    switch signal {
    case SIGTSTP:
      isSuspendPending = true
    case let signal where TerminalSignalMonitor.terminationSignals.contains(signal):
      if pendingTermination == nil {
        pendingTermination = signal
      }
    default:
      break
    }
  }

  func consumeNext() -> TerminalSignalEvent? {
    lock.lock()
    defer { lock.unlock() }

    if let pendingTermination {
      self.pendingTermination = nil
      isSuspendPending = false
      return .terminate(pendingTermination)
    }
    if isSuspendPending {
      isSuspendPending = false
      return .suspend
    }
    return nil
  }
}

struct TerminalSignalMonitorError: Error {
  let code: Int32
}

final class TerminalSignalMonitor {
  static let terminationSignals = [SIGHUP, SIGINT, SIGQUIT, SIGTERM]
  static let watchedSignals = terminationSignals + [SIGTSTP]

  private struct Registration {
    let signal: Int32
    let previousAction: Darwin.sigaction
    let source: any DispatchSourceSignal
  }

  private let state: TerminalSignalState
  private let queue = DispatchQueue(label: "fq.terminal-signals", qos: .userInitiated)
  private var registrations: [Registration] = []
  private var isStopped = false

  init(state: TerminalSignalState = TerminalSignalState()) throws {
    self.state = state

    for signal in Self.watchedSignals {
      var ignoredAction = Darwin.sigaction()
      ignoredAction.__sigaction_u.__sa_handler = SIG_IGN
      _ = sigemptyset(&ignoredAction.sa_mask)
      ignoredAction.sa_flags = 0

      var previousAction = Darwin.sigaction()
      guard
        installSignalAction(signal, action: &ignoredAction, previousAction: &previousAction)
          == 0
      else {
        let code = errno
        stop()
        throw TerminalSignalMonitorError(code: code)
      }

      let source = DispatchSource.makeSignalSource(signal: signal, queue: queue)
      source.setEventHandler { [state] in
        state.record(signal)
      }
      registrations.append(
        Registration(signal: signal, previousAction: previousAction, source: source)
      )
      source.resume()
    }
  }

  func consumeNext() -> TerminalSignalEvent? {
    state.consumeNext()
  }

  func stop() {
    guard !isStopped else {
      return
    }
    isStopped = true

    for registration in registrations.reversed() {
      registration.source.cancel()
      var previousAction = registration.previousAction
      _ = installSignalAction(
        registration.signal,
        action: &previousAction,
        previousAction: nil
      )
    }
    registrations.removeAll()
  }
}

private func installSignalAction(
  _ signal: Int32,
  action: UnsafePointer<Darwin.sigaction>?,
  previousAction: UnsafeMutablePointer<Darwin.sigaction>?
) -> Int32 {
  let implementation:
    (Int32, UnsafePointer<Darwin.sigaction>?, UnsafeMutablePointer<Darwin.sigaction>?) -> Int32 =
      sigaction
  return implementation(signal, action, previousAction)
}
