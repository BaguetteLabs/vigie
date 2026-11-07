import Foundation
import VigieCLI

let status = CLI.run(arguments: Array(CommandLine.arguments.dropFirst())) { print($0) }
exit(status)
