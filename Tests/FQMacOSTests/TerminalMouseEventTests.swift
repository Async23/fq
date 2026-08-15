import XCTest

@testable import FQCore
@testable import FQMacOS

final class TerminalMouseEventTests: XCTestCase {
  func testParsesLeftClickDragReleaseAndWheelEventsFromSGRPayloads() {
    XCTAssertEqual(
      TerminalMouseEvent.parse(sgrPayload: "0;12;4", terminator: "M"),
      TerminalMouseEvent(action: .leftPress, column: 12, row: 4)
    )
    XCTAssertEqual(
      TerminalMouseEvent.parse(sgrPayload: "32;12;5", terminator: "M"),
      TerminalMouseEvent(action: .leftDrag, column: 12, row: 5)
    )
    XCTAssertEqual(
      TerminalMouseEvent.parse(sgrPayload: "0;12;5", terminator: "m"),
      TerminalMouseEvent(action: .leftRelease, column: 12, row: 5)
    )
    XCTAssertEqual(
      TerminalMouseEvent.parse(sgrPayload: "64;8;9", terminator: "M"),
      TerminalMouseEvent(action: .scrollUp, column: 8, row: 9)
    )
    XCTAssertEqual(
      TerminalMouseEvent.parse(sgrPayload: "65;8;9", terminator: "M"),
      TerminalMouseEvent(action: .scrollDown, column: 8, row: 9)
    )
  }

  func testRejectsUnsupportedButtonsAndMalformedMouseEvents() {
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "32;12;4", terminator: "m"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "1;12;4", terminator: "M"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "1;12;4", terminator: "m"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "66;12;4", terminator: "M"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "128;12;4", terminator: "M"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "0;0;4", terminator: "M"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "not-mouse", terminator: "M"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "0;12;4", terminator: "X"))
  }

  func testScrollbarDragStartsOnlyOnThumbAndStopsOnRelease() {
    let applications = (1...20).map { index in
      mouseCandidate(pid: Int32(index), name: "App \(index)")
    }
    var session = PickerSession(
      applications: applications,
      initialQuery: "",
      defaultAction: .forceQuit
    )
    session.synchronizeViewport(listRows: 6)
    let dimensions = TerminalDimensions(rows: 10, columns: 90)
    var interaction = TerminalMouseInteraction()

    XCTAssertNil(
      interaction.event(
        for: TerminalMouseEvent(action: .leftDrag, column: 88, row: 8),
        session: session,
        dimensions: dimensions
      )
    )
    XCTAssertFalse(interaction.isDraggingScrollbar)

    XCTAssertNil(
      interaction.event(
        for: TerminalMouseEvent(action: .leftPress, column: 88, row: 4),
        session: session,
        dimensions: dimensions
      )
    )
    XCTAssertTrue(interaction.isDraggingScrollbar)

    let dragEvent = interaction.event(
      for: TerminalMouseEvent(action: .leftDrag, column: 40, row: 8),
      session: session,
      dimensions: dimensions
    )
    XCTAssertEqual(dragEvent, .positionViewport(startIndex: 14, listRows: 6))
    if let dragEvent {
      _ = session.handle(dragEvent)
    }
    XCTAssertEqual(session.state.selectedIndex, 14)
    XCTAssertEqual(session.visibleApplicationRange(listRows: 6), 14..<20)

    XCTAssertNil(
      interaction.event(
        for: TerminalMouseEvent(action: .leftRelease, column: 40, row: 8),
        session: session,
        dimensions: dimensions
      )
    )
    XCTAssertFalse(interaction.isDraggingScrollbar)
    XCTAssertNil(
      interaction.event(
        for: TerminalMouseEvent(action: .leftDrag, column: 88, row: 4),
        session: session,
        dimensions: dimensions
      )
    )

    XCTAssertEqual(
      interaction.event(
        for: TerminalMouseEvent(action: .leftPress, column: 88, row: 4),
        session: session,
        dimensions: dimensions
      ),
      .positionViewport(startIndex: 0, listRows: 6)
    )
    XCTAssertFalse(interaction.isDraggingScrollbar)
    XCTAssertNil(
      interaction.event(
        for: TerminalMouseEvent(action: .leftDrag, column: 88, row: 6),
        session: session,
        dimensions: dimensions
      )
    )
  }

  func testMouseWheelMovesTheViewportAndKeepsTheSelectedScreenRow() {
    let applications = (1...20).map { index in
      mouseCandidate(pid: Int32(index), name: "App \(index)")
    }
    var session = PickerSession(
      applications: applications,
      initialQuery: "",
      defaultAction: .forceQuit
    )
    session.synchronizeViewport(listRows: 6)
    _ = session.handle(.move(5))
    var interaction = TerminalMouseInteraction()
    let dimensions = TerminalDimensions(rows: 10, columns: 90)

    let scrollDown = interaction.event(
      for: TerminalMouseEvent(action: .scrollDown, column: 40, row: 6),
      session: session,
      dimensions: dimensions
    )
    XCTAssertEqual(scrollDown, .positionViewport(startIndex: 3, listRows: 6))
    if let scrollDown {
      _ = session.handle(scrollDown)
    }
    XCTAssertEqual(session.state.selectedIndex, 8)
    XCTAssertEqual(session.visibleApplicationRange(listRows: 6), 3..<9)

    let scrollUp = interaction.event(
      for: TerminalMouseEvent(action: .scrollUp, column: 40, row: 6),
      session: session,
      dimensions: dimensions
    )
    XCTAssertEqual(scrollUp, .positionViewport(startIndex: 0, listRows: 6))
    if let scrollUp {
      _ = session.handle(scrollUp)
    }
    XCTAssertEqual(session.state.selectedIndex, 5)
    XCTAssertEqual(session.visibleApplicationRange(listRows: 6), 0..<6)
  }

  func testClickingTheCurrentRowTogglesItsMarkInsteadOfOpeningAnAction() {
    let applications = (1...3).map { index in
      mouseCandidate(pid: Int32(index), name: "App \(index)")
    }
    var session = PickerSession(
      applications: applications,
      initialQuery: "",
      defaultAction: .forceQuit
    )
    var interaction = TerminalMouseInteraction()
    let dimensions = TerminalDimensions(rows: 10, columns: 90)

    let markCurrent = interaction.event(
      for: TerminalMouseEvent(action: .leftPress, column: 10, row: 4),
      session: session,
      dimensions: dimensions
    )
    XCTAssertEqual(markCurrent, .text(" "))
    if let markCurrent {
      _ = session.handle(markCurrent)
    }
    XCTAssertEqual(session.markedApplicationIdentities, [applications[0].id])
    XCTAssertEqual(session.phase, .browse)

    let moveToSecond = interaction.event(
      for: TerminalMouseEvent(action: .leftPress, column: 10, row: 5),
      session: session,
      dimensions: dimensions
    )
    XCTAssertEqual(moveToSecond, .move(1))
  }
}

private func mouseCandidate(pid: Int32, name: String) -> ApplicationCandidate {
  ApplicationCandidate(
    id: ApplicationIdentity(
      processIdentifier: pid,
      bundleIdentifier: "example.\(pid)",
      launchDate: nil
    ),
    name: name
  )
}
