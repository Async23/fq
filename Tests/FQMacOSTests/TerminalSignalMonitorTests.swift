import Darwin
import XCTest

@testable import FQMacOS

final class TerminalSignalMonitorTests: XCTestCase {
  func testWatchesInteractiveSuspendAndTerminationSignals() {
    XCTAssertEqual(
      Set(TerminalSignalMonitor.watchedSignals),
      Set([SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGTSTP])
    )
  }

  func testTerminationTakesPriorityOverSuspendAndKeepsTheFirstSignal() {
    let state = TerminalSignalState()

    state.record(SIGTSTP)
    state.record(SIGTERM)
    state.record(SIGHUP)

    XCTAssertEqual(state.consumeNext(), .terminate(SIGTERM))
    XCTAssertNil(state.consumeNext())
  }

  func testRepeatedSuspendSignalsAreCoalesced() {
    let state = TerminalSignalState()

    state.record(SIGTSTP)
    state.record(SIGTSTP)

    XCTAssertEqual(state.consumeNext(), .suspend)
    XCTAssertNil(state.consumeNext())
  }

  func testUnknownSignalsAreIgnored() {
    let state = TerminalSignalState()

    state.record(SIGUSR1)

    XCTAssertNil(state.consumeNext())
  }
}
