import Foundation
import ThemeGenKit

do {
    try ThemeGenCommand.run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("themegen: \(error)\n".utf8))
    exit(1)
}
