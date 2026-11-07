import Foundation

/// The built-in sounds and how a `[sounds]` value turns into a file (Stories 10.1, 10.2).
public struct SoundCatalog: Sendable {
    /// One bundled sound (`builtin:<name>`).
    public struct BuiltIn: Identifiable, Hashable, Sendable {
        /// The `<name>` of `builtin:<name>`.
        public let name: String
        public let label: LocalizedStringResource
        public var id: String { name }

        public init(name: String, label: LocalizedStringResource) {
            self.name = name
            self.label = label
        }

        public static func == (lhs: BuiltIn, rhs: BuiltIn) -> Bool { lhs.name == rhs.name }
        public func hash(into hasher: inout Hasher) { hasher.combine(name) }
    }

    public let builtIns: [BuiltIn]
    private let locate: @Sendable (String) -> URL?

    /// - Parameter locate: the file of a built-in name; nil when there is none.
    public init(builtIns: [BuiltIn], locate: @escaping @Sendable (String) -> URL?) {
        self.builtIns = builtIns
        self.locate = locate
    }

    /// File extension of the bundled sounds.
    public static let fileExtension = "wav"

    /// The four sounds shipped in VigieCore's resources (`Resources/Sounds/<name>.wav`).
    public static let bundled = SoundCatalog(
        builtIns: ["blocked", "failed", "done", "warn"].map {
            BuiltIn(name: $0, label: SettingsText.resource("sounds.builtin.\($0)"))
        },
        locate: { name in
            Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Sounds")
                ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
        })

    public func builtIn(named name: String) -> BuiltIn? { builtIns.first { $0.name == name } }

    /// What a value plays, or why it cannot.
    public enum Resolution: Equatable, Sendable {
        case silent
        case play(URL)
        case problem(SoundProblem.Reason)
    }

    /// Resolves `value` for `key`: built-ins through the catalog, custom files must exist and be readable.
    public func resolve(_ value: SoundValue, fileManager: FileManager = .default) -> Resolution {
        switch value {
        case .off:
            return .silent
        case .builtIn(let name):
            guard builtIn(named: name) != nil, let url = locate(name) else { return .problem(.unknownBuiltIn(name)) }
            return .play(url)
        case .file(let url):
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                return .problem(.fileNotFound(url.path))
            }
            guard fileManager.isReadableFile(atPath: url.path) else { return .problem(.unreadable(url.path)) }
            return .play(url)
        case .invalid(let raw):
            return .problem(.invalidValue(raw))
        }
    }
}

/// A `[sounds]` value that cannot play, reported as a setup problem (Story 10.2).
public struct SoundProblem: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        /// The custom file is missing (path, `~` expanded).
        case fileNotFound(String)
        /// The custom file exists but cannot be read or decoded.
        case unreadable(String)
        /// `builtin:<name>` names no bundled sound.
        case unknownBuiltIn(String)
        /// Neither `off`, `builtin:<name>` nor an absolute or `~` path.
        case invalidValue(String)
    }

    /// The `[sounds]` key, e.g. `blocked`.
    public let key: String
    public let reason: Reason

    public init(key: String, reason: Reason) {
        self.key = key
        self.reason = reason
    }
}
