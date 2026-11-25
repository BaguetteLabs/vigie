import Foundation
import ModuleKit

/// Everything Copy diagnostics prints (Story 17.4, AD-16), gathered by ``DiagnosticsCollector`` from in-process
/// state and rendered by ``DiagnosticsReport``. Plain values only: by construction it holds no secret value, no
/// note content, no environment variable and no raw script output (AD-9, AD-26).
public struct DiagnosticsInputs: Sendable, Equatable {
    public struct App: Sendable, Equatable {
        public var name: String
        public var version: String
        public var build: String
        public var bundleID: String
        /// `dev` or `release` (``AppEnvironment/Flavor``).
        public var flavor: String
        /// `ad-hoc`, `Developer ID (<team>)`, `unsigned` or `unknown`, as the running code's signature reports it.
        public var signing: String
        /// The app bundle's location, home abbreviated to `~`.
        public var installPath: String

        public init(
            name: String, version: String, build: String, bundleID: String, flavor: String, signing: String,
            installPath: String
        ) {
            self.name = name
            self.version = version
            self.build = build
            self.bundleID = bundleID
            self.flavor = flavor
            self.signing = signing
            self.installPath = installPath
        }
    }

    public struct System: Sendable, Equatable {
        public var osVersion: String
        /// `sysctl hw.model`, e.g. `Mac15,6`.
        public var model: String
        /// `machdep.cpu.brand_string`, e.g. `Apple M3 Pro`.
        public var chip: String
        /// `arm64`, `x86_64`, or `x86_64 (Rosetta)`.
        public var architecture: String
        public var locale: String
        public var reduceMotion: Bool
        public var reduceTransparency: Bool
        public var increaseContrast: Bool

        public init(
            osVersion: String, model: String, chip: String, architecture: String, locale: String,
            reduceMotion: Bool, reduceTransparency: Bool, increaseContrast: Bool
        ) {
            self.osVersion = osVersion
            self.model = model
            self.chip = chip
            self.architecture = architecture
            self.locale = locale
            self.reduceMotion = reduceMotion
            self.reduceTransparency = reduceTransparency
            self.increaseContrast = increaseContrast
        }
    }

    /// One connected display. Its name is not collected.
    public struct Display: Sendable, Equatable {
        public var kind: DisplayInfo.Kind
        public var isBuiltIn: Bool
        public var isMain: Bool
        /// Points.
        public var width: Int
        public var height: Int
        public var scale: Double
        /// Vigie draws an island on it (``DisplaySelector``).
        public var isDrawn: Bool

        public init(
            kind: DisplayInfo.Kind, isBuiltIn: Bool, isMain: Bool, width: Int, height: Int, scale: Double,
            isDrawn: Bool
        ) {
            self.kind = kind
            self.isBuiltIn = isBuiltIn
            self.isMain = isMain
            self.width = width
            self.height = height
            self.scale = scale
            self.isDrawn = isDrawn
        }
    }

    /// One registered module. Script modules carry their id only (``isScript``).
    public struct Module: Sendable, Equatable {
        public var id: String
        public var enabled: Bool
        /// `running`, `disabled`, `stopped`, `errored: …`, `needs permission: …`.
        public var status: String
        /// The module's arbitration state while it runs.
        public var state: ModuleState?
        public var alertKinds: [String]
        public var isScript: Bool

        public init(
            id: String, enabled: Bool, status: String, state: ModuleState?, alertKinds: [String], isScript: Bool
        ) {
            self.id = id
            self.enabled = enabled
            self.status = status
            self.state = state
            self.alertKinds = alertKinds
            self.isScript = isScript
        }
    }

    /// An open `setup.problem` alert.
    public struct SetupProblem: Sendable, Equatable {
        public var since: Date
        public var module: String
        public var category: String?
        public var title: String

        public init(since: Date, module: String, category: String?, title: String) {
            self.since = since
            self.module = module
            self.category = category
            self.title = title
        }
    }

    /// A `setup.problem` alert resolved during this launch (the Notifier's history keeps no title).
    public struct ResolvedProblem: Sendable, Equatable {
        public var at: Date
        public var module: String

        public init(at: Date, module: String) {
            self.at = at
            self.module = module
        }
    }

    /// One known config key: the value for plain settings, `<set>` / `<unset>` for secrets, `<path>` for paths.
    public struct ConfigLine: Sendable, Equatable {
        public var key: String
        public var value: String
        /// `local.toml` (this Mac) rather than `config.toml`.
        public var isLocal: Bool

        public init(key: String, value: String, isLocal: Bool) {
            self.key = key
            self.value = value
            self.isLocal = isLocal
        }
    }

    public struct Config: Sendable, Equatable {
        /// Home abbreviated to `~`.
        public var folder: String
        public var syncOn: Bool
        public var iCloudAvailable: Bool
        public var problems: Int
        public var lines: [ConfigLine]

        public init(folder: String, syncOn: Bool, iCloudAvailable: Bool, problems: Int, lines: [ConfigLine]) {
            self.folder = folder
            self.syncOn = syncOn
            self.iCloudAvailable = iCloudAvailable
            self.problems = problems
            self.lines = lines
        }
    }

    public struct Logs: Sendable, Equatable {
        /// Newest last, at most ``DiagnosticsReport/maxLogLines``.
        public var lines: [String]
        /// Why the log store could not be read; nil when it was.
        public var failure: String?

        public init(lines: [String], failure: String? = nil) {
            self.lines = lines
            self.failure = failure
        }
    }

    public var app: App
    public var system: System
    public var displays: [Display]
    public var modules: [Module]
    /// Lines modules contributed (``ModuleDiagnostics``), by section.
    public var moduleLines: [String]
    public var agentLines: [String]
    public var setupProblems: [SetupProblem]
    /// Oldest first, at most ``DiagnosticsReport/maxResolvedProblems``.
    public var resolvedProblems: [ResolvedProblem]
    public var config: Config
    public var logs: Logs
    public var generatedAt: Date

    public init(
        app: App, system: System, displays: [Display], modules: [Module], moduleLines: [String] = [],
        agentLines: [String] = [], setupProblems: [SetupProblem] = [], resolvedProblems: [ResolvedProblem] = [],
        config: Config, logs: Logs, generatedAt: Date
    ) {
        self.app = app
        self.system = system
        self.displays = displays
        self.modules = modules
        self.moduleLines = moduleLines
        self.agentLines = agentLines
        self.setupProblems = setupProblems
        self.resolvedProblems = resolvedProblems
        self.config = config
        self.logs = logs
        self.generatedAt = generatedAt
    }
}
