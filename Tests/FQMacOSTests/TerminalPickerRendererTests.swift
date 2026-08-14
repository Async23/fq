import XCTest

@testable import FQCore
@testable import FQMacOS

final class TerminalPickerRendererTests: XCTestCase {
  private let applications = [
    rendererCandidate(
      pid: 63471,
      name: "Ghostty",
      bundleIdentifier: "com.mitchellh.ghostty",
      isActive: true
    ),
    rendererCandidate(
      pid: 8814,
      name: "微信",
      bundleIdentifier: "com.tencent.xinWeChat",
      isHidden: true
    ),
    rendererCandidate(pid: 1433, name: "Finder", bundleIdentifier: "com.apple.finder"),
  ]

  func testWidePickerUsesBtopStyleFrameColumnsActionsAndLocation() {
    let output = render(makeSession(), rows: 24, columns: 100)

    XCTAssertTrue(output.contains("┌─ 1 fq"))
    XCTAssertTrue(output.contains("f 筛选 │ 实时 │ 模式 强退"))
    XCTAssertTrue(output.contains("PID"))
    XCTAssertTrue(output.contains("应用"))
    XCTAssertTrue(output.contains("BUNDLE ID"))
    XCTAssertTrue(output.contains("状态"))
    XCTAssertTrue(output.contains("● 活跃"))
    XCTAssertTrue(output.contains("◇ 隐藏"))
    XCTAssertTrue(output.contains("t 退出"))
    XCTAssertTrue(output.contains("k 强退"))
    XCTAssertTrue(output.contains("1/3"))

    let lines = renderedLines(output)
    XCTAssertEqual(lines.count, 24)
    XCTAssertTrue(lines.allSatisfy { TerminalText.displayWidth($0) == 99 })
  }

  func testNarrowPickerDropsBundleColumnWithoutBreakingFrameWidth() {
    let output = render(makeSession(), rows: 12, columns: 50)

    XCTAssertFalse(output.contains("BUNDLE ID"))
    XCTAssertTrue(output.contains("应用"))
    XCTAssertEqual(renderedLines(output).count, 12)
    XCTAssertTrue(renderedLines(output).allSatisfy { TerminalText.displayWidth($0) == 49 })
  }

  func testFilteringViewSurfacesModeLiveQueryAndRestoreAction() {
    var session = makeSession()
    _ = session.handle(.text("/"))
    _ = session.handle(.text("微"))

    let output = render(session, rows: 16, columns: 90)

    XCTAssertTrue(output.contains("筛选› 微█"))
    XCTAssertTrue(output.contains("↵ 应用 · esc 还原"))
    XCTAssertTrue(output.contains("输入筛选"))
    XCTAssertTrue(output.contains("微信"))
    XCTAssertFalse(output.contains("Ghostty"))
  }

  func testForceConfirmationStaysInsidePickerAndExplainsFinderRelaunch() {
    var session = PickerSession(
      applications: [applications[2]],
      initialQuery: "",
      defaultAction: .forceQuit
    )
    _ = session.handle(.enter)

    let output = render(session, rows: 18, columns: 90)

    XCTAssertTrue(output.contains("确认"))
    XCTAssertTrue(output.contains("Finder"))
    XCTAssertTrue(output.contains("由 macOS 自动重新打开"))
    XCTAssertTrue(output.contains("Enter 不会确认"))
    XCTAssertTrue(output.contains("y 确认 │ n/esc 返回"))
  }

  func testHelpViewDocumentsBtopStyleCommands() {
    var session = makeSession()
    _ = session.handle(.text("?"))

    let output = render(session, rows: 20, columns: 100)

    XCTAssertTrue(output.contains("导航"))
    XCTAssertTrue(output.contains("f 或 /"))
    XCTAssertTrue(output.contains("t  正常退出 · k  强制退出"))
    XCTAssertTrue(output.contains("q 或 Esc"))
  }

  func testConfirmationDisablesActionWhenRefreshedTargetHasExited() {
    var session = PickerSession(
      applications: applications,
      initialQuery: "",
      defaultAction: .forceQuit
    )
    _ = session.handle(.enter)
    _ = session.replaceApplications(Array(applications.dropFirst()))

    let output = render(session, rows: 18, columns: 90)

    XCTAssertTrue(output.contains("目标应用已经退出或不再可用"))
    XCTAssertTrue(output.contains("fq 不会发送退出请求"))
    XCTAssertTrue(output.contains("按 Esc 返回实时应用列表"))
    XCTAssertFalse(output.contains("y 确认 │"))
  }

  private func makeSession() -> PickerSession {
    PickerSession(
      applications: applications,
      initialQuery: "",
      defaultAction: .forceQuit
    )
  }

  private func render(
    _ session: PickerSession,
    rows: Int,
    columns: Int
  ) -> String {
    TerminalPickerRenderer.render(
      session: session,
      dimensions: TerminalDimensions(rows: rows, columns: columns),
      colorEnabled: false,
      clearScreen: true
    )
  }

  private func renderedLines(_ output: String) -> [String] {
    let prefix = "\u{001B}[H\u{001B}[2J"
    return output.replacingOccurrences(of: prefix, with: "")
      .components(separatedBy: "\r\n")
  }
}

private func rendererCandidate(
  pid: Int32,
  name: String,
  bundleIdentifier: String? = nil,
  isActive: Bool = false,
  isHidden: Bool = false
) -> ApplicationCandidate {
  ApplicationCandidate(
    id: ApplicationIdentity(
      processIdentifier: pid,
      bundleIdentifier: bundleIdentifier,
      launchDate: nil
    ),
    name: name,
    isActive: isActive,
    isHidden: isHidden
  )
}
