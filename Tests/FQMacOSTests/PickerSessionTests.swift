import XCTest

@testable import FQCore
@testable import FQMacOS

final class PickerSessionTests: XCTestCase {
  private let applications = [
    pickerCandidate(pid: 11, name: "Alpha"),
    pickerCandidate(pid: 22, name: "Bravo"),
    pickerCandidate(pid: 33, name: "Charlie"),
  ]

  func testDefaultForceActionRequiresExplicitYConfirmation() {
    var session = makeSession(defaultAction: .forceQuit)

    XCTAssertEqual(session.handle(.enter), .stay(redraw: true))
    XCTAssertEqual(session.phase, .confirming(.forceQuit))
    XCTAssertEqual(session.handle(.enter), .stay(redraw: false))

    XCTAssertEqual(
      session.handle(.text("y")),
      .select(ApplicationExitSelection(application: applications[0], action: .forceQuit))
    )
  }

  func testForceConfirmationCanReturnToBrowsingWithoutExiting() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.enter)

    XCTAssertEqual(session.handle(.escape), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
    XCTAssertEqual(session.state.selectedApplication, applications[0])
  }

  func testActionShortcutsFollowBtopTerminateAndKillKeys() {
    var terminateSession = makeSession(defaultAction: .forceQuit)
    XCTAssertEqual(
      terminateSession.handle(.text("t")),
      .select(ApplicationExitSelection(application: applications[0], action: .quit))
    )

    var killSession = makeSession(defaultAction: .quit)
    XCTAssertEqual(killSession.handle(.text("k")), .stay(redraw: true))
    XCTAssertEqual(killSession.phase, .confirming(.forceQuit))
  }

  func testFilterEditingAppliesLiveAndEscapeRestoresPreviousQuery() {
    var session = PickerSession(
      applications: applications,
      initialQuery: "a",
      defaultAction: .forceQuit
    )

    XCTAssertEqual(session.handle(.text("f")), .stay(redraw: true))
    XCTAssertEqual(session.phase, .filtering(originalQuery: "a"))

    _ = session.handle(.text("q"))
    XCTAssertEqual(session.state.query, "aq")
    XCTAssertTrue(session.state.visibleApplications.isEmpty)

    XCTAssertEqual(session.handle(.escape), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
    XCTAssertEqual(session.state.query, "a")
  }

  func testDirectTypingStartsFilteringAndEnterAppliesIt() {
    var session = makeSession(defaultAction: .forceQuit)

    _ = session.handle(.text("b"))
    _ = session.handle(.text("r"))

    XCTAssertEqual(session.phase, .filtering(originalQuery: ""))
    XCTAssertEqual(session.state.query, "br")
    XCTAssertEqual(session.state.selectedApplication?.name, "Bravo")
    XCTAssertEqual(session.handle(.enter), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
  }

  func testBrowseCommandsClearNavigateHelpAndCancel() {
    var session = PickerSession(
      applications: applications,
      initialQuery: "a",
      defaultAction: .forceQuit
    )

    _ = session.handle(.clear)
    XCTAssertEqual(session.state.query, "")

    _ = session.handle(.last)
    XCTAssertEqual(session.state.selectedApplication?.name, "Charlie")

    _ = session.handle(.text("?"))
    XCTAssertEqual(session.phase, .help)
    XCTAssertEqual(session.handle(.text("?")), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)

    XCTAssertEqual(session.handle(.text("q")), .cancel)
  }

  private func makeSession(defaultAction: ApplicationExitAction) -> PickerSession {
    PickerSession(
      applications: applications,
      initialQuery: "",
      defaultAction: defaultAction
    )
  }
}

private func pickerCandidate(
  pid: Int32,
  name: String,
  bundleIdentifier: String? = nil,
  isActive: Bool = false,
  isHidden: Bool = false
) -> ApplicationCandidate {
  ApplicationCandidate(
    id: ApplicationIdentity(
      processIdentifier: pid,
      bundleIdentifier: bundleIdentifier,
      launchDate: nil
    ),
    name: name,
    isActive: isActive,
    isHidden: isHidden
  )
}
