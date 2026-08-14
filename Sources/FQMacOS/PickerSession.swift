import FQCore

struct ApplicationExitSelection: Equatable {
  let application: ApplicationCandidate
  let action: ApplicationExitAction
}

enum PickerPhase: Equatable {
  case browse
  case filtering(originalQuery: String)
  case confirming(ApplicationExitAction)
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
    case .confirming(let action):
      return handleConfirmation(event, action: action)
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
    action: ApplicationExitAction
  ) -> PickerDecision {
    switch event {
    case .text(let text) where text.lowercased() == "y":
      guard let application = state.selectedApplication else {
        phase = .browse
        return .stay(redraw: true)
      }
      return .select(ApplicationExitSelection(application: application, action: action))
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

    if action == .forceQuit {
      phase = .confirming(action)
      return .stay(redraw: true)
    }

    return .select(ApplicationExitSelection(application: application, action: action))
  }
}
