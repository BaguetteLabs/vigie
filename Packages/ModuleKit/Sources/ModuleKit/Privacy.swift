import Foundation

// Privacy mode marking (AD-24, Story 21.2). Every user-supplied field shown on a surface is declared
// sensitive; while Privacy mode is active the host and VigieUI render it as ``PrivacyMask/text``. There is no
// way to mark a field as not sensitive: user text is sensitive by default and modules cannot opt out.
//
// `Sensitive` lives here, below VigieUI, because `NotifierEvent` (ModuleKit) carries the same marking as the
// VigieUI view models. VigieUI adds the rendering: `.sensitive()`, the dots mask and the `privacyActive`
// environment value.

/// Marks a view-model or event field as user text that Privacy mode hides (AD-24). Reading the property gives
/// the raw value; `$field` gives the marker, whose ``masked`` value is what a surface shows while Privacy mode
/// is active.
@propertyWrapper
public struct Sensitive<Value> {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    public var projectedValue: Sensitive<Value> { self }
}

extension Sensitive: Sendable where Value: Sendable {}
extension Sensitive: Equatable where Value: Equatable {}
extension Sensitive: Hashable where Value: Hashable {}

extension Sensitive where Value: PrivacyMaskable {
    /// The value Privacy mode shows: fixed-width dots for text (presence is kept, length is not).
    public var masked: Value { wrappedValue.privacyMasked }

    /// The raw value, or ``masked`` while `privacyActive`.
    public func value(privacyActive: Bool) -> Value { privacyActive ? masked : wrappedValue }
}

/// A value Privacy mode can replace with a placeholder.
public protocol PrivacyMaskable {
    /// The placeholder shown while Privacy mode is active.
    var privacyMasked: Self { get }
}

extension String: PrivacyMaskable {
    /// ``PrivacyMask/text``, whatever the length (the empty string too, so nothing is given away).
    public var privacyMasked: String { PrivacyMask.text }
}

extension Optional: PrivacyMaskable where Wrapped: PrivacyMaskable {
    /// nil stays nil (the field's absence is not user text); a value becomes its mask.
    public var privacyMasked: Wrapped? { map(\.privacyMasked) }
}

/// The Privacy mode placeholder (UX-DR98, DESIGN "Secret mask"): fixed-width dots, so the length is not given
/// away.
public enum PrivacyMask {
    /// Dots per hidden field, whatever its length.
    public static let glyphCount = 6
    /// `••••••`.
    public static let text = String(repeating: "\u{2022}", count: glyphCount)

    /// `text` with each non-empty `sensitive` value replaced by ``text`` (longest first, so a value that
    /// contains another is replaced whole). For composed strings such as VoiceOver labels ("vigie, blocked,
    /// 12 minutes") built from sensitive fields.
    public static func scrub(_ text: String, removing sensitive: [String?]) -> String {
        let values = Set(sensitive.compactMap { $0 }.filter { !$0.isEmpty }).sorted { $0.count > $1.count }
        return values.reduce(text) { $0.replacingOccurrences(of: $1, with: Self.text) }
    }
}

/// A sensitive field persists as its bare value (Story 20.2: Time item labels in the module's state file);
/// the marking is a rendering rule, not part of the stored data.
extension Sensitive: Codable where Value: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(wrappedValue: try decoder.singleValueContainer().decode(Value.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}
