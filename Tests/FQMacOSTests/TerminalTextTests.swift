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

  func testDisplayWidthAccountsForWideCharacters() {
    XCTAssertEqual(TerminalText.displayWidth("fq"), 2)
    XCTAssertEqual(TerminalText.displayWidth("访达"), 4)
    XCTAssertEqual(TerminalText.displayWidth("e\u{0301}"), 1)
    XCTAssertEqual(TerminalText.displayWidth("👨‍💻"), 2)
  }

  func testClippingPaddingAndCenteringUseDisplayColumns() {
    XCTAssertEqual(TerminalText.clipped("网易云音乐", to: 7), "网易云…")
    XCTAssertEqual(TerminalText.displayWidth(TerminalText.padded("访达", to: 8)), 8)
    XCTAssertEqual(TerminalText.centered("fq", in: 6), "  fq  ")
  }

  func testPrefixAndSuffixWindowsDoNotSplitWideCharacters() {
    XCTAssertEqual(TerminalText.prefixFitting("A访达B", in: 3), "A访")
    XCTAssertEqual(TerminalText.prefixFitting("A访达B", in: 2), "A")
    XCTAssertEqual(TerminalText.suffixFitting("A访达B", in: 3), "达B")
    XCTAssertEqual(TerminalText.suffixFitting("A访达B", in: 2), "B")
    XCTAssertEqual(TerminalText.prefixFitting("👨‍💻Z", in: 2), "👨‍💻")
  }
}
