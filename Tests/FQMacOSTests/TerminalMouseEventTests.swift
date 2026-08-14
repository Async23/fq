import XCTest

@testable import FQMacOS

final class TerminalMouseEventTests: XCTestCase {
  func testParsesLeftClickAndWheelEventsFromSGRPayloads() {
    XCTAssertEqual(
      TerminalMouseEvent.parse(sgrPayload: "0;12;4", terminator: "M"),
      TerminalMouseEvent(action: .leftPress, column: 12, row: 4)
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

  func testRejectsReleaseMotionUnsupportedButtonsAndMalformedCoordinates() {
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "0;12;4", terminator: "m"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "32;12;4", terminator: "M"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "1;12;4", terminator: "M"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "66;12;4", terminator: "M"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "128;12;4", terminator: "M"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "0;0;4", terminator: "M"))
    XCTAssertNil(TerminalMouseEvent.parse(sgrPayload: "not-mouse", terminator: "M"))
  }
}
