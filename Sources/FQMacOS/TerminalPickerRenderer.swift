import FQCore
import Foundation

struct TerminalDimensions: Equatable {
  let rows: Int
  let columns: Int
}

enum PickerMouseTarget: Equatable {
  case application(Int)
  case command(PickerEvent)
  case scrollbarThumb
  case confirmationExecute
  case confirmationCancel
}

enum TerminalPickerRenderer {
  private struct CompactConfirmationLayout {
    let lines: [String]
    let buttons: String
    let buttonRow: Int?
  }

  private struct CompactHelpLayout {
    let lines: [String]
    let returnLabel: String
    let returnRow: Int?
  }

  private struct ListScrollbarLayout {
    let listRows: Int
    let trackCount: Int
    let thumbOffset: Int
    let viewportStartIndex: Int
    let maxStartIndex: Int

    func cell(forListOffset offset: Int) -> String {
      if offset == listRows - 1 {
        return "↓"
      }
      return offset == thumbOffset ? "█" : " "
    }

    func startIndex(forTrackOffset requestedOffset: Int) -> Int {
      guard trackCount > 1 else {
        return viewportStartIndex
      }
      let trackOffset = min(max(0, requestedOffset), trackCount - 1)
      return Int(
        (Double(trackOffset) * Double(maxStartIndex) / Double(trackCount - 1)).rounded()
      )
    }
  }

  static func render(
    session: PickerSession,
    dimensions: TerminalDimensions,
    colorEnabled: Bool,
    clearScreen: Bool
  ) -> String {
    let height = max(1, dimensions.rows)
    let width = max(1, dimensions.columns - 1)

    let lines: [String]
    switch session.phase {
    case .browse, .filtering:
      lines = pickerLines(
        session: session, height: height, width: width, colorEnabled: colorEnabled)
    case .confirming:
      lines = confirmationLines(
        session: session,
        height: height,
        width: width,
        colorEnabled: colorEnabled
      )
    case .help:
      lines = helpLines(
        session: session,
        height: height,
        width: width,
        colorEnabled: colorEnabled
      )
    }

    let home = "\u{001B}[H"
    let clear = clearScreen ? "\u{001B}[2J" : ""
    return home + clear + lines.prefix(height).joined(separator: "\r\n")
  }

  static func mouseTarget(
    session: PickerSession,
    dimensions: TerminalDimensions,
    column: Int,
    row: Int
  ) -> PickerMouseTarget? {
    let height = max(1, dimensions.rows)
    let width = max(1, dimensions.columns - 1)
    guard (1...width).contains(column), (1...height).contains(row) else {
      return nil
    }

    switch session.phase {
    case .browse:
      return browseMouseTarget(
        session: session,
        height: height,
        width: width,
        column: column,
        row: row
      )
    case .confirming:
      return confirmationMouseTarget(
        session: session,
        height: height,
        width: width,
        column: column,
        row: row
      )
    case .help:
      return helpMouseTarget(
        height: height,
        width: width,
        column: column,
        row: row
      )
    case .filtering:
      return nil
    }
  }

  static func scrollbarDragTarget(
    session: PickerSession,
    dimensions: TerminalDimensions,
    row: Int
  ) -> PickerMouseTarget? {
    guard case .browse = session.phase else {
      return nil
    }
    let height = max(1, dimensions.rows)
    guard let scrollbar = listScrollbarLayout(session: session, height: height) else {
      return nil
    }

    let trackOffset = min(max(0, row - 4), scrollbar.trackCount - 1)
    return .command(
      .positionViewport(
        startIndex: scrollbar.startIndex(forTrackOffset: trackOffset),
        listRows: scrollbar.listRows
      )
    )
  }

  private static func browseMouseTarget(
    session: PickerSession,
    height: Int,
    width: Int,
    column: Int,
    row: Int
  ) -> PickerMouseTarget? {
    if height < 6 || width < 20 {
      return compactBrowseMouseTarget(
        session: session,
        height: height,
        width: width,
        column: column,
        row: row
      )
    }

    if row == 1 {
      let line = topBorder(session: session, width: width)
      let pauseAction = session.isPaused ? "u 继续" : "u 暂停"
      let reverse = session.state.isSortReversed ? "r 反向:开" : "r 反向:关"
      return commandMouseTarget(
        column: column,
        line: line,
        mappings: [
          ("f 筛选", .text("f")),
          (pauseAction, .text("u")),
          (reverse, .text("r")),
          ("‹ ", .moveHorizontal(-1)),
          (" ›", .moveHorizontal(1)),
        ]
      )
    }

    if row == 2 {
      let line = filterStatus(session: session, width: width - 2)
      if !session.state.query.isEmpty,
        contains(column: column, label: "del 清除", in: line, startingAt: 2)
      {
        return .command(.deleteForward)
      }
      if session.isPaused,
        contains(column: column, label: "已暂停", in: line, startingAt: 2)
      {
        return .command(.text("u"))
      }
      if contains(column: column, label: "筛选", in: line, startingAt: 2) {
        return .command(.text("f"))
      }
      return nil
    }

    if let target = scrollbarMouseTarget(
      session: session,
      height: height,
      width: width,
      column: column,
      row: row
    ) {
      return target
    }

    if row == height {
      let line = bottomBorder(session: session, width: width)
      let enterAction = session.defaultAction == .forceQuit ? "强退" : "退出"
      return commandMouseTarget(
        column: column,
        line: line,
        mappings: [
          ("↵ \(enterAction)…", .enter),
          ("↵ \(enterAction)", .enter),
          ("t 退出…", .text("t")),
          ("k 强退…", .text("k")),
          ("f 筛选", .text("f")),
          ("F1/?/h 帮助", .help),
          ("?/h 帮助", .help),
          ("? 帮助", .help),
          ("q 关闭", .text("q")),
          ("↵", .enter),
          ("t", .text("t")),
          ("k", .text("k")),
          ("?", .help),
          ("q", .text("q")),
        ]
      )
    }

    return applicationMouseTarget(
      session: session,
      height: height,
      width: width,
      column: column,
      row: row
    )
  }

  private static func scrollbarMouseTarget(
    session: PickerSession,
    height: Int,
    width: Int,
    column: Int,
    row: Int
  ) -> PickerMouseTarget? {
    guard column == width - 1,
      let scrollbar = listScrollbarLayout(session: session, height: height)
    else {
      return nil
    }

    if row == 3 {
      return .command(
        .positionViewport(
          startIndex: max(0, scrollbar.viewportStartIndex - scrollbar.listRows),
          listRows: scrollbar.listRows
        )
      )
    }
    if row == height - 1 {
      return .command(
        .positionViewport(
          startIndex: min(
            scrollbar.maxStartIndex,
            scrollbar.viewportStartIndex + scrollbar.listRows
          ),
          listRows: scrollbar.listRows
        )
      )
    }

    let trackOffset = row - 4
    guard (0..<scrollbar.trackCount).contains(trackOffset) else {
      return nil
    }
    if trackOffset == scrollbar.thumbOffset {
      return .scrollbarThumb
    }

    return .command(
      .positionViewport(
        startIndex: scrollbar.startIndex(forTrackOffset: trackOffset),
        listRows: scrollbar.listRows
      )
    )
  }

  private static func compactBrowseMouseTarget(
    session: PickerSession,
    height: Int,
    width: Int,
    column: Int,
    row: Int
  ) -> PickerMouseTarget? {
    if row == 3, height >= 3 {
      let line = TerminalText.padded(compactValues(session: session)[2], to: width)
      return commandMouseTarget(
        column: column,
        line: line,
        mappings: [
          ("↵", .enter),
          ("q", .text("q")),
        ]
      )
    }
    return applicationMouseTarget(
      session: session,
      height: height,
      width: width,
      column: column,
      row: row
    )
  }

  private static func helpMouseTarget(
    height: Int,
    width: Int,
    column: Int,
    row: Int
  ) -> PickerMouseTarget? {
    if !usesFramedHelp(height: height, width: width) {
      let layout = compactHelpLayout(height: height)
      guard let returnRow = layout.returnRow, row == returnRow else {
        return nil
      }
      let visibleLabel = TerminalText.clipped(layout.returnLabel, to: width)
      guard !visibleLabel.isEmpty else {
        return nil
      }
      let line = TerminalText.centered(layout.returnLabel, in: width)
      return contains(
        column: column,
        label: visibleLabel,
        in: line,
        startingAt: 1
      ) ? .command(.escape) : nil
    }

    guard row == height else {
      return nil
    }
    let line = horizontalBorder(
      start: "└",
      end: "┘",
      leading: "─ \(helpFooter) ",
      trailing: "─",
      width: width
    )
    return commandMouseTarget(
      column: column,
      line: line,
      mappings: [
        (helpFooter, .escape),
        ("返回", .escape),
        ("esc", .escape),
        ("q", .escape),
        ("?", .escape),
        ("h", .escape),
        ("F1", .escape),
      ]
    )
  }

  private static func commandMouseTarget(
    column: Int,
    line: String,
    mappings: [(String, PickerEvent)]
  ) -> PickerMouseTarget? {
    for (label, event) in mappings
    where contains(column: column, label: label, in: line, startingAt: 1) {
      return .command(event)
    }
    return nil
  }

  private static func applicationMouseTarget(
    session: PickerSession,
    height: Int,
    width: Int,
    column: Int,
    row: Int
  ) -> PickerMouseTarget? {
    let visible = session.state.visibleApplications
    guard !visible.isEmpty, column > 1, column < width else {
      return nil
    }

    if height < 6 || width < 20 {
      return row == 2 ? .application(session.state.selectedIndex) : nil
    }

    let offset = row - 4
    let visibleRange = visibleApplicationRange(session: session, height: height)
    guard offset >= 0 else {
      return nil
    }
    let index = visibleRange.lowerBound + offset
    guard visibleRange.contains(index) else {
      return nil
    }
    return .application(index)
  }

  private static func confirmationMouseTarget(
    session: PickerSession,
    height: Int,
    width: Int,
    column: Int,
    row: Int
  ) -> PickerMouseTarget? {
    guard usesFullConfirmation(height: height, width: width) else {
      return compactConfirmationMouseTarget(
        session: session,
        height: height,
        width: width,
        column: column,
        row: row
      )
    }

    let contentCount = 6
    let interiorRows = height - 2
    guard interiorRows >= contentCount else {
      return nil
    }

    let topPadding = max(0, (interiorRows - contentCount) / 2)
    let buttonRow = 2 + topPadding + contentCount - 1
    guard row == buttonRow else {
      return nil
    }

    let buttons = confirmationButtons(session: session)
    let innerWidth = width - 2
    let buttonsWidth = TerminalText.displayWidth(buttons)
    guard buttonsWidth <= innerWidth else {
      return nil
    }
    let startColumn = 2 + (innerWidth - buttonsWidth) / 2

    if session.isConfirmationTargetAvailable,
      contains(
        column: column,
        label: "[ 执行 ]",
        in: buttons,
        startingAt: startColumn
      )
    {
      return .confirmationExecute
    }

    let cancelLabel = session.isConfirmationTargetAvailable ? "[ 取消 ]" : "[ 返回 ]"
    if contains(
      column: column,
      label: cancelLabel,
      in: buttons,
      startingAt: startColumn
    ) {
      return .confirmationCancel
    }
    return nil
  }

  private static func compactConfirmationMouseTarget(
    session: PickerSession,
    height: Int,
    width: Int,
    column: Int,
    row: Int
  ) -> PickerMouseTarget? {
    let layout = compactConfirmationLayout(session: session, height: height, width: width)
    guard let buttonRow = layout.buttonRow, row == buttonRow else {
      return nil
    }
    let line = TerminalText.centered(layout.buttons, in: width)

    if session.isConfirmationTargetAvailable,
      contains(column: column, label: "执行", in: line, startingAt: 1)
    {
      return .confirmationExecute
    }
    let cancelLabel = session.isConfirmationTargetAvailable ? "取消" : "返回"
    if contains(column: column, label: cancelLabel, in: line, startingAt: 1) {
      return .confirmationCancel
    }
    return nil
  }

  private static func contains(
    column: Int,
    label: String,
    in text: String,
    startingAt startColumn: Int
  ) -> Bool {
    var searchStart = text.startIndex
    while searchStart < text.endIndex,
      let range = text.range(of: label, range: searchStart..<text.endIndex)
    {
      let prefix = String(text[..<range.lowerBound])
      let lowerBound = startColumn + TerminalText.displayWidth(prefix)
      let upperBound = lowerBound + TerminalText.displayWidth(label) - 1
      if (lowerBound...upperBound).contains(column) {
        return true
      }
      searchStart = range.upperBound
    }
    return false
  }

  private static func visibleApplicationRange(
    session: PickerSession,
    height: Int
  ) -> Range<Int> {
    let listRows = max(0, height - 4)
    return session.visibleApplicationRange(listRows: listRows)
  }

  private static func listScrollbarLayout(
    session: PickerSession,
    height: Int
  ) -> ListScrollbarLayout? {
    let visibleCount = session.state.visibleApplications.count
    let listRows = max(0, height - 4)
    guard listRows >= 2, visibleCount > listRows else {
      return nil
    }

    let startIndex = visibleApplicationRange(session: session, height: height).lowerBound
    let maxStartIndex = visibleCount - listRows
    let trackCount = listRows - 1
    let maxThumbOffset = max(0, trackCount - 1)
    let thumbOffset = Int(
      (Double(startIndex) * Double(maxThumbOffset) / Double(maxStartIndex)).rounded()
    )
    return ListScrollbarLayout(
      listRows: listRows,
      trackCount: trackCount,
      thumbOffset: thumbOffset,
      viewportStartIndex: startIndex,
      maxStartIndex: maxStartIndex
    )
  }

  private static func pickerLines(
    session: PickerSession,
    height: Int,
    width: Int,
    colorEnabled: Bool
  ) -> [String] {
    guard height >= 6, width >= 20 else {
      return compactLines(
        session: session, height: height, width: width, colorEnabled: colorEnabled)
    }

    let visible = session.state.visibleApplications
    let selectedIndex = min(session.state.selectedIndex, max(0, visible.count - 1))
    let visibleRange = visibleApplicationRange(session: session, height: height)
    let scrollbar = listScrollbarLayout(session: session, height: height)
    let scrollbarWidth = scrollbar == nil ? 0 : 1

    var lines = [
      styled(
        topBorder(session: session, width: width),
        as: .border,
        colorEnabled: colorEnabled
      ),
      framed(
        filterStatus(session: session, width: width - 2),
        width: width,
        contentStyle: session.isPaused ? .warning : .normal,
        colorEnabled: colorEnabled
      ),
      framed(
        tableLine(
          application: nil,
          selected: false,
          innerWidth: width - 2 - scrollbarWidth
        ) + (scrollbar == nil ? "" : "↑"),
        width: width,
        contentStyle: .bold,
        colorEnabled: colorEnabled
      ),
    ]

    if visible.isEmpty {
      let query = TerminalText.sanitize(session.state.query)
      let message = query.isEmpty ? "  没有运行中的普通应用" : "  没有匹配 “\(query)” 的应用"
      lines.append(
        framed(
          message,
          width: width,
          contentStyle: .warning,
          colorEnabled: colorEnabled
        )
      )
    } else if !visibleRange.isEmpty {
      for (offset, index) in visibleRange.enumerated() {
        let scrollbarCell = scrollbar?.cell(forListOffset: offset) ?? ""
        lines.append(
          framed(
            tableLine(
              application: visible[index],
              selected: index == selectedIndex,
              innerWidth: width - 2 - TerminalText.displayWidth(scrollbarCell)
            ) + scrollbarCell,
            width: width,
            contentStyle: index == selectedIndex ? .selected : .normal,
            colorEnabled: colorEnabled
          )
        )
      }
    }

    while lines.count < height - 1 {
      lines.append(
        framed("", width: width, contentStyle: .normal, colorEnabled: colorEnabled)
      )
    }

    lines.append(
      styled(
        bottomBorder(session: session, width: width),
        as: .border,
        colorEnabled: colorEnabled
      )
    )
    return lines
  }

  private static func compactLines(
    session: PickerSession,
    height: Int,
    width: Int,
    colorEnabled: Bool
  ) -> [String] {
    let values = compactValues(session: session)

    return (0..<height).map { index in
      let value = values.indices.contains(index) ? values[index] : ""
      return styled(
        TerminalText.padded(value, to: width),
        as: index == 1 ? .selected : .normal,
        colorEnabled: colorEnabled
      )
    }
  }

  private static func compactValues(session: PickerSession) -> [String] {
    let visible = session.state.visibleApplications
    let application = session.state.selectedApplication
    let action = session.defaultAction == .forceQuit ? "强退" : "退出"
    let sort = sortLabel(session.state.sortOrder)
    let refresh = session.isPaused ? "已暂停" : "实时"
    return [
      "fq · \(action) · \(sort) · \(refresh)",
      application.map { "> \(TerminalText.sanitize($0.name)) · \($0.processIdentifier)" }
        ?? "没有匹配",
      "\(visible.isEmpty ? 0 : session.state.selectedIndex + 1)/\(visible.count) · ↑↓ · ↵ · q",
    ]
  }

  private static func confirmationLines(
    session: PickerSession,
    height: Int,
    width: Int,
    colorEnabled: Bool
  ) -> [String] {
    guard usesFullConfirmation(height: height, width: width) else {
      let layout = compactConfirmationLayout(session: session, height: height, width: width)
      return compactOverlayLines(
        layout.lines,
        height: height,
        width: width,
        colorEnabled: colorEnabled,
        accentedRow: layout.buttonRow.map { $0 - 1 }
      )
    }

    let selection = session.confirmationSelection
    let actionName = selection?.action == .quit ? "正常退出" : "强制退出"
    let application = selection?.application
    let isAvailable = session.isConfirmationTargetAvailable
    let isForceQuit = selection?.action == .forceQuit
    let name = TerminalText.sanitize(application?.name ?? "未知应用")
    let identity =
      application.map { "PID \($0.processIdentifier) · \($0.bundleIdentifier ?? "无 Bundle ID")" }
      ?? "应用已不可用"
    let warning: String
    if !isAvailable {
      warning = "目标应用已经退出或不再可用；fq 不会发送退出请求。"
    } else if isForceQuit, application?.isFinder == true {
      warning = "Finder 会被强制退出，并由 macOS 自动重新打开。"
    } else if isForceQuit {
      warning = "此应用中未保存的内容可能会丢失。"
    } else {
      warning = "fq 会请求应用正常退出；应用可以拒绝或显示保存提示。"
    }
    let buttons = confirmationButtons(session: session)
    let warningStyle: ContentStyle = !isAvailable || isForceQuit ? .warning : .normal
    let content = [
      (actionName, isForceQuit ? ContentStyle.warning : ContentStyle.accent),
      (name, ContentStyle.accent),
      (identity, ContentStyle.normal),
      ("", ContentStyle.normal),
      (warning, warningStyle),
      (buttons, ContentStyle.accent),
    ]

    return overlayFrame(
      title: "操作确认",
      content: content,
      footer: confirmationFooter(session: session, width: width),
      height: height,
      width: width,
      colorEnabled: colorEnabled
    )
  }

  private static func usesFullConfirmation(height: Int, width: Int) -> Bool {
    height >= 8 && width >= 26
  }

  private static func confirmationFooter(session: PickerSession, width: Int) -> String {
    let candidates =
      session.isConfirmationTargetAvailable
      ? [
        "←→/Tab 选择 │ Enter/Space 执行所选 │ Y 执行 │ N/Esc 返回",
        "←→/Tab │ Enter/Space 确认 │ Y 执行 │ N/Esc 返回",
        "Y 执行 │ N/Esc 返回",
        "Esc 返回",
      ]
      : [
        "目标已退出 │ Enter/Space/N/Esc 返回 │ Ctrl-C 取消",
        "Enter/Space/N/Esc 返回",
        "N/Esc 返回",
        "Esc 返回",
      ]
    let availableWidth = max(0, width - 6)
    return candidates.first(where: { TerminalText.displayWidth($0) <= availableWidth })
      ?? "返回"
  }

  private static func compactConfirmationLayout(
    session: PickerSession,
    height: Int,
    width: Int
  ) -> CompactConfirmationLayout {
    let selection = session.confirmationSelection
    let actionName = selection?.action == .quit ? "正常退出" : "强制退出"
    let name = TerminalText.sanitize(selection?.application.name ?? "未知应用")
    let title = "\(actionName) · \(name)"
    let buttons = compactConfirmationButtons(session: session, width: width)
    let warning: String
    if !session.isConfirmationTargetAvailable {
      warning = "目标已退出 · 不会发送请求"
    } else if selection?.action == .forceQuit, selection?.application.isFinder == true {
      warning = "Finder 将由 macOS 自动重新打开"
    } else if selection?.action == .forceQuit {
      warning = "未保存的内容可能会丢失"
    } else {
      warning = "应用可以拒绝或显示保存提示"
    }

    if height <= 1 {
      return CompactConfirmationLayout(
        lines: [buttons],
        buttons: buttons,
        buttonRow: 1
      )
    }
    return CompactConfirmationLayout(
      lines: [title, buttons, warning],
      buttons: buttons,
      buttonRow: 2
    )
  }

  private static func compactConfirmationButtons(
    session: PickerSession,
    width: Int
  ) -> String {
    let fullButtons = confirmationButtons(session: session)
    if TerminalText.displayWidth(fullButtons) <= width {
      return fullButtons
    }
    guard session.isConfirmationTargetAvailable else {
      return "▸返回◂"
    }
    if width >= 12 {
      return session.confirmationChoice == .execute
        ? "▸执行◂  取消" : "执行  ▸取消◂"
    }
    return session.confirmationChoice == .execute ? "▸执行◂" : "▸取消◂"
  }

  private static func confirmationButtons(session: PickerSession) -> String {
    guard session.isConfirmationTargetAvailable else {
      return "▸ [ 返回 ] ◂"
    }
    if session.confirmationChoice == .execute {
      return "▸ [ 执行 ] ◂    [ 取消 ]"
    }
    return "[ 执行 ]    ▸ [ 取消 ] ◂"
  }

  private static func helpLines(
    session: PickerSession,
    height: Int,
    width: Int,
    colorEnabled: Bool
  ) -> [String] {
    guard usesFramedHelp(height: height, width: width) else {
      let layout = compactHelpLayout(height: height)
      return compactOverlayLines(
        layout.lines,
        height: height,
        width: width,
        colorEnabled: colorEnabled
      )
    }

    return overlayFrame(
      title: "帮助",
      content: helpContent(session: session, height: height, width: width),
      footer: helpFooter,
      height: height,
      width: width,
      colorEnabled: colorEnabled
    )
  }

  private static func usesFramedHelp(height: Int, width: Int) -> Bool {
    height >= 6 && width >= 32
  }

  private static func helpContent(
    session: PickerSession,
    height: Int,
    width: Int
  ) -> [(String, ContentStyle)] {
    let defaultAction = session.defaultAction == .forceQuit ? "强制退出" : "正常退出"
    let full: [(String, ContentStyle)] = [
      ("导航", .accent),
      ("↑/↓ 或 Ctrl-P/Ctrl-N  移动 · Home/End  跳转 · PgUp/PgDn  翻页", .normal),
      ("鼠标滚轮浏览 · 单击选择 · 再点打开动作 · 标题/底栏控件可点", .normal),
      ("长列表右侧 ↑/↓ 翻页 · 点击轨迹跳转 · 拖动滑块滚动", .normal),
      ("列表", .accent),
      ("←/→  切换智能/应用/PID/状态 · r  反向", .normal),
      ("u  暂停/继续实时应用列表", .normal),
      ("筛选", .accent),
      ("f 或 /  编辑 · ←/→/Home/End  移动光标", .normal),
      ("Backspace/Delete  删除 · Ctrl-U  清空 · Enter  应用 · Esc  还原筛选与选择", .normal),
      ("操作", .accent),
      ("Enter  \(defaultAction)菜单 · t  正常退出菜单 · k  强制退出菜单", .normal),
      ("动作面板默认选择取消；←/→/Tab 切换，Enter/Space 执行所选；Y 直接执行，N 返回。", .warning),
      ("F1、? 或 h  帮助 · q/Esc/Ctrl-C  取消 · Ctrl-Z  挂起，fg 返回", .normal),
    ]
    let condensed: [(String, ContentStyle)] = [
      ("导航  ↑/↓ 移动 · Home/End 跳转 · PgUp/PgDn 翻页", .accent),
      ("鼠标 滚轮浏览 · 单击选择/再点动作 · 滚动条点击/拖动", .normal),
      ("列表  ←/→ 切换排序 · r 反向 · u 暂停/继续", .normal),
      ("筛选  f 或 / 编辑 · ←/→/Home/End 移动光标", .normal),
      ("Backspace/Delete 删除 · Ctrl-U 清空 · Enter 应用 · Esc 还原", .normal),
      ("操作  Enter \(defaultAction) · t 正常退出 · k 强制退出", .normal),
      ("默认取消 · ←→/Tab 切换 · ↵/Space 确认 · Y 执行 · N 返回", .warning),
      ("F1/?/h 帮助 · q/Esc/Ctrl-C 取消 · Ctrl-Z 挂起，fg 返回", .normal),
    ]
    let terse: [(String, ContentStyle)] = [
      ("↑↓/滚轮 选择 · ←→ 排序", .accent),
      ("f/ 筛选 · u 暂停 · r 反向", .normal),
      ("↵ \(defaultAction) · t 退出 · k 强退", .normal),
      ("默认取消 · Y 执行 · N/Esc 返回", .warning),
    ]
    let capacity = max(0, height - 2)
    if width >= 88, capacity >= full.count {
      return full
    }
    if width >= 58, capacity >= condensed.count {
      return condensed
    }
    return terse
  }

  private static let helpFooter = "F1 / ? / h / q / esc  返回"

  private static func compactHelpLayout(height: Int) -> CompactHelpLayout {
    let returnLabel = "q/Esc 返回"
    if height <= 1 {
      return CompactHelpLayout(
        lines: [returnLabel],
        returnLabel: returnLabel,
        returnRow: 1
      )
    }
    if height == 2 {
      return CompactHelpLayout(
        lines: ["fq 帮助", returnLabel],
        returnLabel: returnLabel,
        returnRow: 2
      )
    }
    if height == 3 {
      return CompactHelpLayout(
        lines: ["fq 帮助", "↑↓ · f · ↵", returnLabel],
        returnLabel: returnLabel,
        returnRow: 3
      )
    }
    return CompactHelpLayout(
      lines: [
        "fq 帮助",
        "↑↓/滚轮 · ←→排序",
        "f 筛选 · ↵ 动作",
        returnLabel,
      ],
      returnLabel: returnLabel,
      returnRow: 4
    )
  }

  private static func compactOverlayLines(
    _ content: [String],
    height: Int,
    width: Int,
    colorEnabled: Bool,
    accentedRow: Int? = nil
  ) -> [String] {
    (0..<height).map { index in
      let value = content.indices.contains(index) ? content[index] : ""
      let style: ContentStyle =
        index == accentedRow ? .accent : (index == 0 ? .warning : .normal)
      return styled(
        TerminalText.centered(value, in: width),
        as: style,
        colorEnabled: colorEnabled
      )
    }
  }

  private static func overlayFrame(
    title: String,
    content: [(String, ContentStyle)],
    footer: String,
    height: Int,
    width: Int,
    colorEnabled: Bool
  ) -> [String] {
    let interiorRows = height - 2
    let visibleContent = Array(content.prefix(interiorRows))
    let topPadding = max(0, (interiorRows - visibleContent.count) / 2)
    var lines = [
      styled(
        horizontalBorder(
          start: "┌",
          end: "┐",
          leading: "─ fq ",
          trailing: " \(title) ─",
          width: width
        ),
        as: .border,
        colorEnabled: colorEnabled
      )
    ]

    for _ in 0..<topPadding {
      lines.append(framed("", width: width, contentStyle: .normal, colorEnabled: colorEnabled))
    }
    for (text, style) in visibleContent {
      lines.append(
        framed(
          TerminalText.centered(text, in: width - 2),
          width: width,
          contentStyle: style,
          colorEnabled: colorEnabled
        )
      )
    }
    while lines.count < height - 1 {
      lines.append(framed("", width: width, contentStyle: .normal, colorEnabled: colorEnabled))
    }

    lines.append(
      styled(
        horizontalBorder(
          start: "└",
          end: "┘",
          leading: "─ \(footer) ",
          trailing: "─",
          width: width
        ),
        as: .border,
        colorEnabled: colorEnabled
      )
    )
    return lines
  }

  private static func topBorder(session: PickerSession, width: Int) -> String {
    let action = session.defaultAction == .forceQuit ? "模式 强退" : "模式 退出"
    let sort = sortLabel(session.state.sortOrder)
    let reverse = session.state.isSortReversed ? "r 反向:开" : "r 反向:关"
    let pauseAction = session.isPaused ? "u 继续" : "u 暂停"
    let refresh = session.isPaused ? "已暂停" : "实时"
    let leading = width >= 10 ? "─ fq " : "─"
    let candidates = [
      " f 筛选 │ \(pauseAction) │ \(reverse) │ ‹ \(sort) › │ \(refresh) │ \(action) ─",
      " \(pauseAction) │ \(reverse) │ ‹ \(sort) › │ \(refresh) │ \(action) ─",
      " \(pauseAction) │ ‹ \(sort) › │ \(refresh) │ \(action) ─",
      " \(pauseAction) │ \(refresh) │ \(action) ─",
      " \(refresh) │ \(action) ─",
      " \(action) ─",
      "─",
    ]
    let trailing =
      candidates.first(where: {
        TerminalText.displayWidth(leading) + TerminalText.displayWidth($0) <= width - 2
      }) ?? "─"
    return horizontalBorder(
      start: "┌",
      end: "┐",
      leading: leading,
      trailing: trailing,
      width: width
    )
  }

  private static func sortLabel(_ order: PickerSortOrder) -> String {
    switch order {
    case .smart:
      "智能"
    case .name:
      "应用"
    case .processIdentifier:
      "PID"
    case .status:
      "状态"
    }
  }

  private static func bottomBorder(session: PickerSession, width: Int) -> String {
    let visible = session.state.visibleApplications
    let location = "\(visible.isEmpty ? 0 : session.state.selectedIndex + 1)/\(visible.count)"
    let actions: [String]
    if case .filtering = session.phase {
      actions = [
        "─ 输入筛选 │ ←→ 光标 │ ↵ 应用 │ esc 还原 │ ^U 清空 ",
        "─ 输入 │ ←→ 光标 │ ↵ 应用 │ esc 返回 ",
        "─ ↵ 应用 │ esc ",
        "─ ",
      ]
    } else {
      let enterAction = session.defaultAction == .forceQuit ? "强退" : "退出"
      actions = [
        "─ ↑↓ 选择 │ ↵ \(enterAction)… │ t 退出… │ k 强退… │ f 筛选 │ F1/?/h 帮助 │ q 关闭 ",
        "─ ↑↓ │ ↵ \(enterAction)… │ t 退出… │ k 强退… │ ? │ q ",
        "─ ↑↓ │ ↵ \(enterAction) │ t/k │ q ",
        "─ ↑↓ │ ↵ │ q ",
        "─ ",
      ]
    }

    let trailing = " \(location) ─"
    let leading =
      actions.first(where: {
        TerminalText.displayWidth($0) + TerminalText.displayWidth(trailing) <= width - 2
      }) ?? "─ "
    return horizontalBorder(
      start: "└",
      end: "┘",
      leading: leading,
      trailing: trailing,
      width: width
    )
  }

  private static func filterStatus(session: PickerSession, width: Int) -> String {
    let visibleCount = session.state.visibleApplications.count
    let query = TerminalText.sanitize(session.state.query)
    let left: String
    let baseRight: String

    if let message = session.statusMessage {
      left = " 提示  \(message)"
      baseRight = "f / 筛选"
    } else if case .filtering(let edit) = session.phase {
      let baseRight = "↵ 应用 · esc 还原"
      let right = session.isPaused ? "已暂停 · \(baseRight)" : baseRight
      return fitFilterEditor(
        query: session.state.query,
        cursorOffset: edit.cursorOffset,
        right: right,
        width: width
      )
    } else if query.isEmpty {
      left = " 筛选  全部应用"
      baseRight = "\(visibleCount) 个应用"
    } else {
      left = " 筛选  \(query)"
      baseRight = "\(visibleCount) 个匹配 · del 清除"
    }

    let right = session.isPaused ? "已暂停 · \(baseRight)" : baseRight
    return fit(left: left, right: right, width: width)
  }

  private static func fitFilterEditor(
    query: String,
    cursorOffset: Int,
    right: String,
    width: Int
  ) -> String {
    guard width > 0 else {
      return ""
    }

    let rightText = TerminalText.clipped(
      right,
      to: min(TerminalText.displayWidth(right), width / 2)
    )
    let availableLeft = max(
      0,
      width - TerminalText.displayWidth(rightText) - (rightText.isEmpty ? 0 : 1)
    )
    let leftText = filterEditor(
      query: query,
      cursorOffset: cursorOffset,
      width: availableLeft
    )
    let spacing = max(
      0,
      width - TerminalText.displayWidth(leftText) - TerminalText.displayWidth(rightText)
    )
    return leftText + String(repeating: " ", count: spacing) + rightText
  }

  private static func filterEditor(
    query: String,
    cursorOffset: Int,
    width: Int
  ) -> String {
    let label = " 筛选› "
    let labelWidth = TerminalText.displayWidth(label)
    guard width > labelWidth else {
      return TerminalText.clipped(label, to: width)
    }

    let characters = Array(query)
    let cursor = min(max(0, cursorOffset), characters.count)
    let prefix = TerminalText.sanitize(String(characters[..<cursor]))
    let suffix = TerminalText.sanitize(String(characters[cursor...]))
    let contentWidth = width - labelWidth - 1
    var leftBudget = min(TerminalText.displayWidth(prefix), contentWidth / 2)
    var rightBudget = min(TerminalText.displayWidth(suffix), contentWidth - leftBudget)
    leftBudget = min(TerminalText.displayWidth(prefix), contentWidth - rightBudget)
    rightBudget = min(TerminalText.displayWidth(suffix), contentWidth - leftBudget)

    let visiblePrefix = TerminalText.suffixFitting(prefix, in: leftBudget)
    let visibleSuffix = TerminalText.prefixFitting(suffix, in: rightBudget)
    return label + visiblePrefix + "█" + visibleSuffix
  }

  private static func tableLine(
    application: ApplicationCandidate?,
    selected: Bool,
    innerWidth: Int
  ) -> String {
    let marker = application == nil ? "  " : (selected ? "› " : "  ")
    let pid = application.map { String($0.processIdentifier) } ?? "PID"
    let name = application.map { TerminalText.sanitize($0.name) } ?? "应用"
    let bundle =
      application.map { TerminalText.sanitize($0.bundleIdentifier ?? "-") } ?? "BUNDLE ID"
    let state: String
    if let application, application.isActive {
      state = "● 活跃"
    } else if let application, application.isHidden {
      state = "◇ 隐藏"
    } else {
      state = application == nil ? "状态" : "—"
    }

    if innerWidth >= 72 {
      let pidWidth = 7
      let nameWidth = min(22, max(16, innerWidth / 4))
      let stateWidth = 8
      let bundleWidth = max(1, innerWidth - 2 - pidWidth - nameWidth - stateWidth - 3)
      return marker
        + TerminalText.leftPadded(pid, to: pidWidth) + " "
        + TerminalText.padded(name, to: nameWidth) + " "
        + TerminalText.padded(bundle, to: bundleWidth) + " "
        + TerminalText.padded(state, to: stateWidth)
    }

    if innerWidth >= 42 {
      let pidWidth = 7
      let stateWidth = 8
      let nameWidth = max(1, innerWidth - 2 - pidWidth - stateWidth - 2)
      return marker
        + TerminalText.leftPadded(pid, to: pidWidth) + " "
        + TerminalText.padded(name, to: nameWidth) + " "
        + TerminalText.padded(state, to: stateWidth)
    }

    let pidWidth = min(7, max(3, innerWidth / 3))
    let nameWidth = max(1, innerWidth - 2 - pidWidth - 1)
    return marker
      + TerminalText.leftPadded(pid, to: pidWidth) + " "
      + TerminalText.padded(name, to: nameWidth)
  }

  private static func framed(
    _ content: String,
    width: Int,
    contentStyle: ContentStyle,
    colorEnabled: Bool
  ) -> String {
    guard width > 1 else {
      return styled(
        TerminalText.padded(content, to: width), as: contentStyle, colorEnabled: colorEnabled)
    }
    let inner = TerminalText.padded(content, to: width - 2)
    return styled("│", as: .border, colorEnabled: colorEnabled)
      + styled(inner, as: contentStyle, colorEnabled: colorEnabled)
      + styled("│", as: .border, colorEnabled: colorEnabled)
  }

  private static func horizontalBorder(
    start: String,
    end: String,
    leading: String,
    trailing: String,
    width: Int
  ) -> String {
    guard width > 1 else {
      return start
    }
    let interiorWidth = width - 2
    let leadingWidth = TerminalText.displayWidth(leading)
    let trailingWidth = TerminalText.displayWidth(trailing)
    guard leadingWidth + trailingWidth <= interiorWidth else {
      let fallback = TerminalText.clipped(leading + trailing, to: interiorWidth)
      return start + TerminalText.padded(fallback, to: interiorWidth) + end
    }
    return start + leading
      + String(repeating: "─", count: interiorWidth - leadingWidth - trailingWidth)
      + trailing + end
  }

  private static func fit(left: String, right: String, width: Int) -> String {
    guard width > 0 else {
      return ""
    }
    let rightText = TerminalText.clipped(
      right, to: min(TerminalText.displayWidth(right), width / 2))
    let availableLeft = max(
      0, width - TerminalText.displayWidth(rightText) - (rightText.isEmpty ? 0 : 1))
    let leftText = TerminalText.clipped(left, to: availableLeft)
    let spacing = max(
      0, width - TerminalText.displayWidth(leftText) - TerminalText.displayWidth(rightText))
    return leftText + String(repeating: " ", count: spacing) + rightText
  }

  private static func styled(
    _ text: String,
    as style: ContentStyle,
    colorEnabled: Bool
  ) -> String {
    guard colorEnabled else {
      return text
    }

    let code: String
    switch style {
    case .normal:
      return text
    case .border:
      code = "38;5;71"
    case .bold:
      code = "1"
    case .selected:
      code = "1;7"
    case .warning:
      code = "1;33"
    case .accent:
      code = "1;36"
    }
    return "\u{001B}[\(code)m\(text)\u{001B}[0m"
  }
}

private enum ContentStyle {
  case normal
  case border
  case bold
  case selected
  case warning
  case accent
}
