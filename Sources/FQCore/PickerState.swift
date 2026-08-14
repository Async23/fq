import Foundation

public struct PickerState: Equatable, Sendable {
  public private(set) var applications: [ApplicationCandidate]
  public private(set) var query: String
  public private(set) var selectedIndex: Int

  public init(
    applications: [ApplicationCandidate],
    initialQuery: String = ""
  ) {
    self.applications = applications
    self.query = initialQuery
    self.selectedIndex = 0
  }

  public var visibleApplications: [ApplicationCandidate] {
    FuzzyMatcher.rank(query: query, applications: applications)
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

  public mutating func moveSelection(by offset: Int) {
    let count = visibleApplications.count
    guard count > 0 else {
      selectedIndex = 0
      return
    }
    selectedIndex = ((selectedIndex + offset) % count + count) % count
  }

  public mutating func moveToFirst() {
    selectedIndex = 0
  }

  public mutating func moveToLast() {
    selectedIndex = max(0, visibleApplications.count - 1)
  }

  public mutating func replaceApplications(_ newApplications: [ApplicationCandidate]) {
    let previousSelection = selectedApplication?.id
    applications = newApplications

    let visible = visibleApplications
    if let previousSelection,
      let newIndex = visible.firstIndex(where: { $0.id == previousSelection })
    {
      selectedIndex = newIndex
    } else {
      selectedIndex = min(selectedIndex, max(0, visible.count - 1))
    }
  }
}
