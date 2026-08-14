import XCTest

@testable import FQMacOS

final class TerminalKeySequenceTests: XCTestCase {
  func testParsesSS3NavigationAndF1() {
    XCTAssertEqual(TerminalKeySequence.ss3(final: 65), .up)
    XCTAssertEqual(TerminalKeySequence.ss3(final: 66), .down)
    XCTAssertEqual(TerminalKeySequence.ss3(final: 67), .right)
    XCTAssertEqual(TerminalKeySequence.ss3(final: 68), .left)
    XCTAssertEqual(TerminalKeySequence.ss3(final: 70), .end)
    XCTAssertEqual(TerminalKeySequence.ss3(final: 72), .home)
    XCTAssertEqual(TerminalKeySequence.ss3(final: 80), .help)
    XCTAssertNil(TerminalKeySequence.ss3(final: 81))
  }

  func testParsesCSIKeyboardSequencesWithModifiers() {
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "", final: 65), .up)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "1;5", final: 66), .down)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "1;2", final: 67), .right)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "", final: 68), .left)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "", final: 72), .home)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "", final: 70), .end)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "", final: 90), .backTab)
  }

  func testParsesCSITildeNavigationDeleteAndF1() {
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "1", final: 126), .home)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "3", final: 126), .deleteForward)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "4", final: 126), .end)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "5", final: 126), .pageUp)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "6", final: 126), .pageDown)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "11", final: 126), .help)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "11;2", final: 126), .help)
  }

  func testDistinguishesCSIDeleteVariantFromModifiedF1() {
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "", final: 80), .deleteForward)
    XCTAssertEqual(TerminalKeySequence.csi(parameters: "1;2", final: 80), .help)
  }

  func testRejectsTerminalControlResponsesAndUnknownKeys() {
    XCTAssertNil(TerminalKeySequence.csi(parameters: "?1", final: 65))
    XCTAssertNil(TerminalKeySequence.csi(parameters: "", intermediates: "$", final: 65))
    XCTAssertNil(TerminalKeySequence.csi(parameters: "12", final: 126))
    XCTAssertNil(TerminalKeySequence.csi(parameters: "", final: 81))
  }
}
