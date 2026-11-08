import Foundation

/// One Account of a Provider (Story 7.10, PRD FR-29, A82): a slug, stable for the Account's lifetime, under
/// `[modules."agents.sessions".adapter.<adapter id>.account.<account id>]` in `local.toml`. The implicit Account
/// every Provider has, and the one a setup made before Story 7.10 becomes, is ``default``.
public struct AccountID: AdapterIdentifier {
    public let rawValue: String

    public init?(_ rawValue: String) {
        guard Self.isValid(rawValue), rawValue.count <= Self.maxLength else { return nil }
        self.rawValue = rawValue
    }

    /// Longest slug ``slug(from:taken:)`` makes.
    public static let maxLength = 32
    /// The Provider's default Account: the agent's default config location, the 7.3 plan keys.
    public static let `default`: AccountID = "default"

    public var isDefault: Bool { self == .default }

    /// A new id from a user label: lowercase ASCII letters, digits and `-`, starting with a letter (`Work` →
    /// `work`, `Côté client` → `cote-client`, `2nd` → `account-2nd`), unique against `taken` (`work-2`). Never
    /// `default` for a new Account.
    public static func slug(from label: String, taken: Set<AccountID>) -> AccountID {
        let folded = label.folding(
            options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en")
        )
        .lowercased()
        var slug = ""
        var lastWasDash = false
        for scalar in folded.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !slug.isEmpty, !lastWasDash {
                slug += "-"
                lastWasDash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        if slug.isEmpty { slug = "account" }
        if let first = slug.unicodeScalars.first, !("a"..."z").contains(first) { slug = "account-" + slug }
        slug = String(slug.prefix(maxLength - 3))
        while slug.hasSuffix("-") { slug.removeLast() }
        var reserved = taken
        reserved.insert(.default)
        var candidate = AccountID(slug) ?? "account"
        var counter = 2
        while reserved.contains(candidate) {
            candidate = AccountID("\(slug)-\(counter)") ?? "account"
            counter += 1
        }
        return candidate
    }
}

/// Where an Account's agent keeps its config and logs (A82). Claude Code: `CLAUDE_CONFIG_DIR` (default
/// `~/.claude`), logs under `<dir>/projects`. Codex (Epic 8): `CODEX_HOME`. Stored as written by the user (may
/// start with `~`); compared after ``normalizedPath(home:)``.
public enum AccountLocation: Hashable, Sendable, Codable {
    case configDirectory(String)

    /// The path as written.
    public var path: String {
        switch self {
        case .configDirectory(let path): path
        }
    }

    /// `~` expanded against `home`, `.`/`..` and duplicate or trailing slashes removed, symlinks resolved.
    public func normalizedPath(home: URL) -> String {
        Self.normalize(path, home: home)
    }

    /// The location as a folder URL (normalized).
    public func url(home: URL) -> URL {
        URL(fileURLWithPath: normalizedPath(home: home), isDirectory: true)
    }

    /// True when both name the same folder once normalized.
    public func matches(_ other: AccountLocation, home: URL) -> Bool {
        normalizedPath(home: home) == other.normalizedPath(home: home)
    }

    static func normalize(_ raw: String, home: URL) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "~" {
            text = home.path
        } else if text.hasPrefix("~/") {
            text = home.path + "/" + text.dropFirst(2)
        }
        guard !text.isEmpty else { return "" }
        if !text.hasPrefix("/") { text = home.path + "/" + text }
        let url = URL(fileURLWithPath: text).standardizedFileURL.resolvingSymlinksInPath()
        var path = url.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

/// An Account as `agents.sessions` and `agents.usage` see it: id, user label, location (nil when the adapter
/// declares no default location and the user set none).
public struct AgentAccount: Hashable, Sendable, Identifiable {
    public let id: AccountID
    /// The user's label (`Work`); empty for a default Account the user never named.
    public let label: String
    public let location: AccountLocation?

    public init(id: AccountID, label: String, location: AccountLocation?) {
        self.id = id
        self.label = label
        self.location = location
    }

    public var isDefault: Bool { id.isDefault }

    /// The adapter-settings key of a per-Account setting: the 7.3 key itself for the default Account (so a
    /// pre-7.10 setup is its default Account unchanged), else `account.<id>.<key>`.
    public func settingKey(_ key: String) -> String {
        isDefault ? key : "\(AgentAccounts.tableSegment).\(id.rawValue).\(key)"
    }

    /// The SecretStore key of a per-Account secret (owner `adapter.<adapter id>`, AD-9: one Keychain item per
    /// Account): `key` for the default Account, else `<key>.<id>`.
    public func secretKey(_ key: String) -> String {
        isDefault ? key : "\(key).\(id.rawValue)"
    }

    /// A per-Account external-credential descriptor id (the consent record): `base` for the default Account,
    /// else `<base>.<id>`.
    public func credentialID(_ base: String) -> String {
        isDefault ? base : "\(base).\(id.rawValue)"
    }
}

/// The Account keys of an adapter's settings table (Story 7.10, AD-8: all `.local`, never synced):
///
/// ```toml
/// # local.toml
/// [modules."agents.sessions".adapter.claude]
/// accounts = ["work"]                   # extra Accounts, in the user's order
/// [modules."agents.sessions".adapter.claude.account.default]
/// label = "Personal"                    # optional name of the default Account
/// [modules."agents.sessions".adapter.claude.account.work]
/// label = "Work"
/// location = "~/.claude-work"
/// usage_providers = ["local", "plan"]   # per-Account copy of the adapter's per-Account keys
/// plan_auth = "claude_code"
/// ```
///
/// Per-Account keys are declared once as templates (`account.*.<key>`); ConfigStore registers each Account's
/// keys when it sees them. An adapter that supports Accounts appends ``descriptors(perAccount:)`` to its
/// `settings`.
public enum AgentAccounts {
    /// `accounts`: the extra Account ids (the default Account is implicit).
    public static let listKey = "accounts"
    /// The sub-table holding one table per Account.
    public static let tableSegment = "account"
    /// The template segment that stands for any Account id.
    public static let wildcard = "*"
    public static let labelKey = "label"
    public static let locationKey = "location"
    /// Labels longer than this are cut in Settings (the wing shows 6 characters anyway).
    public static let maxLabelLength = 40

    /// `account.*.<key>`.
    public static func template(_ key: String) -> String { "\(tableSegment).\(wildcard).\(key)" }

    /// `accounts`, `account.*.label`, `account.*.location`, and a `.local` template copy of each of
    /// `perAccount` (e.g. `usage_providers`, `plan_auth`; secrets excluded: they live in SecretStore).
    public static func descriptors(perAccount: [SettingDescriptor]) -> [SettingDescriptor] {
        [
            SettingDescriptor(
                key: listKey, label: L10n.resource("agentkit.accounts.list"), kind: .list(of: .string, default: []),
                scope: .local, help: L10n.resource("agentkit.accounts.list.help")),
            SettingDescriptor(
                key: template(labelKey), label: L10n.resource("agentkit.accounts.label"), kind: .string(default: ""),
                scope: .local, help: L10n.resource("agentkit.accounts.label.help")),
            SettingDescriptor(
                key: template(locationKey), label: L10n.resource("agentkit.accounts.location"),
                kind: .path(default: nil), scope: .local, help: L10n.resource("agentkit.accounts.location.help")),
        ]
            + perAccount.compactMap { descriptor in
                if case .secret = descriptor.kind { return nil }
                return SettingDescriptor(
                    key: template(descriptor.key), label: descriptor.label, kind: descriptor.kind, scope: .local,
                    help: descriptor.help)
            }
    }

    /// The configured Accounts: the default first (its label from `account.default.label`, its location
    /// `defaultLocation`), then each listed id with a valid slug, once, in list order. A listed Account
    /// without a location is skipped (it could never be told apart from the default).
    public static func accounts(in settings: any ReadOnlySettings, defaultLocation: AccountLocation?)
        -> [AgentAccount]
    {
        var result = [
            AgentAccount(
                id: .default,
                label: settings.value("\(tableSegment).\(AccountID.default.rawValue).\(labelKey)", as: String.self)
                    ?? "", location: defaultLocation)
        ]
        var seen: Set<AccountID> = [.default]
        for raw in settings.value(listKey, as: [String].self) ?? [] {
            guard let id = AccountID(raw), seen.insert(id).inserted else { continue }
            let prefix = "\(tableSegment).\(id.rawValue)."
            guard
                let path = settings.value(prefix + locationKey, as: String.self)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty
            else { continue }
            let label = settings.value(prefix + labelKey, as: String.self) ?? ""
            result.append(
                AgentAccount(id: id, label: label.isEmpty ? id.rawValue : label, location: .configDirectory(path)))
        }
        return result
    }

    /// The Account a Session belongs to (A82): the first whose location matches `hint` once normalized
    /// (`~`, trailing slash, symlinks), else ``AccountID/default``.
    public static func attribute(_ hint: AccountLocation?, among accounts: [AgentAccount], home: URL) -> AccountID {
        guard let hint else { return .default }
        let wanted = hint.normalizedPath(home: home)
        guard !wanted.isEmpty else { return .default }
        // A non-default match wins over the default (same folder configured twice).
        if let match = accounts.first(where: { !$0.isDefault && $0.location?.normalizedPath(home: home) == wanted }) {
            return match.id
        }
        return .default
    }
}

/// AgentKit catalog lookups.
enum L10n {
    static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: bundle)
    }
}
