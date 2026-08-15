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
}

enum TerminalPickerRenderer {
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
      return commandMouseTarget(
        column: column,
        line: line,
        mappings: [
          ("Space 标记", .text(" ")),
          ("v 范围", .text("v")),
          ("a 全选", .text("a")),
          ("i 反选", .text("i")),
          ("x 清空", .text("x")),
          ("a/", .text("a")),
          ("/i/", .text("i")),
          ("/x", .text("x")),
          ("esc 撤销", .escape),
          ("↵ 操作", .enter),
          ("t 退出", .text("t")),
          ("K 强退", .text("K")),
          ("f 筛选", .text("f")),
          ("F1/?/H 帮助", .help),
          ("?/H 帮助", .help),
          ("? 帮助", .help),
          ("q 关闭", .text("q")),
          ("Space", .text(" ")),
          ("v", .text("v")),
          ("↵", .enter),
          ("t", .text("t")),
          ("K", .text("K")),
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
      let line = TerminalText.padded(
        compactValues(session: session, height: height, width: width)[2],
        to: width
      )
      return commandMouseTarget(
        column: column,
        line: line,
        mappings: [
          ("Space", .text(" ")),
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
        ("H", .escape),
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
    let line: String
    if height < 6 || width < 20 {
      let values = compactValues(session: session, height: height, width: width)
      guard values.indices.contains(row - 1) else {
        return nil
      }
      line = TerminalText.padded(values[row - 1], to: width)
    } else {
      guard row == height else {
        return nil
      }
      line = bottomBorder(session: session, width: width)
    }
    var mappings: [(String, PickerEvent)] = [
      ("n/Esc 返回", .cancelExit),
      ("n 返回", .cancelExit),
      ("/n", .cancelExit),
      ("n", .cancelExit),
      ("返回", .cancelExit),
    ]
    if session.isConfirmationTargetAvailable {
      mappings.insert(("y 执行", .confirmExit), at: 0)
      mappings.insert(("y/", .confirmExit), at: 1)
    }
    return commandMouseTarget(column: column, line: line, mappings: mappings)
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
        contentStyle: statusContentStyle(session: session),
        colorEnabled: colorEnabled
      ),
      framed(
        tableLine(
          application: nil,
          selected: false,
          marked: false,
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
              marked: session.isMarked(visible[index])
                || session.isConfirmationTarget(visible[index]),
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
    let values = compactValues(session: session, height: height, width: width)

    return (0..<height).map { index in
      let value = values.indices.contains(index) ? values[index] : ""
      return styled(
        TerminalText.padded(value, to: width),
        as: index == 1 ? .selected : .normal,
        colorEnabled: colorEnabled
      )
    }
  }

  private static func compactValues(session: PickerSession, height: Int, width: Int) -> [String] {
    if case .confirming = session.phase {
      let action = session.confirmationPlan?.action == .quit ? "正常退出" : "强制退出"
      let total = session.confirmationPlan?.applications.count ?? 0
      let commandCandidates =
        session.isConfirmationTargetAvailable
        ? ["y 执行 · n 返回", "y/n", "n"]
        : ["n/Esc 返回", "n 返回", "n"]
      let command =
        commandCandidates.first(where: { TerminalText.displayWidth($0) <= width })
        ?? "n"
      let title = "确认 · \(action) · \(total) 个"
      if height <= 1 {
        return [command]
      }
      if height == 2 {
        return [title, command]
      }
      return [title, confirmationWarning(session: session), command]
    }
    let visible = session.state.visibleApplications
    let application = session.state.selectedApplication
    let action = session.defaultAction == .forceQuit ? "强退" : "退出"
    let sort = sortLabel(session.state.sortOrder)
    let refresh = session.isPaused ? "已暂停" : "实时"
    return [
      "fq · \(action) · \(sort) · \(refresh)",
      application.map {
        let marker = session.isMarked($0) || session.isConfirmationTarget($0) ? ">✓" : "> "
        return "\(marker) \(TerminalText.sanitize($0.name)) · \($0.processIdentifier)"
      }
        ?? "没有匹配",
      "\(visible.isEmpty ? 0 : session.state.selectedIndex + 1)/\(visible.count) · hjkl · Space · ↵ · q",
    ]
  }

  private static func confirmationLines(
    session: PickerSession,
    height: Int,
    width: Int,
    colorEnabled: Bool
  ) -> [String] {
    pickerLines(
      session: session,
      height: height,
      width: width,
      colorEnabled: colorEnabled
    )
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
      ("h/j/k/l 或方向键  排序/移动 · Home/End  跳转 · PgUp/PgDn  翻页", .normal),
      ("鼠标滚轮浏览 · 单击定位 · 再点标记/取消 · 标题/底栏控件可点", .normal),
      ("长列表右侧 ↑/↓ 翻页 · 点击轨迹跳转 · 拖动滑块滚动", .normal),
      ("列表", .accent),
      ("←/→  切换智能/应用/PID/状态 · r  反向", .normal),
      ("u  暂停/继续实时应用列表", .normal),
      ("选择", .accent),
      ("Space  标记/取消 · v  范围（j/k 扩展，v 完成，Esc 撤销）", .normal),
      ("a  全选可见 · i  反选可见 · x  清空全部标记", .normal),
      ("筛选", .accent),
      ("f 或 /  编辑 · ←/→/Home/End  移动光标", .normal),
      ("Backspace/Delete  删除 · Ctrl-U  清空 · Enter  应用 · Esc  还原筛选与选择", .normal),
      ("操作", .accent),
      ("Enter  \(defaultAction) · t  正常退出 · K  强制退出", .normal),
      ("有标记时对整组执行；没有标记时只操作当前行。", .normal),
      ("确认时保留列表上下文；y 执行，n/Esc/Enter/Space 返回。", .warning),
      ("F1、? 或 H  帮助 · q/Esc/Ctrl-C  取消 · Ctrl-Z  挂起，fg 返回", .normal),
    ]
    let condensed: [(String, ContentStyle)] = [
      ("导航  hjkl/方向键 排序与移动 · Home/End 跳转 · PgUp/PgDn 翻页", .accent),
      ("鼠标 滚轮浏览 · 单击定位/再点标记 · 滚动条点击/拖动", .normal),
      ("列表  ←/→ 切换排序 · r 反向 · u 暂停/继续", .normal),
      ("选择  Space 切换 · v 范围 · a 全选 · i 反选 · x 清空", .normal),
      ("筛选  f/ 编辑 · ←→ 移动 · BS/Del 删除 · ^U 清空 · ↵ 应用 · Esc 还原", .normal),
      ("操作  Enter \(defaultAction) · t 正常退出 · K 强制退出", .normal),
      ("确认  y 执行 · n/Esc/Enter/Space 返回", .warning),
      ("F1/?/H 帮助 · q/Esc/Ctrl-C 取消 · Ctrl-Z 挂起，fg 返回", .normal),
    ]
    let terse: [(String, ContentStyle)] = [
      ("hjkl/方向键 选择与排序", .accent),
      ("Space/v/a/i/x 选择 · f/ 筛选", .normal),
      ("↵/t/K 操作 · u 暂停 · r 反向", .normal),
      ("确认 y 执行 · n/Esc 返回", .warning),
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

  private static let helpFooter = "F1 / ? / H / q / esc  返回"

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
        lines: ["fq 帮助", "hjkl · Space · t/K", returnLabel],
        returnLabel: returnLabel,
        returnRow: 3
      )
    }
    return CompactHelpLayout(
      lines: [
        "fq 帮助",
        "hjkl/方向键 · Space 标记",
        "f 筛选 · ↵/t/K 操作",
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

  private static func statusContentStyle(session: PickerSession) -> ContentStyle {
    if let plan = session.confirmationPlan {
      return !session.isConfirmationTargetAvailable || plan.action == .forceQuit
        ? .warning : .accent
    }
    if session.isRangeSelecting {
      return .accent
    }
    return session.isPaused ? .warning : .normal
  }

  private static func confirmationWarning(session: PickerSession) -> String {
    let applications = session.confirmationPlan?.applications ?? []
    let isBatch = applications.count > 1
    let isForceQuit = session.confirmationPlan?.action == .forceQuit
    if !session.isConfirmationTargetAvailable {
      return isBatch
        ? "所有目标均已退出；不会发送请求"
        : "目标应用已经退出或不再可用；fq 不会发送退出请求"
    }
    if session.unavailableConfirmationTargetCount > 0 {
      return
        "跳过 \(session.unavailableConfirmationTargetCount) 个；只会处理剩余 \(session.confirmationAvailableApplications.count) 个"
    }
    if isForceQuit, applications.contains(where: \.isFinder) {
      return isBatch
        ? "未保存内容可能丢失；Finder 将由 macOS 自动重新打开"
        : "Finder 会被强制退出，并由 macOS 自动重新打开"
    }
    if isForceQuit {
      return isBatch ? "这些应用中未保存的内容可能会丢失" : "未保存的内容可能会丢失"
    }
    return isBatch
      ? "逐个请求正常退出；应用可以拒绝或显示保存提示"
      : "应用可以拒绝或显示保存提示"
  }

  private static func topBorder(session: PickerSession, width: Int) -> String {
    let leading = width >= 10 ? "─ fq " : "─"
    if let plan = session.confirmationPlan {
      let action = plan.action == .forceQuit ? "强制退出" : "正常退出"
      let count = plan.applications.count
      let candidates = [
        " 确认\(action) ×\(count) ─",
        " 确认 ×\(count) ─",
        " 确认 ─",
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

    let action = session.defaultAction == .forceQuit ? "模式 强退" : "模式 退出"
    let sort = sortLabel(session.state.sortOrder)
    let reverse = session.state.isSortReversed ? "r 反向:开" : "r 反向:关"
    let pauseAction = session.isPaused ? "u 继续" : "u 暂停"
    let refresh = session.isRangeSelecting ? "范围选择" : (session.isPaused ? "已暂停" : "实时")
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
    if case .confirming = session.phase {
      actions =
        session.isConfirmationTargetAvailable
        ? [
          "─ y 执行 │ n/Esc 返回 ",
          "─ y 执行 │ n 返回 ",
          "─ y │ n ",
          "─ ",
        ]
        : [
          "─ 目标已退出 │ n/Esc 返回 ",
          "─ n 返回 ",
          "─ ",
        ]
    } else if case .filtering = session.phase {
      actions = [
        "─ 输入筛选 │ ←→ 光标 │ ↵ 应用 │ esc 还原 │ ^U 清空 ",
        "─ 输入 │ ←→ 光标 │ ↵ 应用 │ esc 返回 ",
        "─ ↵ 应用 │ esc ",
        "─ ",
      ]
    } else if session.isRangeSelecting {
      actions = [
        "─ 范围选择 │ jk 扩展 │ v/Space 完成 │ esc 撤销 │ ↵/t/K 操作 ",
        "─ jk 扩展 │ v 完成 │ esc 撤销 │ ↵/t/K ",
        "─ v 完成 │ esc 撤销 ",
        "─ ",
      ]
    } else {
      actions = [
        "─ jk 移动 │ Space 标记 │ v 范围 │ a 全选 │ i 反选 │ x 清空 │ ↵ 操作 │ t 退出 │ K 强退 │ f 筛选 │ ? 帮助 │ q 关闭 ",
        "─ jk │ Space 标记 │ v 范围 │ a/i/x │ ↵/t/K │ ? │ q ",
        "─ jk │ Space │ v │ a/i/x │ t/K │ q ",
        "─ jk │ Space │ q ",
        "─ ",
      ]
    }

    if case .confirming = session.phase {
      let total = session.confirmationPlan?.applications.count ?? 0
      let available = session.confirmationAvailableApplications.count
      let trailing = " \(available)/\(total) 可用 ─"
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

    let marked =
      session.markedApplicationIdentities.isEmpty
      ? "" : "已选 \(session.markedApplicationIdentities.count) · "
    let trailing = " \(marked)\(location) ─"
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

    if case .confirming = session.phase {
      return fit(
        left: " ! \(confirmationWarning(session: session))",
        right: "",
        width: width
      )
    } else if let message = session.statusMessage {
      left = " 提示  \(message)"
      baseRight = session.isRangeSelecting ? "v 完成 · esc 撤销" : "f / 筛选"
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

    let marked =
      session.markedApplicationIdentities.isEmpty
      ? "" : "已选 \(session.markedApplicationIdentities.count) · "
    let rightBase = marked + baseRight
    let right = session.isPaused ? "已暂停 · \(rightBase)" : rightBase
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
    marked: Bool,
    innerWidth: Int
  ) -> String {
    let marker =
      application == nil
      ? "  " : "\(selected ? "›" : " ")\(marked ? "✓" : " ")"
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
