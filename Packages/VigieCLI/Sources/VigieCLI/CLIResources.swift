import Darwin
import Foundation

/// Locates this module's String Catalog bundle, also when the CLI runs through a symlink.
///
/// SwiftPM's generated `Bundle.module` looks next to `Bundle.main`, which for a command-line
/// tool is the folder of the path it was *invoked* through. Hooks call the CLI through
/// `~/.local/bin/<cliName>` (AD-22), so `Bundle.module` would look there and `fatalError`.
/// This finder resolves the real executable first: the resource bundle sits next to it in a
/// SwiftPM build folder, or in `Contents/Resources` when the CLI is `Contents/Helpers/<cliName>`
/// inside the app. It then tries the same places as `Bundle.module`, and never traps: without
/// a bundle, lookups return their keys.
enum CLIResources {
    static let bundleName = "VigieCLI_VigieCLI"

    static let bundle: Bundle = locate(executable: realExecutableURL()) ?? .main

    static func locate(executable: URL?) -> Bundle? {
        var folders: [URL?] = []
        if let directory = executable?.deletingLastPathComponent() {
            folders.append(directory)
            folders.append(directory.deletingLastPathComponent().appendingPathComponent("Resources", isDirectory: true))
        }
        folders += [Bundle.main.resourceURL, Bundle(for: Finder.self).resourceURL, Bundle.main.bundleURL]
        for folder in folders.compactMap({ $0 }) {
            if let bundle = Bundle(url: folder.appendingPathComponent(bundleName + ".bundle")) { return bundle }
        }
        return nil
    }

    /// This process's executable with every symlink resolved.
    static func realExecutableURL() -> URL? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buffer, &size) == 0, let resolved = realpath(buffer, nil) else { return nil }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    private final class Finder {}
}
