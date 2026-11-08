import ModuleKit
import UniformTypeIdentifiers

/// A stand-in Stash zone for `-VigieSimulateDrop YES` in Debug builds when the Shelf module is off (Ask AI,
/// AirDrop and Image to Text come from their modules since Stories 9.6, 9.8 and 9.9). Its handler rejects
/// every payload.
public enum DropSampleZones {
    public static func make() -> [DropZone] {
        [
            DropZone(
                id: "sample.stash", label: resource("drop.sample.stash.label"), glyph: "drop.stash",
                accentToken: "iris-2", role: .primary,
                cell: DropCell(preferredColumn: 1, preferredRow: 1, span: .init(columns: 2, rows: 2)), order: 0,
                accepts: [], handler: { _ in .rejected }, meta: resource("drop.sample.stash.meta"),
                releaseLine: resource("drop.sample.stash.release"),
                accessibilityLabel: resource("drop.sample.stash.a11y"))
        ]
    }

    private static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(Bundle.module.bundleURL))
    }
}
