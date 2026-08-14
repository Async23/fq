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

enum PickerPhase: Equatable {
  case browse
  case filtering(originalQuery: String)
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
  case first
  case last
  case backspace
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

  init(
    applications: [ApplicationCandidate],
    initialQuery: String,
    defaultAction: ApplicationExitAction
  ) {
    state = PickerState(applications: applications, initialQuery: initialQuery)
    self.defaultAction = defaultAction
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

  var isConfirmationTargetAvailable: Bool {
    guard let selection = confirmationSelection else {
      return false
    }
    return state.applications.contains(where: { $0.id == selection.application.id })
  }

  @discardableResult
  mutating func replaceApplications(_ applications: [ApplicationCandidate]) -> Bool {
    guard applications != state.applications else {
      return false
    }

    state.replaceApplications(applications)
    if case .confirming(var confirmation) = phase,
      let refreshedApplication = applications.first(where: {
        $0.id == confirmation.selection.application.id
      })
    {
      confirmation = PickerConfirmation(
        selection: ApplicationExitSelection(
          application: refreshedApplication,
          action: confirmation.selection.action
        ),
        choice: confirmation.choice
      )
      phase = .confirming(confirmation)
    } else if case .confirming(var confirmation) = phase {
      confirmation.choice = .cancel
      phase = .confirming(confirmation)
    }
    return true
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
    case .filtering(let originalQuery):
      return handleFiltering(event, originalQuery: originalQuery)
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
    case .first:
      state.moveToFirst()
    case .last:
      state.moveToLast()
    case .backspace:
      guard !state.query.isEmpty else {
        return .stay(redraw: false)
      }
      beginFiltering()
      state.deleteLastQueryCharacter()
    case .clear:
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
    originalQuery: String
  ) -> PickerDecision {
    switch event {
    case .enter, .move:
      phase = .browse
    case .moveHorizontal, .cycleFocus:
      return .stay(redraw: false)
    case .escape:
      state.replaceQuery(originalQuery)
      phase = .browse
    case .first:
      state.moveToFirst()
      phase = .browse
    case .last:
      state.moveToLast()
      phase = .browse
    case .backspace:
      state.deleteLastQueryCharacter()
    case .clear:
      state.clearQuery()
    case .text(let text):
      state.appendToQuery(text)
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
    phase = .filtering(originalQuery: state.query)
  }

  private mutating func requestExit(_ action: ApplicationExitAction) -> PickerDecision {
    guard let application = state.selectedApplication else {
      statusMessage = state.query.isEmpty ? "没有可操作的应用" : "当前筛选没有匹配"
      return .stay(redraw: true)
    }

    let selection = ApplicationExitSelection(application: application, action: action)
    phase = .confirming(PickerConfirmation(selection: selection))
    return .stay(redraw: true)
  }
}
