import Foundation
import VigieCLI

// Captured first: the hook's 150 ms budget is measured from process start (AD-6).
let start = ContinuousClock.now
let status = CLI.run(arguments: Array(CommandLine.arguments.dropFirst()), startedAt: start) { print($0) }
exit(status)
