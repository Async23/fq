import XCTest

@testable import FQCore

final class PickerStateTests: XCTestCase {
  private let applications = [
    coreCandidate(pid: 1, name: "Alpha"),
    coreCandidate(pid: 2, name: "Bravo"),
    coreCandidate(pid: 3, name: "Charlie"),
  ]

  func testQueryFiltersAndSelectsFirstMatch() {
    var state = PickerState(applications: applications)

    state.appendToQuery("br")

    XCTAssertEqual(state.visibleApplications.map(\.name), ["Bravo"])
    XCTAssertEqual(state.selectedApplication?.name, "Bravo")
  }

  func testSelectionWrapsInBothDirections() {
    var state = PickerState(applications: applications)

    state.moveSelection(by: -1)
    XCTAssertEqual(state.selectedApplication?.name, "Charlie")

    state.moveSelection(by: 1)
    XCTAssertEqual(state.selectedApplication?.name, "Alpha")
  }

  func testDeletingAndClearingQueryResetSelection() {
    var state = PickerState(applications: applications, initialQuery: "char")
    state.moveSelection(by: 1)

    state.deleteLastQueryCharacter()
    XCTAssertEqual(state.query, "cha")
    XCTAssertEqual(state.selectedIndex, 0)

    state.clearQuery()
    XCTAssertEqual(state.query, "")
    XCTAssertEqual(state.selectedIndex, 0)
  }

  func testReplacingApplicationsPreservesSelectedIdentity() {
    var state = PickerState(applications: applications)
    state.moveSelection(by: 1)

    state.replaceApplications([applications[2], applications[1]])

    XCTAssertEqual(state.selectedApplication?.name, "Bravo")
  }
}
