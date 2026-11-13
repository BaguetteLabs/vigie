import AppKit
import ModuleKit
import SwiftUI
import Testing

@testable import VigieUI

/// Story 15.3: the floating panel frame and the Privacy-mode text editor.
@MainActor @Suite struct FloatingPanelFrameTests {
    let dark = PreviewThemes.theme(.dark)

    @Test func notesPanelTokens() {
        #expect(dark.notesPanelSize == CGSize(width: 460, height: 372))
        #expect(dark.radius(.notesPanel) == 16)
        #expect(dark.floatingPanelTopGap == dark.spacing(.gridPaddingX))
    }

    @Test func theFrameRendersInEveryVariant() {
        for theme in [dark, PreviewThemes.theme(.light), PreviewThemes.theme(.dark, variant: "twin-metal-tactical")] {
            let view = FloatingPanelFrame { Text(verbatim: "x") }
                .frame(width: theme.notesPanelSize.width, height: theme.notesPanelSize.height)
                .vigieTheme(theme)
            #expect(ImageRenderer(content: view).nsImage != nil)
        }
    }

    @Test func lineMaskKeepsLineCountNotLength() {
        #expect(PrivacyLineMask.masked("") == "")
        #expect(PrivacyLineMask.masked("a") == PrivacyMask.text)
        #expect(
            PrivacyLineMask.masked("a very long line indeed\n  \nb") == "\(PrivacyMask.text)\n\n\(PrivacyMask.text)")
    }

    @Test func typingStillEditsWhileMasked() throws {
        final class Box { var text = "secret line" }
        let box = Box()
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let view = SensitiveTextEditor(text: binding).privacyActive(true).vigieTheme(dark)
        let (window, hosting) = hostOffscreen(view, size: CGSize(width: 300, height: 200))
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        let textView = try #require(Self.find(NSTextView.self, in: hosting))
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        textView.insertText("!", replacementRange: textView.selectedRange())
        #expect(box.text == "secret line!")
    }

    static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews { if let match = find(type, in: sub) { return match } }
        return nil
    }
}
