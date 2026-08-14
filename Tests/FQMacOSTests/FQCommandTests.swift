import Foundation
import XCTest

@testable import FQCore
@testable import FQMacOS

@MainActor
final class FQCommandTests: XCTestCase {
  func testDefaultModeForceQuitsPickerConfirmedApplication() {
    let selected = candidate(pid: 42, name: "Preview")
    let manager = FakeApplicationManager(applications: [selected])
    let picker = FakePicker(selection: selected)
    let console = FakeConsole()
    let command = FQCommand(applicationManager: manager, picker: picker, console: console)

    XCTAssertEqual(command.run(arguments: []), 0)
    XCTAssertEqual(manager.requests, [ExitRequest(application: selected, action: .forceQuit)])
    XCTAssertEqual(picker.receivedActions, [.forceQuit])
    XCTAssertTrue(console.standardOutput.contains("已强制退出"))
  }

  func testPickerShortcutCanOverrideDefaultForceActionWithNormalQuit() {
    let selected = candidate(pid: 42, name: "Preview")
    let manager = FakeApplicationManager(applications: [selected], outcome: .requested)
    let console = FakeConsole()
    let command = FQCommand(
      applicationManager: manager,
      picker: FakePicker(selection: selected, selectedAction: .quit),
      console: console
    )

    XCTAssertEqual(command.run(arguments: []), 0)
    XCTAssertEqual(manager.requests.first?.action, .quit)
    XCTAssertTrue(console.standardOutput.contains("正常退出请求"))
  }

  func testNormalQuitUsesPickerSelectionWithoutForceConfirmation() {
    let selected = candidate(pid: 42, name: "Preview")
    let manager = FakeApplicationManager(applications: [selected], outcome: .requested)
    let console = FakeConsole()
    let command = FQCommand(
      applicationManager: manager,
      picker: FakePicker(selection: selected, selectedAction: .quit),
      console: console
    )

    XCTAssertEqual(command.run(arguments: ["--quit"]), 0)
    XCTAssertEqual(manager.requests.first?.action, .quit)
    XCTAssertTrue(console.standardOutput.contains("正常退出请求"))
  }

  func testCancellationDoesNotRequestExit() {
    let application = candidate(pid: 42, name: "Preview")
    let manager = FakeApplicationManager(applications: [application])
    let command = FQCommand(
      applicationManager: manager,
      picker: FakePicker(selection: nil),
      console: FakeConsole()
    )

    XCTAssertEqual(command.run(arguments: []), 0)
    XCTAssertTrue(manager.requests.isEmpty)
  }

  func testListModeDoesNotRequireATerminalOrInvokePicker() {
    let application = candidate(
      pid: 42,
      name: "Preview",
      bundleIdentifier: "com.apple.Preview"
    )
    let picker = FakePicker(selection: nil)
    let console = FakeConsole(isInputTerminal: false, isOutputTerminal: false)
    let command = FQCommand(
      applicationManager: FakeApplicationManager(applications: [application]),
      picker: picker,
      console: console
    )

    XCTAssertEqual(command.run(arguments: ["--list", "prev"]), 0)
    XCTAssertEqual(console.standardOutput, "42\tPreview\tcom.apple.Preview\n")
    XCTAssertEqual(picker.chooseCallCount, 0)
  }

  func testJSONListHasStablePublicShape() throws {
    let application = candidate(pid: 42, name: "Preview")
    let console = FakeConsole(isInputTerminal: false, isOutputTerminal: false)
    let command = FQCommand(
      applicationManager: FakeApplicationManager(applications: [application]),
      picker: FakePicker(selection: nil),
      console: console
    )

    XCTAssertEqual(command.run(arguments: ["--json"]), 0)
    let records = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(console.standardOutput.utf8)) as? [[String: Any]]
    )
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records[0]["pid"] as? Int, 42)
    XCTAssertEqual(records[0]["name"] as? String, "Preview")
  }

  func testInteractiveModeExplainsWhenStandardInputIsNotATerminal() {
    let console = FakeConsole(isInputTerminal: false)
    let command = FQCommand(
      applicationManager: FakeApplicationManager(applications: []),
      picker: FakePicker(selection: nil),
      console: console
    )

    XCTAssertEqual(command.run(arguments: []), 2)
    XCTAssertTrue(console.standardError.contains("fq --list"))
  }
}

@MainActor
private final class FakeApplicationManager: ApplicationManaging {
  let applications: [ApplicationCandidate]
  let outcome: ApplicationExitOutcome
  var requests: [ExitRequest] = []

  init(
    applications: [ApplicationCandidate],
    outcome: ApplicationExitOutcome = .terminated
  ) {
    self.applications = applications
    self.outcome = outcome
  }

  func runningApplications() -> [ApplicationCandidate] {
    applications
  }

  func requestExit(
    _ application: ApplicationCandidate,
    action: ApplicationExitAction
  ) throws -> ApplicationExitOutcome {
    requests.append(ExitRequest(application: application, action: action))
    return outcome
  }
}

@MainActor
private final class FakePicker: ApplicationPicking {
  let selection: ApplicationExitSelection?
  var chooseCallCount = 0
  var receivedActions: [ApplicationExitAction] = []

  init(
    selection: ApplicationCandidate?,
    selectedAction: ApplicationExitAction = .forceQuit
  ) {
    self.selection = selection.map {
      ApplicationExitSelection(application: $0, action: selectedAction)
    }
  }

  func choose(
    from applications: [ApplicationCandidate],
    initialQuery: String,
    action: ApplicationExitAction,
    refreshApplications: () -> [ApplicationCandidate]
  ) throws -> ApplicationExitSelection? {
    chooseCallCount += 1
    receivedActions.append(action)
    return selection
  }
}

private final class FakeConsole: Console {
  let isInputTerminal: Bool
  let isOutputTerminal: Bool
  var standardOutput = ""
  var standardError = ""

  init(
    isInputTerminal: Bool = true,
    isOutputTerminal: Bool = true
  ) {
    self.isInputTerminal = isInputTerminal
    self.isOutputTerminal = isOutputTerminal
  }

  func write(_ text: String) {
    standardOutput += text
  }

  func writeError(_ text: String) {
    standardError += text
  }
}

private struct ExitRequest: Equatable {
  let application: ApplicationCandidate
  let action: ApplicationExitAction
}

private func candidate(
  pid: Int32,
  name: String,
  bundleIdentifier: String? = nil
) -> ApplicationCandidate {
  ApplicationCandidate(
    id: ApplicationIdentity(
      processIdentifier: pid,
      bundleIdentifier: bundleIdentifier,
      launchDate: nil
    ),
    name: name
  )
}
