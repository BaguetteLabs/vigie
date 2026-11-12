import Foundation

/// One example script the app bundles (Story 12.7, A85): its file in the bundle and its parsed definition.
public struct BundledExample: Identifiable, Sendable {
    /// The file name (`github-prs.md`), also the name of the copy in the scripts folder.
    public let id: String
    public let url: URL
    public let definition: ScriptModuleDefinition

    public var fileName: String { id }
    public var name: String { definition.frontMatter?.name ?? id }
}

/// Why an example could not be added.
public enum ExampleAddError: Error, Equatable, Sendable {
    /// The host has no scripts folder.
    case noFolder
    /// `<scripts folder>/<file>` already exists; it is never replaced.
    case exists(fileName: String)
    /// Another file of the folder declares the example's id (both files would error).
    case idInUse(fileName: String, usedBy: String)
}

extension IntegrationsModule {
    /// The bundled subset of the example scripts (SPEC §9.6): GitHub PRs, site status and Mac uptime, sorted by
    /// file name. The others live in the Script repository.
    public nonisolated static var bundledExamples: [BundledExample] {
        // SwiftPM's `.process` flattens the folder under the build system `swift test` uses and keeps it under
        // Xcode's: the only Markdown files in the bundle are the examples either way.
        let urls =
            (Bundle.module.urls(forResourcesWithExtension: "md", subdirectory: "Examples") ?? [])
            + (Bundle.module.urls(forResourcesWithExtension: "md", subdirectory: nil) ?? [])
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            let definition = ScriptModuleDefinition(url: url, folderName: "modules", data: data, enabled: { _ in nil })
            return BundledExample(id: url.lastPathComponent, url: url, definition: definition)
        }
    }

    /// Copies `example` into `<config folder>/modules/` (creating the folder if needed) and rescans. The copy
    /// then follows the normal awaiting-confirmation path (SPEC §9.2): nothing runs until the user confirms it.
    /// An existing file is never overwritten.
    @discardableResult
    public func addExample(_ example: BundledExample) async throws -> URL {
        guard let folder = context?.scriptFolder.url else { throw ExampleAddError.noFolder }
        if let id = example.definition.frontMatter?.id,
            let other = scripts.first(where: { $0.frontMatter?.id == id && $0.fileName != example.fileName })
        {
            throw ExampleAddError.idInUse(fileName: example.fileName, usedBy: other.fileName)
        }
        let target = folder.appendingPathComponent(example.fileName, isDirectory: false)
        let data = try Data(contentsOf: example.url)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try data.write(to: target, options: .withoutOverwriting)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            throw ExampleAddError.exists(fileName: example.fileName)
        }
        await rescan()
        return target
    }
}
