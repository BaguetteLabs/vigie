import Foundation
import ModuleKit

// View models of the script widget templates (AD-18, Story 12.5, DESIGN "Script widget" and "Side-slot item",
// UX-DR36, UX-DR61, UX-DR82, UX-DR86). Plain `Sendable` values: the integrations module builds them from a
// script's output and run state; these templates are the only renderers of script output. Script-provided text
// (values of text and status widgets, labels, details, targets) is user text that Privacy mode hides with no
// opt-out (AD-24); levels, numbers, core labels and the script's name stay.

/// The segmented 6px bar under a number widget's numeral (UX-DR36): `segmentCount` segments, the first
/// `filled` lit, the segment at the warn threshold outlined in the quota-warning yellow (A43).
public struct ScriptNumberBar: Sendable, Equatable {
    /// Segments when nothing sets a threshold (the mocked `3 open · Warn ≥ 5`).
    public static let defaultSegmentCount = 5

    public enum Segment: Sendable, Equatable {
        case off
        case on
        /// The warn segment, lit or not.
        case warn(lit: Bool)
    }

    public let segmentCount: Int
    /// Lit segments, `0...segmentCount`.
    public let filled: Int
    /// Index of the warn segment.
    public let warnIndex: Int

    /// - Parameters:
    ///   - value: the widget's number; a value that is not a number lights nothing.
    ///   - warnAt: the warn threshold, one segment per unit up to it; nil puts it on the last of
    ///     ``defaultSegmentCount`` segments.
    public init(value: Double?, warnAt: Int? = nil) {
        let threshold = max(1, warnAt ?? Self.defaultSegmentCount)
        segmentCount = max(threshold, Self.defaultSegmentCount)
        let lit = value.map { $0.isFinite ? Int(max(0, $0).rounded(.down)) : 0 } ?? 0
        filled = min(lit, segmentCount)
        warnIndex = threshold - 1
    }

    public var segments: [Segment] {
        (0..<segmentCount).map { index in
            let lit = index < filled
            if index == warnIndex { return .warn(lit: lit) }
            return lit ? .on : .off
        }
    }
}

/// What a widget shows from a script's (last good) output, per `widget.type`.
public enum ScriptWidgetContent: Sendable, Equatable {
    /// A level on the status vocabulary, an optional qualifier after the level (`OK · UP`, the output's
    /// `detail`) and the value line (`200 · 142 ms`).
    case status(level: StatusLevel, qualifier: String?, value: String?)
    /// The big numeral, its label (`open`), the detail under the bar, the bar, and the level when the output
    /// gives one.
    case number(value: String, label: String?, detail: String?, bar: ScriptNumberBar, level: StatusLevel?)
    /// Its label (nil: `TEXT`) over the value.
    case text(label: String?, value: String, level: StatusLevel?)

    public var level: StatusLevel? {
        switch self {
        case .status(let level, _, _): level
        case .number(_, _, _, _, let level), .text(_, _, let level): level
        }
    }

    /// Script text masked (AD-24): status qualifier and value, number label and detail, text label and value.
    /// The number itself and the level stay.
    func redacted() -> ScriptWidgetContent {
        switch self {
        case .status(let level, let qualifier, let value):
            .status(level: level, qualifier: qualifier.privacyMasked, value: value.privacyMasked)
        case .number(let value, let label, let detail, let bar, let level):
            .number(value: value, label: label.privacyMasked, detail: detail.privacyMasked, bar: bar, level: level)
        case .text(let label, let value, let level):
            .text(label: label.privacyMasked, value: value.privacyMasked, level: level)
        }
    }

    /// The parts VoiceOver reads after the name: level, qualifier, value, label, detail.
    var spokenParts: [String] {
        let formatter = StatusLabelFormatter()
        switch self {
        case .status(let level, let qualifier, let value):
            return [formatter.label(for: level), qualifier, value].compactMap { $0 }
        case .number(let value, let label, let detail, _, let level):
            return [level.map { formatter.label(for: $0) }, value, label, detail].compactMap { $0 }
        case .text(let label, let value, let level):
            return [level.map { formatter.label(for: $0) }, label, value].compactMap { $0 }
        }
    }
}

/// The meta line under a card's body, in `ink-3` (DESIGN "Script widget").
public enum ScriptCardMeta: Sendable, Equatable {
    /// `CHECKED 2 MIN AGO` (status widgets).
    case checked(Date)
    /// `DOWN SINCE 14:44` (a status widget at DOWN).
    case downSince(Date)
    /// `UPDATED 4 MIN AGO` (number and text widgets).
    case updated(Date)
    /// Core copy given as is: a failure (`EXIT 3`, `TIMED OUT · 30S`).
    case label(String)

    /// The line at `now`; relative times count whole minutes.
    public func text(now: Date, timeZone: TimeZone = .current) -> String {
        let formatter = StatusLabelFormatter(timeZone: timeZone)
        switch self {
        case .checked(let date):
            return formatter.qualifier(.checkedAgo(Self.elapsed(from: date, to: now)))
        case .downSince(let date):
            return formatter.label(for: RunStatus.down, qualifier: .since(date))
        case .updated(let date):
            let elapsed = Self.elapsed(from: date, to: now)
            let minutes = StatusLabelFormatter.wholeMinutes(elapsed)
            if minutes < 1 { return L10n.string("script.meta.updatedUnderMinute") }
            if minutes < 60 { return L10n.format("script.meta.updatedMinutesAgo", minutes) }
            return L10n.format("script.meta.updatedAgo", formatter.elapsed(elapsed))
        case .label(let text):
            return text
        }
    }

    static func elapsed(from date: Date, to now: Date) -> Duration {
        .seconds(max(0, now.timeIntervalSince(date)))
    }
}

/// What a click on a widget does (the output's `action`); its target stays with the module.
public enum ScriptWidgetAction: String, Sendable, Equatable, CaseIterable {
    case open
    case run
    case copy

    /// VoiceOver hint; never the script's URL, argv or text.
    public var hint: String { L10n.string("script.action.\(rawValue).hint") }
}

/// A script's Home card (`components.script-card`, 222 × 138): header name and target left, cadence right; a
/// body per state; the meta line, with the WARN triangle badge while the latest run failed (UX-DR86).
public struct ScriptCardModel: Sendable, Equatable, PrivacyRedactable {
    /// What the body shows.
    public enum Body: Sendable, Equatable {
        /// The (last good) output.
        case output(ScriptWidgetContent)
        /// Awaiting confirmation on this Mac: `NOT CONFIRMED`, no level glyph (UX-DR87).
        case notConfirmed
        /// Core copy in `ink-3`, no glyph: `WAITING · FIRST RUN`, or a failure with no good output yet.
        case state(String)
    }

    /// The script's (module) name: stays under Privacy mode.
    public var name: String
    /// The script's target (`VIGIE.APP`), script text.
    @Sensitive public var target: String?
    /// `EVERY 1M`.
    public var cadence: String
    public var body: Body
    public var meta: ScriptCardMeta?
    /// The latest run failed: the meta line leads with the WARN triangle (UX-DR86).
    public var warningBadge: Bool
    /// The output's `action`, when the body is clickable.
    public var action: ScriptWidgetAction?

    public init(
        name: String, target: String? = nil, cadence: String, body: Body, meta: ScriptCardMeta? = nil,
        warningBadge: Bool = false, action: ScriptWidgetAction? = nil
    ) {
        self.name = name
        self.target = target
        self.cadence = cadence
        self.body = body
        self.meta = meta
        self.warningBadge = warningBadge
        self.action = action
    }

    /// `GitHub PRs · vigie`, or the name alone.
    public var title: String {
        guard let target, !target.isEmpty else { return name }
        return StatusLabelFormatter.joined(name, target)
    }

    public func redacted() -> ScriptCardModel {
        var copy = self
        copy.target = $target.masked
        if case .output(let content) = body { copy.body = .output(content.redacted()) }
        return copy
    }

    /// "GitHub PRs, vigie, 3, open, updated 2 min ago": name, target, the body, the meta line.
    public func accessibilityLabel(now: Date, timeZone: TimeZone = .current) -> String {
        var parts = [name]
        if let target, !target.isEmpty { parts.append(target) }
        switch body {
        case .output(let content): parts += content.spokenParts
        case .notConfirmed: parts.append(ScriptStateLabel.notConfirmedText)
        case .state(let text): parts.append(text)
        }
        if warningBadge { parts.append(StatusLabelFormatter().label(for: StatusLevel.warn)) }
        if let meta { parts.append(meta.text(now: now, timeZone: timeZone)) }
        return parts.dropFirst().reduce(parts[0]) { AccessibilityLabel.joined($0, $1) }
    }
}

/// A script's item on the closed notch's left-wing lane (DESIGN "Side-slot item", A22, UX-DR86).
public struct ScriptSideItemModel: Sendable, Equatable, PrivacyRedactable {
    public enum Content: Sendable, Equatable {
        /// 16px glyph, then the level (`OK`, in the level hue) over the target (`VIGIE.APP`, `ink-3`).
        case level(StatusLevel, target: String)
        /// The value over the label, no glyph (number and text widgets). `valueIsText`: a text widget's value
        /// (masked under Privacy mode); a number stays.
        case value(String, label: String, valueIsText: Bool)
        /// Core copy under the name, no glyph: `NOT CONFIRMED`, `WAITING · FIRST RUN`.
        case state(String)
    }

    /// The script's (module) name.
    public var name: String
    public var content: Content
    /// The level VoiceOver reads after the name, when there is one.
    public var level: StatusLevel?

    public init(name: String, content: Content, level: StatusLevel? = nil) {
        self.name = name
        self.content = content
        self.level = level
    }

    /// "vigie.app, OK" (UX-DR86): the name, then the level, else the value, else the state.
    public var accessibilityLabel: String {
        if let level { return AccessibilityLabel.item(name: name, level: level) }
        switch content {
        case .level(let level, _): return AccessibilityLabel.item(name: name, level: level)
        case .value(let value, _, _): return AccessibilityLabel.item(name: name, status: value)
        case .state(let text): return AccessibilityLabel.item(name: name, status: text)
        }
    }

    public func redacted() -> ScriptSideItemModel {
        var copy = self
        switch content {
        case .level(let level, let target):
            copy.content = .level(level, target: target.privacyMasked)
        case .value(let value, let label, let valueIsText):
            copy.content = .value(
                valueIsText ? value.privacyMasked : value, label: label.privacyMasked, valueIsText: valueIsText)
        case .state:
            break
        }
        return copy
    }
}
