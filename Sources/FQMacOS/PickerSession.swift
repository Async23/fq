import FQCore

struct ApplicationExitPlan: Equatable {
  let applications: [ApplicationCandidate]
  let action: ApplicationExitAction

  init(applications: [ApplicationCandidate], action: ApplicationExitAction) {
    precondition(!applications.isEmpty)
    self.applications = applications
    self.action = action
  }
}

struct PickerConfirmation: Equatable {
  let plan: ApplicationExitPlan
  var isDirectExecutionArmed = false
}

private struct PickerRangeSelection: Equatable {
  let anchorIdentity: ApplicationIdentity
  let baselineMarkedIdentities: [ApplicationIdentity]
}

struct PickerFilterEdit: Equatable {
  let originalQuery: String
  let originalSelectionIdentity: ApplicationIdentity?
  let originalSelectedIndex: Int
  let originalViewportStartIndex: Int
  private(set) var cursorOffset: Int

  init(
    query: String,
    selectedIdentity: ApplicationIdentity? = nil,
    selectedIndex: Int = 0,
    viewportStartIndex: Int = 0
  ) {
    originalQuery = query
    originalSelectionIdentity = selectedIdentity
    originalSelectedIndex = max(0, selectedIndex)
    originalViewportStartIndex = max(0, viewportStartIndex)
    cursorOffset = query.count
  }

  mutating func moveCursor(by offset: Int, in query: String) -> Bool {
    let previousOffset = cursorOffset
    cursorOffset = min(max(0, cursorOffset + offset), query.count)
    return cursorOffset != previousOffset
  }

  mutating func moveToStart() -> Bool {
    guard cursorOffset != 0 else {
      return false
    }
    cursorOffset = 0
    return true
  }

  mutating func moveToEnd(of query: String) -> Bool {
    guard cursorOffset != query.count else {
      return false
    }
    cursorOffset = query.count
    return true
  }

  mutating func inserting(_ text: String, into query: String) -> String {
    let (prefix, suffix) = split(query)
    let updatedPrefix = prefix + text
    let updatedQuery = updatedPrefix + suffix
    cursorOffset = min(updatedPrefix.count, updatedQuery.count)
    return updatedQuery
  }

  mutating func deletingBackward(in query: String) -> String? {
    var characters = Array(query)
    cursorOffset = min(cursorOffset, characters.count)
    guard cursorOffset > 0 else {
      return nil
    }
    characters.remove(at: cursorOffset - 1)
    cursorOffset -= 1
    return String(characters)
  }

  mutating func deletingForward(in query: String) -> String? {
    var characters = Array(query)
    cursorOffset = min(cursorOffset, characters.count)
    guard cursorOffset < characters.count else {
      return nil
    }
    characters.remove(at: cursorOffset)
    return String(characters)
  }

  mutating func clear(query: String) -> String? {
    guard !query.isEmpty else {
      return nil
    }
    cursorOffset = 0
    return ""
  }

  private func split(_ query: String) -> (String, String) {
    let characters = Array(query)
    let offset = min(cursorOffset, characters.count)
    return (
      String(characters[..<offset]),
      String(characters[offset...])
    )
  }
}

enum PickerPhase: Equatable {
  case browse
  case filtering(PickerFilterEdit)
  case confirming(PickerConfirmation)
  case help
}

enum PickerEvent: Equatable {
  case enter
  case escape
  case interrupt
  case suspend
  case move(Int)
  case positionViewport(startIndex: Int, listRows: Int)
  case moveHorizontal(Int)
  case cycleFocus
  case confirmExit
  case cancelExit
  case first
  case last
  case backspace
  case deleteForward
  case clear
  case redraw
  case inputIdle
  case help
  case text(String)
  case paste(String)
}

enum PickerDecision: Equatable {
  case stay(redraw: Bool)
  case cancel
  case select(ApplicationExitPlan)
  case suspend
}

struct PickerSession {
  private(set) var state: PickerState
  let defaultAction: ApplicationExitAction
  private(set) var phase: PickerPhase = .browse
  private(set) var statusMessage: String?
  private(set) var isPaused = false
  private(set) var viewportStartIndex = 0
  private(set) var markedApplicationIdentities: [ApplicationIdentity] = []
  private var viewportListRows: Int?
  private var latestApplications: [ApplicationCandidate]
  private var rangeSelection: PickerRangeSelection?

  init(
    applications: [ApplicationCandidate],
    initialQuery: String,
    defaultAction: ApplicationExitAction
  ) {
    state = PickerState(applications: applications, initialQuery: initialQuery)
    self.defaultAction = defaultAction
    latestApplications = applications
  }

  var confirmationPlan: ApplicationExitPlan? {
    guard case .confirming(let confirmation) = phase else {
      return nil
    }
    return confirmation.plan
  }

  var confirmationAvailableApplications: [ApplicationCandidate] {
    guard let plan = confirmationPlan else {
      return []
    }
    return plan.applications.compactMap { target in
      latestApplications.first(where: { $0.id == target.id })
    }
  }

  var unavailableConfirmationTargetCount: Int {
    max(0, (confirmationPlan?.applications.count ?? 0) - confirmationAvailableApplications.count)
  }

  var isRangeSelecting: Bool {
    rangeSelection != nil
  }

  var filterCursorOffset: Int? {
    guard case .filtering(let edit) = phase else {
      return nil
    }
    return edit.cursorOffset
  }

  var isConfirmationTargetAvailable: Bool {
    !confirmationAvailableApplications.isEmpty
  }

  func isMarked(_ application: ApplicationCandidate) -> Bool {
    markedApplicationIdentities.contains(application.id)
  }

  func isConfirmationTarget(_ application: ApplicationCandidate) -> Bool {
    confirmationPlan?.applications.contains(where: { $0.id == application.id }) == true
  }

  func visibleApplicationRange(listRows: Int) -> Range<Int> {
    let visibleCount = state.visibleApplications.count
    let rowCount = max(0, listRows)
    guard visibleCount > 0, rowCount > 0 else {
      return 0..<0
    }

    let selectedIndex = min(state.selectedIndex, visibleCount - 1)
    let maxStartIndex = max(0, visibleCount - rowCount)
    var startIndex = min(max(0, viewportStartIndex), maxStartIndex)
    if selectedIndex < startIndex {
      startIndex = selectedIndex
    } else if selectedIndex >= startIndex + rowCount {
      startIndex = min(maxStartIndex, selectedIndex - rowCount + 1)
    }
    return startIndex..<min(visibleCount, startIndex + rowCount)
  }

  mutating func synchronizeViewport(listRows: Int) {
    let rowCount = max(1, listRows)
    viewportListRows = rowCount
    viewportStartIndex = visibleApplicationRange(listRows: rowCount).lowerBound
  }

  @discardableResult
  mutating func replaceApplications(_ applications: [ApplicationCandidate]) -> Bool {
    let previousAvailableTargetCount = confirmationAvailableApplications.count
    latestApplications = applications

    var shouldRedraw = false
    if !isPaused, !isRangeSelecting, applications != state.applications {
      state.replaceApplications(applications)
      shouldRedraw = true
    }

    if !isPaused, !isRangeSelecting {
      if discardUnavailableMarks(in: applications) {
        shouldRedraw = true
      }
    }

    if case .confirming(let confirmation) = phase {
      let refreshedApplications = confirmation.plan.applications.map { target in
        applications.first(where: { $0.id == target.id }) ?? target
      }
      let refreshedConfirmation = PickerConfirmation(
        plan: ApplicationExitPlan(
          applications: refreshedApplications,
          action: confirmation.plan.action
        ),
        isDirectExecutionArmed: confirmation.isDirectExecutionArmed
      )
      if refreshedConfirmation != confirmation {
        phase = .confirming(refreshedConfirmation)
        shouldRedraw = true
      }
    }

    let availableTargetCountChanged =
      previousAvailableTargetCount != confirmationAvailableApplications.count
    if case .confirming(var confirmation) = phase,
      availableTargetCountChanged,
      confirmation.isDirectExecutionArmed
    {
      confirmation.isDirectExecutionArmed = false
      phase = .confirming(confirmation)
      shouldRedraw = true
    }

    if availableTargetCountChanged {
      shouldRedraw = true
    }
    if let viewportListRows {
      synchronizeViewport(listRows: viewportListRows)
    }
    return shouldRedraw
  }

  mutating func handle(_ event: PickerEvent) -> PickerDecision {
    defer {
      if let viewportListRows {
        synchronizeViewport(listRows: viewportListRows)
      }
    }
    if case .interrupt = event {
      return .cancel
    }
    if case .suspend = event {
      return .suspend
    }
    if case .redraw = event {
      return .stay(redraw: true)
    }
    if case .inputIdle = event {
      guard case .confirming(let confirmation) = phase else {
        return .stay(redraw: false)
      }
      return handleConfirmation(event, confirmation: confirmation)
    }
    statusMessage = nil

    switch phase {
    case .browse:
      return handleBrowse(event)
    case .filtering(let edit):
      return handleFiltering(event, edit: edit)
    case .confirming(let confirmation):
      return handleConfirmation(event, confirmation: confirmation)
    case .help:
      return handleHelp(event)
    }
  }

  private mutating func handleBrowse(_ event: PickerEvent) -> PickerDecision {
    switch event {
    case .enter:
      return requestExit(defaultAction)
    case .escape:
      if cancelRangeSelection() {
        return .stay(redraw: true)
      }
      return .cancel
    case .move(let offset):
      moveSelection(by: offset)
    case .positionViewport(let startIndex, let listRows):
      positionViewport(at: startIndex, listRows: listRows)
      updateRangeSelection()
    case .moveHorizontal(let offset):
      finishRangeSelection(commit: true, announce: false)
      state.cycleSort(by: offset)
    case .cycleFocus:
      return .stay(redraw: false)
    case .confirmExit, .cancelExit:
      return .stay(redraw: false)
    case .first:
      state.moveToFirst()
      updateRangeSelection()
    case .last:
      state.moveToLast()
      updateRangeSelection()
    case .backspace:
      guard !state.query.isEmpty else {
        return .stay(redraw: false)
      }
      return handleFiltering(.backspace, edit: filterEditSnapshot())
    case .deleteForward, .clear:
      guard !state.query.isEmpty else {
        return .stay(redraw: false)
      }
      state.clearQuery()
      viewportStartIndex = 0
    case .text(let text):
      switch text {
      case "q":
        return .cancel
      case "f", "/":
        finishRangeSelection(commit: true, announce: false)
        beginFiltering()
      case "?", "H":
        finishRangeSelection(commit: true, announce: false)
        phase = .help
      case "h":
        finishRangeSelection(commit: true, announce: false)
        state.cycleSort(by: -1)
      case "j":
        moveSelection(by: 1)
      case "k":
        moveSelection(by: -1)
      case "l":
        finishRangeSelection(commit: true, announce: false)
        state.cycleSort(by: 1)
      case " ":
        if isRangeSelecting {
          finishRangeSelection(commit: true)
        } else {
          toggleMark()
        }
      case "v":
        toggleRangeSelection()
      case "a":
        markAllVisibleApplications()
      case "i":
        invertVisibleApplicationMarks()
      case "x":
        clearApplicationMarks()
      case "t":
        return requestExit(.quit)
      case "K":
        return requestExit(.forceQuit)
      case "r":
        finishRangeSelection(commit: true, announce: false)
        state.toggleSortDirection()
      case "u":
        finishRangeSelection(commit: true, announce: false)
        togglePause()
      default:
        statusMessage = "筛选请先按 f 或 /"
      }
    case .paste:
      statusMessage = "粘贴筛选请先按 f 或 /"
    case .help:
      finishRangeSelection(commit: true, announce: false)
      phase = .help
    case .interrupt, .suspend, .redraw, .inputIdle:
      return .stay(redraw: false)
    }

    return .stay(redraw: true)
  }

  private mutating func handleFiltering(
    _ event: PickerEvent,
    edit: PickerFilterEdit
  ) -> PickerDecision {
    var updatedEdit = edit
    switch event {
    case .enter:
      phase = .browse
    case .move(let offset) where offset == 1:
      phase = .browse
      state.moveSelection(by: offset)
    case .move, .positionViewport, .cycleFocus, .confirmExit, .cancelExit, .help, .inputIdle:
      return .stay(redraw: false)
    case .moveHorizontal(let offset):
      guard updatedEdit.moveCursor(by: offset, in: state.query) else {
        return .stay(redraw: false)
      }
      phase = .filtering(updatedEdit)
    case .escape:
      restoreFilterSnapshot(edit)
      phase = .browse
    case .first:
      guard updatedEdit.moveToStart() else {
        return .stay(redraw: false)
      }
      phase = .filtering(updatedEdit)
    case .last:
      guard updatedEdit.moveToEnd(of: state.query) else {
        return .stay(redraw: false)
      }
      phase = .filtering(updatedEdit)
    case .backspace:
      guard let query = updatedEdit.deletingBackward(in: state.query) else {
        return .stay(redraw: false)
      }
      state.replaceQuery(query)
      viewportStartIndex = 0
      phase = .filtering(updatedEdit)
    case .deleteForward:
      guard let query = updatedEdit.deletingForward(in: state.query) else {
        return .stay(redraw: false)
      }
      state.replaceQuery(query)
      viewportStartIndex = 0
      phase = .filtering(updatedEdit)
    case .clear:
      guard let query = updatedEdit.clear(query: state.query) else {
        return .stay(redraw: false)
      }
      state.replaceQuery(query)
      viewportStartIndex = 0
      phase = .filtering(updatedEdit)
    case .text(let text):
      state.replaceQuery(updatedEdit.inserting(text, into: state.query))
      viewportStartIndex = 0
      phase = .filtering(updatedEdit)
    case .paste(let text):
      let normalizedText = normalizedPastedText(text)
      guard !normalizedText.isEmpty else {
        return .stay(redraw: false)
      }
      state.replaceQuery(updatedEdit.inserting(normalizedText, into: state.query))
      viewportStartIndex = 0
      phase = .filtering(updatedEdit)
    case .interrupt, .suspend, .redraw:
      return .stay(redraw: false)
    }

    return .stay(redraw: true)
  }

  private mutating func handleConfirmation(
    _ event: PickerEvent,
    confirmation: PickerConfirmation
  ) -> PickerDecision {
    switch event {
    case .confirmExit:
      guard let plan = availableConfirmationPlan() else {
        return .stay(redraw: false)
      }
      return .select(plan)
    case .text("y"), .text("Y"):
      guard confirmation.isDirectExecutionArmed, let plan = availableConfirmationPlan() else {
        return .stay(redraw: false)
      }
      return .select(plan)
    case .inputIdle:
      guard !confirmation.isDirectExecutionArmed else {
        return .stay(redraw: false)
      }
      var updated = confirmation
      updated.isDirectExecutionArmed = true
      phase = .confirming(updated)
      return .stay(redraw: false)
    case .move, .positionViewport:
      return .stay(redraw: false)
    case .enter, .escape, .backspace, .cancelExit, .text(" "), .text("n"), .text("N"),
      .text("q"):
      phase = .browse
      return .stay(redraw: true)
    default:
      return .stay(redraw: false)
    }
  }

  private mutating func handleHelp(_ event: PickerEvent) -> PickerDecision {
    switch event {
    case .escape, .help, .text("?"), .text("h"), .text("H"), .text("q"):
      phase = .browse
      return .stay(redraw: true)
    default:
      return .stay(redraw: false)
    }
  }

  private func normalizedPastedText(_ text: String) -> String {
    var result = ""
    var previousWasWhitespace = false
    for character in TerminalText.sanitize(text) {
      if character.isWhitespace {
        if !previousWasWhitespace {
          result.append(" ")
        }
        previousWasWhitespace = true
      } else {
        result.append(character)
        previousWasWhitespace = false
      }
    }
    return result
  }

  private mutating func beginFiltering() {
    phase = .filtering(filterEditSnapshot())
  }

  private func filterEditSnapshot() -> PickerFilterEdit {
    PickerFilterEdit(
      query: state.query,
      selectedIdentity: state.selectedApplication?.id,
      selectedIndex: state.selectedIndex,
      viewportStartIndex: viewportStartIndex
    )
  }

  private mutating func restoreFilterSnapshot(_ edit: PickerFilterEdit) {
    state.replaceQuery(edit.originalQuery)
    let targetIndex: Int
    if let identity = edit.originalSelectionIdentity,
      let restoredIndex = state.visibleApplications.firstIndex(where: { $0.id == identity })
    {
      targetIndex = restoredIndex
    } else {
      targetIndex = edit.originalSelectedIndex
    }
    let originalSelectedRow = max(
      0,
      edit.originalSelectedIndex - edit.originalViewportStartIndex
    )
    viewportStartIndex = max(0, targetIndex - originalSelectedRow)
    state.moveSelection(by: targetIndex - state.selectedIndex)
  }

  private mutating func positionViewport(at requestedStartIndex: Int, listRows: Int) {
    let visibleCount = state.visibleApplications.count
    let rowCount = max(1, listRows)
    viewportListRows = rowCount
    guard visibleCount > 0 else {
      viewportStartIndex = 0
      return
    }

    let currentStartIndex = visibleApplicationRange(listRows: rowCount).lowerBound
    let selectedRow = min(max(0, state.selectedIndex - currentStartIndex), rowCount - 1)
    let maxStartIndex = max(0, visibleCount - rowCount)
    let targetStartIndex = min(max(0, requestedStartIndex), maxStartIndex)
    let targetSelectedIndex = min(visibleCount - 1, targetStartIndex + selectedRow)
    viewportStartIndex = targetStartIndex
    state.moveSelection(by: targetSelectedIndex - state.selectedIndex)
  }

  private mutating func moveSelection(by offset: Int) {
    state.moveSelection(by: offset)
    updateRangeSelection()
  }

  private mutating func toggleRangeSelection() {
    if isRangeSelecting {
      finishRangeSelection(commit: true)
      return
    }
    guard let application = state.selectedApplication else {
      statusMessage = state.query.isEmpty ? "没有可范围标记的应用" : "当前筛选没有匹配"
      return
    }
    rangeSelection = PickerRangeSelection(
      anchorIdentity: application.id,
      baselineMarkedIdentities: markedApplicationIdentities
    )
    updateRangeSelection()
  }

  private mutating func updateRangeSelection() {
    guard let rangeSelection, let currentIdentity = state.selectedApplication?.id else {
      return
    }
    let visibleIdentities = state.visibleApplications.map(\.id)
    guard let anchorIndex = visibleIdentities.firstIndex(of: rangeSelection.anchorIdentity),
      let currentIndex = visibleIdentities.firstIndex(of: currentIdentity)
    else {
      finishRangeSelection(commit: true, announce: false)
      return
    }

    let lowerBound = min(anchorIndex, currentIndex)
    let upperBound = max(anchorIndex, currentIndex)
    let rangeIdentities = visibleIdentities[lowerBound...upperBound]
    var updated = rangeSelection.baselineMarkedIdentities
    for identity in rangeIdentities where !updated.contains(identity) {
      updated.append(identity)
    }
    markedApplicationIdentities = updated
    statusMessage =
      "范围选择 \(rangeIdentities.count) 项 · v/Space 完成 · Esc 撤销"
  }

  private mutating func finishRangeSelection(
    commit: Bool,
    announce: Bool = true
  ) {
    guard let rangeSelection else {
      return
    }
    if !commit {
      markedApplicationIdentities = rangeSelection.baselineMarkedIdentities
    }
    self.rangeSelection = nil
    applyLatestApplicationsAfterRangeSelection()
    if announce {
      statusMessage = commit ? "范围标记已保留" : "已撤销范围标记"
    }
  }

  @discardableResult
  private mutating func cancelRangeSelection() -> Bool {
    guard isRangeSelecting else {
      return false
    }
    finishRangeSelection(commit: false)
    return true
  }

  private mutating func applyLatestApplicationsAfterRangeSelection() {
    guard !isPaused else {
      return
    }
    if latestApplications != state.applications {
      state.replaceApplications(latestApplications)
    }
    discardUnavailableMarks(in: latestApplications)
  }

  private mutating func markAllVisibleApplications() {
    finishRangeSelection(commit: true, announce: false)
    let visibleIdentities = state.visibleApplications.map(\.id)
    for identity in visibleIdentities where !markedApplicationIdentities.contains(identity) {
      markedApplicationIdentities.append(identity)
    }
    statusMessage = "已标记全部 \(visibleIdentities.count) 个可见应用"
  }

  private mutating func invertVisibleApplicationMarks() {
    finishRangeSelection(commit: true, announce: false)
    let visibleIdentities = state.visibleApplications.map(\.id)
    let visibleIdentitySet = Set(visibleIdentities)
    let previouslyMarked = Set(markedApplicationIdentities)
    let retained = markedApplicationIdentities.filter { !visibleIdentitySet.contains($0) }
    let inverted = visibleIdentities.filter { !previouslyMarked.contains($0) }
    markedApplicationIdentities = retained + inverted
    statusMessage = "已反选 \(visibleIdentities.count) 个可见应用"
  }

  private mutating func clearApplicationMarks() {
    finishRangeSelection(commit: true, announce: false)
    let count = markedApplicationIdentities.count
    markedApplicationIdentities.removeAll()
    statusMessage = count == 0 ? "没有已标记的应用" : "已清空 \(count) 个标记"
  }

  private mutating func togglePause() {
    isPaused.toggle()
    if !isPaused {
      if latestApplications != state.applications {
        state.replaceApplications(latestApplications)
      }
      discardUnavailableMarks(in: latestApplications)
    }
  }

  @discardableResult
  private mutating func discardUnavailableMarks(
    in applications: [ApplicationCandidate]
  ) -> Bool {
    let availableIdentities = Set(applications.map(\.id))
    let retainedIdentities = markedApplicationIdentities.filter(availableIdentities.contains)
    guard retainedIdentities != markedApplicationIdentities else {
      return false
    }
    markedApplicationIdentities = retainedIdentities
    return true
  }

  private mutating func toggleMark() {
    guard let application = state.selectedApplication else {
      statusMessage = state.query.isEmpty ? "没有可标记的应用" : "当前筛选没有匹配"
      return
    }

    if let index = markedApplicationIdentities.firstIndex(of: application.id) {
      markedApplicationIdentities.remove(at: index)
      statusMessage = "已取消标记 “\(TerminalText.sanitize(application.name))”"
    } else {
      markedApplicationIdentities.append(application.id)
      statusMessage = "已标记 “\(TerminalText.sanitize(application.name))”"
    }
  }

  private mutating func requestExit(_ action: ApplicationExitAction) -> PickerDecision {
    let hadMarkedApplications = !markedApplicationIdentities.isEmpty
    finishRangeSelection(commit: true, announce: false)
    if hadMarkedApplications, markedApplicationIdentities.isEmpty {
      statusMessage = "已标记的应用均已退出"
      return .stay(redraw: true)
    }
    let applications: [ApplicationCandidate]
    if markedApplicationIdentities.isEmpty {
      guard let application = state.selectedApplication else {
        statusMessage = state.query.isEmpty ? "没有可操作的应用" : "当前筛选没有匹配"
        return .stay(redraw: true)
      }
      applications = [
        latestApplications.first(where: { $0.id == application.id }) ?? application
      ]
    } else {
      applications = markedApplicationIdentities.compactMap { identity in
        latestApplications.first(where: { $0.id == identity })
          ?? state.applications.first(where: { $0.id == identity })
      }
      guard !applications.isEmpty else {
        statusMessage = "已标记的应用均已退出"
        return .stay(redraw: true)
      }
    }

    let plan = ApplicationExitPlan(applications: applications, action: action)
    phase = .confirming(PickerConfirmation(plan: plan))
    return .stay(redraw: true)
  }

  private func availableConfirmationPlan() -> ApplicationExitPlan? {
    guard let confirmationPlan, !confirmationAvailableApplications.isEmpty else {
      return nil
    }
    return ApplicationExitPlan(
      applications: confirmationAvailableApplications,
      action: confirmationPlan.action
    )
  }
}
