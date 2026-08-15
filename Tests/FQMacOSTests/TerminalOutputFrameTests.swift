import XCTest

@testable import FQMacOS

final class TerminalOutputFrameTests: XCTestCase {
  func testSynchronizedUpdateWrapsTheEntireRenderedFrame() {
    let content = "\u{001B}[Hframe"

    XCTAssertEqual(
      TerminalOutputFrame.synchronized(content),
      "\u{001B}[?2026h\u{001B}[Hframe\u{001B}[?2026l"
    )
  }
}
