import Darwin
import FQMacOS

@main
struct FQMain {
  @MainActor
  static func main() {
    let exitCode = FQCommand().run(arguments: Array(CommandLine.arguments.dropFirst()))
    Darwin.exit(exitCode)
  }
}
