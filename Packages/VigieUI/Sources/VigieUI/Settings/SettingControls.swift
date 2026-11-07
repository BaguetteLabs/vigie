import AppKit
import ModuleKit
import Observation
import SwiftUI

// Generated settings controls (FR5, FR93, UX-DR39). The Settings window is a regular macOS window: these are
// native controls in the system appearance, not the island look, so they read no Vigie theme tokens.
// VigieUI cannot import VigieCore (AD-1): values, writes, duration parsing and the hotkey recorder are
// injected by VigieCore through `SettingBinding` and `SettingControlServices`.

/// A setting value as the generated controls see it. Mirrors VigieCore's `ConfigResolvedValue`.
public enum SettingControlValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case duration(Duration)
    case strings([String])
    /// No value (a hotkey or path that is not set).
    case none

    /// The default of a kind.
    public init(defaultOf kind: SettingKind) {
        switch kind {
        case .bool(let value): self = .bool(value)
        case .int(let value, _, _, _): self = .int(value)
        case .double(let value, _, _, _): self = .double(value)
        case .string(let value): self = .string(value)
        case .secret: self = .none
        case .enumeration(_, let value): self = .string(value)
        case .duration(let value): self = .duration(value)
        case .hotkey(let value), .path(let value): self = value.map(Self.string) ?? .none
        case .list(_, let value): self = .strings(value)
        }
    }

    public var boolValue: Bool? { if case .bool(let value) = self { value } else { nil } }
    public var intValue: Int? {
        switch self {
        case .int(let value): value
        case .double(let value): Int(value)
        default: nil
        }
    }
    public var doubleValue: Double? {
        switch self {
        case .int(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }
    public var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    public var durationValue: Duration? { if case .duration(let value) = self { value } else { nil } }
    public var stringsValue: [String]? { if case .strings(let value) = self { value } else { nil } }
}

/// Reads and writes one setting. `set(nil)` resets it to its default (removes the key from its file).
/// `set` throws when the write is refused; the row shows the error's `LocalizedError.errorDescription`.
public struct SettingBinding {
    public let get: @MainActor () -> SettingControlValue?
    public let set: @MainActor (SettingControlValue?) async throws -> Void

    public init(
        get: @escaping @MainActor () -> SettingControlValue?,
        set: @escaping @MainActor (SettingControlValue?) async throws -> Void
    ) {
        self.get = get
        self.set = set
    }
}

/// One generated row: label, help, control for `kind`, inline error, and a "Reset to default" context action.
public struct SettingRowModel: Identifiable {
    /// Stable id (the config key path).
    public let id: String
    public let label: LocalizedStringResource
    public let help: LocalizedStringResource?
    public let kind: SettingKind
    public let binding: SettingBinding
    /// Display text of an enumeration option (config values are raw, e.g. `menu_bar`).
    public let optionLabel: @MainActor (String) -> String

    public init(
        id: String,
        label: LocalizedStringResource,
        help: LocalizedStringResource? = nil,
        kind: SettingKind,
        binding: SettingBinding,
        optionLabel: @escaping @MainActor (String) -> String = { $0 }
    ) {
        self.id = id
        self.label = label
        self.help = help
        self.kind = kind
        self.binding = binding
        self.optionLabel = optionLabel
    }

    /// The current value, or the kind's default when the binding has none.
    @MainActor public var currentValue: SettingControlValue {
        binding.get() ?? SettingControlValue(defaultOf: kind)
    }
}

/// What VigieCore injects into the generated controls.
public struct SettingControlServices: Sendable {
    /// Parses duration text such as `15m` or `1h30m`; nil when invalid.
    public var parseDuration: @Sendable (String) -> Duration?
    /// Canonical duration text (VigieCore passes its config duration formatter).
    public var formatDuration: @Sendable (Duration) -> String
    /// The control for a `hotkey` setting (KeyboardShortcuts' recorder lives in VigieCore only).
    public var hotkeyRecorder: @MainActor (SettingBinding, SettingFieldState) -> AnyView
    /// Asks the user for a path (`NSOpenPanel`); nil when cancelled.
    public var choosePath: @MainActor () async -> String?
    /// The text shown for a refused write.
    public var errorMessage: @MainActor (any Error) -> String

    public init(
        parseDuration: @escaping @Sendable (String) -> Duration?,
        formatDuration: @escaping @Sendable (Duration) -> String,
        hotkeyRecorder: @escaping @MainActor (SettingBinding, SettingFieldState) -> AnyView =
            SettingControlServices.unavailableRecorder,
        choosePath: @escaping @MainActor () async -> String? = SettingControlServices.openPanel,
        errorMessage: @escaping @MainActor (any Error) -> String = SettingControlServices.defaultErrorMessage
    ) {
        self.parseDuration = parseDuration
        self.formatDuration = formatDuration
        self.hotkeyRecorder = hotkeyRecorder
        self.choosePath = choosePath
        self.errorMessage = errorMessage
    }

    /// Without injected services: no duration parsing (every duration text is rejected).
    public static let standard = SettingControlServices(
        parseDuration: { _ in nil }, formatDuration: { "\($0.components.seconds)s" })

    /// Shown for a `hotkey` setting when no recorder is injected.
    @MainActor public static func unavailableRecorder(_ binding: SettingBinding, _ state: SettingFieldState) -> AnyView
    {
        AnyView(Text(L10n.resource("settings.hotkey.unavailable")).foregroundStyle(.secondary))
    }

    /// `LocalizedError.errorDescription` when the error has one, else a generic catalog message.
    @MainActor public static func defaultErrorMessage(_ error: any Error) -> String {
        if let description = (error as? any LocalizedError)?.errorDescription { return description }
        return L10n.string("settings.error.generic")
    }

    /// A folder-or-file `NSOpenPanel`; returns the path with the home folder abbreviated to `~`.
    @MainActor public static func openPanel() async -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.string("settings.path.choose.prompt")
        let response = await panel.begin()
        guard response == .OK, let url = panel.url else { return nil }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }
}

extension EnvironmentValues {
    @Entry public var settingControlServices: SettingControlServices = .standard
}

/// Per-row write state: the inline error of the last refused edit. Validation of typed text happens here, so
/// invalid text never reaches the binding.
@MainActor @Observable
public final class SettingFieldState {
    public private(set) var error: String?

    public init() {}

    /// Writes `value` (nil = reset to default). Returns whether it was written; on failure `error` is set.
    @discardableResult
    public func apply(
        _ value: SettingControlValue?, to binding: SettingBinding, services: SettingControlServices
    ) async -> Bool {
        do {
            try await binding.set(value)
            error = nil
            return true
        } catch {
            self.error = services.errorMessage(error)
            return false
        }
    }

    /// Shows `message` as the row's error without writing.
    public func report(_ message: String) { error = message }

    public func clearError() { error = nil }

    /// Duration text (`15m`): parsed with the injected parser; invalid text shows an error and writes nothing.
    @discardableResult
    public func commitDuration(_ text: String, to binding: SettingBinding, services: SettingControlServices) async
        -> Bool
    {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let duration = services.parseDuration(trimmed) else {
            error = L10n.string("settings.error.duration")
            return false
        }
        return await apply(.duration(duration), to: binding, services: services)
    }

    /// Whole-number text; invalid text shows an error and writes nothing (range is checked by the writer).
    @discardableResult
    public func commitInt(_ text: String, to binding: SettingBinding, services: SettingControlServices) async -> Bool {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else {
            error = L10n.string("settings.error.integer")
            return false
        }
        return await apply(.int(value), to: binding, services: services)
    }

    /// Number text (`.` or the locale's decimal separator); invalid text shows an error and writes nothing.
    @discardableResult
    public func commitDouble(_ text: String, to binding: SettingBinding, services: SettingControlServices) async
        -> Bool
    {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let value = Double(trimmed) ?? (try? Double(trimmed, format: .number))
        guard let value, value.isFinite else {
            error = L10n.string("settings.error.number")
            return false
        }
        return await apply(.double(value), to: binding, services: services)
    }

    /// List rows: empty rows are dropped before writing.
    @discardableResult
    public func commitList(_ rows: [String], to binding: SettingBinding, services: SettingControlServices) async
        -> Bool
    {
        let items = rows.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return await apply(.strings(items), to: binding, services: services)
    }
}

/// Fixed sizes of the Settings window's fields (native window, not island tokens).
public enum SettingsMetrics {
    public static let numberFieldWidth: CGFloat = 72
    public static let textFieldMinWidth: CGFloat = 180
    public static let textFieldMaxWidth: CGFloat = 280
    public static let listMinWidth: CGFloat = 240
}

/// One generated settings row for a `Form` (`.formStyle(.grouped)`): label and help on the left, the native
/// control on the right, the inline error under the label, "Reset to default" in the context menu.
public struct SettingRow: View {
    @Environment(\.settingControlServices) private var services
    @State private var state = SettingFieldState()
    private let model: SettingRowModel

    public init(_ model: SettingRowModel) {
        self.model = model
    }

    public var body: some View {
        LabeledContent {
            SettingControl(model: model, state: state)
                .textFieldStyle(.roundedBorder)
        } label: {
            Text(model.label)
            if let help = model.help {
                Text(help)
            }
            if let error = state.error {
                Text(verbatim: error)
                    .foregroundStyle(.red)
                    .accessibilityLabel(Text(verbatim: error))
            }
        }
        .contextMenu {
            Button {
                Task { await state.apply(nil, to: model.binding, services: services) }
            } label: {
                Text(L10n.resource("settings.reset"))
            }
            .disabled(model.kind == .secret)
        }
    }
}

/// The native control for one `SettingKind`.
public struct SettingControl: View {
    @Environment(\.settingControlServices) private var services
    let model: SettingRowModel
    let state: SettingFieldState

    public init(model: SettingRowModel, state: SettingFieldState) {
        self.model = model
        self.state = state
    }

    public var body: some View {
        switch model.kind {
        case .bool:
            Toggle(
                isOn: Binding(
                    get: { model.currentValue.boolValue ?? false },
                    set: { newValue in write(.bool(newValue)) })
            ) { Text(model.label) }
            .labelsHidden()
            .toggleStyle(.switch)
        case .int(_, let min, let max, let step):
            IntField(model: model, state: state, min: min, max: max, step: step ?? 1)
        case .double(_, let min, let max, let step):
            if let min, let max, min < max {
                DoubleSlider(model: model, state: state, range: min...max, step: step)
            } else {
                TextDraftField(model: model, state: state, kind: .double)
            }
        case .string:
            TextDraftField(model: model, state: state, kind: .string)
        case .secret:
            VStack(alignment: .trailing) {
                SecureField(text: .constant("")) { Text(model.label) }
                    .labelsHidden()
                    .disabled(true)
                    .frame(minWidth: SettingsMetrics.textFieldMinWidth, maxWidth: SettingsMetrics.textFieldMaxWidth)
                Text(L10n.resource("settings.secret.footnote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .enumeration(let options, _):
            Picker(
                selection: Binding(
                    get: { model.currentValue.stringValue ?? "" },
                    set: { newValue in write(.string(newValue)) })
            ) {
                ForEach(options, id: \.self) { option in
                    Text(verbatim: model.optionLabel(option)).tag(option)
                }
            } label: {
                Text(model.label)
            }
            .labelsHidden()
            .fixedSize()
        case .duration:
            TextDraftField(model: model, state: state, kind: .duration)
        case .hotkey:
            services.hotkeyRecorder(model.binding, state)
        case .path:
            PathField(model: model, state: state)
        case .list(let element, _):
            ListEditor(model: model, state: state, element: element)
        }
    }

    private func write(_ value: SettingControlValue) {
        Task { await state.apply(value, to: model.binding, services: services) }
    }
}

/// A text field holding a draft; commits on Return and when focus leaves. Refreshes from outside edits.
struct TextDraftField: View {
    enum Kind { case string, double, duration }

    @Environment(\.settingControlServices) private var services
    let model: SettingRowModel
    let state: SettingFieldState
    let kind: Kind
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let current = model.currentValue
        TextField(text: $draft) { Text(model.label) }
            .labelsHidden()
            .multilineTextAlignment(kind == .string ? .leading : .trailing)
            .frame(minWidth: SettingsMetrics.textFieldMinWidth, maxWidth: SettingsMetrics.textFieldMaxWidth)
            .focused($focused)
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onAppear { draft = text(for: current) }
            .onChange(of: current) { _, newValue in draft = text(for: newValue) }
    }

    private func text(for value: SettingControlValue) -> String {
        switch kind {
        case .string: value.stringValue ?? ""
        case .double: value.doubleValue.map { $0.formatted(.number.grouping(.never)) } ?? ""
        case .duration: value.durationValue.map(services.formatDuration) ?? ""
        }
    }

    private func commit() {
        let current = model.currentValue
        guard draft != text(for: current) else {
            state.clearError()
            return
        }
        let text = draft
        Task {
            switch kind {
            case .string: await state.apply(.string(text), to: model.binding, services: services)
            case .double: await state.commitDouble(text, to: model.binding, services: services)
            case .duration: await state.commitDuration(text, to: model.binding, services: services)
            }
        }
    }
}

/// Whole-number field plus a stepper honoring min / max / step.
struct IntField: View {
    @Environment(\.settingControlServices) private var services
    let model: SettingRowModel
    let state: SettingFieldState
    let min: Int?
    let max: Int?
    let step: Int
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let current = model.currentValue.intValue ?? 0
        HStack {
            TextField(text: $draft) { Text(model.label) }
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: SettingsMetrics.numberFieldWidth)
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            Stepper {
                Text(model.label)
            } onIncrement: {
                step(from: current, by: step)
            } onDecrement: {
                step(from: current, by: -step)
            }
            .labelsHidden()
        }
        .onAppear { draft = String(current) }
        .onChange(of: current) { _, newValue in draft = String(newValue) }
    }

    /// Adds `delta`, clamped to min / max without overflowing.
    private func step(from current: Int, by delta: Int) {
        var (next, overflow) = current.addingReportingOverflow(delta)
        if overflow { next = delta > 0 ? Int.max : Int.min }
        if let min { next = Swift.max(next, min) }
        if let max { next = Swift.min(next, max) }
        guard next != current else { return }
        Task { await state.apply(.int(next), to: model.binding, services: services) }
    }

    private func commit() {
        let current = model.currentValue.intValue ?? 0
        guard draft != String(current) else {
            state.clearError()
            return
        }
        let text = draft
        Task { await state.commitInt(text, to: model.binding, services: services) }
    }
}

/// A slider for a bounded number; writes when the drag ends.
struct DoubleSlider: View {
    @Environment(\.settingControlServices) private var services
    let model: SettingRowModel
    let state: SettingFieldState
    let range: ClosedRange<Double>
    let step: Double?
    @State private var dragValue: Double?

    var body: some View {
        let current = model.currentValue.doubleValue ?? range.lowerBound
        let shown = dragValue ?? current
        HStack {
            slider(current: current)
                .labelsHidden()
                .frame(minWidth: SettingsMetrics.textFieldMinWidth)
            Text(verbatim: shown.formatted(.number.precision(.fractionLength(0...2))))
                .monospacedDigit()
                .frame(width: SettingsMetrics.numberFieldWidth, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func slider(current: Double) -> some View {
        let binding = Binding(get: { dragValue ?? current }, set: { dragValue = $0 })
        if let step, step > 0 {
            Slider(value: binding, in: range, step: step) {
                Text(model.label)
            } onEditingChanged: { editing in
                if !editing { commit() }
            }
        } else {
            Slider(value: binding, in: range) {
                Text(model.label)
            } onEditingChanged: { editing in
                if !editing { commit() }
            }
        }
    }

    private func commit() {
        guard let value = dragValue else { return }
        Task {
            await state.apply(.double(value), to: model.binding, services: services)
            dragValue = nil
        }
    }
}

/// Path text plus `Choose…` (`NSOpenPanel`). Empty text writes "no path".
struct PathField: View {
    @Environment(\.settingControlServices) private var services
    let model: SettingRowModel
    let state: SettingFieldState
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let current = model.currentValue.stringValue ?? ""
        HStack {
            TextField(text: $draft) { Text(model.label) }
                .labelsHidden()
                .frame(minWidth: SettingsMetrics.textFieldMinWidth, maxWidth: SettingsMetrics.textFieldMaxWidth)
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            Button {
                Task {
                    guard let path = await services.choosePath() else { return }
                    draft = path
                    await state.apply(.string(path), to: model.binding, services: services)
                }
            } label: {
                Text(L10n.resource("settings.path.choose"))
            }
        }
        .onAppear { draft = current }
        .onChange(of: current) { _, newValue in draft = newValue }
    }

    private func commit() {
        let current = model.currentValue.stringValue ?? ""
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard text != current else {
            state.clearError()
            return
        }
        Task {
            await state.apply(
                text.isEmpty ? SettingControlValue.none : .string(text), to: model.binding, services: services)
        }
    }
}

/// An editable list of strings or paths: one field per row, a remove button per row, and an add button.
struct ListEditor: View {
    @Environment(\.settingControlServices) private var services
    let model: SettingRowModel
    let state: SettingFieldState
    let element: SettingListElement
    @State private var rows: [String] = []

    var body: some View {
        let current = model.currentValue.stringsValue ?? []
        VStack(alignment: .trailing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack {
                    TextField(text: rowBinding(index)) { Text(model.label) }
                        .labelsHidden()
                        .frame(minWidth: SettingsMetrics.listMinWidth, maxWidth: SettingsMetrics.textFieldMaxWidth)
                        .onSubmit { commit() }
                    Button {
                        rows.remove(at: index)
                        commit()
                    } label: {
                        Image(systemName: "minus.circle")
                            .accessibilityLabel(Text(L10n.resource("settings.list.remove")))
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                if element == .path {
                    Button {
                        Task {
                            guard let path = await services.choosePath() else { return }
                            rows.append(path)
                            commit()
                        }
                    } label: {
                        Text(L10n.resource("settings.path.choose"))
                    }
                }
                Button {
                    rows.append("")
                } label: {
                    Label {
                        Text(L10n.resource("settings.list.add"))
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .onAppear { rows = current }
        .onChange(of: current) { _, newValue in rows = newValue }
    }

    private func rowBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { rows.indices.contains(index) ? rows[index] : "" },
            set: { newValue in if rows.indices.contains(index) { rows[index] = newValue } })
    }

    private func commit() {
        let snapshot = rows
        Task { await state.commitList(snapshot, to: model.binding, services: services) }
    }
}
