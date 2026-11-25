import Foundation

/// The redaction gate of Copy diagnostics (Story 17.4, AD-9): every line of the assembled text goes through it
/// before the text reaches the clipboard. Patterns, in order (documented in `docs/diagnostics.md`):
///
/// 1. every known secret value (``SecretValues``: the Keychain values of the declared `secret` settings and the
///    script `secret` settings), exact match on the whole text (so a multi-line value matches), longest first, plus
///    the one-line JSON-escaped form of a value holding a newline or quote → `<redacted>`;
/// 2. `Authorization:` header values and `Bearer …` tokens;
/// 3. `key = value` / `key: value` pairs whose key names a token, password, secret or API key (a quoted value is
///    redacted up to its closing quote, an unquoted one up to the next space);
/// 4. token shapes: JWTs, `sk-…`, Slack `xox?-…`, GitHub `ghp_…` / `github_pat_…`, AWS `AKIA…`, runs of 32+ hex
///    digits, runs of 40+ base64 characters mixing digits, upper and lower case;
/// 5. URL userinfo, `scheme://user:pass@host` → `scheme://<redacted>@host`;
/// 6. email addresses (the domain is kept);
/// 7. the home folder → `~` (and any other `/Users/<name>`).
public struct DiagnosticsRedactor: Sendable {
    public static let placeholder = "<redacted>"
    /// Known values shorter than this are not scrubbed exactly: they would match ordinary words.
    public static let minimumSecretLength = 4

    private let secrets: [String]
    /// The secrets plus the escaped one-line form of those holding a newline, quote or backslash, longest first.
    private let scrubList: [String]
    private let homePath: String

    public init(secretValues: [String], homeDirectory: URL) {
        secrets = Array(
            Set(
                secretValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count >= Self.minimumSecretLength })
        ).sorted { $0.count > $1.count || ($0.count == $1.count && $0 < $1) }
        scrubList = Array(
            Set(
                secrets.flatMap { secret -> [String] in
                    let escaped = secret.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                        .replacingOccurrences(of: "\r", with: "\\r")
                        .replacingOccurrences(of: "\n", with: "\\n")
                    return escaped == secret ? [secret] : [secret, escaped]
                })
        ).sorted { $0.count > $1.count || ($0.count == $1.count && $0 < $1) }
        var home = homeDirectory.standardizedFileURL.path
        while home.count > 1 && home.hasSuffix("/") { home.removeLast() }
        homePath = home
    }

    public func redact(_ text: String) -> String {
        var text = text
        for secret in scrubList { text = text.replacingOccurrences(of: secret, with: Self.placeholder) }
        return text.components(separatedBy: "\n").map(redactLine).joined(separator: "\n")
    }

    public func redactLine(_ line: String) -> String {
        var line = line
        for secret in secrets { line = line.replacingOccurrences(of: secret, with: Self.placeholder) }
        for rule in Self.rules { line = rule.apply(line) }
        if homePath.count > 1 {
            line = Self.replace(
                line, pattern: NSRegularExpression.escapedPattern(for: homePath) + "(?=/|\\s|$|[\"'),;:])",
                with: "~")
        }
        line = Self.otherHomes.apply(line)
        return line
    }

    struct Rule: Sendable {
        let regex: NSRegularExpression?
        let template: String

        init(pattern: String, template: String) {
            regex = try? NSRegularExpression(pattern: pattern)
            self.template = template
        }

        func apply(_ line: String) -> String {
            guard let regex else { return line }
            return regex.stringByReplacingMatches(
                in: line, range: NSRange(line.startIndex..., in: line), withTemplate: template)
        }
    }

    static let otherHomes = Rule(pattern: "/Users/(?!Shared(?=/|\\s|$))[^/\\s]+(?=/|\\s|$)", template: "~")

    static let base64Char = "A-Za-z0-9+/=_-"

    static let rules: [Rule] = [
        // Authorization header values, whatever the scheme.
        Rule(pattern: "(?i)(authorization[\"']?\\s*[:=]\\s*)[^\\n]+", template: "$1<redacted>"),
        Rule(pattern: "(?i)\\b(bearer|basic)\\s+(?!<redacted>)[A-Za-z0-9._~+/=-]+", template: "$1 <redacted>"),
        // The same with a quoted value: everything up to the closing quote (or the end of the line).
        Rule(
            pattern:
                "(?i)\\b([A-Za-z0-9_.-]*(?:token|password|passwd|secret|api[_-]?key|apikey)[A-Za-z0-9_.-]*[\"']?\\s*[:=]\\s*)([\"'])(?!<set>|<unset>|<redacted>|<path>)[^\\n]*?(?:(?=\\2)|$)",
            template: "$1$2<redacted>"),
        // Named credentials: `api_key = …`, `token: …`, `"password": "…"`.
        Rule(
            pattern:
                "(?i)\\b([A-Za-z0-9_.-]*(?:token|password|passwd|secret|api[_-]?key|apikey)[A-Za-z0-9_.-]*[\"']?\\s*[:=]\\s*[\"']?)(?!<set>|<unset>|<redacted>|<path>)[^\\s\"',]+",
            template: "$1<redacted>"),
        // JWTs.
        Rule(pattern: "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}(?:\\.[A-Za-z0-9_-]+)?", template: "<redacted>"),
        // Vendor key shapes.
        Rule(pattern: "\\bsk-[A-Za-z0-9_-]{8,}", template: "<redacted>"),
        Rule(pattern: "\\bxox[baprs]-[A-Za-z0-9-]{8,}", template: "<redacted>"),
        Rule(pattern: "\\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})", template: "<redacted>"),
        Rule(pattern: "\\bAKIA[0-9A-Z]{16}\\b", template: "<redacted>"),
        // Long hex runs (keys, hashes, hex-encoded tokens).
        Rule(pattern: "(?<![0-9A-Za-z])[0-9A-Fa-f]{32,}(?![0-9A-Za-z])", template: "<redacted>"),
        // Long base64 / base64url runs mixing digits, upper and lower case (never a path: no leading `/`).
        Rule(
            pattern:
                "(?<![\(base64Char)])(?=[\(base64Char)]*[0-9])(?=[\(base64Char)]*[a-z])(?=[\(base64Char)]*[A-Z])[A-Za-z0-9+_-][\(base64Char)]{39,}",
            template: "<redacted>"),
        // URL userinfo (`scheme://user:pass@host`): host and path stay.
        Rule(pattern: "([A-Za-z][A-Za-z0-9+.-]*://)[^/\\s@]+@", template: "$1<redacted>@"),
        // Email addresses: keep the domain.
        Rule(
            pattern: "[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,})",
            template: "<redacted>@$1"),
    ]

    static func replace(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

/// The values the redactor scrubs exactly (Story 17.4): the caller's seam onto `SecretStore` and the modules that
/// hold secret settings. The values never leave this closure's result except as `<redacted>`.
public struct SecretValues: Sendable {
    public let values: @MainActor @Sendable () async -> [String]

    public init(_ values: @escaping @MainActor @Sendable () async -> [String]) {
        self.values = values
    }

    public static let none = SecretValues { [] }
}
