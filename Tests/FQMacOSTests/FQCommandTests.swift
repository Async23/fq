import Foundation
import XCTest

@testable import FQCore
@testable import FQMacOS

@MainActor
final class FQCommandTests: XCTestCase {
  func testDefaultModeConfirmsThenForceQuitsSelectedApplication() {
    let selected = candidate(pid: 42, name: "Preview")
    let manager = FakeApplicationManager(applications: [selected])
    let picker = FakePicker(selection: selected)
    let console = FakeConsole(responses: ["y"])
    let command = FQCommand(applicationManager: manager, picker: picker, console: console)

    XCTAssertEqual(command.run(arguments: []), 0)
    XCTAssertEqual(manager.requests, [ExitRequest(application: selected, action: .forceQuit)])
    XCTAssertEqual(console.prompts.count, 1)
    XCTAssertTrue(console.standardOutput.contains("已强制退出"))
  }

  func testForceQuitDefaultsToNoWhenConfirmationIsEmpty() {
    let selected = candidate(pid: 42, name: "Preview")
    let manager = FakeApplicationManager(applications: [selected])
    let console = FakeConsole(responses: [""])
    let command = FQCommand(
      applicationManager: manager,
      picker: FakePicker(selection: selected),
      console: console
    )

    XCTAssertEqual(command.run(arguments: []), 0)
    XCTAssertTrue(manager.requests.isEmpty)
    XCTAssertEqual(console.standardOutput, "已取消。\n")
  }

  func testNormalQuitDoesNotAskForConfirmation() {
    let selected = candidate(pid: 42, name: "Preview")
    let manager = FakeApplicationManager(applications: [selected], outcome: .requested)
    let console = FakeConsole()
    let command = FQCommand(
      applicationManager: manager,
      picker: FakePicker(selection: selected),
      console: console
    )

    XCTAssertEqual(command.run(arguments: ["--quit"]), 0)
    XCTAssertEqual(manager.requests.first?.action, .quit)
    XCTAssertTrue(console.prompts.isEmpty)
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

  func testFinderUsesRelaunchWarning() {
    let finder = candidate(pid: 7, name: "Finder", bundleIdentifier: "com.apple.finder")
    let console = FakeConsole(responses: ["no"])
    let command = FQCommand(
      applicationManager: FakeApplicationManager(applications: [finder]),
      picker: FakePicker(selection: finder),
      console: console
    )

    XCTAssertEqual(command.run(arguments: []), 0)
    XCTAssertTrue(console.prompts.first?.contains("自动重新打开") == true)
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
  let selection: ApplicationCandidate?
  var chooseCallCount = 0

  init(selection: ApplicationCandidate?) {
    self.selection = selection
  }

  func choose(
    from applications: [ApplicationCandidate],
    initialQuery: String,
    action: ApplicationExitAction
  ) throws -> ApplicationCandidate? {
    chooseCallCount += 1
    return selection
  }
}

private final class FakeConsole: Console {
  let isInputTerminal: Bool
  let isOutputTerminal: Bool
  private var responses: [String]
  var standardOutput = ""
  var standardError = ""
  var prompts: [String] = []

  init(
    isInputTerminal: Bool = true,
    isOutputTerminal: Bool = true,
    responses: [String] = []
  ) {
    self.isInputTerminal = isInputTerminal
    self.isOutputTerminal = isOutputTerminal
    self.responses = responses
  }

  func write(_ text: String) {
    standardOutput += text
  }

  func writeError(_ text: String) {
    standardError += text
  }

  func readLine(prompt: String) -> String? {
    prompts.append(prompt)
    guard !responses.isEmpty else {
      return nil
    }
    return responses.removeFirst()
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
