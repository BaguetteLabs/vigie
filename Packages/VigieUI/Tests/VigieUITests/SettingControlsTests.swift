import AppKit
import ModuleKit
import SwiftUI
import Testing

@testable import VigieUI

/// In-memory binding that records writes.
@MainActor
final class MemorySetting {
    var value: SettingControlValue?
    var writes: [SettingControlValue?] = []
    var failure: (any Error)?

    init(_ value: SettingControlValue? = nil) { self.value = value }

    var binding: SettingBinding {
        SettingBinding(
            get: { [unowned self] in value },
            set: { [unowned self] newValue in
                if let failure { throw failure }
                writes.append(newValue)
                value = newValue
            })
    }
}

struct RefusedWrite: LocalizedError {
    var errorDescription: String? { "Refused (localized)" }
}

@MainActor
let testServices = SettingControlServices(
    parseDuration: { $0 == "15m" ? .seconds(900) : nil },
    formatDuration: { "\($0.components.seconds)s" })

@MainActor @Suite struct SettingControlsTests {
    static let kinds: [SettingKind] = [
        .bool(default: true),
        .int(default: 3, min: 1, max: 4, step: 1),
        .int(default: 3),
        .double(default: 0.5, min: 0, max: 1, step: 0.1),
        .double(default: 2.5),
        .string(default: "x"),
        .secret,
        .enumeration(options: ["a", "b"], default: "a"),
        .duration(default: .seconds(60)),
        .hotkey(default: "cmd+k"),
        .path(default: "~/Code"),
        .list(of: .string, default: ["one", "two"]),
        .list(of: .path, default: []),
    ]

    @Test func defaultsMirrorTheKind() {
        #expect(SettingControlValue(defaultOf: .bool(default: true)) == .bool(true))
        #expect(SettingControlValue(defaultOf: .secret) == SettingControlValue.none)
        #expect(SettingControlValue(defaultOf: .hotkey(default: nil)) == SettingControlValue.none)
        #expect(SettingControlValue(defaultOf: .path(default: "~/x")) == .string("~/x"))
        #expect(SettingControlValue(defaultOf: .duration(default: .seconds(5))) == .duration(.seconds(5)))
        #expect(SettingControlValue.int(3).doubleValue == 3)
    }

    @Test func invalidDurationShowsLocalizedErrorAndWritesNothing() async {
        let setting = MemorySetting(.duration(.seconds(60)))
        let state = SettingFieldState()
        #expect(!(await state.commitDuration("15 minutes", to: setting.binding, services: testServices)))
        #expect(state.error == "Enter a duration such as 90s, 15m or 1h30m.")
        #expect(setting.writes.isEmpty)
        #expect(await state.commitDuration(" 15m ", to: setting.binding, services: testServices))
        #expect(state.error == nil)
        #expect(setting.writes == [.duration(.seconds(900))])
    }

    @Test func numbersAndListsValidateBeforeWriting() async {
        let setting = MemorySetting()
        let state = SettingFieldState()
        #expect(!(await state.commitInt("3.5", to: setting.binding, services: testServices)))
        #expect(state.error == "Enter a whole number.")
        #expect(!(await state.commitDouble("abc", to: setting.binding, services: testServices)))
        #expect(state.error == "Enter a number.")
        #expect(setting.writes.isEmpty)
        #expect(await state.commitInt("4", to: setting.binding, services: testServices))
        #expect(await state.commitDouble("0.25", to: setting.binding, services: testServices))
        #expect(await state.commitList(["a", " ", " b "], to: setting.binding, services: testServices))
        #expect(setting.writes == [.int(4), .double(0.25), .strings(["a", "b"])])
    }

    @Test func refusedWriteShowsItsLocalizedDescriptionAndResetPassesNil() async {
        let setting = MemorySetting(.bool(true))
        let state = SettingFieldState()
        setting.failure = RefusedWrite()
        #expect(!(await state.apply(.bool(false), to: setting.binding, services: testServices)))
        #expect(state.error == "Refused (localized)")
        setting.failure = CocoaError(.fileWriteUnknown)
        _ = await state.apply(.bool(false), to: setting.binding, services: testServices)
        #expect(state.error != nil)
        setting.failure = nil
        #expect(await state.apply(nil, to: setting.binding, services: testServices))
        #expect(setting.writes == [nil])
        #expect(state.error == nil)
    }

    @Test func catalogKeysResolve() {
        for key in [
            "settings.reset", "settings.secret.footnote", "settings.error.duration", "settings.error.integer",
            "settings.error.number", "settings.error.generic", "settings.hotkey.unavailable", "settings.path.choose",
            "settings.path.choose.prompt", "settings.list.add", "settings.list.remove", "settings.secret.set",
            "settings.secret.clear", "settings.secret.stored", "settings.secret.empty", "settings.secret.unavailable",
        ] {
            #expect(L10n.string(key) != key, "\(key)")
        }
    }

    @Test func controlsRenderForEverySettingKindWithTheBundledTheme() async throws {
        let theme = PreviewThemes.theme(.dark)
        for (index, kind) in Self.kinds.enumerated() {
            let setting = MemorySetting()
            let model = SettingRowModel(
                id: "k\(index)", label: "Label", help: "Help", kind: kind, binding: setting.binding)
            let view = NSHostingView(
                rootView: Form { SettingRow(model) }
                    .formStyle(.grouped)
                    .environment(\.settingControlServices, testServices)
                    .vigieTheme(theme))
            view.frame = NSRect(x: 0, y: 0, width: 560, height: 200)
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            #expect(rep.pixelsWide > 0, "\(kind)")
            #expect(view.fittingSize.height > 0, "\(kind)")
            #expect(setting.writes.isEmpty, "rendering must not write: \(kind)")
            window.close()
        }
    }

    @Test func secretRowRendersWithAStoreWithoutWriting() async throws {
        let secret = MemorySecret()
        let setting = MemorySetting()
        let model = SettingRowModel(
            id: "s", label: "Token", kind: .secret, binding: setting.binding, secret: secret.binding)
        let view = NSHostingView(
            rootView: Form { SettingRow(model) }.formStyle(.grouped).environment(\.settingControlServices, testServices)
        )
        view.frame = NSRect(x: 0, y: 0, width: 560, height: 200)
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.height > 0)
        #expect(secret.writes.isEmpty)
        #expect(setting.writes.isEmpty)
    }
}

/// In-memory Keychain binding that records writes.
@MainActor
final class MemorySecret {
    var value: String?
    var writes: [String?] = []
    var failure: (any Error)?

    var binding: SecretSettingBinding {
        SecretSettingBinding(
            isSet: { [unowned self] in
                if let failure { throw failure }
                return value != nil
            },
            set: { [unowned self] newValue in
                if let failure { throw failure }
                writes.append(newValue)
                value = newValue
            })
    }
}

@MainActor @Suite struct SecretFieldStateTests {
    @Test func saveStoresTheValueAndClearDeletesIt() async {
        let secret = MemorySecret()
        let field = SettingFieldState()
        let state = SecretFieldState()
        #expect(state.isSet == nil)
        await state.refresh(secret.binding, field: field, services: testServices)
        #expect(state.isSet == false)

        #expect(await state.save("", to: secret.binding, field: field, services: testServices) == false)
        #expect(await state.save("\n", to: secret.binding, field: field, services: testServices) == false)
        #expect(secret.writes.isEmpty)

        #expect(await state.save("tok en\n", to: secret.binding, field: field, services: testServices))
        #expect(secret.writes == ["tok en"])
        #expect(state.isSet == true)

        #expect(await state.clear(secret.binding, field: field, services: testServices))
        #expect(secret.writes == ["tok en", nil])
        #expect(state.isSet == false)
    }

    @Test func refusedWriteShowsTheErrorAndKeepsTheState() async {
        let secret = MemorySecret()
        secret.value = "old"
        let field = SettingFieldState()
        let state = SecretFieldState()
        await state.refresh(secret.binding, field: field, services: testServices)
        secret.failure = RefusedWrite()
        #expect(await state.save("new", to: secret.binding, field: field, services: testServices) == false)
        #expect(field.error == "Refused (localized)")
        #expect(state.isSet == true)
        secret.failure = nil
        #expect(await state.save("new", to: secret.binding, field: field, services: testServices))
        #expect(field.error == nil)
    }
}
