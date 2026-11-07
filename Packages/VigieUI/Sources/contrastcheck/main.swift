import Foundation
import VigieUI

// Story 2.15 / UX-DR94: WCAG contrast of the DESIGN contrast and further-surfaces pairs on the built-in themes.
// Usage: contrastcheck [--themes <folder with base.toml and the variant files>] [--quiet]
// Exits 1 when a Chrome Hologram pair DESIGN claims passes is below its minimum (4.5:1 text, 3:1 non-text).

var arguments = Array(CommandLine.arguments.dropFirst())
var themesFolder: URL?
var verbose = true
while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
    case "--themes":
        guard let path = arguments.first else {
            FileHandle.standardError.write(Data("contrastcheck: --themes needs a folder\n".utf8))
            exit(2)
        }
        arguments.removeFirst()
        themesFolder = URL(fileURLWithPath: path, isDirectory: true)
    case "--quiet":
        verbose = false
    default:
        FileHandle.standardError.write(Data("contrastcheck: unknown argument \(argument)\n".utf8))
        exit(2)
    }
}

let library: ThemeLibrary
do {
    library = try themesFolder.map(ThemeLoader.loadBuiltIns(from:)) ?? ThemeLoader.loadBundled()
} catch {
    FileHandle.standardError.write(Data("contrastcheck: cannot load themes: \(error)\n".utf8))
    exit(2)
}

let results = ContrastAudit.evaluate(library: library)
print(ContrastAudit.report(results, verbose: verbose))
let drift = ContrastAudit.claimDrift(results)
if !drift.isEmpty {
    print("note: \(drift.count) measured ratios differ from the value DESIGN states by more than 0.1:")
    for r in drift {
        print(String(format: "  %@: measured %.2f, DESIGN %.2f", r.pair.description, r.ratio, r.pair.designClaim ?? 0))
    }
}
let failures = results.filter { $0.status == .fail }
if !failures.isEmpty {
    FileHandle.standardError.write(Data("contrastcheck: \(failures.count) pair(s) below the minimum\n".utf8))
    exit(1)
}
print("check-contrast: OK")
