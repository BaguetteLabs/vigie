/// Durations in script front matter (`interval`, `duration` settings), with the config grammar (Conventions:
/// Config keys; `ConfigDuration` in VigieCore, which a module may not import, AD-1): one or more
/// `<number><unit>` parts with no spaces, units `ms`, `s`, `m`, `h`, `d`, e.g. `30s`, `5m`, `1h30m`, `7d`.
/// A bare number is not a duration. The schema's `#/$defs/duration` pattern is the same grammar.
public enum ScriptDuration {
    /// The duration, or nil when `text` does not follow the grammar. Same algorithm as `ConfigDuration.parse`.
    public static func parse(_ text: String) -> Duration? {
        var scalars = Array(text.unicodeScalars)[...]
        guard !scalars.isEmpty else { return nil }
        var total = Duration.zero
        while !scalars.isEmpty {
            var digits = ""
            while let scalar = scalars.first, ("0"..."9").contains(scalar) || scalar == "." {
                digits.unicodeScalars.append(scalar)
                scalars.removeFirst()
            }
            guard let number = Double(digits), number.isFinite, number >= 0 else { return nil }
            var unit = ""
            while let scalar = scalars.first, ("a"..."z").contains(scalar) {
                unit.unicodeScalars.append(scalar)
                scalars.removeFirst()
            }
            let seconds: Double
            switch unit {
            case "ms": seconds = number / 1000
            case "s": seconds = number
            case "m": seconds = number * 60
            case "h": seconds = number * 3600
            case "d": seconds = number * 86_400
            default: return nil
            }
            total += .milliseconds(Int64((seconds * 1000).rounded()))
        }
        return total
    }

    /// An interval: a duration with at least one non-zero digit (the schema's `#/$defs/interval`), so `0s` and
    /// `0m` are rejected.
    public static func parseInterval(_ text: String) -> Duration? {
        guard text.unicodeScalars.contains(where: { ("1"..."9").contains($0) }) else { return nil }
        return parse(text)
    }
}

extension ScriptDuration {
    /// Canonical spelling (whole milliseconds), e.g. `1h30m`, `150ms`, `0s`; same as `ConfigDuration.format`.
    public static func format(_ duration: Duration) -> String {
        var ms = duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
        guard ms > 0 else { return "0s" }
        var out = ""
        for (unit, size) in [("d", Int64(86_400_000)), ("h", 3_600_000), ("m", 60_000), ("s", 1000), ("ms", 1)]
        where ms >= size {
            out += "\(ms / size)\(unit)"
            ms %= size
        }
        return out
    }
}
