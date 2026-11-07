import AppKit
import KeyboardShortcuts
import Testing

@testable import VigieCore

@Suite struct HotkeySpecTests {
    @Test(arguments: [
        ("cmd+shift+space", "cmd+shift+space"),
        ("Shift + Cmd + Space", "cmd+shift+space"),
        ("command+shift+space", "cmd+shift+space"),
        ("⌘+⇧+space", "cmd+shift+space"),
        ("ctrl+opt+k", "ctrl+opt+k"),
        ("control+alt+K", "ctrl+opt+k"),
        ("⌃⌥k", "ctrl+opt+k"),
        ("opt+cmd+n", "opt+cmd+n"),
        ("⌥⌘N", "opt+cmd+n"),
        ("cmd+,", "cmd+,"),
        ("cmd+comma", "cmd+,"),
        ("cmd+shift+/", "cmd+shift+/"),
        ("ctrl+`", "ctrl+`"),
        ("cmd+enter", "cmd+return"),
        ("cmd+esc", "cmd+escape"),
        ("cmd+backspace", "cmd+delete"),
        ("ctrl+tab", "ctrl+tab"),
        ("cmd+opt+left", "opt+cmd+left"),
        ("cmd+1", "cmd+1"),
        ("f5", "f5"),
        ("shift+f12", "shift+f12"),
    ])
    func parsesAndPrintsCanonically(input: String, canonical: String) throws {
        let parsed = try HotkeySpec(parsing: input)
        #expect(parsed.description == canonical)
        #expect(try HotkeySpec(parsing: canonical) == parsed)
    }

    @Test func parsedValues() throws {
        let parsed = try HotkeySpec(parsing: "cmd+shift+space")
        #expect(parsed.key == .space)
        #expect(parsed.modifiers == [.command, .shift])
        #expect(parsed.shortcut == KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .shift]))
    }

    @Test(arguments: [
        ("", HotkeyError.empty),
        ("+", HotkeyError.empty),
        ("opt+k", HotkeyError.optionOnlyModifier),
        ("alt+k", HotkeyError.optionOnlyModifier),
        ("⌥k", HotkeyError.optionOnlyModifier),
        ("opt+shift+k", HotkeyError.optionOnlyModifier),
        ("k", HotkeyError.missingModifier),
        ("space", HotkeyError.missingModifier),
        ("shift+k", HotkeyError.missingModifier),
        ("cmd+shift", HotkeyError.missingKey),
        ("cmd+a+b", HotkeyError.multipleKeys),
        ("cmd+hyper", HotkeyError.unknownToken("hyper")),
        ("cmd+f13", HotkeyError.unknownToken("f13")),
        ("opt+f1", HotkeyError.optionOnlyModifier),
    ])
    func rejects(input: String, error: HotkeyError) {
        #expect(throws: error) { try HotkeySpec(parsing: input) }
    }

    @Test func memberwiseInitValidatesToo() {
        #expect(throws: HotkeyError.optionOnlyModifier) { try HotkeySpec(key: .n, modifiers: .option) }
        #expect(throws: HotkeyError.missingModifier) { try HotkeySpec(key: .n, modifiers: []) }
        #expect((try? HotkeySpec(key: .f3, modifiers: [])) != nil)
    }
}
