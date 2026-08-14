import FQCore

struct ApplicationExitSelection: Equatable {
  let application: ApplicationCandidate
  let action: ApplicationExitAction
}

enum PickerConfirmationChoice: Equatable {
  case execute
  case cancel
}

struct PickerConfirmation: Equatable {
  let selection: ApplicationExitSelection
  var choice: PickerConfirmationChoice = .cancel
}

struct PickerFilterEdit: Equatable {
  let originalQuery: String
  private(set) var cursorOffset: Int

  init(query: String) {
    originalQuery = query
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
  case move(Int)
  case moveHorizontal(Int)
  case cycleFocus
  case chooseConfirmation(PickerConfirmationChoice)
  case first
  case last
  case backspace
  case deleteForward
  case clear
  case redraw
  case text(String)
}

enum PickerDecision: Equatable {
  case stay(redraw: Bool)
  case cancel
  case select(ApplicationExitSelection)
}

struct PickerSession {
  private(set) var state: PickerState
  let defaultAction: ApplicationExitAction
  private(set) var phase: PickerPhase = .browse
  private(set) var statusMessage: String?
  private(set) var isPaused = false
  private var latestApplications: [ApplicationCandidate]

  init(
    applications: [ApplicationCandidate],
    initialQuery: String,
    defaultAction: ApplicationExitAction
  ) {
    state = PickerState(applications: applications, initialQuery: initialQuery)
    self.defaultAction = defaultAction
    latestApplications = applications
  }

  var confirmationSelection: ApplicationExitSelection? {
    guard case .confirming(let confirmation) = phase else {
      return nil
    }
    return confirmation.selection
  }

  var confirmationChoice: PickerConfirmationChoice? {
    guard case .confirming(let confirmation) = phase else {
      return nil
    }
    return confirmation.choice
  }

  var filterCursorOffset: Int? {
    guard case .filtering(let edit) = phase else {
      return nil
    }
    return edit.cursorOffset
  }

  var isConfirmationTargetAvailable: Bool {
    guard let selection = confirmationSelection else {
      return false
    }
    return latestApplications.contains(where: { $0.id == selection.application.id })
  }

  @discardableResult
  mutating func replaceApplications(_ applications: [ApplicationCandidate]) -> Bool {
    let targetWasAvailable = isConfirmationTargetAvailable
    latestApplications = applications

    var shouldRedraw = false
    if !isPaused, applications != state.applications {
      state.replaceApplications(applications)
      shouldRedraw = true
    }

    if case .confirming(let confirmation) = phase,
      let refreshedApplication = applications.first(where: {
        $0.id == confirmation.selection.application.id
      })
    {
      let refreshedConfirmation = PickerConfirmation(
        selection: ApplicationExitSelection(
          application: refreshedApplication,
          action: confirmation.selection.action
        ),
        choice: confirmation.choice
      )
      if refreshedConfirmation != confirmation {
        phase = .confirming(refreshedConfirmation)
        shouldRedraw = true
      }
    } else if case .confirming(var confirmation) = phase {
      if confirmation.choice != .cancel {
        confirmation.choice = .cancel
        phase = .confirming(confirmation)
        shouldRedraw = true
      }
    }

    if targetWasAvailable != isConfirmationTargetAvailable {
      shouldRedraw = true
    }
    return shouldRedraw
  }

  mutating func handle(_ event: PickerEvent) -> PickerDecision {
    if case .interrupt = event {
      return .cancel
    }
    if case .redraw = event {
      return .stay(redraw: true)
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
      return .cancel
    case .move(let offset):
      state.moveSelection(by: offset)
    case .moveHorizontal(let offset):
      state.cycleSort(by: offset)
    case .cycleFocus:
      return .stay(redraw: false)
    case .chooseConfirmation:
      return .stay(redraw: false)
    case .first:
      state.moveToFirst()
    case .last:
      state.moveToLast()
    case .backspace:
      guard !state.query.isEmpty else {
        return .stay(redraw: false)
      }
      return handleFiltering(.backspace, edit: PickerFilterEdit(query: state.query))
    case .deleteForward, .clear:
      guard !state.query.isEmpty else {
        return .stay(redraw: false)
      }
      state.clearQuery()
    case .text(let text):
      switch text {
      case "q":
        return .cancel
      case "f", "/":
        beginFiltering()
      case "?":
        phase = .help
      case "t":
        return requestExit(.quit)
      case "k":
        return requestExit(.forceQuit)
      case "r":
        state.toggleSortDirection()
      case "u":
        togglePause()
      default:
        statusMessage = "筛选请先按 f 或 /"
      }
    case .interrupt, .redraw:
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
    case .move, .cycleFocus, .chooseConfirmation:
      return .stay(redraw: false)
    case .moveHorizontal(let offset):
      guard updatedEdit.moveCursor(by: offset, in: state.query) else {
        return .stay(redraw: false)
      }
      phase = .filtering(updatedEdit)
    case .escape:
      state.replaceQuery(edit.originalQuery)
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
      phase = .filtering(updatedEdit)
    case .deleteForward:
      guard let query = updatedEdit.deletingForward(in: state.query) else {
        return .stay(redraw: false)
      }
      state.replaceQuery(query)
      phase = .filtering(updatedEdit)
    case .clear:
      guard let query = updatedEdit.clear(query: state.query) else {
        return .stay(redraw: false)
      }
      state.replaceQuery(query)
      phase = .filtering(updatedEdit)
    case .text(let text):
      state.replaceQuery(updatedEdit.inserting(text, into: state.query))
      phase = .filtering(updatedEdit)
    case .interrupt, .redraw:
      return .stay(redraw: false)
    }

    return .stay(redraw: true)
  }

  private mutating func handleConfirmation(
    _ event: PickerEvent,
    confirmation: PickerConfirmation
  ) -> PickerDecision {
    switch event {
    case .enter:
      guard confirmation.choice == .execute, isConfirmationTargetAvailable else {
        phase = .browse
        return .stay(redraw: true)
      }
      return .select(confirmation.selection)
    case .moveHorizontal, .cycleFocus:
      guard isConfirmationTargetAvailable else {
        return .stay(redraw: false)
      }
      var updated = confirmation
      updated.choice = confirmation.choice == .cancel ? .execute : .cancel
      phase = .confirming(updated)
      return .stay(redraw: true)
    case .chooseConfirmation(.cancel):
      phase = .browse
      return .stay(redraw: true)
    case .chooseConfirmation(.execute):
      guard isConfirmationTargetAvailable else {
        return .stay(redraw: false)
      }
      return .select(confirmation.selection)
    case .move:
      return .stay(redraw: false)
    case .escape, .text("n"), .text("N"), .text("q"):
      phase = .browse
      return .stay(redraw: true)
    default:
      return .stay(redraw: false)
    }
  }

  private mutating func handleHelp(_ event: PickerEvent) -> PickerDecision {
    switch event {
    case .escape, .text("?"), .text("q"):
      phase = .browse
      return .stay(redraw: true)
    default:
      return .stay(redraw: false)
    }
  }

  private mutating func beginFiltering() {
    phase = .filtering(PickerFilterEdit(query: state.query))
  }

  private mutating func togglePause() {
    isPaused.toggle()
    if !isPaused, latestApplications != state.applications {
      state.replaceApplications(latestApplications)
    }
  }

  private mutating func requestExit(_ action: ApplicationExitAction) -> PickerDecision {
    guard let application = state.selectedApplication else {
      statusMessage = state.query.isEmpty ? "没有可操作的应用" : "当前筛选没有匹配"
      return .stay(redraw: true)
    }

    let latestApplication =
      latestApplications.first(where: { $0.id == application.id }) ?? application
    let selection = ApplicationExitSelection(application: latestApplication, action: action)
    phase = .confirming(PickerConfirmation(selection: selection))
    return .stay(redraw: true)
  }
}
