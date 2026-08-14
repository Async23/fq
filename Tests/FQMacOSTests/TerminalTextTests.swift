import XCTest

@testable import FQMacOS

final class TerminalTextTests: XCTestCase {
  func testPreservesOrdinaryUnicodeText() {
    XCTAssertEqual(TerminalText.sanitize("访达 Preview"), "访达 Preview")
  }

  func testReplacesControlAndBidirectionalOverrideCharacters() {
    XCTAssertEqual(
      TerminalText.sanitize("Bad\u{001B}[31m\nName\u{202E}"),
      "Bad [31m Name "
    )
  }
}
