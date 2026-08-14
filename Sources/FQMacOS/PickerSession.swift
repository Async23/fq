import FQCore

struct ApplicationExitSelection: Equatable {
  let application: ApplicationCandidate
  let action: ApplicationExitAction
}

enum PickerPhase: Equatable {
  case browse
  case filtering(originalQuery: String)
  case confirming(ApplicationExitSelection)
  case help
}

enum PickerEvent: Equatable {
  case enter
  case escape
  case interrupt
  case move(Int)
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

  init(
    applications: [ApplicationCandidate],
    initialQuery: String,
    defaultAction: ApplicationExitAction
  ) {
    state = PickerState(applications: applications, initialQuery: initialQuery)
    self.defaultAction = defaultAction
  }

  var confirmationSelection: ApplicationExitSelection? {
    guard case .confirming(let selection) = phase else {
      return nil
    }
    return selection
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
    if case .confirming(let selection) = phase,
      let refreshedApplication = applications.first(where: {
        $0.id == selection.application.id
      })
    {
      phase = .confirming(
        ApplicationExitSelection(
          application: refreshedApplication,
          action: selection.action
        )
      )
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

    switch phase {
    case .browse:
      return handleBrowse(event)
    case .filtering(let originalQuery):
      return handleFiltering(event, originalQuery: originalQuery)
    case .confirming(let selection):
      return handleConfirmation(event, selection: selection)
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
      default:
        beginFiltering()
        state.appendToQuery(text)
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
    selection: ApplicationExitSelection
  ) -> PickerDecision {
    switch event {
    case .text(let text) where text.lowercased() == "y":
      guard isConfirmationTargetAvailable else {
        return .stay(redraw: false)
      }
      return .select(selection)
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
      return .stay(redraw: false)
    }

    let selection = ApplicationExitSelection(application: application, action: action)
    if action == .forceQuit {
      phase = .confirming(selection)
      return .stay(redraw: true)
    }

    return .select(selection)
  }
}
