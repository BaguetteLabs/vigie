import Foundation

/// One foreground/surface pair the contrast check measures (UX-DR13, UX-DR94, Story 2.15). Every pair cites
/// the DESIGN.md row it comes from (`docs/ux-designs/ux-vigie-2026-11-04/DESIGN.md`, Colors › Contrast and
/// the "Further surfaces" table, Components › Increase contrast).
public struct ContrastPair: Sendable, Equatable, CustomStringConvertible {
    public enum Kind: String, Sendable, Equatable {
        /// Text: at least 4.5:1 (WCAG 1.4.3).
        case text
        /// Non-text UI that carries meaning: at least 3:1 (WCAG 1.4.11).
        case nonText = "non-text"
    }

    public var variant: String
    public var look: Look
    /// Measured on the theme resolved with macOS Increase contrast on.
    public var increaseContrast: Bool
    public var foreground: ColorRole
    /// Foreground alpha, composited over the (tinted) surface: e.g. the selection ring at 55 %.
    public var foregroundOpacity: Double
    public var surface: ColorRole
    /// An alert tint laid over the surface first (10 % blocked / failed row fade).
    public var tint: ColorRole?
    public var tintOpacity: Double
    public var kind: Kind
    /// The DESIGN row this pair comes from.
    public var source: String
    /// The ratio DESIGN states for this pair, when it states one (reported, not enforced).
    public var designClaim: Double?
    /// Set for a pair DESIGN itself says fails and restricts (e.g. `c-light-gold` is never text): the check
    /// reports it but never fails on it. The string is the DESIGN citation.
    public var exception: String?

    public init(
        variant: String, look: Look, increaseContrast: Bool = false, foreground: ColorRole,
        foregroundOpacity: Double = 1, surface: ColorRole, tint: ColorRole? = nil, tintOpacity: Double = 0,
        kind: Kind, source: String, designClaim: Double? = nil, exception: String? = nil
    ) {
        self.variant = variant
        self.look = look
        self.increaseContrast = increaseContrast
        self.foreground = foreground
        self.foregroundOpacity = foregroundOpacity
        self.surface = surface
        self.tint = tint
        self.tintOpacity = tintOpacity
        self.kind = kind
        self.source = source
        self.designClaim = designClaim
        self.exception = exception
    }

    public var minimum: Double { kind == .text ? 4.5 : 3 }

    /// `a-light ink-3 on surface-vn-bottom` style name.
    public var description: String {
        let prefix = variant == ThemeLibrary.defaultVariantID ? "a" : "c"
        var name = "\(prefix)-\(look.rawValue) \(foreground.rawValue)"
        if foregroundOpacity < 1 { name += " @\(Int((foregroundOpacity * 100).rounded()))%" }
        name += " on \(surface.rawValue)"
        if let tint { name += " + \(Int((tintOpacity * 100).rounded()))% \(tint.rawValue) tint" }
        if increaseContrast { name += " [increase contrast]" }
        return name
    }
}

/// The outcome of measuring one pair.
public struct ContrastResult: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case pass
        /// Below the minimum on a pair DESIGN claims passes: fails the build (Chrome Hologram).
        case fail
        /// Below the minimum on a DESIGN-acknowledged exception: reported only.
        case allowed
        /// Below the minimum in Twin Metal Tactical: reported only until Story 18.1.
        case advisory
    }

    public var pair: ContrastPair
    public var ratio: Double
    public var status: Status
}

/// The CI contrast check (`Scripts/check-contrast.sh` → `contrastcheck`) and its unit test share this table.
public enum ContrastAudit {
    /// Variants whose failures fail the build. Twin Metal Tactical is reported but non-fatal until Story 18.1.
    public static let enforcedVariants: Set<String> = [ThemeLibrary.defaultVariantID]
    static let tactical = "twin-metal-tactical"

    // MARK: Pair table

    /// Every checked pair. Text roles are checked on every surface of the look they are used on (panel,
    /// card, and the island in dark looks / the virtual notch in light looks): DESIGN Contrast rule "Every
    /// text color, status label included, reaches at least 4.5:1 on its surface". A text pass at 4.5:1 also
    /// covers the same hue as a glyph (3:1), so status glyphs are not listed twice.
    public static let pairs: [ContrastPair] = chromeHologram + twinMetal

    static func surfaces(_ look: Look) -> [ColorRole] {
        look == .dark
            ? [.surfacePanel, .surfaceCard, .island]
            : [.surfacePanel, .surfaceCard, .surfaceVNTop, .surfaceVNBottom]
    }

    static let statusRoles: [ColorRole] = [.statusIdle, .statusWorking, .statusDone, .statusBlocked, .statusFailed]

    static func text(
        _ variant: String, _ look: Look, _ roles: [ColorRole], source: String, claims: [String: Double] = [:]
    ) -> [ContrastPair] {
        roles.flatMap { role in
            surfaces(look).map { surface in
                ContrastPair(
                    variant: variant, look: look, foreground: role, surface: surface, kind: .text, source: source,
                    designClaim: claims["\(role.rawValue)/\(surface.rawValue)"])
            }
        }
    }

    // DESIGN "Shared roles" table + "Contrast" table rows A dark / A light; "Further surfaces" table.
    static let chromeHologram: [ContrastPair] = {
        let a = ThemeLibrary.defaultVariantID
        let contrastTable = "DESIGN Colors › Contrast table"
        let further = "DESIGN Colors › Contrast › Further surfaces table"
        let rule = "DESIGN Colors › Contrast rules (non-text 3:1, WCAG 1.4.11)"
        let ic =
            "DESIGN Components › Increase contrast table; Contrast rules (decorative reach 3:1 under Increase contrast)"
        var pairs: [ContrastPair] = []

        // Text.
        pairs += text(
            a, .dark, [.ink1, .ink2, .ink3] + statusRoles + [.paceAhead, .quotaWarningText],
            source: "\(contrastTable), row A dark",
            claims: [
                "ink-1/surface-panel": 16.3, "ink-2/surface-panel": 10.1, "ink-3/surface-panel": 5.1,
                "status-blocked/surface-panel": 7.8, "pace-ahead/surface-panel": 8.2,
                "quota-warning-text/surface-panel": 14.8,
            ])
        pairs += text(
            a, .dark, [.iris1, .iris2, .iris3], source: "\(further), row A dark iris",
            claims: [
                "iris-1/surface-panel": 14.97, "iris-2/surface-panel": 11.02, "iris-3/surface-panel": 13.09,
                "iris-1/surface-card": 13.51, "iris-2/surface-card": 9.94, "iris-3/surface-card": 11.81,
            ])
        pairs += text(
            a, .light, [.ink1, .ink2, .ink3, .statusWorking, .statusBlocked, .statusFailed, .paceAhead],
            source: "\(contrastTable), row A light",
            claims: [
                "ink-1/surface-panel": 15.8, "ink-2/surface-panel": 7.7, "ink-3/surface-panel": 5.3,
                "pace-ahead/surface-panel": 5.2,
            ])
        pairs += text(
            a, .light, [.statusIdle, .statusDone],
            source: "\(further), row A light status-idle #0B7651 / status-done #1A68B5 (UX-DR94)",
            claims: [
                "status-done/surface-panel": 4.9, "status-idle/surface-vn-bottom": 4.89,
                "status-done/surface-vn-bottom": 4.94,
            ])
        pairs += text(
            a, .light, [.quotaWarningText],
            source: "\(further), row quota-warning-text #7E6300 (every A light surface, UX-DR94)",
            claims: ["quota-warning-text/surface-panel": 5.24, "quota-warning-text/surface-vn-bottom": 4.96])
        pairs += text(
            a, .light, [.iris1, .iris2, .iris3], source: "\(further), row A light iris",
            claims: [
                "iris-1/surface-panel": 5.23, "iris-2/surface-panel": 5.28, "iris-3/surface-panel": 5.71,
                "iris-1/surface-card": 5.71, "iris-2/surface-card": 5.77, "iris-3/surface-card": 6.23,
                "iris-1/surface-vn-bottom": 4.95, "iris-2/surface-vn-bottom": 5.00, "iris-3/surface-vn-bottom": 5.41,
            ])

        // Status labels in their own hue on their 10 % alert tint, and the secondary line on that tint. DESIGN's
        // figures (4.74–6.67, 4.94–5.33) are the tinted session row on `surface-card`, where rows live; a
        // tinted row straight on `surface-panel` is not a DESIGN pair (A light blocked would measure 4.36).
        for look in Look.allCases {
            for status in [ColorRole.statusBlocked, .statusFailed] {
                for surface in [ColorRole.surfaceCard] {
                    pairs.append(
                        ContrastPair(
                            variant: a, look: look, foreground: status, surface: surface, tint: status,
                            tintOpacity: 0.10, kind: .text,
                            source: "\(further), row status labels on their alert tint (4.74–6.67)"))
                    pairs.append(
                        ContrastPair(
                            variant: a, look: look, foreground: look == .dark ? .ink2 : .ink3, surface: surface,
                            tint: status, tintOpacity: 0.10, kind: .text,
                            source: look == .dark
                                ? "\(further), row ink-2 on a 10% blocked/failed row tint (A dark 9.1)"
                                : "\(further), row ink-3 on a 10% blocked/failed row tint (A light 4.94–5.33)"))
                    if look == .dark {
                        pairs.append(
                            ContrastPair(
                                variant: a, look: .dark, foreground: .ink3, surface: surface, tint: status,
                                tintOpacity: 0.10, kind: .text, source: rule,
                                exception:
                                    "DESIGN Contrast rules: dark alert-tinted rows set the secondary line in ink-2, never ink-3 (3.85–4.46)"
                            ))
                    }
                }
            }
        }

        // Non-text meaning (3:1).
        for surface in [ColorRole.surfacePanel, .surfaceCard] {
            pairs.append(
                ContrastPair(
                    variant: a, look: .dark, foreground: .ink1, foregroundOpacity: 0.55, surface: surface,
                    kind: .nonText, source: "\(rule): selection ring ink-1 at 55% (A dark 5.43)",
                    designClaim: surface == .surfacePanel ? 5.43 : nil))
            pairs.append(
                ContrastPair(
                    variant: a, look: .light, foreground: .ink1, foregroundOpacity: 0.55, surface: surface,
                    kind: .nonText, source: "\(rule): selection ring (A light graphite ring)"))
            for look in Look.allCases {
                pairs.append(
                    ContrastPair(
                        variant: a, look: look, foreground: .iris1, surface: surface, kind: .nonText,
                        source: "\(rule): focus ring iris-1 (ActionButton) and Time arc"))
            }
        }
        for surface in surfaces(.light) {
            pairs.append(
                ContrastPair(
                    variant: a, look: .light, foreground: .quotaWarning, surface: surface, kind: .nonText,
                    source: "\(rule): light quota-warning fill #8A6D00 (4.03–4.51)"))
            pairs.append(
                ContrastPair(
                    variant: a, look: .light, foreground: .paceOn, surface: surface, kind: .nonText,
                    source: "DESIGN Pace and quota-warning colors: pace-on fill (A light graphite)"))
            pairs.append(
                ContrastPair(
                    variant: a, look: .light, foreground: .quotaWarning, surface: surface, kind: .text,
                    source: "DESIGN Contrast: #8A6D00 as text",
                    exception:
                        "DESIGN Contrast: warning text uses quota-warning-text #7E6300; #8A6D00 only for hatch, triangles, arcs and fills"
                ))
        }
        for surface in surfaces(.dark) {
            pairs.append(
                ContrastPair(
                    variant: a, look: .dark, foreground: .quotaWarning, surface: surface, kind: .nonText,
                    source: "\(rule): quota-warning fill, triangle, arc"))
            pairs.append(
                ContrastPair(
                    variant: a, look: .dark, foreground: .paceOn, surface: surface, kind: .nonText,
                    source: "DESIGN Pace and quota-warning colors: pace-on fill (A dark platinum)"))
        }
        pairs.append(
            ContrastPair(
                variant: a, look: .light, foreground: .iris1, surface: .line, kind: .nonText,
                source: "\(rule): A light iris-1 Time arc against the line track (3.99)", designClaim: 3.99))
        for look in Look.allCases {
            for surface in [ColorRole.surfacePanel, .surfaceCard] {
                pairs.append(
                    ContrastPair(
                        variant: a, look: look, foreground: .ink3, surface: surface, kind: .nonText,
                        source: "\(rule): stale ring and process-only dot in ink-3 (≥ 4.56)"))
            }
        }
        // Decorative-only by default (exempt): measured so the exemption stays visible.
        for surface in [ColorRole.surfacePanel, .surfaceCard] {
            for role in [ColorRole.filament1, .filament2, .filament3, .lineSilver] {
                pairs.append(
                    ContrastPair(
                        variant: a, look: .light, foreground: role, surface: surface, kind: .nonText,
                        source: "DESIGN Variant accents / Contrast rules: decorative-only",
                        designClaim: role == .filament1 && surface == .surfacePanel ? 2.65 : nil,
                        exception:
                            "DESIGN Contrast rules: decorative-only (A light filament-*, line-silver) are exempt; filament-1 is the rim only, never an arc (2.65)"
                    ))
            }
        }

        // Increase contrast (resolved with the flag on).
        for look in Look.allCases {
            for surface in [ColorRole.surfacePanel, .surfaceCard] {
                for role in [ColorRole.ink3, .iris1, .filament1, .filament2, .filament3, .lineSilver, .line] {
                    pairs.append(
                        ContrastPair(
                            variant: a, look: look, increaseContrast: true, foreground: role, surface: surface,
                            kind: .nonText, source: "\(ic): \(role == .ink3 ? "solid ink-3 borders" : "decorative")"))
                }
            }
        }
        return pairs
    }()

    // Twin Metal Tactical (non-fatal until Story 18.1).
    static let twinMetal: [ContrastPair] = {
        let c = tactical
        let contrastTable = "DESIGN Colors › Contrast table"
        let further = "DESIGN Colors › Contrast › Further surfaces table"
        let rule = "DESIGN Colors › Contrast rules (non-text 3:1)"
        var pairs: [ContrastPair] = []
        pairs += text(
            c, .dark, [.ink1, .ink2, .ink3, .goldText] + statusRoles + [.paceAhead, .quotaWarningText],
            source: "\(contrastTable), row C dark; \(further), row C dark gold-text",
            claims: [
                "ink-1/surface-panel": 17.6, "ink-2/surface-panel": 12.2, "ink-3/surface-panel": 5.2,
                "status-blocked/surface-panel": 6.0, "pace-ahead/surface-panel": 9.8,
                "quota-warning-text/surface-panel": 14.9, "gold-text/surface-panel": 13.43,
                "gold-text/surface-card": 12.83,
            ])
        pairs += text(
            c, .light, [.ink1, .ink2, .ink3, .goldText, .quotaWarningText, .paceOn] + statusRoles,
            source: "\(contrastTable), row C light; \(further), rows C light gold-text, quota-warning-text",
            claims: [
                "ink-1/surface-panel": 14.6, "ink-2/surface-panel": 8.3, "ink-3/surface-panel": 5.6,
                "status-working/surface-panel": 4.9, "quota-warning-text/surface-panel": 4.69,
                "quota-warning-text/surface-card": 5.23, "quota-warning-text/surface-vn-bottom": 4.56,
                "gold-text/surface-panel": 5.49, "gold-text/surface-card": 6.12, "gold-text/surface-vn-bottom": 5.34,
                "pace-on/surface-panel": 5.1,
            ])
        for surface in [ColorRole.surfacePanel, .surfaceCard] {
            pairs.append(
                ContrastPair(
                    variant: c, look: .light, foreground: .gold, surface: surface, kind: .nonText,
                    source: "\(rule): C light gold ring (3.44 / 3.84)",
                    designClaim: surface == .surfacePanel ? 3.44 : 3.84))
            pairs.append(
                ContrastPair(
                    variant: c, look: .light, foreground: .gold, surface: surface, kind: .text,
                    source: "DESIGN Contrast: c-light-gold as text",
                    exception:
                        "DESIGN Contrast: c-light-gold (3.4) only for frames, arcs, markers, fills; text uses gold-text"
                ))
            pairs.append(
                ContrastPair(
                    variant: c, look: .light, foreground: .paceAhead, surface: surface, kind: .text,
                    source: "DESIGN Contrast table, row C light pace-ahead",
                    exception: "DESIGN Contrast table: C light pace-ahead 3.4 is fill only"))
            pairs.append(
                ContrastPair(
                    variant: c, look: .light, foreground: .paceAhead, surface: surface, kind: .nonText,
                    source: "DESIGN Contrast table, row C light pace-ahead (fill)"))
            for look in Look.allCases {
                pairs.append(
                    ContrastPair(
                        variant: c, look: look, foreground: .ink1, foregroundOpacity: 0.55, surface: surface,
                        kind: .nonText, source: "\(rule): selection ring ink-1 at 55% (C dark 5.76 / C light 3.75)",
                        designClaim: surface == .surfacePanel ? (look == .dark ? 5.76 : 3.75) : nil))
            }
            pairs.append(
                ContrastPair(
                    variant: c, look: .light, foreground: .quotaWarning, surface: surface, kind: .nonText,
                    source: "DESIGN Contrast table, row C light quota-warning fill 4.0 (non-text)"))
        }
        return pairs
    }()

    // MARK: Evaluation

    /// Resolves each (variant, look, increase-contrast) once and measures every pair.
    public static func evaluate(library: ThemeLibrary, pairs: [ContrastPair] = pairs) -> [ContrastResult] {
        struct Key: Hashable {
            let variant: String
            let look: Look
            let increaseContrast: Bool
        }
        var themes: [Key: Theme] = [:]
        return pairs.map { pair in
            let key = Key(variant: pair.variant, look: pair.look, increaseContrast: pair.increaseContrast)
            let theme =
                themes[key]
                ?? library.resolve(
                    themeID: pair.variant, look: pair.look,
                    accessibility: AccessibilityAdjustments(increaseContrast: pair.increaseContrast)
                ).theme
            themes[key] = theme
            let ratio = measure(pair, in: theme)
            let status: ContrastResult.Status
            if ratio >= pair.minimum {
                status = .pass
            } else if pair.exception != nil {
                status = .allowed
            } else if !enforcedVariants.contains(pair.variant) {
                status = .advisory
            } else {
                status = .fail
            }
            return ContrastResult(pair: pair, ratio: ratio, status: status)
        }
    }

    /// The pair's ratio in a resolved theme: tint composited on the surface, then the foreground on that.
    public static func measure(_ pair: ContrastPair, in theme: Theme) -> Double {
        var background = theme.themeColor(pair.surface)
        if let tint = pair.tint {
            background = theme.themeColor(tint).composited(opacity: pair.tintOpacity, over: background)
        }
        let foreground = theme.themeColor(pair.foreground).composited(opacity: pair.foregroundOpacity, over: background)
        return foreground.contrastRatio(with: background)
    }

    /// A plain-text report: one line per pair, failures first, then a summary.
    public static func report(_ results: [ContrastResult], verbose: Bool = true) -> String {
        func line(_ r: ContrastResult) -> String {
            var s = String(
                format: "%-8@ %6.2f:1 (min %.1f) %@", r.status.rawValue.uppercased(), r.ratio, r.pair.minimum,
                r.pair.description)
            if let claim = r.pair.designClaim { s += String(format: "  [DESIGN %.2f]", claim) }
            if let exception = r.pair.exception, r.status == .allowed { s += "  — \(exception)" }
            s += "  ← \(r.pair.source)"
            return s
        }
        let order: [ContrastResult.Status] = [.fail, .advisory, .allowed, .pass]
        var lines: [String] = []
        for status in order {
            let group = results.filter { $0.status == status }
            if status == .pass && !verbose { continue }
            lines += group.map(line)
        }
        let counts = order.map { status in "\(results.filter { $0.status == status }.count) \(status.rawValue)" }
        lines.append("contrast: \(results.count) pairs — " + counts.joined(separator: ", "))
        return lines.joined(separator: "\n")
    }

    /// Pairs whose ratio is more than `tolerance` away from the value DESIGN states (doc drift, reported).
    public static func claimDrift(_ results: [ContrastResult], tolerance: Double = 0.1) -> [ContrastResult] {
        results.filter { r in r.pair.designClaim.map { abs($0 - r.ratio) > tolerance } ?? false }
    }
}
