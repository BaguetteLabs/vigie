import AgentKit
import Foundation

/// The recorded hook payloads in `Tests/Fixtures/<cli version>/<event>[.<variant>].json` (AD-23).
enum FixtureCatalog {
    struct Fixture {
        let version: String
        let event: String
        /// `nil` for `<event>.json`, else the middle part of `<event>.<variant>.json`.
        let variant: String?
        let url: URL

        /// `Event` or `Event.variant`.
        var name: String { variant.map { "\(event).\($0)" } ?? event }

        func raw() throws -> JSONValue {
            try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        }
    }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    /// Version folder names, sorted.
    static var versions: [String] {
        let items =
            (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]))
            ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent).sorted()
    }

    static func fixtures(version: String) -> [Fixture] {
        let folder = root.appendingPathComponent(version, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.map { url in
            let parts = url.deletingPathExtension().lastPathComponent.split(separator: ".", maxSplits: 1)
            return Fixture(
                version: version, event: String(parts[0]), variant: parts.count > 1 ? String(parts[1]) : nil, url: url)
        }.sorted { $0.name < $1.name }
    }

    static func fixture(_ name: String, version: String = "2.1.319") throws -> Fixture {
        guard let fixture = fixtures(version: version).first(where: { $0.name == name }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return fixture
    }
}
