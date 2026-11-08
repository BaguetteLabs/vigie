import SwiftUI

/// The Time tab (Story 20.2, DESIGN "Time tab", EXPERIENCE "Time", mockup `key-design-pass-1-7.html` 1.7e):
/// the quick-start card (Pomodoro with its lengths, presets, `+ COUNTDOWN`, a minutes field with `START ↵`)
/// over the running card (`RUNNING · N`, sorted by end time; `NOTHING RUNNING` when empty). Rows: a 30px time
/// ring (a track for a Countdown), label over kind, remaining time over `ENDS 14:52`, and the chips.
///
/// Keyboard (focus order): the quick-start buttons (`←→` inside the group), the minutes field, `START`, the
/// running list (`↑↓`; on the selected row Space = Pause / Resume, `⌘R` = Reset, `⌘⌫` = Remove, `⌘Z` = undo
/// within 5 s, `↵` = Dismiss on an ended row), then the row chips.
///
/// `snapshot` is read in `body`, so an `@Observable` source re-renders the tab when it changes.
public struct TimeTabView: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.privacyActive) private var privacyActive
    @FocusState private var focus: TimeFocus?
    @State private var minutes = ""
    @State private var showsCountdown = false

    /// False draws the field as text and the rows in a plain stack (offscreen renders).
    var interactive = true
    private let snapshot: @MainActor () -> TimeTabSnapshot
    private let actions: TimeTabActions

    public init(snapshot: @escaping @MainActor () -> TimeTabSnapshot, actions: TimeTabActions) {
        self.snapshot = snapshot
        self.actions = actions
    }

    /// An offscreen-render copy with `minutes` typed in the field.
    func rendering(minutes text: String) -> TimeTabView {
        var copy = self
        copy.interactive = false
        copy._minutes = State(initialValue: text)
        return copy
    }

    public var body: some View {
        let snapshot = snapshot().privacy(privacyActive)
        VStack(spacing: theme.spacing(.gridGap)) {
            quickStart(snapshot)
                .frame(height: theme.componentLength("time-tab", "quick-start-height") ?? TimeMetrics.quickStartHeight)
            running(snapshot)
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, theme.spacing(.gridPaddingX))
        .padding(.top, theme.spacing(.cardPaddingY))
        .padding(.bottom, theme.spacing(.gridPaddingX))
        .onAppear {
            actions.visibility(true)
            takeHotkeyFocus(snapshot.focusQuickStart)
        }
        .onDisappear { actions.visibility(false) }
        .onChange(of: snapshot.focusQuickStart) { _, pending in takeHotkeyFocus(pending) }
    }

    private func takeHotkeyFocus(_ pending: Bool) {
        guard pending else { return }
        focus = .quick(0)
        actions.quickStartFocused()
    }

    // MARK: Quick start

    /// Focusable buttons of the group: the presets, then `+ COUNTDOWN` (Pomodoro is disabled until 20.5).
    private func quickCount(_ snapshot: TimeTabSnapshot) -> Int { snapshot.quickStart.presets.count + 1 }

    @ViewBuilder private func quickStart(_ snapshot: TimeTabSnapshot) -> some View {
        let quick = snapshot.quickStart
        WidgetCard(
            title: Text(L10n.resource("time.quickStart.title")), meta: Text(L10n.resource("time.quickStart.meta"))
        ) {
            HStack(spacing: TimeMetrics.quickGap) {
                TimeQuickButton(isPomodoro: true, accessibility: L10n.string("time.quickStart.pomodoro.a11y")) {
                } label: {
                    Text(L10n.resource("time.quickStart.pomodoro"))
                    Text(verbatim: quick.pomodoroLengths).font(
                        TimeMetrics.font(theme, .readoutLabel, size: TimeMetrics.quickUnitSize)
                    )
                    .foregroundStyle(theme.color(.ink3))
                }
                .disabled(!quick.pomodoroAvailable)
                .help(Text(L10n.resource("time.quickStart.pomodoro.later")))
                ForEach(Array(quick.presets.enumerated()), id: \.offset) { index, preset in
                    TimeQuickButton(accessibility: L10n.format("time.quickStart.preset.a11y", preset)) {
                        actions.startPreset(preset)
                    } label: {
                        Text(verbatim: "\(preset)")
                            .font(TimeMetrics.font(theme, .numeralBig, size: TimeMetrics.quickValueSize, weight: 300))
                        Text(L10n.resource("time.quickStart.min"))
                    }
                    .focused($focus, equals: .quick(index))
                    .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in moveQuick(index, press.key, snapshot) }
                }
                countdownButton(snapshot, index: quick.presets.count)
                Spacer(minLength: TimeMetrics.quickGap)
                customField
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func moveQuick(_ index: Int, _ key: KeyEquivalent, _ snapshot: TimeTabSnapshot) -> KeyPress.Result {
        let count = quickCount(snapshot)
        let next = key == .leftArrow ? max(index - 1, 0) : min(index + 1, count - 1)
        focus = .quick(next)
        return .handled
    }

    @ViewBuilder private func countdownButton(_ snapshot: TimeTabSnapshot, index: Int) -> some View {
        TimeQuickButton(accessibility: L10n.string("time.quickStart.countdown.a11y")) {
            showsCountdown = true
        } label: {
            Text(L10n.resource("time.quickStart.countdown"))
        }
        .focused($focus, equals: .quick(index))
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in moveQuick(index, press.key, snapshot) }
        .popover(isPresented: $showsCountdown, arrowEdge: .bottom) {
            TimeCountdownForm(initial: snapshot.countdownDefault) { date, label in
                if actions.startCountdown(date, label) { showsCountdown = false }
            }
            .vigieTheme(theme)
        }
    }

    /// The custom minutes field and `START ↵` (mockup `.qf`).
    @ViewBuilder private var customField: some View {
        let shape = RoundedRectangle(
            cornerRadius: theme.actionRadius(height: TimeMetrics.quickButtonHeight), style: .continuous)
        HStack(spacing: TimeMetrics.quickGap) {
            Group {
                if interactive {
                    TextField(text: $minutes, prompt: Text(L10n.resource("time.quickStart.field.prompt"))) {
                        Text(L10n.resource("time.quickStart.field.a11y"))
                    }
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .minutes)
                    .onSubmit(startCustom)
                } else if minutes.isEmpty {
                    Text(L10n.resource("time.quickStart.field.prompt")).foregroundStyle(theme.color(.ink3))
                } else {
                    Text(verbatim: minutes)
                }
            }
            .font(TimeMetrics.font(theme, .numeralBig, size: TimeMetrics.quickValueSize, weight: 300))
            .foregroundStyle(theme.color(.ink2))
            .frame(width: TimeMetrics.fieldWidth)
            Text(L10n.resource("time.quickStart.min"))
                .font(TimeMetrics.font(theme, .readoutLabel, size: TimeMetrics.chipSize))
                .tracking(theme.tracking(.readoutLabel))
                .foregroundStyle(theme.color(.ink3))
            TimeChip(label: L10n.resource("time.quickStart.start"), shortcut: "↵", height: TimeMetrics.startHeight) {
                startCustom()
            }
            .focused($focus, equals: .start)
        }
        .padding(.leading, TimeMetrics.quickPaddingX)
        .padding(.trailing, TimeMetrics.quickGap)
        .frame(height: TimeMetrics.quickButtonHeight)
        .fixedSize(horizontal: true, vertical: false)
        .background(theme.color(.ink1).opacity(TimeMetrics.fieldFill), in: shape)
        .overlay {
            shape.strokeBorder(
                theme.borderColor(.ink1, opacity: TimeMetrics.fieldBorder), lineWidth: theme.a11y.hairlineWidth)
        }
    }

    private func startCustom() {
        if actions.startCustom(minutes) { minutes = "" }
    }

    // MARK: Running

    @ViewBuilder private func running(_ snapshot: TimeTabSnapshot) -> some View {
        WidgetCard(
            title: Text(L10n.format("time.running.title", snapshot.runningCount)),
            meta: Text(L10n.resource("time.running.meta"))
        ) {
            if snapshot.rows.isEmpty {
                VStack(spacing: 0) {
                    EmptyStateBlock(VigieCopy.nothingRunning)
                    undoBar(snapshot)
                }
            } else {
                VStack(spacing: 0) {
                    rowList(snapshot)
                        .frame(maxHeight: .infinity, alignment: .top)
                    undoBar(snapshot)
                }
            }
        }
    }

    @ViewBuilder private func undoBar(_ snapshot: TimeTabSnapshot) -> some View {
        if snapshot.canUndo {
            HStack(spacing: TimeMetrics.chipGap) {
                Text(L10n.resource("time.undo.removed"))
                    .font(TimeMetrics.font(theme, .readoutLabel, size: TimeMetrics.sublineSize))
                    .tracking(theme.tracking(.readoutLabel))
                    .foregroundStyle(theme.color(.ink3))
                Spacer(minLength: 0)
                TimeChip(label: L10n.resource("time.action.undo"), shortcut: "⌘Z") { actions.undo() }
            }
        }
    }

    @ViewBuilder private func rowList(_ snapshot: TimeTabSnapshot) -> some View {
        let selected = snapshot.validSelection
        let rows = VStack(spacing: 0) {
            ForEach(Array(snapshot.rows.enumerated()), id: \.element.id) { index, row in
                TimeRowView(
                    row: row, isFirst: index == 0, isSelected: row.id == selected, focus: $focus,
                    perform: { control in
                        actions.select(row.id)
                        actions.perform(row.id, control)
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    actions.select(row.id)
                    focus = .list
                }
            }
        }
        if interactive {
            ScrollFadeList(showsHint: false) { rows }
                .focusable()
                .focusEffectDisabled()
                .focused($focus, equals: .list)
                .onKeyPress(keys: [
                    .upArrow, .downArrow, .space, .return, .delete, KeyEquivalent("r"), KeyEquivalent("z"),
                ]) { press in
                    handle(press, snapshot)
                }
        } else {
            rows
        }
    }

    private func handle(_ press: KeyPress, _ snapshot: TimeTabSnapshot) -> KeyPress.Result {
        let command = press.modifiers == .command
        switch press.key {
        case .upArrow, .downArrow:
            guard press.modifiers.isEmpty, let id = snapshot.moved(by: press.key == .upArrow ? -1 : 1) else {
                return .ignored
            }
            actions.select(id)
            return .handled
        case KeyEquivalent("z") where command:
            guard snapshot.canUndo else { return .ignored }
            actions.undo()
            return .handled
        default:
            break
        }
        guard let id = snapshot.validSelection, let row = snapshot.rows.first(where: { $0.id == id }) else {
            return .ignored
        }
        let control: TimeRowModel.Control? =
            switch press.key {
            case .space where press.modifiers.isEmpty: row.pauseToggle
            case .return where press.modifiers.isEmpty: row.isEnded ? .dismiss : nil
            case .delete where command: row.isEnded ? .dismiss : .remove
            case KeyEquivalent("r") where command: row.controls.contains(.reset) ? .reset : nil
            default: nil
            }
        guard let control else { return .ignored }
        actions.perform(id, control)
        return .handled
    }
}

/// Where keyboard focus is inside the tab.
enum TimeFocus: Hashable {
    case quick(Int)
    case minutes
    case start
    case list
    case chip(UUID, TimeRowModel.Control)
}

/// One running-list row (mockup `.trow`): `30px | 1fr | 92px | 196px`, 62px tall.
struct TimeRowView: View {
    @Environment(\.vigieTheme) private var theme
    let row: TimeRowModel
    let isFirst: Bool
    let isSelected: Bool
    var focus: FocusState<TimeFocus?>.Binding
    let perform: @MainActor (TimeRowModel.Control) -> Void

    var body: some View {
        HStack(spacing: TimeMetrics.columnGap) {
            visual
                .frame(width: TimeMetrics.ringSize(theme))
            VStack(alignment: .leading, spacing: TimeMetrics.labelGap) {
                Text(verbatim: row.label)
                    .font(theme.font(.rowPrimary))
                    .foregroundStyle(theme.color(.ink1))
                    .lineLimit(1)
                Text(verbatim: row.kind)
                    .font(TimeMetrics.font(theme, .readoutLabel, size: TimeMetrics.kindSize))
                    .tracking(theme.tracking(.readoutLabel))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.color(row.isEnded ? TimeMetrics.accentTextRole(theme) : .ink3))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: TimeMetrics.valueGap) {
                Text(verbatim: row.value)
                    .font(theme.font(.timeValue))
                    .tracking(theme.tracking(.timeValue))
                    .monospacedDigit()
                    .foregroundStyle(theme.color(row.isEnded ? .ink3 : .ink1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: row.subline)
                    .font(TimeMetrics.font(theme, .readoutLabel, size: TimeMetrics.sublineSize))
                    .tracking(theme.tracking(.readoutLabel))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.color(row.isEnded ? TimeMetrics.accentTextRole(theme) : .ink3))
                    .lineLimit(1)
            }
            .frame(width: TimeMetrics.valueWidth, alignment: .trailing)
            HStack(spacing: TimeMetrics.chipGap) {
                ForEach(row.controls, id: \.self) { control in
                    TimeChip(
                        label: L10n.resource("time.action.\(control.rawValue)"),
                        dim: control == .remove
                    ) { perform(control) }
                    .focused(focus, equals: .chip(row.id, control))
                }
            }
            .frame(width: TimeMetrics.controlsWidth, alignment: .trailing)
        }
        .padding(.horizontal, theme.spacing(.glyphGap))
        .frame(height: theme.componentLength("time-tab", "item-row-height") ?? TimeMetrics.rowHeight)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(theme.color(.ink1).opacity(TimeMetrics.rowRule(theme.look)))
                    .frame(height: theme.a11y.hairlineWidth)
            }
        }
        .rowHoverBrighten()
        .keyboardSelectionRing(isSelected: isSelected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: row.accessibilityLabel))
    }

    @ViewBuilder private var visual: some View {
        switch row.visual {
        case .ring(let fraction, let paused):
            TimeRing(fractionLeft: fraction, dimmed: paused)
        case .track(let elapsed):
            CountdownTrack(fractionElapsed: elapsed)
        case .ended:
            TimeRing(fractionLeft: 1)
        }
    }
}

/// A quick-start pill (mockup `.qb`, 34px; the Pomodoro one accent-tinted).
struct TimeQuickButton<Label: View>: View {
    @Environment(\.vigieTheme) private var theme
    var isPomodoro = false
    let accessibility: String
    let action: @MainActor () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: TimeMetrics.quickGap) { label() }.fixedSize()
        }
        .buttonStyle(TimeQuickButtonStyle(isPomodoro: isPomodoro))
        .focusable(interactions: .activate)
        .focusEffectDisabled()
        .accessibilityLabel(Text(verbatim: accessibility))
    }
}

struct TimeQuickButtonStyle: ButtonStyle {
    let isPomodoro: Bool

    func makeBody(configuration: Configuration) -> some View {
        TimeQuickButtonBody(label: configuration.label, isPomodoro: isPomodoro, isPressed: configuration.isPressed)
    }
}

private struct TimeQuickButtonBody: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    let label: ButtonStyleConfiguration.Label
    let isPomodoro: Bool
    let isPressed: Bool

    var body: some View {
        let height = TimeMetrics.quickButtonHeight
        let shape = RoundedRectangle(cornerRadius: theme.actionRadius(height: height), style: .continuous)
        let tint: ColorRole = isPomodoro ? TimeMetrics.accentRole(theme) : .ink1
        label
            .font(TimeMetrics.font(theme, .action, size: TimeMetrics.quickUnitSize))
            .tracking(theme.tracking(.action))
            .textCase(.uppercase)
            .foregroundStyle(theme.color(.ink1))
            .lineLimit(1)
            .padding(.horizontal, TimeMetrics.quickPaddingX)
            .frame(height: height)
            .background(
                theme.glassFill(
                    LinearGradient(
                        colors: [
                            theme.color(tint).opacity(TimeMetrics.quickGlassTop),
                            theme.color(tint).opacity(TimeMetrics.quickGlassBottom),
                        ], startPoint: .top, endPoint: .bottom), flat: .surfaceCard),
                in: shape
            )
            .overlay {
                shape.strokeBorder(
                    theme.borderColor(
                        theme.usesCornerMarks && !isPomodoro ? .structure : tint,
                        opacity: isPomodoro ? TimeMetrics.pomodoroBorder : TimeMetrics.quickBorder),
                    lineWidth: theme.a11y.hairlineWidth)
            }
            .overlay {
                if isFocused { shape.strokeBorder(theme.color(.iris1), lineWidth: theme.a11y.focusRingWidth) }
            }
            .contentShape(shape)
            .opacity(isPressed ? ComponentMetrics.pressedOpacity : (isEnabled ? 1 : ComponentMetrics.disabledOpacity))
    }
}

/// A row chip (mockup `.chip`): `PAUSE`, `RESET`, `REMOVE` (dim), `DISMISS`, `START ↵`, `UNDO ⌘Z`. At least
/// 24px tall; keyboard focus draws the `iris-1` ring.
struct TimeChip: View {
    let label: LocalizedStringResource
    var shortcut: String?
    var dim = false
    var height: CGFloat = TimeMetrics.chipHeight
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
        }
        .buttonStyle(TimeChipStyle(shortcut: shortcut, dim: dim, height: height))
        .focusable(interactions: .activate)
        .focusEffectDisabled()
        .accessibilityLabel(Text(verbatim: AccessibilityLabel.control(String(localized: label), shortcut: shortcut)))
    }
}

struct TimeChipStyle: ButtonStyle {
    let shortcut: String?
    let dim: Bool
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        TimeChipBody(
            label: configuration.label, shortcut: shortcut, dim: dim, height: height, isPressed: configuration.isPressed
        )
    }
}

private struct TimeChipBody: View {
    @Environment(\.vigieTheme) private var theme
    @Environment(\.isFocused) private var isFocused
    let label: ButtonStyleConfiguration.Label
    let shortcut: String?
    let dim: Bool
    let height: CGFloat
    let isPressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.actionRadius(height: height), style: .continuous)
        HStack(spacing: theme.spacing(.glyphGap)) {
            label
            if let shortcut {
                Text(verbatim: shortcut).foregroundStyle(theme.color(.ink2))
            }
        }
        .font(TimeMetrics.font(theme, .action, size: TimeMetrics.chipSize))
        .tracking(theme.tracking(.action))
        .textCase(.uppercase)
        .foregroundStyle(theme.color(dim ? .ink2 : .ink1))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, TimeMetrics.chipPaddingX)
        .frame(height: height)
        .overlay {
            shape.strokeBorder(
                theme.usesCornerMarks
                    ? theme.borderColor(.structure, opacity: ComponentMetrics.structBorder)
                    : theme.borderColor(.ink1, opacity: dim ? TimeMetrics.chipBorderDim : TimeMetrics.chipBorder),
                lineWidth: theme.a11y.hairlineWidth)
        }
        .overlay {
            if isFocused { shape.strokeBorder(theme.color(.iris1), lineWidth: theme.a11y.focusRingWidth) }
        }
        .contentShape(shape)
        .opacity(isPressed ? ComponentMetrics.pressedOpacity : 1)
    }
}

/// The `+ COUNTDOWN` form: a clock time (date optional, today or later), an optional name, `START`.
struct TimeCountdownForm: View {
    @Environment(\.vigieTheme) private var theme
    @State private var date: Date
    @State private var label = ""
    let start: @MainActor (Date, String) -> Void

    init(initial: Date, start: @escaping @MainActor (Date, String) -> Void) {
        _date = State(initialValue: initial)
        self.start = start
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.rowGap)) {
            Text(L10n.resource("time.countdown.title"))
                .font(theme.font(.cardTitle))
                .tracking(theme.tracking(.cardTitle))
                .foregroundStyle(theme.color(.ink3))
            DatePicker(selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute]) {
                Text(L10n.resource("time.countdown.date"))
            }
            .labelsHidden()
            TextField(text: $label, prompt: Text(L10n.resource("time.countdown.name.prompt"))) {
                Text(L10n.resource("time.countdown.name"))
            }
            .onSubmit { start(date, label) }
            HStack {
                Spacer()
                TimeChip(label: L10n.resource("time.quickStart.start"), shortcut: "↵") { start(date, label) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(theme.spacing(.cardPaddingX))
        .frame(width: TimeMetrics.countdownFormWidth)
    }
}

#Preview("Time tab · dark") {
    TimeTabPreview(look: .dark)
}

#Preview("Time tab · light") {
    TimeTabPreview(look: .light)
}

private struct TimeTabPreview: View {
    let look: Look

    var body: some View {
        let theme = PreviewThemes.theme(look)
        TimeTabView(snapshot: { TimePreviewSamples.snapshot }, actions: TimeTabActions())
            .frame(width: theme.componentLength("expanded-panel", "width"), height: TimeMetrics.previewHeight)
            .background(theme.color(.surfacePanel))
            .vigieTheme(theme)
    }
}

enum TimePreviewSamples {
    static let snapshot = TimeTabSnapshot(
        quickStart: TimeQuickStart(presets: [5, 10, 25], pomodoroLengths: "25 · 5 · 15"),
        rows: [
            TimeRowModel(
                id: UUID(), label: "Tea", kind: "5 MIN TIMER", value: "3:06", subline: "ENDS 14:52",
                visual: .ring(fractionLeft: 0.62, paused: false), controls: [.pause, .reset, .remove],
                accessibilityLabel: "Tea, 5 minute timer"),
            TimeRowModel(
                id: UUID(), label: "Release 0.3", kind: "COUNTDOWN · FRI 14 NOV · 14:00", value: "7D 23H",
                subline: "IN 191 H", visual: .track(fractionElapsed: 0.1), controls: [.remove],
                accessibilityLabel: "Release 0.3, countdown"),
        ],
        runningCount: 2)
}
