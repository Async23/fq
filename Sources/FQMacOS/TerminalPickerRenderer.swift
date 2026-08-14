import FQCore
import Foundation

struct TerminalDimensions: Equatable {
  let rows: Int
  let columns: Int
}

enum TerminalPickerRenderer {
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
    let listRows = height - 4
    let startIndex = max(0, selectedIndex - listRows + 1)
    let endIndex = min(visible.count, startIndex + listRows)

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
        tableLine(application: nil, selected: false, innerWidth: width - 2),
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
    } else if startIndex < endIndex {
      for index in startIndex..<endIndex {
        lines.append(
          framed(
            tableLine(
              application: visible[index],
              selected: index == selectedIndex,
              innerWidth: width - 2
            ),
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
    let visible = session.state.visibleApplications
    let application = session.state.selectedApplication
    let action = session.defaultAction == .forceQuit ? "强退" : "退出"
    let sort = sortLabel(session.state.sortOrder)
    let refresh = session.isPaused ? "已暂停" : "实时"
    let values = [
      "fq · \(action) · \(sort) · \(refresh)",
      application.map { "> \(TerminalText.sanitize($0.name)) · \($0.processIdentifier)" }
        ?? "没有匹配",
      "\(visible.isEmpty ? 0 : session.state.selectedIndex + 1)/\(visible.count) · ↑↓ · ↵ · q",
    ]

    return (0..<height).map { index in
      let value = values.indices.contains(index) ? values[index] : ""
      return styled(
        TerminalText.padded(value, to: width),
        as: index == 1 ? .selected : .normal,
        colorEnabled: colorEnabled
      )
    }
  }

  private static func confirmationLines(
    session: PickerSession,
    height: Int,
    width: Int,
    colorEnabled: Bool
  ) -> [String] {
    let selection = session.confirmationSelection
    let actionName = selection?.action == .quit ? "正常退出" : "强制退出"
    guard height >= 6, width >= 20 else {
      let name =
        selection.map {
          TerminalText.sanitize($0.application.name)
        } ?? "-"
      let action =
        session.isConfirmationTargetAvailable
        ? "←→ 选择 · ↵ 执行" : "目标已退出 · ↵ 返回"
      return compactOverlayLines(
        ["确认\(actionName)", name, action],
        height: height,
        width: width,
        colorEnabled: colorEnabled
      )
    }

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
    let buttons: String
    if !isAvailable {
      buttons = "▸ [ 返回 ] ◂"
    } else if session.confirmationChoice == .execute {
      buttons = "▸ [ 执行 ] ◂    [ 取消 ]"
    } else {
      buttons = "[ 执行 ]    ▸ [ 取消 ] ◂"
    }
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
      footer: isAvailable
        ? "←→/tab 选择 │ Enter 执行所选 │ Esc 返回"
        : "Enter/Esc 返回 │ ctrl-c 取消",
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
    let defaultAction = session.defaultAction == .forceQuit ? "强制退出" : "正常退出"
    let content: [(String, ContentStyle)] = [
      ("导航", .accent),
      ("↑/↓ 或 Ctrl-P/Ctrl-N  移动 · Home/End  跳转 · PgUp/PgDn  翻页", .normal),
      ("", .normal),
      ("列表", .accent),
      ("←/→  切换智能/应用/PID/状态 · r  反向", .normal),
      ("u  暂停/继续实时应用列表", .normal),
      ("", .normal),
      ("筛选", .accent),
      ("f 或 /  编辑 · Delete/Ctrl-U  清除 · Enter  应用 · Esc  还原", .normal),
      ("", .normal),
      ("操作", .accent),
      ("Enter  \(defaultAction)菜单 · t  正常退出菜单 · k  强制退出菜单", .normal),
      ("动作面板默认选择取消；←/→/Tab 切换，Enter 执行所选。", .warning),
      ("", .normal),
      ("q 或 Esc  关闭 fq · Ctrl-C  随时取消", .normal),
    ]

    return overlayFrame(
      title: "帮助",
      content: content,
      footer: "? / q / esc  返回",
      height: height,
      width: width,
      colorEnabled: colorEnabled
    )
  }

  private static func compactOverlayLines(
    _ content: [String],
    height: Int,
    width: Int,
    colorEnabled: Bool
  ) -> [String] {
    (0..<height).map { index in
      let value = content.indices.contains(index) ? content[index] : ""
      return styled(
        TerminalText.centered(value, in: width),
        as: index == 0 ? .warning : .normal,
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
        "─ 输入筛选 │ ↵ 应用 │ esc 还原 │ ^U 清除 ",
        "─ 输入 │ ↵ 应用 │ esc 返回 ",
        "─ ↵ 应用 │ esc ",
        "─ ",
      ]
    } else {
      let enterAction = session.defaultAction == .forceQuit ? "强退" : "退出"
      actions = [
        "─ ↑↓ 选择 │ ↵ \(enterAction)… │ t 退出… │ k 强退… │ f 筛选 │ ? 帮助 │ q 关闭 ",
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
    } else if case .filtering = session.phase {
      left = " 筛选› \(query)█"
      baseRight = "↵ 应用 · esc 还原"
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
