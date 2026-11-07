import Foundation
import SwiftUI
import Testing

@testable import VigieUI

/// Story 2.15: the accessibility floor (FR-63, UX-DR13, UX-DR63–66, UX-DR94–96).
@Suite struct AccessibilityResolutionTests {
    let library = Fixtures.library

    func theme(
        _ look: Look, _ flags: AccessibilityAdjustments = .none, overrides: ColorOverrides = .none,
        variant: String = ThemeLibrary.defaultVariantID
    ) -> Theme {
        library.resolve(themeID: variant, look: look, overrides: overrides, accessibility: flags).theme
    }

    @Test func defaultRulesAreOff() {
        let rules = theme(.dark).a11y
        #expect(!rules.flatSurfaces)
        #expect(!rules.solidHairlines)
        #expect(!rules.fullStrengthAccentBorders)
        #expect(rules.focusRingWidth == 1)
        #expect(rules.haloEnabled)
        #expect(rules.minTrackOpacity == 0)
        #expect(rules.motionEnabled)
        #expect(rules.drainStyle == .animated)
    }

    @Test(arguments: Look.allCases)
    func increaseContrastAppliesTheDesignTable(look: Look) {
        let t = theme(look, AccessibilityAdjustments(increaseContrast: true))
        let rules = t.a11y
        #expect(rules.solidHairlines)
        #expect(rules.fullStrengthAccentBorders)
        #expect(rules.focusRingWidth == 2)
        #expect(!rules.haloEnabled)
        #expect(rules.minTrackOpacity == 0.40)
        #expect(rules.flatSurfaces)
        #expect(rules.hairlineWidth == 1)
        #expect(rules.motionEnabled)
        // Hairline / border role → solid ink-3.
        #expect(t.borderColor(.ink1, opacity: 0.06) == t.color(.ink3))
        #expect(t.borderColor(.structure, opacity: 0.3) == t.color(.ink3))
        // Tracks: ink-3 at ≥ 40 %.
        #expect(t.trackColor() == t.color(.ink3).opacity(0.40))
        #expect(t.trackColor(.ink3, opacity: 0.6) == t.color(.ink3).opacity(0.6))
        // Ask AI dashed border at 100 %.
        #expect(t.accentBorderColor(.iris2, opacity: 0.35) == t.color(.iris2).opacity(1))
        // Flat fills.
        let gradient = LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
        _ = t.glassFill(gradient, flat: .surfaceCard)
    }

    @Test func defaultBordersKeepTheirAlpha() {
        let t = theme(.dark)
        #expect(t.borderColor(.ink1, opacity: 0.06) == t.color(.ink1).opacity(0.06))
        #expect(t.trackColor() == t.color(.line).opacity(1))
        #expect(t.accentBorderColor(.iris2, opacity: 0.35) == t.color(.iris2).opacity(0.35))
    }

    @Test(arguments: Look.allCases)
    func reduceTransparencyFlattensSurfacesOnly(look: Look) {
        let t = theme(look, AccessibilityAdjustments(reduceTransparency: true))
        #expect(t.a11y.flatSurfaces)
        #expect(!t.a11y.solidHairlines)
        #expect(t.a11y.focusRingWidth == 1)
        let gradient = LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
        _ = t.glassFill(gradient, flat: .surfacePanel)
        // No color changes, and the island stays black.
        #expect(t.colors == theme(look).colors)
        #expect(t.themeColor(.island).hex == "#000000")
    }

    @Test(arguments: Look.allCases)
    func increaseContrastBringsDecorativeRolesToThreeToOne(look: Look) {
        let t = theme(look, AccessibilityAdjustments(increaseContrast: true))
        let surfaces = AccessibilityAdjustments.surfaceRoles(look).map(t.themeColor)
        for role in [ColorRole.filament1, .filament2, .filament3, .lineSilver, .line] where t.defines(role) {
            #expect(t.themeColor(role).worstContrast(against: surfaces) >= 3, "\(role)")
        }
        for role in AccessibilityAdjustments.textFloorRoles where t.defines(role) {
            #expect(t.themeColor(role).worstContrast(against: surfaces) >= 4.5, "\(role)")
        }
    }

    @Test func increaseContrastKeepsTheHueOfAUserOverrideAndRaisesItsContrast() {
        let pale = "#FFB0B0"
        let overrides = ColorOverrides(light: [.statusBlocked: pale])
        let plain = theme(.light, overrides: overrides)
        let contrast = theme(.light, AccessibilityAdjustments(increaseContrast: true), overrides: overrides)
        let before = plain.themeColor(.statusBlocked)
        let after = contrast.themeColor(.statusBlocked)
        #expect(before.hex == pale)
        #expect(abs(after.hsl.hue - before.hsl.hue) < 1)
        #expect(abs(after.hsl.saturation - before.hsl.saturation) < 0.02)
        let panel = contrast.themeColor(.surfacePanel)
        #expect(after.contrastRatio(with: panel) >= 4.5)
        #expect(after.contrastRatio(with: panel) > before.contrastRatio(with: panel))
    }

    @Test func increaseContrastNeverLowersAPassingColor() {
        let t = theme(.dark, AccessibilityAdjustments(increaseContrast: true))
        #expect(t.themeColor(.statusBlocked).hex == "#FF7B8C")
        #expect(t.themeColor(.ink1).hex == "#E8ECF2")
    }

    @Test func reduceMotionTurnsAnimationsOff() {
        let t = theme(.dark, AccessibilityAdjustments(reduceMotion: true))
        #expect(!t.a11y.motionEnabled)
        #expect(!t.loopsEnabled)
        for role in MotionRole.allCases {
            #expect(t.animation(role) == nil)
            #expect(t.loopAnimation(role) == nil)
        }
        #expect(t.animation(.peekGrow, reducedMotion: .crossFade) == .easeInOut(duration: t.motionSeconds(.exit)))
        #expect(t.a11y.drainStyle == .staticFullLine)
        // Colors are untouched by Reduce motion.
        #expect(t.colors == theme(.dark).colors)
    }

    @Test func animationReadsTheMotionToken() {
        let t = theme(.dark)
        #expect(t.animation(.enter) == .easeOut(duration: 0.28))
        #expect(t.animation(.exit, curve: .easeIn) == .easeIn(duration: 0.2))
        #expect(t.loopAnimation(.cardIris) == .linear(duration: 12).repeatForever(autoreverses: false))
        var calm = t
        calm.presence = .calm
        #expect(calm.loopAnimation(.cardIris) == nil)
        #expect(calm.animation(.enter) != nil)
    }
}

@Suite struct DrainLineTests {
    @Test func animatedFollowsTheRemainingTime() {
        #expect(DrainStyle.animated.visibleFraction(remaining: 1) == 1)
        #expect(DrainStyle.animated.visibleFraction(remaining: 0.4) == 0.4)
        #expect(DrainStyle.animated.visibleFraction(remaining: 0) == 0)
        #expect(DrainStyle.animated.visibleFraction(remaining: 2) == 1)
    }

    @Test func staticIsAFullLineThatDisappearsAtTheEnd() {
        #expect(DrainStyle.staticFullLine.visibleFraction(remaining: 1) == 1)
        #expect(DrainStyle.staticFullLine.visibleFraction(remaining: 0.01) == 1)
        #expect(DrainStyle.staticFullLine.visibleFraction(remaining: 0) == 0)
        #expect(DrainStyle.staticFullLine.visibleFraction(remaining: -1) == 0)
    }

    @Test func styleComesFromReduceMotion() {
        #expect(AccessibilityRules(.none).drainStyle == .animated)
        #expect(AccessibilityRules(AccessibilityAdjustments(reduceMotion: true)).drainStyle == .staticFullLine)
    }

    @MainActor @Test func rendersInBothStyles() {
        for flags in [AccessibilityAdjustments.none, AccessibilityAdjustments(reduceMotion: true)] {
            let theme = Fixtures.library.resolve(
                themeID: ThemeLibrary.defaultVariantID, look: .dark, accessibility: flags
            ).theme
            let view = VStack {
                DrainLine(remaining: 0.5)
                DrainLine(duration: theme.motion(.confirmReadout))
            }
            .frame(width: 200, height: 20).vigieTheme(theme)
            #expect(ImageRenderer(content: view).nsImage != nil)
        }
    }
}

@MainActor final class FakeAccessibilitySettings: AccessibilitySettingsProvider {
    var flags = AccessibilityAdjustments.none
    func currentAdjustments() -> AccessibilityAdjustments { flags }
}

@MainActor @Suite struct LiveAccessibilityTests {
    @Test func controllerReResolvesWhenEachFlagFlips() {
        let settings = FakeAccessibilitySettings()
        let controller = ThemeController(library: Fixtures.library, mode: .light, accessibilityProvider: settings)
        #expect(controller.theme.a11y == AccessibilityRules(.none))

        settings.flags.increaseContrast = true
        controller.refreshAccessibility()
        #expect(controller.theme.a11y.solidHairlines)
        #expect(controller.islandTheme.a11y.focusRingWidth == 2)
        #expect(
            controller.theme.themeColor(.ink3)
                != Fixtures.library.resolve(themeID: "chrome-hologram", look: .light).theme.themeColor(.ink3))

        settings.flags.reduceTransparency = true
        settings.flags.increaseContrast = false
        controller.refreshAccessibility()
        #expect(controller.theme.a11y.flatSurfaces && !controller.theme.a11y.solidHairlines)
        #expect(controller.islandTheme.a11y.flatSurfaces)

        settings.flags.reduceMotion = true
        controller.refreshAccessibility()
        #expect(!controller.theme.a11y.motionEnabled)
        #expect(!controller.islandTheme.a11y.motionEnabled)
        #expect(controller.theme.animation(.enter) == nil)

        settings.flags = .none
        controller.refreshAccessibility()
        #expect(controller.theme.a11y == AccessibilityRules(.none))
        #expect(controller.theme.animation(.enter) != nil)
    }

    @Test func systemNotificationTriggersReResolution() async throws {
        let settings = FakeAccessibilitySettings()
        let controller = ThemeController(library: Fixtures.library, accessibilityProvider: settings)
        controller.startObservingSystem()
        defer { controller.stopObservingSystem() }
        settings.flags.reduceMotion = true
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        for _ in 0..<100 where controller.theme.a11y.motionEnabled {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!controller.theme.a11y.motionEnabled)
    }
}

/// Color is never the only cue (FR-63, EXPERIENCE "Accessibility Floor").
@Suite struct NonColorCueTests {
    let formatter = StatusLabelFormatter(timeZone: TimeZone(identifier: "Europe/Paris")!)

    @Test func everySessionStatusHasADistinctGlyphAndLabelInBothVariants() {
        let all = SessionStatus.allCases
        #expect(Set(all.map(\.glyph)).count == all.count)
        #expect(Set(all.map(\.tacticalGlyph)).count == all.count)
        #expect(Set(all.map { formatter.label(for: $0) }).count == all.count)
        #expect(all.allSatisfy { $0.glyph != .none && $0.tacticalGlyph != .none })
    }

    @Test func glyphFollowsTheVariant() {
        let a = Fixtures.library.resolve(themeID: "chrome-hologram", look: .dark).theme
        let c = Fixtures.library.resolve(themeID: "twin-metal-tactical", look: .dark).theme
        #expect(SessionStatus.blocked.glyph(in: a) == .diamond)
        #expect(SessionStatus.blocked.glyph(in: c) == .squareInBrackets)
    }

    @Test func statusLevelsHaveDistinctShapesAndLabels() {
        let all = StatusLevel.allCases
        #expect(Set(all.map(\.glyph)).count == all.count)
        #expect(Set(all.map { formatter.label(for: $0) }).count == all.count)
        for look in Look.allCases {
            #expect(Set(all.map { StatusMarkStyle(level: $0, look: look).shape }).count == all.count)
        }
    }

    @Test func runStatusesDifferByGlyphOrLabel() {
        let all: [RunStatus] = [.running, .failedExit(3), .ok, .warn, .down]
        let cues = all.map { "\($0.glyph.rawValue)|\(formatter.label(for: $0))" }
        #expect(Set(cues).count == all.count)
        #expect(Set(all.map { formatter.label(for: $0) }).count == all.count)
        #expect(all.allSatisfy { $0.glyph != .none })
    }

    @Test func paceAndQuotaStatesHaveANonColorCue() {
        #expect(Set(PaceState.allCases.map(\.cue)).count == PaceState.allCases.count)
        #expect(PaceState.ahead.cue.label == "AHEAD OF PACE")
        #expect(Set(QuotaState.allCases.map(\.cue)).count == QuotaState.allCases.count)
        let warning = QuotaState.warning.cue
        #expect(warning.glyph == .hatch && warning.secondaryGlyph == .triangle && warning.label == "WARN")
    }
}

/// The CI contrast table (`contrastcheck`), run against the bundled themes.
@Suite struct ContrastAuditTests {
    @Test func wcagMath() {
        let black = ThemeColor(hex: "#000000")!
        let white = ThemeColor(hex: "#FFFFFF")!
        #expect(abs(black.contrastRatio(with: white) - 21) < 0.001)
        #expect(black.contrastRatio(with: black) == 1)
        let grey = white.composited(opacity: 0.5, over: black)
        #expect(abs(grey.red - 0.5) < 0.001)
        // DESIGN Contrast table: A light ink-3 on panel 5.3.
        #expect(abs(ThemeColor(hex: "#5D6676")!.contrastRatio(with: ThemeColor(hex: "#F3F5F9")!) - 5.30) < 0.01)
    }

    @Test func noEnforcedPairFails() {
        let results = ContrastAudit.evaluate(library: Fixtures.library)
        let failures = results.filter { $0.status == .fail }
        #expect(failures.isEmpty, "\(ContrastAudit.report(failures))")
        #expect(results.count == ContrastAudit.pairs.count)
    }

    @Test func tableCoversTheDesignPairs() {
        let pairs = ContrastAudit.pairs
        func has(_ look: Look, _ fg: ColorRole, _ surface: ColorRole, _ kind: ContrastPair.Kind = .text) -> Bool {
            pairs.contains {
                $0.variant == "chrome-hologram" && $0.look == look && $0.foreground == fg && $0.surface == surface
                    && $0.kind == kind && $0.tint == nil && !$0.increaseContrast
            }
        }
        for surface in [ColorRole.surfacePanel, .surfaceCard, .surfaceVNTop, .surfaceVNBottom] {
            #expect(has(.light, .quotaWarningText, surface))
            #expect(has(.light, .statusIdle, surface))
            #expect(has(.light, .statusDone, surface))
            for ink in [ColorRole.ink1, .ink2, .ink3] { #expect(has(.light, ink, surface)) }
        }
        for surface in [ColorRole.surfacePanel, .surfaceCard, .island] {
            for ink in [ColorRole.ink1, .ink2, .ink3] { #expect(has(.dark, ink, surface)) }
        }
        #expect(has(.light, .iris1, .line, .nonText))
        #expect(pairs.allSatisfy { !$0.source.isEmpty })
    }

    @Test func shippedLightTokensMatchUXDR94() {
        let light = Fixtures.library.resolve(themeID: "chrome-hologram", look: .light).theme
        #expect(light.themeColor(.quotaWarningText).hex == "#7E6300")
        #expect(light.themeColor(.quotaWarning).hex == "#8A6D00")
        #expect(light.themeColor(.statusIdle).hex == "#0B7651")
        #expect(light.themeColor(.statusDone).hex == "#1A68B5")
    }

    @Test func aFailingTokenIsReported() {
        var library = Fixtures.library
        library.builtIns["chrome-hologram"]?.looks["light"]?.colors["ink-3"] = "#B0B0B0"
        let results = ContrastAudit.evaluate(library: library)
        let failures = results.filter { $0.status == .fail }
        #expect(failures.contains { $0.pair.foreground == .ink3 && $0.pair.look == .light })
        #expect(ContrastAudit.report(failures).contains("FAIL"))
    }

    @Test func exceptionsAreAllowedNotFailed() {
        let results = ContrastAudit.evaluate(library: Fixtures.library)
        let allowed = results.filter { $0.status == .allowed }
        #expect(!allowed.isEmpty)
        #expect(allowed.allSatisfy { $0.pair.exception != nil })
    }
}
