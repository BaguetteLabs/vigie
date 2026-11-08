import ModuleKit
import UniformTypeIdentifiers

/// Two stand-in zones (Stash and Ask AI) for `-VigieSimulateDrop YES` in Debug builds: the real ones arrive with
/// the Shelf (Story 9.2) and Ask AI (Story 9.6). Their handlers reject every payload.
public enum DropSampleZones {
    public static func make() -> [DropZone] {
        [
            DropZone(
                id: "sample.stash", label: resource("drop.sample.stash.label"), glyph: "drop.stash",
                accentToken: "iris-2", role: .primary,
                cell: DropCell(preferredColumn: 1, preferredRow: 1, span: .init(columns: 2, rows: 2)), order: 0,
                accepts: [], handler: { _ in .rejected }, meta: resource("drop.sample.stash.meta"),
                releaseLine: resource("drop.sample.stash.release"),
                accessibilityLabel: resource("drop.sample.stash.a11y")),
            DropZone(
                id: "sample.ask", label: resource("drop.sample.ask.label"), glyph: "plus", accentToken: "iris-2",
                role: .secondary,
                cell: DropCell(preferredColumn: 3, preferredRow: 1, span: .init(columns: 1, rows: 2)), order: 10,
                accepts: [], handler: { _ in .rejected }, releaseLine: resource("drop.sample.ask.release"),
                accessibilityLabel: resource("drop.sample.ask.a11y"),
                modifierHint: DropModifierHint(
                    modifiers: .option, idle: resource("drop.sample.ask.hint"),
                    active: resource("drop.sample.ask.hintActive")),
                style: .target),
        ]
    }

    private static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(Bundle.module.bundleURL))
    }
}
