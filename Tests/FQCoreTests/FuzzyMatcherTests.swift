import XCTest

@testable import FQCore

final class FuzzyMatcherTests: XCTestCase {
  private let applications = [
    coreCandidate(pid: 101, name: "Safari", bundleIdentifier: "com.apple.Safari"),
    coreCandidate(
      pid: 202,
      name: "Visual Studio Code",
      bundleIdentifier: "com.microsoft.VSCode"
    ),
    coreCandidate(pid: 303, name: "备忘录", bundleIdentifier: "com.apple.Notes"),
  ]

  func testEmptyQueryPreservesApplicationOrder() {
    XCTAssertEqual(FuzzyMatcher.rank(query: "", applications: applications), applications)
  }

  func testMatchesApplicationNameAsASubsequence() {
    XCTAssertEqual(
      FuzzyMatcher.rank(query: "vsc", applications: applications).map(\.name),
      ["Visual Studio Code"]
    )
  }

  func testMatchesBundleIdentifierCaseInsensitively() {
    XCTAssertEqual(
      FuzzyMatcher.rank(query: "APPLE.SAF", applications: applications).map(\.name),
      ["Safari"]
    )
  }

  func testMatchesPID() {
    XCTAssertEqual(
      FuzzyMatcher.rank(query: "303", applications: applications).map(\.name),
      ["备忘录"]
    )
  }

  func testAllTermsMustMatch() {
    XCTAssertEqual(
      FuzzyMatcher.rank(query: "visual microsoft", applications: applications).map(\.name),
      ["Visual Studio Code"]
    )
    XCTAssertTrue(FuzzyMatcher.rank(query: "visual apple", applications: applications).isEmpty)
  }
}

func coreCandidate(
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
