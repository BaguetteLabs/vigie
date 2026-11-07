import Foundation

/// The theme file schema this build reads (AD-14). A file with a newer `schema` is not used.
public let supportedThemeSchema = 1

/// Id of the shared base file every theme extends.
public let baseThemeID = "base"

/// One typography token, as written in DESIGN.md (`fontSize = "14px"`, `letterSpacing = "0.24em"`).
/// Values stay strings on disk; ``Theme`` parses them.
public struct TypographyToken: Codable, Sendable, Equatable {
    public var fontFamily: String
    public var fontSize: String
    public var fontWeight: String
    public var lineHeight: String?
    public var letterSpacing: String?

    public init(
        fontFamily: String,
        fontSize: String,
        fontWeight: String,
        lineHeight: String? = nil,
        letterSpacing: String? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
    }
}

/// The tokens of one look (`dark` or `light`) of a variant: role -> `#RRGGBB`.
public struct LookTokens: Codable, Sendable, Equatable {
    public var colors: [String: String]

    public init(colors: [String: String]) {
        self.colors = colors
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        colors = try container.decodeIfPresent([String: String].self, forKey: AnyKey("colors")) ?? [:]
    }
}

/// `Themes/base.toml`: tokens shared by every variant and look.
public struct BaseThemeFile: Decodable, Sendable, Equatable {
    public var schema: Int
    public var id: String
    public var name: String
    /// Look-independent colors (`island`, `band`, `shadow`).
    public var colors: [String: String]
    public var rounded: [String: String]
    public var spacing: [String: String]
    public var motion: [String: String]
    /// Raw component specs (`components.<name>.<key>`); parsed on read by ``Theme/component(_:_:)``.
    public var components: [String: [String: String]]
    /// Top-level keys this build does not know; ignored.
    public var ignoredKeys: [String]

    public init(
        schema: Int = supportedThemeSchema,
        id: String = baseThemeID,
        name: String = "Base",
        colors: [String: String] = [:],
        rounded: [String: String] = [:],
        spacing: [String: String] = [:],
        motion: [String: String] = [:],
        components: [String: [String: String]] = [:]
    ) {
        self.schema = schema
        self.id = id
        self.name = name
        self.colors = colors
        self.rounded = rounded
        self.spacing = spacing
        self.motion = motion
        self.components = components
        self.ignoredKeys = []
    }

    static let knownKeys: Set<String> = [
        "schema", "id", "name", "colors", "rounded", "spacing", "motion", "components",
    ]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        schema = try c.decode(Int.self, forKey: AnyKey("schema"))
        id = try c.decodeIfPresent(String.self, forKey: AnyKey("id")) ?? baseThemeID
        name = try c.decodeIfPresent(String.self, forKey: AnyKey("name")) ?? "Base"
        colors = try c.decodeIfPresent([String: String].self, forKey: AnyKey("colors")) ?? [:]
        rounded = try c.decodeIfPresent([String: String].self, forKey: AnyKey("rounded")) ?? [:]
        spacing = try c.decodeIfPresent([String: String].self, forKey: AnyKey("spacing")) ?? [:]
        motion = try c.decodeIfPresent([String: String].self, forKey: AnyKey("motion")) ?? [:]
        components =
            try c.decodeIfPresent([String: [String: String]].self, forKey: AnyKey("components")) ?? [:]
        ignoredKeys = c.allKeys.map(\.stringValue).filter { !Self.knownKeys.contains($0) }.sorted()
    }
}

/// A variant theme file (`Themes/chrome-hologram.toml`) or a custom theme from the config folder.
/// Every table is optional so a custom theme can override only what it needs.
public struct ThemeFile: Decodable, Sendable, Equatable {
    public var schema: Int
    public var id: String
    public var name: String
    /// `base` for built-ins; a custom theme may name a built-in variant id to start from it.
    public var extends: String?
    public var typography: [String: TypographyToken]
    /// Variant-specific radii (override the base `rounded` table).
    public var rounded: [String: String]
    /// Variant-specific motion tokens (override the base `motion` table).
    public var motion: [String: String]
    /// `dark` and `light`.
    public var looks: [String: LookTokens]
    /// Top-level keys this build does not know; ignored.
    public var ignoredKeys: [String]

    public init(
        schema: Int = supportedThemeSchema,
        id: String,
        name: String,
        extends: String? = baseThemeID,
        typography: [String: TypographyToken] = [:],
        rounded: [String: String] = [:],
        motion: [String: String] = [:],
        looks: [String: LookTokens] = [:]
    ) {
        self.schema = schema
        self.id = id
        self.name = name
        self.extends = extends
        self.typography = typography
        self.rounded = rounded
        self.motion = motion
        self.looks = looks
        self.ignoredKeys = []
    }

    static let knownKeys: Set<String> = [
        "schema", "id", "name", "extends", "typography", "rounded", "motion", "looks",
    ]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        schema = try c.decode(Int.self, forKey: AnyKey("schema"))
        id = try c.decode(String.self, forKey: AnyKey("id"))
        name = try c.decodeIfPresent(String.self, forKey: AnyKey("name")) ?? id
        extends = try c.decodeIfPresent(String.self, forKey: AnyKey("extends"))
        typography =
            try c.decodeIfPresent([String: TypographyToken].self, forKey: AnyKey("typography")) ?? [:]
        rounded = try c.decodeIfPresent([String: String].self, forKey: AnyKey("rounded")) ?? [:]
        motion = try c.decodeIfPresent([String: String].self, forKey: AnyKey("motion")) ?? [:]
        looks = try c.decodeIfPresent([String: LookTokens].self, forKey: AnyKey("looks")) ?? [:]
        ignoredKeys = c.allKeys.map(\.stringValue).filter { !Self.knownKeys.contains($0) }.sorted()
    }

    /// Tokens for one look, empty when the file does not define it.
    public func tokens(for look: Look) -> LookTokens {
        looks[look.rawValue] ?? LookTokens(colors: [:])
    }
}

/// Reads only `schema` (and `id`), so a file written for a newer schema can be reported without decoding it.
struct ThemeSchemaProbe: Decodable {
    var schema: Int
    var id: String?
}

/// Dynamic coding key: lets the token types enumerate and ignore unknown keys.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

// MARK: - Roles

/// A look of a variant. The hardware island always uses ``dark`` (AD-14).
public enum Look: String, Sendable, CaseIterable, Codable {
    case dark
    case light
}

/// `[appearance] mode` (SPEC §11).
public enum AppearanceMode: String, Sendable, CaseIterable, Codable {
    case system
    case light
    case dark
}

/// `[appearance] presence` (SPEC §10.2): animation intensity.
public enum PresenceLevel: String, Sendable, CaseIterable, Codable {
    case full
    case calm
}

/// Color roles. Raw values are the TOML keys (base `colors` table and `looks.<look>.colors`).
public enum ColorRole: String, Sendable, CaseIterable, Codable {
    // Base (every look).
    case island
    case band
    case shadow
    // Look roles.
    case surfacePanel = "surface-panel"
    case surfaceCard = "surface-card"
    case surfaceVNTop = "surface-vn-top"
    case surfaceVNBottom = "surface-vn-bottom"
    case ink1 = "ink-1"
    case ink2 = "ink-2"
    case ink3 = "ink-3"
    case line
    case lineSilver = "line-silver"
    case iris1 = "iris-1"
    case iris2 = "iris-2"
    case iris3 = "iris-3"
    case filament1 = "filament-1"
    case filament2 = "filament-2"
    case filament3 = "filament-3"
    case structure = "struct"
    case gold
    case goldText = "gold-text"
    case statusIdle = "status-idle"
    case statusWorking = "status-working"
    case statusDone = "status-done"
    case statusBlocked = "status-blocked"
    case statusFailed = "status-failed"
    case paceOn = "pace-on"
    case paceAhead = "pace-ahead"
    case quotaWarning = "quota-warning"
    case quotaWarningText = "quota-warning-text"

    /// Roles held by the base file rather than a look.
    public static let baseRoles: Set<ColorRole> = [.island, .band, .shadow]
}

/// Typography roles (DESIGN.md "Typography"). Raw values are the TOML keys, without the variant prefix.
public enum TypographyRole: String, Sendable, CaseIterable, Codable {
    case readoutValue = "readout-value"
    case readoutLabel = "readout-label"
    case kicker
    case peekTitle = "peek-title"
    case body
    case prose
    case action
    case tab
    case cardTitle = "card-title"
    case rowPrimary = "row-primary"
    case rowStatus = "row-status"
    case numeralBig = "numeral-big"
    case code
    case timeValue = "time-value"

    /// Roles that render live numerals (T+, percentages, countdowns, time left): tabular figures.
    public var usesTabularDigits: Bool {
        switch self {
        case .readoutValue, .numeralBig, .timeValue, .rowStatus, .kicker: true
        default: false
        }
    }
}

/// Corner radius roles. Raw values are `rounded` keys (shared in base, variant-specific in the variant file).
public enum RadiusRole: String, Sendable, CaseIterable, Codable {
    case islandClosed = "island-closed"
    case peek
    case expanded
    case notesPanel = "notes-panel"
    case full
    case card
    case setupCard = "setup-card"
    case zone
    case miniZone = "mini-zone"
    case row
    case dayCell = "day-cell"
    case code
    case action
}

/// Spacing roles (base `spacing` table).
public enum SpacingRole: String, Sendable, CaseIterable, Codable {
    case bandHeight = "band-height"
    case wingPaddingX = "wing-padding-x"
    case wingGap = "wing-gap"
    case glyphGap = "glyph-gap"
    case peekInsetX = "peek-inset-x"
    case peekColumnGap = "peek-column-gap"
    case peekTimerBottom = "peek-timer-bottom"
    case expandedBarPaddingX = "expanded-bar-padding-x"
    case tabsMarginX = "tabs-margin-x"
    case tabPaddingX = "tab-padding-x"
    case gridGap = "grid-gap"
    case gridPaddingX = "grid-padding-x"
    case cardPaddingY = "card-padding-y"
    case cardPaddingX = "card-padding-x"
    case actionGap = "action-gap"
    case rowGap = "row-gap"
    case tabRowGap = "tab-row-gap"
    case dropGridInsetX = "drop-grid-inset-x"
    case dropGridTop = "drop-grid-top"
    case dropGridBottom = "drop-grid-bottom"
    case dropGridGap = "drop-grid-gap"
    case dropBandPaddingX = "drop-band-padding-x"
    case miniZoneGap = "mini-zone-gap"
}

/// Motion roles (base `motion` table, plus variant-specific ones in the variant file).
public enum MotionRole: String, Sendable, CaseIterable, Codable {
    case enter
    case exit
    case peekGrow = "peek-grow"
    case dropDisplayGrow = "drop-display-grow"
    case ambientLoop = "ambient-loop"
    case workingCycle = "working-cycle"
    case blockedCycle = "blocked-cycle"
    case failedCycle = "failed-cycle"
    case calmPulse = "calm-pulse"
    case peekDwell = "peek-dwell"
    case confirmReadout = "confirm-readout"
    case panelScan = "panel-scan"
    case dialBezel = "dial-bezel"
    /// Chrome Hologram card filament loop.
    case cardIris = "card-iris"
    /// Twin Metal Tactical Usage bezel.
    case usageBezel = "usage-bezel"
}
