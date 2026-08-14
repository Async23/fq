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

    XCTAssertTrue(output.contains("┌─ fq"))
    XCTAssertFalse(output.contains("┌─ 1 fq"))
    XCTAssertTrue(
      output.contains("f 筛选 │ u 暂停 │ r 反向:关 │ ‹ 智能 › │ 实时 │ 模式 强退")
    )
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

  func testFilteringViewRendersCursorInsideUnicodeQuery() {
    var session = makeSession()
    _ = session.handle(.text("/"))
    _ = session.handle(.text("微"))
    _ = session.handle(.text("信"))
    _ = session.handle(.moveHorizontal(-1))

    let output = render(session, rows: 16, columns: 90)

    XCTAssertTrue(output.contains("筛选› 微█信"))
    XCTAssertEqual(session.filterCursorOffset, 1)
    XCTAssertTrue(renderedLines(output).allSatisfy { TerminalText.displayWidth($0) == 89 })
  }

  func testLongFilterScrollsHorizontallyToKeepCursorVisible() {
    var session = PickerSession(
      applications: applications,
      initialQuery: "abcdefghijklmnopqrstuvwxyz0123456789",
      defaultAction: .forceQuit
    )
    _ = session.handle(.text("f"))

    let output = render(session, rows: 12, columns: 50)
    let statusLine = renderedLines(output)[1]

    XCTAssertTrue(statusLine.contains("█"))
    XCTAssertFalse(statusLine.contains("abcdefgh"))
    XCTAssertEqual(TerminalText.displayWidth(statusLine), 49)
  }

  func testForceConfirmationStaysInsidePickerAndExplainsFinderRelaunch() {
    var session = PickerSession(
      applications: [applications[2]],
      initialQuery: "",
      defaultAction: .forceQuit
    )
    _ = session.handle(.enter)

    let output = render(session, rows: 18, columns: 90)

    XCTAssertTrue(output.contains("操作确认"))
    XCTAssertTrue(output.contains("强制退出"))
    XCTAssertTrue(output.contains("Finder"))
    XCTAssertTrue(output.contains("由 macOS 自动重新打开"))
    XCTAssertTrue(output.contains("[ 执行 ]    ▸ [ 取消 ] ◂"))
    XCTAssertTrue(output.contains("←→/tab 选择 │ Enter/点击 执行"))
  }

  func testHelpViewDocumentsBtopStyleCommands() {
    var session = makeSession()
    _ = session.handle(.text("?"))

    let output = render(session, rows: 20, columns: 100)

    XCTAssertTrue(output.contains("导航"))
    XCTAssertTrue(output.contains("鼠标滚轮浏览 · 单击选择 · 再点打开动作"))
    XCTAssertTrue(output.contains("标题/底栏控件可点"))
    XCTAssertTrue(output.contains("切换智能/应用/PID/状态 · r  反向"))
    XCTAssertTrue(output.contains("u  暂停/继续实时应用列表"))
    XCTAssertTrue(output.contains("f 或 /"))
    XCTAssertTrue(output.contains("Backspace/Delete  删除"))
    XCTAssertTrue(output.contains("t  正常退出菜单 · k  强制退出菜单"))
    XCTAssertTrue(output.contains("默认选择取消"))
    XCTAssertTrue(output.contains("q 或 Esc"))
  }

  func testMouseHitTestingTracksVisibleRowsAfterScrolling() {
    let manyApplications = (1...20).map { index in
      rendererCandidate(pid: Int32(index), name: "App \(index)")
    }
    var session = PickerSession(
      applications: manyApplications,
      initialQuery: "",
      defaultAction: .forceQuit
    )
    _ = session.handle(.last)
    let dimensions = TerminalDimensions(rows: 10, columns: 90)

    XCTAssertEqual(
      TerminalPickerRenderer.mouseTarget(
        session: session,
        dimensions: dimensions,
        column: 10,
        row: 4
      ),
      .application(14)
    )
    XCTAssertEqual(
      TerminalPickerRenderer.mouseTarget(
        session: session,
        dimensions: dimensions,
        column: 10,
        row: 9
      ),
      .application(19)
    )
    XCTAssertNil(
      TerminalPickerRenderer.mouseTarget(
        session: session,
        dimensions: dimensions,
        column: 1,
        row: 4
      )
    )
  }

  func testMouseHitTestingMapsVisibleBtopStyleControlsToKeyboardCommands() {
    let session = makeSession()
    let dimensions = TerminalDimensions(rows: 24, columns: 100)

    XCTAssertEqual(
      mouseTarget(at: "f 筛选", row: 1, session: session, dimensions: dimensions),
      .command(.text("f"))
    )
    XCTAssertEqual(
      mouseTarget(at: "u 暂停", row: 1, session: session, dimensions: dimensions),
      .command(.text("u"))
    )
    XCTAssertEqual(
      mouseTarget(at: "r 反向:关", row: 1, session: session, dimensions: dimensions),
      .command(.text("r"))
    )
    XCTAssertEqual(
      mouseTarget(at: "‹ ", row: 1, session: session, dimensions: dimensions),
      .command(.moveHorizontal(-1))
    )
    XCTAssertEqual(
      mouseTarget(at: " ›", row: 1, session: session, dimensions: dimensions),
      .command(.moveHorizontal(1))
    )
    XCTAssertEqual(
      mouseTarget(at: "筛选", row: 2, session: session, dimensions: dimensions),
      .command(.text("f"))
    )
    XCTAssertEqual(
      mouseTarget(at: "↵ 强退…", row: 24, session: session, dimensions: dimensions),
      .command(.enter)
    )
    XCTAssertEqual(
      mouseTarget(at: "t 退出…", row: 24, session: session, dimensions: dimensions),
      .command(.text("t"))
    )
    XCTAssertEqual(
      mouseTarget(at: "k 强退…", row: 24, session: session, dimensions: dimensions),
      .command(.text("k"))
    )
    XCTAssertEqual(
      mouseTarget(at: "f 筛选", row: 24, session: session, dimensions: dimensions),
      .command(.text("f"))
    )
    XCTAssertEqual(
      mouseTarget(at: "? 帮助", row: 24, session: session, dimensions: dimensions),
      .command(.text("?"))
    )
    XCTAssertEqual(
      mouseTarget(at: "q 关闭", row: 24, session: session, dimensions: dimensions),
      .command(.text("q"))
    )
  }

  func testMouseHitTestingMapsClearResumeAndCompactControlsOnlyWhenVisible() {
    var filteredSession = PickerSession(
      applications: applications,
      initialQuery: "ghost",
      defaultAction: .forceQuit
    )
    let dimensions = TerminalDimensions(rows: 16, columns: 90)
    XCTAssertEqual(
      mouseTarget(
        at: "del 清除",
        row: 2,
        session: filteredSession,
        dimensions: dimensions
      ),
      .command(.deleteForward)
    )

    _ = filteredSession.handle(.text("u"))
    XCTAssertEqual(
      mouseTarget(
        at: "已暂停",
        row: 2,
        session: filteredSession,
        dimensions: dimensions
      ),
      .command(.text("u"))
    )

    let compactDimensions = TerminalDimensions(rows: 4, columns: 40)
    let compactSession = makeSession()
    XCTAssertEqual(
      mouseTarget(
        at: "↵",
        row: 3,
        session: compactSession,
        dimensions: compactDimensions
      ),
      .command(.enter)
    )
    XCTAssertEqual(
      mouseTarget(
        at: "q",
        row: 3,
        session: compactSession,
        dimensions: compactDimensions
      ),
      .command(.text("q"))
    )
  }

  func testHelpCanBeClosedByClickingItsFooterAtRegularAndTinySizes() {
    var session = makeSession()
    _ = session.handle(.text("?"))
    let dimensions = TerminalDimensions(rows: 18, columns: 90)

    XCTAssertEqual(
      mouseTarget(
        at: "? / q / esc  返回",
        row: 18,
        session: session,
        dimensions: dimensions
      ),
      .command(.escape)
    )

    let tinyDimensions = TerminalDimensions(rows: 2, columns: 10)
    let output = render(session, rows: tinyDimensions.rows, columns: tinyDimensions.columns)
    XCTAssertEqual(renderedLines(output).count, 2)
    XCTAssertEqual(
      TerminalPickerRenderer.mouseTarget(
        session: session,
        dimensions: tinyDimensions,
        column: 1,
        row: 2
      ),
      .command(.escape)
    )
  }

  func testMouseHitTestingFindsBothConfirmationButtons() {
    var session = makeSession()
    _ = session.handle(.enter)
    let dimensions = TerminalDimensions(rows: 18, columns: 90)
    var targets: [PickerMouseTarget] = []

    for row in 1...dimensions.rows {
      for column in 1..<dimensions.columns {
        if let target = TerminalPickerRenderer.mouseTarget(
          session: session,
          dimensions: dimensions,
          column: column,
          row: row
        ) {
          targets.append(target)
        }
      }
    }

    XCTAssertTrue(targets.contains(.confirmationExecute))
    XCTAssertTrue(targets.contains(.confirmationCancel))
  }

  func testMouseHitTestingExposesOnlyReturnWhenConfirmationTargetDisappears() {
    var session = makeSession()
    _ = session.handle(.enter)
    _ = session.replaceApplications([])
    let dimensions = TerminalDimensions(rows: 18, columns: 90)
    var targets: [PickerMouseTarget] = []

    for row in 1...dimensions.rows {
      for column in 1..<dimensions.columns {
        if let target = TerminalPickerRenderer.mouseTarget(
          session: session,
          dimensions: dimensions,
          column: column,
          row: row
        ) {
          targets.append(target)
        }
      }
    }

    XCTAssertFalse(targets.contains(.confirmationExecute))
    XCTAssertTrue(targets.contains(.confirmationCancel))
  }

  func testNormalQuitShortcutOpensNonDestructiveActionPanel() {
    var session = makeSession()
    _ = session.handle(.text("t"))

    let output = render(session, rows: 18, columns: 90)

    XCTAssertTrue(output.contains("正常退出"))
    XCTAssertTrue(output.contains("应用可以拒绝或显示保存提示"))
    XCTAssertTrue(output.contains("[ 执行 ]    ▸ [ 取消 ] ◂"))
    XCTAssertFalse(output.contains("未保存的内容可能会丢失"))
  }

  func testBrowseTextShowsFilterHintInsteadOfChangingQuery() {
    var session = makeSession()
    _ = session.handle(.text("c"))

    let output = render(session, rows: 16, columns: 90)

    XCTAssertTrue(output.contains("提示  筛选请先按 f 或 /"))
    XCTAssertTrue(output.contains("f / 筛选"))
    XCTAssertEqual(session.state.query, "")
  }

  func testBrowseHeaderReflectsSortFieldAndReverseState() {
    var session = makeSession()

    _ = session.handle(.moveHorizontal(1))
    var output = render(session, rows: 16, columns: 90)
    XCTAssertTrue(output.contains("‹ 应用 ›"))
    XCTAssertTrue(output.contains("r 反向:关"))

    _ = session.handle(.text("r"))
    output = render(session, rows: 16, columns: 90)
    XCTAssertTrue(output.contains("‹ 应用 ›"))
    XCTAssertTrue(output.contains("r 反向:开"))
  }

  func testPausedListMakesFrozenStateAndResumeActionVisible() {
    var session = makeSession()
    _ = session.handle(.text("u"))

    let output = render(session, rows: 16, columns: 100)

    XCTAssertTrue(output.contains("u 继续"))
    XCTAssertTrue(output.contains("已暂停 │ 模式 强退"))
    XCTAssertTrue(output.contains("已暂停 · 3 个应用"))
  }

  func testActionOnEmptyFilterExplainsWhyNothingOpened() {
    var session = PickerSession(
      applications: applications,
      initialQuery: "does-not-match",
      defaultAction: .forceQuit
    )

    XCTAssertEqual(session.handle(.enter), .stay(redraw: true))
    let output = render(session, rows: 16, columns: 90)

    XCTAssertEqual(session.phase, .browse)
    XCTAssertTrue(output.contains("提示  当前筛选没有匹配"))
    XCTAssertTrue(output.contains("0/0"))
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
    XCTAssertTrue(output.contains("▸ [ 返回 ] ◂"))
    XCTAssertTrue(output.contains("Enter/Esc 返回"))
    XCTAssertFalse(output.contains("[ 执行 ]"))
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

  private func mouseTarget(
    at label: String,
    row: Int,
    session: PickerSession,
    dimensions: TerminalDimensions
  ) -> PickerMouseTarget? {
    let output = render(session, rows: dimensions.rows, columns: dimensions.columns)
    let line = renderedLines(output)[row - 1]
    guard let range = line.range(of: label) else {
      XCTFail("Expected rendered row \(row) to contain \(label)")
      return nil
    }
    let column = TerminalText.displayWidth(String(line[..<range.lowerBound])) + 1
    return TerminalPickerRenderer.mouseTarget(
      session: session,
      dimensions: dimensions,
      column: column,
      row: row
    )
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
