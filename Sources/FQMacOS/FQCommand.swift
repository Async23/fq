import FQCore
import Foundation

@MainActor
public final class FQCommand {
  public static let version = "0.1.0"

  private let applicationManager: ApplicationManaging
  private let picker: ApplicationPicking
  private let console: Console

  public convenience init() {
    self.init(
      applicationManager: WorkspaceApplicationManager(),
      picker: TerminalPicker(),
      console: StandardConsole()
    )
  }

  init(
    applicationManager: ApplicationManaging,
    picker: ApplicationPicking,
    console: Console
  ) {
    self.applicationManager = applicationManager
    self.picker = picker
    self.console = console
  }

  @discardableResult
  public func run(arguments: [String]) -> Int32 {
    let mode: FQCommandMode
    do {
      mode = try CommandLineOptions.parse(arguments)
    } catch {
      console.writeError("fq: \(TerminalText.sanitize(error.localizedDescription))\n试试 fq --help\n")
      return 2
    }

    switch mode {
    case .help:
      console.write(Self.helpText)
      return 0
    case .version:
      console.write("fq \(Self.version)\n")
      return 0
    case .list(let format, let query):
      return listApplications(format: format, query: query)
    case .interactive(let action, let query):
      return runInteractive(action: action, query: query)
    }
  }

  private func listApplications(format: ApplicationListFormat, query: String) -> Int32 {
    let applications = FuzzyMatcher.rank(
      query: query,
      applications: applicationManager.runningApplications()
    )

    switch format {
    case .text:
      if applications.isEmpty {
        return 0
      }
      let lines = applications.map { application in
        let name = TerminalText.sanitize(application.name)
        let bundle = TerminalText.sanitize(application.bundleIdentifier ?? "-")
        return "\(application.processIdentifier)\t\(name)\t\(bundle)"
      }
      console.write(lines.joined(separator: "\n") + "\n")
      return 0
    case .json:
      do {
        let records = applications.map(ApplicationListRecord.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(records)
        console.write(String(decoding: data, as: UTF8.self) + "\n")
        return 0
      } catch {
        console.writeError("fq: 无法生成 JSON：\(error.localizedDescription)\n")
        return 1
      }
    }
  }

  private func runInteractive(action: ApplicationExitAction, query: String) -> Int32 {
    guard console.isInputTerminal, console.isOutputTerminal else {
      console.writeError("fq: 交互模式需要终端；查看应用可用 fq --list。\n")
      return 2
    }

    let applications = applicationManager.runningApplications()
    guard !applications.isEmpty else {
      console.writeError("fq: 没有找到可退出的普通 macOS 应用。\n")
      return 1
    }

    let selection: ApplicationExitSelection?
    do {
      selection = try picker.choose(
        from: applications,
        initialQuery: query,
        action: action,
        refreshApplications: applicationManager.runningApplications
      )
    } catch {
      console.writeError("fq: \(TerminalText.sanitize(error.localizedDescription))\n")
      return 1
    }

    guard let selection else {
      console.write("已取消。\n")
      return 0
    }

    do {
      let outcome = try applicationManager.requestExit(
        selection.application,
        action: selection.action
      )
      console.write(
        successMessage(
          for: selection.application,
          action: selection.action,
          outcome: outcome
        ) + "\n"
      )
      return 0
    } catch {
      console.writeError("fq: \(TerminalText.sanitize(error.localizedDescription))\n")
      return 1
    }
  }

  private func successMessage(
    for application: ApplicationCandidate,
    action: ApplicationExitAction,
    outcome: ApplicationExitOutcome
  ) -> String {
    switch (action, outcome) {
    case (.forceQuit, .terminated):
      "已强制退出 “\(TerminalText.sanitize(application.name))”。"
    case (.forceQuit, .requested):
      "已发送强制退出请求：“\(TerminalText.sanitize(application.name))”。"
    case (.quit, .terminated):
      "已退出 “\(TerminalText.sanitize(application.name))”。"
    case (.quit, .requested):
      "已发送正常退出请求：“\(TerminalText.sanitize(application.name))”。"
    }
  }

  private static let helpText = """
    fq — 在终端里选择并退出普通 macOS 应用

    用法：
      fq [搜索词]             选择应用，确认后强制退出
      fq --quit [搜索词]      选择应用并请求正常退出
      fq --list [搜索词]      列出与系统“强制退出应用”接近的应用范围
      fq --json [搜索词]      以 JSON 列出应用

    选项：
      -f, --force             强制退出（默认）
      -q, --quit              正常退出
      -l, --list              只列出，不操作
          --json              以 JSON 列出，不操作
      -h, --help              显示帮助
      -V, --version           显示版本

    选择器按键：
      ↑ / ↓，PgUp / PgDn      移动选择；Home / End 跳转
      f 或 /                   进入筛选
      Enter                   打开当前模式的动作面板
      t / k                   打开正常退出 / 强制退出动作
      Delete / Ctrl-U         清空筛选
      ?                       查看选择器内帮助
      q / Esc / Ctrl-C        取消

    动作面板默认选中取消；用 ← / → 或 Tab 切换，再按 Enter 执行所选项。
    应用列表会自动刷新，并按进程身份保留当前选择与确认目标。
    fq 只显示 macOS 认定为普通 GUI 应用的进程，不显示守护进程和大多数菜单栏工具。
    """ + "\n"
}

private struct ApplicationListRecord: Encodable {
  let pid: Int32
  let name: String
  let bundleIdentifier: String?
  let isActive: Bool
  let isHidden: Bool

  init(_ application: ApplicationCandidate) {
    pid = application.processIdentifier
    name = application.name
    bundleIdentifier = application.bundleIdentifier
    isActive = application.isActive
    isHidden = application.isHidden
  }
}
