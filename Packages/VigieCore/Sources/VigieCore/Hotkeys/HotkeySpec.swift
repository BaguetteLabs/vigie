import AppKit
import KeyboardShortcuts

/// Why a hotkey string or registration was rejected.
public enum HotkeyError: Error, Hashable, Sendable {
    /// The string is empty or only separators.
    case empty
    /// A token is not a known key or modifier.
    case unknownToken(String)
    /// Modifiers but no key, e.g. `cmd+shift`.
    case missingKey
    /// More than one non-modifier key, e.g. `cmd+a+b`.
    case multipleKeys
    /// Only Option (or Option+Shift): blocked by macOS 15.0–15.1 and never used by Vigie (Conventions: Hotkeys).
    case optionOnlyModifier
    /// No modifier (or Shift only) on a key other than F1–F12: it would hijack typing.
    case missingModifier
    /// The full name `<owner>.<name>` is already registered (the earlier registration wins, AD-13).
    case duplicateName(String)
    /// The name is empty or contains whitespace.
    case invalidName(String)
    /// `HotkeyRegistry.register` was called off the main thread.
    case notOnMainActor
}

/// A parsed global shortcut, e.g. `cmd+shift+space` (SPEC §11 `expand_hotkey`, module `hotkey` keys).
///
/// Accepted modifier spellings: `cmd`/`command`/`⌘`, `shift`/`⇧`, `opt`/`option`/`alt`/`⌥`,
/// `ctrl`/`control`/`⌃`; symbols may also be written glued to the key (`⌥⌘N`). Keys: letters, digits, `space`,
/// `return`/`enter`, `escape`/`esc`, `tab`, `delete`/`backspace`, arrows (`up`, `down`, `left`, `right`),
/// `f1`–`f12` and punctuation (`,` `.` `/` `;` `'` `[` `]` `\` `` ` `` `-` `=` or their names).
/// Matching is case-insensitive. The canonical printed form orders modifiers `ctrl+opt+cmd+shift`, so
/// `cmd+shift+space` and `opt+cmd+n` round-trip unchanged.
///
/// Every instance is valid by construction: Option-only modifiers and modifier-less typing keys are
/// rejected, so no default or override can ever use them.
public struct HotkeySpec: Hashable, Sendable, CustomStringConvertible {
    public let key: KeyboardShortcuts.Key
    /// Only `.control`, `.option`, `.command`, `.shift`.
    public let modifiers: NSEvent.ModifierFlags

    /// Validates the combination (see type docs).
    public init(key: KeyboardShortcuts.Key, modifiers: NSEvent.ModifierFlags) throws {
        let mods = modifiers.intersection(Self.allowedModifiers)
        if mods == .option || mods == [.option, .shift] { throw HotkeyError.optionOnlyModifier }
        if mods.subtracting(.shift).isEmpty, !Self.functionKeys.contains(key) {
            throw HotkeyError.missingModifier
        }
        self.key = key
        self.modifiers = mods
    }

    /// Parses a config string such as `cmd+shift+space` or `ctrl+opt+k`.
    public init(parsing string: String) throws {
        var tokens: [String] = []
        for raw in string.split(separator: "+", omittingEmptySubsequences: true) {
            var token = raw.trimmingCharacters(in: .whitespaces)
            // Peel modifier symbols glued to the front: `⌥⌘N` -> `⌥`, `⌘`, `N`.
            while token.count > 1, let first = token.first, Self.symbolModifiers[first] != nil {
                tokens.append(String(first))
                token.removeFirst()
            }
            if !token.isEmpty { tokens.append(token) }
        }
        guard !tokens.isEmpty else { throw HotkeyError.empty }

        var modifiers: NSEvent.ModifierFlags = []
        var key: KeyboardShortcuts.Key?
        for token in tokens {
            let lower = token.lowercased()
            if let modifier = Self.modifierNames[lower] {
                modifiers.insert(modifier)
            } else if let found = Self.keyNames[lower] {
                guard key == nil else { throw HotkeyError.multipleKeys }
                key = found
            } else {
                throw HotkeyError.unknownToken(token)
            }
        }
        guard let key else { throw HotkeyError.missingKey }
        try self.init(key: key, modifiers: modifiers)
    }

    /// The KeyboardShortcuts value to bind.
    public var shortcut: KeyboardShortcuts.Shortcut { .init(key, modifiers: modifiers) }

    /// Canonical config form, e.g. `cmd+shift+space`.
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.shift) { parts.append("shift") }
        parts.append(Self.canonicalKeyNames[key] ?? "?")
        return parts.joined(separator: "+")
    }

    public static func == (lhs: HotkeySpec, rhs: HotkeySpec) -> Bool {
        lhs.key == rhs.key && lhs.modifiers.rawValue == rhs.modifiers.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers.rawValue)
    }

    // MARK: - Tables

    static let allowedModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift]

    static let functionKeys: Set<KeyboardShortcuts.Key> = [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12,
    ]

    static let symbolModifiers: [Character: NSEvent.ModifierFlags] = [
        "⌘": .command, "⇧": .shift, "⌥": .option, "⌃": .control,
    ]

    static let modifierNames: [String: NSEvent.ModifierFlags] = [
        "cmd": .command, "command": .command, "⌘": .command,
        "shift": .shift, "⇧": .shift,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "ctrl": .control, "control": .control, "⌃": .control,
    ]

    /// Canonical name first; used by the printer.
    private static let keyTable: [(KeyboardShortcuts.Key, [String])] = {
        var table: [(KeyboardShortcuts.Key, [String])] = [
            (.a, ["a"]), (.b, ["b"]), (.c, ["c"]), (.d, ["d"]), (.e, ["e"]), (.f, ["f"]), (.g, ["g"]),
            (.h, ["h"]), (.i, ["i"]), (.j, ["j"]), (.k, ["k"]), (.l, ["l"]), (.m, ["m"]), (.n, ["n"]),
            (.o, ["o"]), (.p, ["p"]), (.q, ["q"]), (.r, ["r"]), (.s, ["s"]), (.t, ["t"]), (.u, ["u"]),
            (.v, ["v"]), (.w, ["w"]), (.x, ["x"]), (.y, ["y"]), (.z, ["z"]),
            (.zero, ["0"]), (.one, ["1"]), (.two, ["2"]), (.three, ["3"]), (.four, ["4"]),
            (.five, ["5"]), (.six, ["6"]), (.seven, ["7"]), (.eight, ["8"]), (.nine, ["9"]),
            (.space, ["space"]), (.return, ["return", "enter"]), (.escape, ["escape", "esc"]),
            (.tab, ["tab"]), (.delete, ["delete", "backspace"]),
            (.upArrow, ["up", "uparrow"]), (.downArrow, ["down", "downarrow"]),
            (.leftArrow, ["left", "leftarrow"]), (.rightArrow, ["right", "rightarrow"]),
            (.comma, [",", "comma"]), (.period, [".", "period"]), (.slash, ["/", "slash"]),
            (.semicolon, [";", "semicolon"]), (.quote, ["'", "quote"]),
            (.leftBracket, ["[", "leftbracket"]), (.rightBracket, ["]", "rightbracket"]),
            (.backslash, ["\\", "backslash"]), (.backtick, ["`", "backtick", "grave"]),
            (.minus, ["-", "minus"]), (.equal, ["=", "equal"]),
        ]
        let functionKeys: [KeyboardShortcuts.Key] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
        for (index, key) in functionKeys.enumerated() { table.append((key, ["f\(index + 1)"])) }
        return table
    }()

    static let keyNames: [String: KeyboardShortcuts.Key] = {
        var names: [String: KeyboardShortcuts.Key] = [:]
        for (key, aliases) in keyTable { for alias in aliases { names[alias] = key } }
        return names
    }()

    static let canonicalKeyNames: [KeyboardShortcuts.Key: String] = {
        var names: [KeyboardShortcuts.Key: String] = [:]
        for (key, aliases) in keyTable { names[key] = aliases[0] }
        return names
    }()
}
