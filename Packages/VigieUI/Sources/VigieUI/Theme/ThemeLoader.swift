import Foundation
import TOML
import os

/// The themes available to the app: the shared base, the built-in variants and any custom themes.
public struct ThemeLibrary: Sendable, Equatable {
    public var base: BaseThemeFile
    /// Built-in variants by id (`chrome-hologram`, `twin-metal-tactical`).
    public var builtIns: [String: ThemeFile]
    /// Custom themes by id (config folder `themes/`).
    public var customs: [String: ThemeFile]
    /// Problems found while loading.
    public var problems: [ThemeProblem]

    /// The default variant (DESIGN.md: Chrome Hologram).
    public static let defaultVariantID = "chrome-hologram"

    public init(
        base: BaseThemeFile,
        builtIns: [String: ThemeFile],
        customs: [String: ThemeFile] = [:],
        problems: [ThemeProblem] = []
    ) {
        self.base = base
        self.builtIns = builtIns
        self.customs = customs
        self.problems = problems
    }

    public var defaultVariant: ThemeFile? { builtIns[Self.defaultVariantID] }

    /// A theme the user can pick in Settings › Appearance.
    public struct Choice: Sendable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var isCustom: Bool

        public init(id: String, name: String, isCustom: Bool) {
            self.id = id
            self.name = name
            self.isCustom = isCustom
        }
    }

    /// Built-in themes (default first), then custom themes, each group sorted by name.
    public var choices: [Choice] {
        func sorted(_ files: [String: ThemeFile], custom: Bool) -> [Choice] {
            files.values
                .map { Choice(id: $0.id, name: $0.name, isCustom: custom) }
                .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        }
        let builtIn = sorted(builtIns, custom: false)
        let defaults = builtIn.filter { $0.id == Self.defaultVariantID }
        return defaults + builtIn.filter { $0.id != Self.defaultVariantID } + sorted(customs, custom: true)
    }

    /// ``choices``, plus an entry for `current` when no theme has that id (a typo or a removed file), so a picker
    /// shows what is configured.
    public func choices(including current: String) -> [Choice] {
        let all = choices
        guard !all.contains(where: { $0.id == current }) else { return all }
        return all + [Choice(id: current, name: current, isCustom: false)]
    }

    /// This library with the custom themes found in `folder` (`<config folder>/themes/`) in place of any it had,
    /// and their load problems added after the existing ones. Call it on a library without custom themes.
    public func replacingCustomThemes(from folder: URL?) -> ThemeLibrary {
        var copy = self
        copy.customs = [:]
        guard let folder else { return copy }
        let loaded = ThemeLoader.loadCustom(from: folder)
        for theme in loaded.themes { copy.customs[theme.id] = theme }
        copy.problems = problems + loaded.problems
        return copy
    }

    /// Resolves a theme id (built-in or custom) for a look. Unknown ids fall back to the default theme.
    public func resolve(
        themeID: String,
        look: Look,
        overrides: ColorOverrides = .none,
        accessibility: AccessibilityAdjustments = .none
    ) -> ThemeResolution {
        var problems: [ThemeProblem] = []
        let fallback = defaultVariant ?? ThemeFile(id: Self.defaultVariantID, name: "Chrome Hologram")
        let variant: ThemeFile
        var custom: ThemeFile?
        if let builtIn = builtIns[themeID] {
            variant = builtIn
        } else if let c = customs[themeID] {
            // A custom theme extends the base; when it names a built-in it starts from that skin,
            // otherwise from the default skin so every role has a value.
            variant = c.extends.flatMap { builtIns[$0] } ?? fallback
            custom = c
        } else {
            problems.append(.unknownTheme(themeID: themeID))
            variant = fallback
        }
        var resolution = ThemeResolver.resolve(
            base: base,
            variant: variant,
            custom: custom,
            fallbackVariant: fallback,
            look: look,
            customOverrides: overrides,
            accessibility: accessibility
        )
        resolution.problems.insert(contentsOf: problems, at: 0)
        return resolution
    }
}

/// Reads theme TOML files with swift-toml (decode only, AD-16).
public enum ThemeLoader {
    static let logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "theme")

    /// Built-in variant ids shipped in `Resources/Themes`.
    public static let builtInIDs = ["chrome-hologram", "twin-metal-tactical"]

    /// The bundled `Themes` folder (an identical copy of the repository `Themes/`).
    public static var bundledThemesURL: URL? {
        Bundle.module.url(forResource: "Themes", withExtension: nil)
    }

    public enum LoadError: Error, Equatable {
        case missingBundle
        case schemaTooNew(found: Int)
    }

    /// Loads base and built-in variants from the bundle.
    public static func loadBundled() throws -> ThemeLibrary {
        guard let folder = bundledThemesURL else { throw LoadError.missingBundle }
        return try loadBuiltIns(from: folder)
    }

    /// Loads `base.toml` and every built-in variant from a folder.
    public static func loadBuiltIns(from folder: URL) throws -> ThemeLibrary {
        let base = try decodeBase(Data(contentsOf: folder.appending(path: "base.toml")))
        var builtIns: [String: ThemeFile] = [:]
        var problems: [ThemeProblem] = []
        for id in builtInIDs {
            let url = folder.appending(path: "\(id).toml")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            switch decodeVariant(try Data(contentsOf: url), file: url.lastPathComponent) {
            case .success(let file): builtIns[file.id] = file
            case .failure(let problem): problems.append(problem)
            }
        }
        return ThemeLibrary(base: base, builtIns: builtIns, problems: problems)
    }

    /// Decodes `base.toml`.
    public static func decodeBase(_ data: Data) throws -> BaseThemeFile {
        let probe = try TOMLDecoder().decode(ThemeSchemaProbe.self, from: data)
        guard probe.schema <= supportedThemeSchema else { throw LoadError.schemaTooNew(found: probe.schema) }
        let base = try TOMLDecoder().decode(BaseThemeFile.self, from: data)
        logIgnored(base.ignoredKeys, id: base.id)
        return base
    }

    /// Decodes a variant or custom theme file. A newer schema is reported, not decoded.
    public static func decodeVariant(_ data: Data, file: String) -> Result<ThemeFile, ThemeProblem> {
        do {
            let probe = try TOMLDecoder().decode(ThemeSchemaProbe.self, from: data)
            guard probe.schema <= supportedThemeSchema else {
                return .failure(
                    .schemaTooNew(
                        themeID: probe.id ?? file, file: file, found: probe.schema, supported: supportedThemeSchema))
            }
            let theme = try TOMLDecoder().decode(ThemeFile.self, from: data)
            logIgnored(theme.ignoredKeys, id: theme.id)
            let unknownRoles = theme.looks.values.flatMap(\.colors.keys).filter { ColorRole(rawValue: $0) == nil }
            logIgnored(Array(Set(unknownRoles)).sorted(), id: theme.id)
            let unknownType = theme.typography.keys.filter { TypographyRole(rawValue: $0) == nil }
            logIgnored(unknownType.sorted(), id: theme.id)
            return .success(theme)
        } catch {
            return .failure(.unreadable(file: file, reason: String(describing: error)))
        }
    }

    /// Parses every `*.toml` in a custom themes folder. Ids equal to a built-in id (or `base`) are rejected.
    /// Precedence between duplicate custom ids is decided by a later story; the first file in name order wins.
    public static func loadCustom(from folder: URL) -> (themes: [ThemeFile], problems: [ThemeProblem]) {
        let urls =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "toml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        var themes: [ThemeFile] = []
        var problems: [ThemeProblem] = []
        let reserved = Set(builtInIDs + [baseThemeID])
        for url in urls {
            let file = url.lastPathComponent
            guard let data = try? Data(contentsOf: url) else {
                problems.append(.unreadable(file: file, reason: "cannot read file"))
                continue
            }
            switch decodeVariant(data, file: file) {
            case .success(let theme):
                if reserved.contains(theme.id) {
                    problems.append(.idClash(themeID: theme.id, file: file))
                } else if !themes.contains(where: { $0.id == theme.id }) {
                    themes.append(theme)
                }
            case .failure(let problem):
                problems.append(problem)
            }
        }
        return (themes, problems)
    }

    private static func logIgnored(_ keys: [String], id: String) {
        guard !keys.isEmpty else { return }
        let list = keys.joined(separator: ", ")
        logger.info("theme \(id, privacy: .public): ignoring unknown keys \(list, privacy: .public)")
    }
}
