import XCTest

@testable import FQCore

final class CommandLineOptionsTests: XCTestCase {
  func testNoArgumentsDefaultsToInteractiveForceQuit() throws {
    XCTAssertEqual(
      try CommandLineOptions.parse([]),
      .interactive(action: .forceQuit, query: "")
    )
  }

  func testWordsBecomeInitialSearchQuery() throws {
    XCTAssertEqual(
      try CommandLineOptions.parse(["Visual", "Studio"]),
      .interactive(action: .forceQuit, query: "Visual Studio")
    )
  }

  func testQuitModeAndDoubleDash() throws {
    XCTAssertEqual(
      try CommandLineOptions.parse(["--quit", "--", "-preview"]),
      .interactive(action: .quit, query: "-preview")
    )
  }

  func testJSONImpliesListMode() throws {
    XCTAssertEqual(
      try CommandLineOptions.parse(["--json", "safari"]),
      .list(format: .json, query: "safari")
    )
  }

  func testConflictingActionsAreRejected() {
    XCTAssertThrowsError(try CommandLineOptions.parse(["--quit", "--force"])) { error in
      XCTAssertEqual(error as? CommandLineOptionsError, .conflictingActions)
    }
  }

  func testListCannotBeCombinedWithAnAction() {
    XCTAssertThrowsError(try CommandLineOptions.parse(["--list", "--quit"])) { error in
      XCTAssertEqual(error as? CommandLineOptionsError, .incompatibleOption("--list"))
    }
  }

  func testUnknownOptionIsRejected() {
    XCTAssertThrowsError(try CommandLineOptions.parse(["--wat"])) { error in
      XCTAssertEqual(error as? CommandLineOptionsError, .unexpectedArgument("--wat"))
    }
  }
}
