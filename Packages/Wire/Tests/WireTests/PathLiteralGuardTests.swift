import Foundation
import Testing

/// AD-17: all paths come from `AppEnvironment`. No Swift file outside `Wire/Sources/Wire`
/// may spell a path literal.
@Suite struct PathLiteralGuardTests {
    // Built by concatenation so this file does not match itself.
    static let forbidden = [
        "Application" + " Support",
        ".config" + "/vigie",
        "vigie" + ".sock",
    ]

    static func repoRoot(from file: String = #filePath) -> URL? {
        var dir = URL(fileURLWithPath: file).deletingLastPathComponent()
        let fm = FileManager.default
        while dir.path != "/" {
            if fm.fileExists(atPath: dir.appendingPathComponent("Packages").path),
                fm.fileExists(atPath: dir.appendingPathComponent("App").path)
            {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    @Test func noPathLiteralsOutsideWire() throws {
        let root = try #require(Self.repoRoot())
        let fm = FileManager.default
        let wireSources = root.appendingPathComponent("Packages/Wire/Sources/Wire").standardizedFileURL.path + "/"
        var scanned = 0
        var violations: [String] = []
        for top in ["Packages", "App"] {
            let base = root.appendingPathComponent(top)
            guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for case let url as URL in walker {
                let name = url.lastPathComponent
                if name == ".build" || name == ".worktrees" {
                    walker.skipDescendants()
                    continue
                }
                guard url.pathExtension == "swift" else { continue }
                if url.standardizedFileURL.path.hasPrefix(wireSources) { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                scanned += 1
                for literal in Self.forbidden where text.contains(literal) {
                    violations.append("\(url.path): \(literal)")
                }
            }
        }
        #expect(scanned > 0)
        #expect(violations.isEmpty, "Path literals outside Wire: \(violations)")
    }
}
