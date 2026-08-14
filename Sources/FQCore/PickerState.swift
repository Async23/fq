import Foundation

public enum PickerSortOrder: CaseIterable, Equatable, Sendable {
  case smart
  case name
  case processIdentifier
  case status
}

public struct PickerState: Equatable, Sendable {
  public private(set) var applications: [ApplicationCandidate]
  public private(set) var query: String
  public private(set) var selectedIndex: Int
  public private(set) var sortOrder: PickerSortOrder
  public private(set) var isSortReversed: Bool

  public init(
    applications: [ApplicationCandidate],
    initialQuery: String = "",
    sortOrder: PickerSortOrder = .smart,
    isSortReversed: Bool = false
  ) {
    self.applications = applications
    self.query = initialQuery
    self.selectedIndex = 0
    self.sortOrder = sortOrder
    self.isSortReversed = isSortReversed
  }

  public var visibleApplications: [ApplicationCandidate] {
    let ranked = FuzzyMatcher.rank(query: query, applications: applications)
    let sorted: [ApplicationCandidate]
    switch sortOrder {
    case .smart:
      sorted = ranked
    case .name:
      sorted = ranked.sorted(by: compareByName)
    case .processIdentifier:
      sorted = ranked.sorted { lhs, rhs in
        if lhs.processIdentifier != rhs.processIdentifier {
          return lhs.processIdentifier < rhs.processIdentifier
        }
        return compareByName(lhs, rhs)
      }
    case .status:
      sorted = ranked.sorted { lhs, rhs in
        let lhsRank = statusRank(lhs)
        let rhsRank = statusRank(rhs)
        if lhsRank != rhsRank {
          return lhsRank < rhsRank
        }
        return compareByName(lhs, rhs)
      }
    }

    return isSortReversed ? Array(sorted.reversed()) : sorted
  }

  public var selectedApplication: ApplicationCandidate? {
    let visible = visibleApplications
    guard visible.indices.contains(selectedIndex) else {
      return nil
    }
    return visible[selectedIndex]
  }

  public mutating func appendToQuery(_ text: String) {
    query.append(text)
    selectedIndex = 0
  }

  public mutating func deleteLastQueryCharacter() {
    guard !query.isEmpty else {
      return
    }
    query.removeLast()
    selectedIndex = 0
  }

  public mutating func clearQuery() {
    query = ""
    selectedIndex = 0
  }

  public mutating func replaceQuery(_ newQuery: String) {
    query = newQuery
    selectedIndex = 0
  }

  public mutating func moveSelection(by offset: Int) {
    let count = visibleApplications.count
    guard count > 0 else {
      selectedIndex = 0
      return
    }
    selectedIndex = min(max(selectedIndex + offset, 0), count - 1)
  }

  public mutating func moveToFirst() {
    selectedIndex = 0
  }

  public mutating func moveToLast() {
    selectedIndex = max(0, visibleApplications.count - 1)
  }

  public mutating func cycleSort(by offset: Int) {
    guard offset != 0 else {
      return
    }

    let previousSelection = selectedApplication?.id
    let orders = PickerSortOrder.allCases
    guard let currentIndex = orders.firstIndex(of: sortOrder) else {
      return
    }
    let normalizedOffset = offset % orders.count
    let nextIndex = (currentIndex + normalizedOffset + orders.count) % orders.count
    sortOrder = orders[nextIndex]
    restoreSelection(previousSelection)
  }

  public mutating func toggleSortDirection() {
    let previousSelection = selectedApplication?.id
    isSortReversed.toggle()
    restoreSelection(previousSelection)
  }

  public mutating func replaceApplications(_ newApplications: [ApplicationCandidate]) {
    let previousSelection = selectedApplication?.id
    applications = newApplications

    restoreSelection(previousSelection)
  }

  private mutating func restoreSelection(_ identity: ApplicationIdentity?) {
    let visible = visibleApplications
    if let identity,
      let newIndex = visible.firstIndex(where: { $0.id == identity })
    {
      selectedIndex = newIndex
    } else {
      selectedIndex = min(selectedIndex, max(0, visible.count - 1))
    }
  }

  private func compareByName(
    _ lhs: ApplicationCandidate,
    _ rhs: ApplicationCandidate
  ) -> Bool {
    let comparison = lhs.name.localizedStandardCompare(rhs.name)
    if comparison != .orderedSame {
      return comparison == .orderedAscending
    }
    return lhs.processIdentifier < rhs.processIdentifier
  }

  private func statusRank(_ application: ApplicationCandidate) -> Int {
    if application.isActive {
      return 0
    }
    if application.isHidden {
      return 2
    }
    return 1
  }
}
