import Foundation
import VigieUI

/// Feeds `[appearance]` from `ConfigStore` into ``ThemeController`` (Stories 18.1, 18.2): `theme`, `mode` and the
/// `[appearance.colors]` overrides (all looks, then `.dark` / `.light`) at start and on every change, plus the
/// custom themes of `<config folder>/themes/`, so the whole app re-skins live (AD-8, AD-14). The controller
/// layers them in the AD-14 order; an unknown theme id resolves to the default theme.
///
/// Theme problems (id clash, newer schema, unreadable file, unknown id) go to `problems`, which posts the
/// setup-problem alerts.
@MainActor
public final class AppearanceConfigBridge {
    static let themePath = CoreSettings.path("appearance", "theme")
    static let modePath = CoreSettings.path("appearance", "mode")
    static let colorsPath = ConfigKeyPath("appearance", "colors")

    private let store: ConfigStore
    private let themes: ThemeController
    private let problems: ThemeProblemReporter?
    private let watcher: any DirectoryWatching
    /// The built-in themes, without custom ones: custom themes are layered on it on every reload.
    private let baseLibrary: ThemeLibrary
    private var watchedFiles: [String]?
    private var changesTask: Task<Void, Never>?
    private var folderTask: Task<Void, Never>?

    public init(
        store: ConfigStore, themes: ThemeController, problems: ThemeProblemReporter? = nil,
        watcher: any DirectoryWatching = DispatchDirectoryWatcher()
    ) {
        self.store = store
        self.themes = themes
        self.problems = problems
        self.watcher = watcher
        self.baseLibrary = themes.library.replacingCustomThemes(from: nil)
    }

    public func start() {
        guard changesTask == nil else { return }
        let changes = store.changes  // subscribe before the first apply so no change is missed
        let folderChanges = store.location.changes()
        reloadCustomThemes()
        apply()
        changesTask = Task { [weak self] in
            for await keys in changes {
                guard let self else { return }
                if keys.contains(where: Self.isAppearanceKey) { self.apply() }
            }
        }
        folderTask = Task { [weak self] in
            for await _ in folderChanges {
                guard let self else { return }
                self.watchedFiles = nil
                self.reloadCustomThemes()
            }
        }
    }

    public func stop() {
        changesTask?.cancel()
        changesTask = nil
        folderTask?.cancel()
        folderTask = nil
        watcher.stopAll()
        watchedFiles = nil
    }

    private static func isAppearanceKey(_ key: ConfigKeyPath) -> Bool {
        key == themePath || key == modePath || key.segments.starts(with: colorsPath.segments)
    }

    private func apply() {
        let mode = store.value(Self.modePath, as: String.self).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        if themes.mode != mode { themes.mode = mode }
        let overrides = Self.colorOverrides(from: store)
        if themes.overrides != overrides { themes.overrides = overrides }
        let id = store.value(Self.themePath, as: String.self) ?? ThemeLibrary.defaultVariantID
        if themes.variantID != id { themes.variantID = id }
        problems?.reconcile(themes.problems)
    }

    /// Reads the custom theme files and replaces the controller's library when they differ. Watches the folder
    /// (and the files in it, for in-place saves) so an edit or a new file applies live.
    private func reloadCustomThemes() {
        let folder = store.location.themesFolderURL
        let library = baseLibrary.replacingCustomThemes(from: folder)
        if library != themes.library { themes.replaceLibrary(library) }
        let files = Self.themeFileNames(in: folder)
        if files != watchedFiles {
            watchedFiles = files
            watcher.stopAll()
            watcher.watch(folder, files: files) { [weak self] in self?.reloadCustomThemes() }
        }
        problems?.reconcile(themes.problems)
    }

    private static func themeFileNames(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".toml") }.sorted()
    }

    /// `[appearance.colors]` (every look), `[appearance.colors.dark]` and `[appearance.colors.light]`. A key is a
    /// color role (`status-blocked`) or, as in the examples, its status name (`blocked`); values that are not
    /// strings are skipped here, and bad hex values are ignored by the resolver.
    static func colorOverrides(from store: ConfigStore) -> ColorOverrides {
        guard let table = store.rawTable(at: colorsPath) else { return .none }
        func roles(_ table: [String: ConfigValue]?) -> [ColorRole: String] {
            var result: [ColorRole: String] = [:]
            for (key, value) in table ?? [:] {
                guard case .string(let hex) = value else { continue }
                guard let role = ColorRole(rawValue: key) ?? ColorRole(rawValue: "status-\(key)") else { continue }
                result[role] = hex
            }
            return result
        }
        func subtable(_ name: String) -> [String: ConfigValue]? {
            if case .table(let sub) = table[name] { return sub }
            return nil
        }
        return ColorOverrides(all: roles(table), dark: roles(subtable("dark")), light: roles(subtable("light")))
    }
}
