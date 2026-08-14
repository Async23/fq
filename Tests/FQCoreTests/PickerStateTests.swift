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

  func testSelectionStopsAtListBoundaries() {
    var state = PickerState(applications: applications)

    state.moveSelection(by: -1)
    XCTAssertEqual(state.selectedApplication?.name, "Alpha")

    state.moveSelection(by: 99)
    XCTAssertEqual(state.selectedApplication?.name, "Charlie")

    state.moveSelection(by: 1)
    XCTAssertEqual(state.selectedApplication?.name, "Charlie")
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

  func testReplacingQuerySupportsRestoringAFilterEdit() {
    var state = PickerState(applications: applications, initialQuery: "br")

    state.replaceQuery("char")

    XCTAssertEqual(state.query, "char")
    XCTAssertEqual(state.selectedApplication?.name, "Charlie")
    XCTAssertEqual(state.selectedIndex, 0)
  }

  func testReplacingApplicationsPreservesSelectedIdentity() {
    var state = PickerState(applications: applications)
    state.moveSelection(by: 1)

    state.replaceApplications([applications[2], applications[1]])

    XCTAssertEqual(state.selectedApplication?.name, "Bravo")
  }

  func testSortOrdersCoverNamePIDAndApplicationStatus() {
    let sortableApplications = [
      coreCandidate(pid: 30, name: "Zulu", isHidden: true),
      coreCandidate(pid: 20, name: "Alpha"),
      coreCandidate(pid: 10, name: "Bravo", isActive: true),
    ]
    var state = PickerState(applications: sortableApplications)

    state.cycleSort(by: 1)
    XCTAssertEqual(state.sortOrder, .name)
    XCTAssertEqual(state.visibleApplications.map(\.name), ["Alpha", "Bravo", "Zulu"])

    state.cycleSort(by: 1)
    XCTAssertEqual(state.sortOrder, .processIdentifier)
    XCTAssertEqual(state.visibleApplications.map(\.name), ["Bravo", "Alpha", "Zulu"])

    state.cycleSort(by: 1)
    XCTAssertEqual(state.sortOrder, .status)
    XCTAssertEqual(state.visibleApplications.map(\.name), ["Bravo", "Alpha", "Zulu"])

    state.toggleSortDirection()
    XCTAssertEqual(state.visibleApplications.map(\.name), ["Zulu", "Alpha", "Bravo"])
  }

  func testChangingSortPreservesSelectionAndWrapsInBothDirections() {
    var state = PickerState(applications: applications)
    state.moveSelection(by: 1)

    state.cycleSort(by: -1)
    XCTAssertEqual(state.sortOrder, .status)
    XCTAssertEqual(state.selectedApplication?.name, "Bravo")

    state.cycleSort(by: 1)
    XCTAssertEqual(state.sortOrder, .smart)
    XCTAssertEqual(state.selectedApplication?.name, "Bravo")

    state.toggleSortDirection()
    XCTAssertEqual(state.selectedApplication?.name, "Bravo")
  }
}
