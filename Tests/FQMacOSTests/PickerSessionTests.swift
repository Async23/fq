import XCTest

@testable import FQCore
@testable import FQMacOS

final class PickerSessionTests: XCTestCase {
  private let applications = [
    pickerCandidate(pid: 11, name: "Alpha"),
    pickerCandidate(pid: 22, name: "Bravo"),
    pickerCandidate(pid: 33, name: "Charlie"),
  ]

  func testDefaultActionOpensCommandConfirmationAndEnterReturnsSafely() {
    var session = makeSession(defaultAction: .forceQuit)
    let plan = ApplicationExitPlan(
      applications: [applications[0]],
      action: .forceQuit
    )

    XCTAssertEqual(session.handle(.enter), .stay(redraw: true))
    XCTAssertEqual(
      session.phase,
      .confirming(PickerConfirmation(plan: plan))
    )
    XCTAssertEqual(session.handle(.enter), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)

    _ = session.handle(.enter)
    XCTAssertEqual(
      session.handle(.confirmExit),
      .select(plan)
    )
  }

  func testForceConfirmationCanReturnToBrowsingWithoutExiting() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.enter)

    XCTAssertEqual(session.handle(.escape), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
    XCTAssertEqual(session.state.selectedApplication, applications[0])
  }

  func testConfirmationCommandsCanBeActivatedDirectlyByMouse() {
    var cancelSession = makeSession(defaultAction: .forceQuit)
    _ = cancelSession.handle(.enter)
    XCTAssertEqual(
      cancelSession.handle(.cancelExit),
      .stay(redraw: true)
    )
    XCTAssertEqual(cancelSession.phase, .browse)

    var executeSession = makeSession(defaultAction: .forceQuit)
    _ = executeSession.handle(.enter)
    XCTAssertEqual(
      executeSession.handle(.confirmExit),
      .select(
        ApplicationExitPlan(applications: [applications[0]], action: .forceQuit)
      )
    )

    var unavailableSession = makeSession(defaultAction: .forceQuit)
    _ = unavailableSession.handle(.enter)
    _ = unavailableSession.replaceApplications(Array(applications.dropFirst()))
    XCTAssertEqual(
      unavailableSession.handle(.confirmExit),
      .stay(redraw: false)
    )
    XCTAssertFalse(unavailableSession.isConfirmationTargetAvailable)
  }

  func testConfirmationIgnoresNavigationAndTabInput() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.enter)
    let confirmation = session.phase

    for event in [PickerEvent.move(-1), .moveHorizontal(-1), .cycleFocus] {
      XCTAssertEqual(session.handle(event), .stay(redraw: false))
      XCTAssertEqual(session.phase, confirmation)
    }
  }

  func testConfirmationUsesYesToExecuteAndCommonReturnKeysToCancel() {
    let expectedPlan = ApplicationExitPlan(
      applications: [applications[0]],
      action: .forceQuit
    )

    var yesSession = makeSession(defaultAction: .forceQuit)
    _ = yesSession.handle(.enter)
    XCTAssertEqual(yesSession.handle(.text("Y")), .stay(redraw: false))
    _ = yesSession.handle(.inputIdle)
    XCTAssertEqual(yesSession.handle(.text("Y")), .select(expectedPlan))

    var spaceSession = makeSession(defaultAction: .forceQuit)
    _ = spaceSession.handle(.enter)
    XCTAssertEqual(spaceSession.handle(.text(" ")), .stay(redraw: true))
    XCTAssertEqual(spaceSession.phase, .browse)

    var directSession = makeSession(defaultAction: .forceQuit)
    _ = directSession.handle(.enter)
    XCTAssertEqual(directSession.handle(.confirmExit), .select(expectedPlan))

    for cancelEvent in [PickerEvent.text("n"), .text("N"), .backspace] {
      var cancelSession = makeSession(defaultAction: .forceQuit)
      _ = cancelSession.handle(.enter)
      XCTAssertEqual(cancelSession.handle(cancelEvent), .stay(redraw: true))
      XCTAssertEqual(cancelSession.phase, .browse)
    }

    var unavailableSession = makeSession(defaultAction: .forceQuit)
    _ = unavailableSession.handle(.enter)
    _ = unavailableSession.handle(.inputIdle)
    _ = unavailableSession.replaceApplications(Array(applications.dropFirst()))
    XCTAssertEqual(unavailableSession.handle(.text("y")), .stay(redraw: false))
  }

  func testActionShortcutsFollowBtopTerminateAndUppercaseKillKeys() {
    var terminateSession = makeSession(defaultAction: .forceQuit)
    XCTAssertEqual(
      terminateSession.handle(.text("t")),
      .stay(redraw: true)
    )
    XCTAssertEqual(
      terminateSession.phase,
      .confirming(
        PickerConfirmation(
          plan: ApplicationExitPlan(applications: [applications[0]], action: .quit)
        )
      )
    )
    XCTAssertEqual(
      terminateSession.handle(.confirmExit),
      .select(ApplicationExitPlan(applications: [applications[0]], action: .quit))
    )

    var killSession = makeSession(defaultAction: .quit)
    XCTAssertEqual(killSession.handle(.text("K")), .stay(redraw: true))
    XCTAssertEqual(
      killSession.phase,
      .confirming(
        PickerConfirmation(
          plan: ApplicationExitPlan(
            applications: [applications[0]],
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
      XCTAssertEqual(session.state.query, "")
    }
  }

  func testBracketedPasteIsAtomicAndSafeInBrowseMode() {
    var session = makeSession(defaultAction: .forceQuit)

    XCTAssertEqual(session.handle(.paste("typora keynote")), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
    XCTAssertEqual(session.state.query, "")
    XCTAssertNil(session.confirmationPlan)
    XCTAssertEqual(session.statusMessage, "粘贴筛选请先按 f 或 /")
  }

  func testBracketedPasteNormalizesAndInsertsTextAtTheFilterCursor() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.text("f"))
    _ = session.handle(.paste("  Ghostty\n\t访达  "))

    XCTAssertEqual(session.state.query, " Ghostty 访达 ")
    XCTAssertEqual(session.filterCursorOffset, 12)
  }

  func testBracketedPasteCannotConfirmAnArmedAction() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.enter)
    _ = session.handle(.inputIdle)
    let confirmation = session.phase

    XCTAssertEqual(session.handle(.paste("y")), .stay(redraw: false))
    XCTAssertEqual(session.phase, confirmation)
  }

  func testBrowseUsesVimNavigationAndUppercaseActionKeys() {
    var session = makeSession(defaultAction: .quit)

    XCTAssertEqual(session.handle(.text("j")), .stay(redraw: true))
    XCTAssertEqual(session.state.selectedApplication, applications[1])
    XCTAssertEqual(session.handle(.text("k")), .stay(redraw: true))
    XCTAssertEqual(session.state.selectedApplication, applications[0])

    _ = session.handle(.text("l"))
    XCTAssertEqual(session.state.sortOrder, .name)
    _ = session.handle(.text("h"))
    XCTAssertEqual(session.state.sortOrder, .smart)

    XCTAssertEqual(session.handle(.text("H")), .stay(redraw: true))
    XCTAssertEqual(session.phase, .help)
    _ = session.handle(.text("H"))
    XCTAssertEqual(session.phase, .browse)

    XCTAssertEqual(session.handle(.text("K")), .stay(redraw: true))
    XCTAssertEqual(session.confirmationPlan?.action, .forceQuit)
  }

  func testSpaceMarksMultipleApplicationsAndActionsUseTheMarkedBatch() {
    var session = makeSession(defaultAction: .quit)

    XCTAssertEqual(session.handle(.text(" ")), .stay(redraw: true))
    _ = session.handle(.text("j"))
    _ = session.handle(.text(" "))

    XCTAssertEqual(
      session.markedApplicationIdentities,
      [applications[0].id, applications[1].id]
    )
    XCTAssertEqual(session.handle(.text("K")), .stay(redraw: true))

    let expectedPlan = ApplicationExitPlan(
      applications: [applications[0], applications[1]],
      action: .forceQuit
    )
    XCTAssertEqual(session.confirmationPlan, expectedPlan)
    XCTAssertEqual(session.confirmationAvailableApplications, expectedPlan.applications)

    XCTAssertEqual(session.handle(.confirmExit), .select(expectedPlan))
  }

  func testVisualRangeSelectionExtendsShrinksCommitsAndCanBeCancelled() {
    var session = makeSession(defaultAction: .forceQuit)

    _ = session.handle(.text("v"))
    XCTAssertEqual(session.markedApplicationIdentities, [applications[0].id])
    _ = session.handle(.text("j"))
    _ = session.handle(.text("j"))
    XCTAssertEqual(session.markedApplicationIdentities, applications.map(\.id))

    _ = session.handle(.text("k"))
    XCTAssertEqual(
      session.markedApplicationIdentities,
      Array(applications.prefix(2)).map(\.id)
    )
    _ = session.handle(.text("v"))
    XCTAssertEqual(session.statusMessage, "范围标记已保留")

    _ = session.handle(.text("v"))
    _ = session.handle(.text("j"))
    _ = session.handle(.escape)
    XCTAssertEqual(
      session.markedApplicationIdentities,
      Array(applications.prefix(2)).map(\.id)
    )
    XCTAssertEqual(session.phase, .browse)
  }

  func testBulkSelectionCommandsOperateOnVisibleApplications() {
    var session = makeSession(defaultAction: .forceQuit)

    _ = session.handle(.text("a"))
    XCTAssertEqual(session.markedApplicationIdentities, applications.map(\.id))

    _ = session.handle(.text("i"))
    XCTAssertTrue(session.markedApplicationIdentities.isEmpty)

    _ = session.handle(.text(" "))
    _ = session.handle(.text("i"))
    XCTAssertEqual(
      session.markedApplicationIdentities,
      Array(applications.dropFirst()).map(\.id)
    )

    _ = session.handle(.text("x"))
    XCTAssertTrue(session.markedApplicationIdentities.isEmpty)
  }

  func testBulkSelectionCommandsRespectFilterAndPreserveHiddenMarks() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.text(" "))
    _ = session.handle(.text("f"))
    _ = session.handle(.text("b"))
    _ = session.handle(.text("r"))
    _ = session.handle(.enter)

    XCTAssertEqual(session.state.visibleApplications, [applications[1]])

    _ = session.handle(.text("a"))
    XCTAssertEqual(
      session.markedApplicationIdentities,
      [applications[0].id, applications[1].id]
    )

    _ = session.handle(.text("i"))
    XCTAssertEqual(session.markedApplicationIdentities, [applications[0].id])

    _ = session.handle(.text("x"))
    XCTAssertTrue(session.markedApplicationIdentities.isEmpty)
  }

  func testRangeSelectionFreezesDisplayAndAppliesLatestSnapshotWhenFinished() {
    let refreshedBravo = pickerCandidate(pid: 22, name: "Bravo", isActive: true)
    let delta = pickerCandidate(pid: 44, name: "Delta")
    let latestApplications = [applications[2], refreshedBravo, delta]

    var commitSession = makeSession(defaultAction: .forceQuit)
    _ = commitSession.handle(.text("v"))
    _ = commitSession.handle(.text("j"))

    XCTAssertFalse(commitSession.replaceApplications(latestApplications))
    XCTAssertEqual(commitSession.state.applications, applications)
    XCTAssertEqual(
      commitSession.markedApplicationIdentities,
      Array(applications.prefix(2)).map(\.id)
    )

    _ = commitSession.handle(.text("v"))
    XCTAssertEqual(commitSession.state.applications, latestApplications)
    XCTAssertEqual(commitSession.state.selectedApplication, refreshedBravo)
    XCTAssertEqual(commitSession.markedApplicationIdentities, [refreshedBravo.id])

    var cancelSession = makeSession(defaultAction: .forceQuit)
    _ = cancelSession.handle(.text("v"))
    _ = cancelSession.handle(.text("j"))
    XCTAssertFalse(cancelSession.replaceApplications(latestApplications))

    _ = cancelSession.handle(.escape)
    XCTAssertEqual(cancelSession.state.applications, latestApplications)
    XCTAssertTrue(cancelSession.markedApplicationIdentities.isEmpty)
  }

  func testActionDoesNotFallThroughToANeighbourWhenASelectedRangeExits() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.text("v"))

    XCTAssertFalse(session.replaceApplications(Array(applications.dropFirst())))
    XCTAssertEqual(session.handle(.text("K")), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
    XCTAssertNil(session.confirmationPlan)
    XCTAssertEqual(session.statusMessage, "已标记的应用均已退出")
  }

  func testDefaultAndQuitActionsAlsoUseTheMarkedBatch() {
    for (event, action) in [
      (PickerEvent.enter, ApplicationExitAction.quit),
      (.text("t"), .quit),
      (.text("K"), .forceQuit),
    ] {
      var session = makeSession(defaultAction: .quit)
      _ = session.handle(.text(" "))
      _ = session.handle(.text("j"))
      _ = session.handle(.text(" "))

      XCTAssertEqual(session.handle(event), .stay(redraw: true))
      XCTAssertEqual(
        session.confirmationPlan,
        ApplicationExitPlan(applications: Array(applications.prefix(2)), action: action)
      )
    }
  }

  func testVimAndMarkingKeysRemainLiteralWhileFiltering() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.text("f"))

    for key in ["h", "j", "k", "l", " ", "v", "a", "i", "x"] {
      _ = session.handle(.text(key))
    }

    XCTAssertEqual(session.state.query, "hjkl vaix")
    XCTAssertTrue(session.markedApplicationIdentities.isEmpty)
    guard case .filtering = session.phase else {
      return XCTFail("Expected filtering phase")
    }
  }

  func testMarkedApplicationsSurviveFilteringAndRefreshByIdentity() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.text(" "))
    _ = session.handle(.text("j"))
    _ = session.handle(.text(" "))
    _ = session.handle(.text("f"))
    _ = session.handle(.text("c"))

    XCTAssertEqual(session.markedApplicationIdentities.count, 2)

    let refreshedBravo = pickerCandidate(pid: 22, name: "Bravo", isActive: true)
    _ = session.replaceApplications([applications[2], refreshedBravo])

    XCTAssertEqual(session.markedApplicationIdentities, [applications[1].id])
    XCTAssertTrue(session.isMarked(refreshedBravo))
  }

  func testPausedBatchSkipsTargetsThatExitedBeforeConfirmation() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.text(" "))
    _ = session.handle(.text("j"))
    _ = session.handle(.text(" "))
    _ = session.handle(.text("u"))
    _ = session.replaceApplications([applications[1], applications[2]])

    _ = session.handle(.text("K"))

    XCTAssertEqual(session.confirmationPlan?.applications, [applications[0], applications[1]])
    XCTAssertEqual(session.confirmationAvailableApplications, [applications[1]])
    XCTAssertEqual(session.unavailableConfirmationTargetCount, 1)

    XCTAssertEqual(
      session.handle(.confirmExit),
      .select(ApplicationExitPlan(applications: [applications[1]], action: .forceQuit))
    )
  }

  func testBatchConfirmationRequiresFreshYesAfterATargetExits() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.text(" "))
    _ = session.handle(.text("j"))
    _ = session.handle(.text(" "))
    _ = session.handle(.text("K"))
    _ = session.handle(.inputIdle)

    XCTAssertTrue(session.replaceApplications(Array(applications.dropFirst())))
    XCTAssertEqual(session.confirmationAvailableApplications, [applications[1]])
    XCTAssertEqual(session.handle(.text("y")), .stay(redraw: false))
    _ = session.handle(.inputIdle)
    XCTAssertEqual(
      session.handle(.text("y")),
      .select(ApplicationExitPlan(applications: [applications[1]], action: .forceQuit))
    )
  }

  func testFilterEditingAppliesLiveAndEscapeRestoresPreviousQuery() {
    var session = PickerSession(
      applications: applications,
      initialQuery: "a",
      defaultAction: .forceQuit
    )
    _ = session.handle(.move(1))

    XCTAssertEqual(session.handle(.text("f")), .stay(redraw: true))
    XCTAssertEqual(
      session.phase,
      .filtering(
        PickerFilterEdit(
          query: "a",
          selectedIdentity: applications[1].id,
          selectedIndex: 1
        )
      )
    )

    _ = session.handle(.text("q"))
    XCTAssertEqual(session.state.query, "aq")
    XCTAssertTrue(session.state.visibleApplications.isEmpty)

    XCTAssertEqual(session.handle(.escape), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)
    XCTAssertEqual(session.state.query, "a")
    XCTAssertEqual(session.state.selectedApplication, applications[1])
  }

  func testCancellingUnchangedFilterKeepsTheCurrentApplicationSelected() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.last)

    _ = session.handle(.text("f"))
    XCTAssertEqual(session.handle(.escape), .stay(redraw: true))

    XCTAssertEqual(session.phase, .browse)
    XCTAssertEqual(session.state.query, "")
    XCTAssertEqual(session.state.selectedApplication, applications[2])
    XCTAssertEqual(session.state.selectedIndex, 2)
  }

  func testCancellingFilterRestoresIdentityAcrossRefreshAndFallsBackToOriginalRow() {
    var reorderedSession = makeSession(defaultAction: .forceQuit)
    _ = reorderedSession.handle(.move(1))
    _ = reorderedSession.handle(.text("f"))
    _ = reorderedSession.handle(.text("z"))
    _ = reorderedSession.replaceApplications([
      applications[2], applications[1], applications[0],
    ])

    _ = reorderedSession.handle(.escape)
    XCTAssertEqual(reorderedSession.state.selectedApplication, applications[1])
    XCTAssertEqual(reorderedSession.state.selectedIndex, 1)

    var exitedSession = makeSession(defaultAction: .forceQuit)
    _ = exitedSession.handle(.move(1))
    _ = exitedSession.handle(.text("f"))
    _ = exitedSession.handle(.text("z"))
    _ = exitedSession.replaceApplications([applications[0], applications[2]])

    _ = exitedSession.handle(.escape)
    XCTAssertEqual(exitedSession.state.selectedApplication, applications[2])
    XCTAssertEqual(exitedSession.state.selectedIndex, 1)
  }

  func testCancellingBrowseBackspaceRestoresItsQueryAndSelectionSnapshot() {
    var session = PickerSession(
      applications: applications,
      initialQuery: "a",
      defaultAction: .forceQuit
    )
    _ = session.handle(.last)

    _ = session.handle(.backspace)
    XCTAssertEqual(session.state.query, "")
    XCTAssertNotNil(session.filterCursorOffset)

    _ = session.handle(.escape)
    XCTAssertEqual(session.state.query, "a")
    XCTAssertEqual(session.state.selectedApplication, applications[2])
  }

  func testBrowseTextDoesNotStartFilteringAndShowsHowToFilter() {
    var session = makeSession(defaultAction: .forceQuit)

    _ = session.handle(.text("b"))

    XCTAssertEqual(session.phase, .browse)
    XCTAssertEqual(session.state.query, "")
    XCTAssertEqual(session.statusMessage, "筛选请先按 f 或 /")
    _ = session.handle(.inputIdle)
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
    XCTAssertEqual(session.handle(.text("h")), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)

    _ = session.handle(.text("H"))
    XCTAssertEqual(session.phase, .help)
    XCTAssertEqual(session.handle(.text("?")), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)

    XCTAssertEqual(session.handle(.help), .stay(redraw: true))
    XCTAssertEqual(session.phase, .help)
    XCTAssertEqual(session.handle(.help), .stay(redraw: true))
    XCTAssertEqual(session.phase, .browse)

    XCTAssertEqual(session.handle(.text("q")), .cancel)
  }

  func testF1DoesNotDisruptFilteringOrConfirmation() {
    var filteringSession = makeSession(defaultAction: .forceQuit)
    _ = filteringSession.handle(.text("f"))
    let filteringPhase = filteringSession.phase

    XCTAssertEqual(filteringSession.handle(.help), .stay(redraw: false))
    XCTAssertEqual(filteringSession.phase, filteringPhase)

    var confirmingSession = makeSession(defaultAction: .forceQuit)
    _ = confirmingSession.handle(.enter)
    let confirmingPhase = confirmingSession.phase

    XCTAssertEqual(confirmingSession.handle(.help), .stay(redraw: false))
    XCTAssertEqual(confirmingSession.phase, confirmingPhase)
  }

  func testSuspendPreservesTheCurrentPickerPhaseAndState() {
    var filteringSession = makeSession(defaultAction: .forceQuit)
    _ = filteringSession.handle(.move(1))
    _ = filteringSession.handle(.text("f"))
    _ = filteringSession.handle(.text("r"))
    let filteringPhase = filteringSession.phase
    let filteringState = filteringSession.state

    XCTAssertEqual(filteringSession.handle(.suspend), .suspend)
    XCTAssertEqual(filteringSession.phase, filteringPhase)
    XCTAssertEqual(filteringSession.state, filteringState)

    var confirmingSession = makeSession(defaultAction: .forceQuit)
    _ = confirmingSession.handle(.enter)
    let confirmingPhase = confirmingSession.phase

    XCTAssertEqual(confirmingSession.handle(.suspend), .suspend)
    XCTAssertEqual(confirmingSession.phase, confirmingPhase)

    var helpSession = makeSession(defaultAction: .forceQuit)
    _ = helpSession.handle(.text("H"))
    XCTAssertEqual(helpSession.handle(.suspend), .suspend)
    XCTAssertEqual(helpSession.phase, .help)
  }

  func testViewportScrollingKeepsTheSelectionOnItsScreenRow() {
    let manyApplications = (1...20).map { index in
      pickerCandidate(pid: Int32(index), name: "App \(index)")
    }
    var session = PickerSession(
      applications: manyApplications,
      initialQuery: "",
      defaultAction: .forceQuit
    )
    session.synchronizeViewport(listRows: 6)

    _ = session.handle(.move(5))
    XCTAssertEqual(session.state.selectedIndex, 5)
    XCTAssertEqual(session.visibleApplicationRange(listRows: 6), 0..<6)

    _ = session.handle(.positionViewport(startIndex: 6, listRows: 6))
    XCTAssertEqual(session.state.selectedIndex, 11)
    XCTAssertEqual(session.visibleApplicationRange(listRows: 6), 6..<12)

    _ = session.handle(.move(-1))
    XCTAssertEqual(session.state.selectedIndex, 10)
    XCTAssertEqual(session.visibleApplicationRange(listRows: 6), 6..<12)

    _ = session.handle(.positionViewport(startIndex: 100, listRows: 6))
    XCTAssertEqual(session.state.selectedIndex, 18)
    XCTAssertEqual(session.visibleApplicationRange(listRows: 6), 14..<20)
  }

  func testCancellingFilterRestoresThePreviousViewport() {
    let manyApplications = (1...20).map { index in
      pickerCandidate(pid: Int32(index), name: "App \(index)")
    }
    var session = PickerSession(
      applications: manyApplications,
      initialQuery: "",
      defaultAction: .forceQuit
    )
    session.synchronizeViewport(listRows: 6)
    _ = session.handle(.positionViewport(startIndex: 9, listRows: 6))
    _ = session.handle(.move(2))
    let selectedApplication = session.state.selectedApplication

    _ = session.handle(.text("f"))
    _ = session.handle(.text("z"))
    _ = session.replaceApplications(Array(manyApplications.reversed()))
    XCTAssertEqual(session.viewportStartIndex, 0)
    XCTAssertTrue(session.state.visibleApplications.isEmpty)

    _ = session.handle(.escape)
    XCTAssertEqual(session.state.selectedApplication, selectedApplication)
    XCTAssertEqual(session.state.selectedIndex, 8)
    XCTAssertEqual(session.visibleApplicationRange(listRows: 6), 6..<12)
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

  func testResumeDiscardsMarksForApplicationsThatExitedWhilePaused() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.text(" "))
    _ = session.handle(.text("j"))
    _ = session.handle(.text(" "))
    _ = session.handle(.text("u"))

    XCTAssertFalse(session.replaceApplications(Array(applications.dropFirst())))
    XCTAssertEqual(session.markedApplicationIdentities.count, 2)

    _ = session.handle(.text("u"))

    XCTAssertEqual(session.markedApplicationIdentities, [applications[1].id])
  }

  func testPausedConfirmationUsesLatestSnapshotToDisableMissingTarget() {
    var session = makeSession(defaultAction: .forceQuit)
    _ = session.handle(.text("u"))
    _ = session.handle(.enter)
    _ = session.handle(.inputIdle)

    XCTAssertTrue(session.replaceApplications(Array(applications.dropFirst())))
    XCTAssertTrue(session.isPaused)
    XCTAssertEqual(session.state.applications, applications)
    XCTAssertEqual(session.confirmationPlan?.applications, [applications[0]])
    XCTAssertFalse(session.isConfirmationTargetAvailable)
    XCTAssertEqual(session.handle(.text("y")), .stay(redraw: false))

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
    _ = session.handle(.inputIdle)

    XCTAssertTrue(session.replaceApplications(Array(applications.dropFirst())))
    XCTAssertEqual(session.confirmationPlan?.applications, [applications[0]])
    XCTAssertFalse(session.isConfirmationTargetAvailable)
    XCTAssertEqual(session.handle(.text("y")), .stay(redraw: false))

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
