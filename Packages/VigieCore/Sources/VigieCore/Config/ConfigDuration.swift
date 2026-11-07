import Foundation

/// Durations in config are strings (Conventions: Config keys): one or more `<number><unit>` parts with no
/// spaces, units `ms`, `s`, `m`, `h`, `d`, e.g. `"150ms"`, `"90s"`, `"20m"`, `"1h30m"`, `"7d"`. A bare number
/// is not a duration.
public enum ConfigDuration {
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

    /// Canonical spelling for a duration (whole milliseconds), e.g. `1h30m`, `150ms`, `0s`. Used by the
    /// writer (Story 2.13) and the settings UI.
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
