import XCTest

@testable import FQCore
@testable import FQMacOS

final class PickerSessionTests: XCTestCase {
  private let applications = [
    pickerCandidate(pid: 11, name: "Alpha"),
    pickerCandidate(pid: 22, name: "Bravo"),
    pickerCandidate(pid: 33, name: "Charlie"),
  ]

  func testDefaultActionOpensCancelFocusedConfirmation() {
    var session = makeSession(defaultAction: .forceQuit)
    let selection = ApplicationExitSelection(
      application: applications[0],
      action: .forceQuit
    )

    XCTAssertEqual(session.handle(.enter), .stay(redraw: true))
    XCTAssertEqual(
      session.phase,
      .confirming(PickerConfirmation(selection: selection, choice: .cancel))
    )
    XCTAssertEqual(session.handle(.enter), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)

    _ = session.handle(.enter)
    XCTAssertEqual(session.handle(.cycleFocus), .stay(redraw: true))
    XCTAssertEqual(
      session.handle(.enter),
      .select(selection)
    )
  }

  func testForceConfirmationCanReturnToBrowsingWithoutExiting() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.enter)

    XCTAssertEqual(session.handle(.escape), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
    XCTAssertEqual(session.state.selectedApplication, applications[0])
  }

  func testConfirmationUsesHorizontalOrTabInputButNotVerticalMovement() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.enter)

    XCTAssertEqual(session.handle(.move(-1)), .stay(redraw: false))
    XCTAssertEqual(session.confirmationChoice, .cancel)

    _ = session.handle(.moveHorizontal(-1))
    XCTAssertEqual(session.confirmationChoice, .execute)

    _ = session.handle(.cycleFocus)
    XCTAssertEqual(session.confirmationChoice, .cancel)
  }

  func testActionShortcutsFollowBtopTerminateAndKillKeys() {
    var terminateSession = makeSession(defaultAction: .forceQuit)
    XCTAssertEqual(
      terminateSession.handle(.text("t")),
      .stay(redraw: true)
    )
    XCTAssertEqual(
      terminateSession.phase,
      .confirming(
        PickerConfirmation(
          selection: ApplicationExitSelection(application: applications[0], action: .quit)
        )
      )
    )
    _ = terminateSession.handle(.cycleFocus)
    XCTAssertEqual(
      terminateSession.handle(.enter),
      .select(ApplicationExitSelection(application: applications[0], action: .quit))
    )

    var killSession = makeSession(defaultAction: .quit)
    XCTAssertEqual(killSession.handle(.text("k")), .stay(redraw: true))
    XCTAssertEqual(
      killSession.phase,
      .confirming(
        PickerConfirmation(
          selection: ApplicationExitSelection(
            application: applications[0],
            action: .forceQuit
          )
        )
      )
    )
  }

  func testPastedApplicationNameCannotAccidentallyExecuteAnAction() {
    for pastedText in ["typora", "keynote"] {
      var session = makeSession(defaultAction: .forceQuit)
      let decisions = pastedText.map { character in
        session.handle(.text(String(character)))
      }

      XCTAssertFalse(
        decisions.contains(where: { decision in
          if case .select = decision {
            return true
          }
          return false
        })
      )
      XCTAssertEqual(session.confirmationChoice, .cancel)
      XCTAssertEqual(session.state.query, "")
    }
  }

  func testFilterEditingAppliesLiveAndEscapeRestoresPreviousQuery() {
    var session = PickerSession(
      applications: applications,
      initialQuery: "a",
      defaultAction: .forceQuit
    )

    XCTAssertEqual(session.handle(.text("f")), .stay(redraw: true))
    XCTAssertEqual(session.phase, .filtering(PickerFilterEdit(query: "a")))

    _ = session.handle(.text("q"))
    XCTAssertEqual(session.state.query, "aq")
    XCTAssertTrue(session.state.visibleApplications.isEmpty)

    XCTAssertEqual(session.handle(.escape), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
    XCTAssertEqual(session.state.query, "a")
  }

  func testBrowseTextDoesNotStartFilteringAndShowsHowToFilter() {
    var session = makeSession(defaultAction: .forceQuit)

    _ = session.handle(.text("b"))

    XCTAssertEqual(session.phase, .browse)
    XCTAssertEqual(session.state.query, "")
    XCTAssertEqual(session.statusMessage, "筛选请先按 f 或 /")

    _ = session.handle(.text("/"))
    _ = session.handle(.text("b"))
    _ = session.handle(.text("r"))

    guard case .filtering(let edit) = session.phase else {
      return XCTFail("Expected filtering phase")
    }
    XCTAssertEqual(edit.originalQuery, "")
    XCTAssertEqual(edit.cursorOffset, 2)
    XCTAssertEqual(session.state.query, "br")
    XCTAssertEqual(session.handle(.enter), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
  }

  func testFilterEditorSupportsUnicodeCursorInsertionAndDeletion() {
    var session = PickerSession(
      applications: applications,
      initialQuery: "A访👨‍💻Z",
      defaultAction: .forceQuit
    )
    _ = session.handle(.text("f"))

    XCTAssertEqual(session.filterCursorOffset, 4)
    XCTAssertEqual(session.handle(.first), .stay(redraw: true))
    XCTAssertEqual(session.filterCursorOffset, 0)
    _ = session.handle(.moveHorizontal(2))
    XCTAssertEqual(session.filterCursorOffset, 2)

    _ = session.handle(.text("新"))
    XCTAssertEqual(session.state.query, "A访新👨‍💻Z")
    XCTAssertEqual(session.filterCursorOffset, 3)

    _ = session.handle(.backspace)
    XCTAssertEqual(session.state.query, "A访👨‍💻Z")
    XCTAssertEqual(session.filterCursorOffset, 2)

    _ = session.handle(.deleteForward)
    XCTAssertEqual(session.state.query, "A访Z")
    XCTAssertEqual(session.filterCursorOffset, 2)

    _ = session.handle(.last)
    _ = session.handle(.backspace)
    XCTAssertEqual(session.state.query, "A访")
    XCTAssertEqual(session.filterCursorOffset, 2)

    _ = session.handle(.clear)
    XCTAssertEqual(session.state.query, "")
    XCTAssertEqual(session.filterCursorOffset, 0)

    _ = session.handle(.escape)
    XCTAssertEqual(session.state.query, "A访👨‍💻Z")
    XCTAssertEqual(session.phase, .browse)
  }

  func testFilterDownAppliesQueryAndMovesWhileUpKeepsEditing() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.text("f"))
    _ = session.handle(.text("a"))

    XCTAssertEqual(session.handle(.move(-1)), .stay(redraw: false))
    XCTAssertNotNil(session.filterCursorOffset)

    XCTAssertEqual(session.handle(.move(1)), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
    XCTAssertEqual(session.state.selectedApplication?.name, "Bravo")
  }

  func testBrowseCommandsClearNavigateHelpAndCancel() {
    var session = PickerSession(
      applications: applications,
      initialQuery: "a",
      defaultAction: .forceQuit
    )

    _ = session.handle(.deleteForward)
    XCTAssertEqual(session.state.query, "")

    _ = session.handle(.last)
    XCTAssertEqual(session.state.selectedApplication?.name, "Charlie")

    _ = session.handle(.text("?"))
    XCTAssertEqual(session.phase, .help)
    XCTAssertEqual(session.handle(.text("?")), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)

    XCTAssertEqual(session.handle(.text("q")), .cancel)
  }

  func testBrowseHorizontalAndReverseCommandsControlSorting() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.move(1))
    XCTAssertEqual(session.state.selectedApplication?.name, "Bravo")

    XCTAssertEqual(session.handle(.moveHorizontal(1)), .stay(redraw: true))
    XCTAssertEqual(session.state.sortOrder, .name)
    XCTAssertEqual(session.state.selectedApplication?.name, "Bravo")

    XCTAssertEqual(session.handle(.text("r")), .stay(redraw: true))
    XCTAssertTrue(session.state.isSortReversed)
    XCTAssertEqual(session.state.selectedApplication?.name, "Bravo")
  }

  func testPauseFreezesDisplayedApplicationsAndResumeAppliesLatestSnapshot() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.move(1))
    let refreshedBravo = pickerCandidate(pid: 22, name: "Bravo", isActive: true)
    let delta = pickerCandidate(pid: 44, name: "Delta")
    let latestApplications = [applications[2], refreshedBravo, delta]

    XCTAssertEqual(session.handle(.text("u")), .stay(redraw: true))
    XCTAssertTrue(session.isPaused)
    XCTAssertFalse(session.replaceApplications(latestApplications))
    XCTAssertEqual(session.state.applications, applications)
    XCTAssertEqual(session.state.selectedApplication, applications[1])

    XCTAssertEqual(session.handle(.text("u")), .stay(redraw: true))
    XCTAssertFalse(session.isPaused)
    XCTAssertEqual(session.state.applications, latestApplications)
    XCTAssertEqual(session.state.selectedApplication, refreshedBravo)
  }

  func testPausedConfirmationUsesLatestSnapshotToDisableMissingTarget() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.text("u"))
    _ = session.handle(.enter)
    _ = session.handle(.cycleFocus)

    XCTAssertTrue(session.replaceApplications(Array(applications.dropFirst())))
    XCTAssertTrue(session.isPaused)
    XCTAssertEqual(session.state.applications, applications)
    XCTAssertEqual(session.confirmationSelection?.application, applications[0])
    XCTAssertFalse(session.isConfirmationTargetAvailable)
    XCTAssertEqual(session.confirmationChoice, .cancel)

    XCTAssertEqual(session.handle(.enter), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
  }

  func testRefreshPreservesSelectionAndUpdatesCandidateMetadata() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.move(1))
    let refreshedBravo = pickerCandidate(pid: 22, name: "Bravo", isActive: true)

    XCTAssertTrue(session.replaceApplications([applications[2], refreshedBravo]))

    XCTAssertEqual(session.state.selectedApplication, refreshedBravo)
    XCTAssertEqual(session.state.selectedIndex, 1)
    XCTAssertFalse(session.replaceApplications([applications[2], refreshedBravo]))
  }

  func testConfirmationRemainsPinnedWhenTargetDisappearsDuringRefresh() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.enter)
    _ = session.handle(.cycleFocus)
    XCTAssertEqual(session.confirmationChoice, .execute)

    XCTAssertTrue(session.replaceApplications(Array(applications.dropFirst())))
    XCTAssertEqual(session.confirmationSelection?.application, applications[0])
    XCTAssertFalse(session.isConfirmationTargetAvailable)
    XCTAssertEqual(session.confirmationChoice, .cancel)

    XCTAssertEqual(session.handle(.enter), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
    XCTAssertEqual(session.state.selectedApplication, applications[1])
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
