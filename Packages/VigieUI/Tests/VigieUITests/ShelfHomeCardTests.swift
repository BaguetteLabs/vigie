import AppKit
import ModuleKit
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import VigieUI

/// Story 11.3: the Home shelf widget view.
@MainActor @Suite struct ShelfHomeCardTests {
    static func stashTarget() -> SendToTarget {
        let zone = DropZone(
            id: "shelf.stash", label: "Stash", glyph: "drop.stash", accentToken: "iris-2", role: .primary,
            cell: DropCell(preferredColumn: 1, preferredRow: 1, span: .init(columns: 2, rows: 2)), order: 0,
            accepts: [], handler: { _ in .accepted }, meta: "KEEP 7 DAYS · 0 ITEMS", releaseLine: "RELEASE TO STASH")
        return SendToTarget(summary: DropZoneSummary(zone, moduleID: "shelf"))
    }

    static let askTarget = SendToTarget(summary: SendToCardTests.askSummary())

    /// The mockup's rows, the expiring one first with its tag.
    static func items(_ count: Int) -> [ShelfHomeItem] {
        let expiring = ShelfHomeItem(row: ShelfTabTests.rows[3], tag: "5H")
        let others = (ShelfTabTests.rows.filter { $0.id != ShelfTabTests.ids[3] } + extraRows).map {
            ShelfHomeItem(row: $0)
        }
        return Array(([expiring] + others).prefix(count))
    }

    static let extraRows: [ShelfRowModel] = (0..<6).map { index in
        ShelfRowModel(
            id: UUID(), name: "capture-\(index).png", kind: "PNG", sizeMode: "40 KB · REF", sourceApp: nil,
            addedTime: "08:0\(index)", addedDay: "TODAY", expiry: .timeLeft("6D LEFT", fraction: 0.9),
            accessibilityLabel: "capture-\(index).png")
    }

    static func model(_ count: Int, ask: Bool = true) -> ShelfHomeCardModel {
        let items = items(count)
        return ShelfHomeCardModel(
            title: "Shelf", meta: "\(count) items", items: items,
            warning: items.contains(where: \.isExpiring) ? "1 EXPIRES IN 5H" : nil, stashZone: stashTarget(),
            askZone: ask ? askTarget : nil)
    }

    /// AC 1: the list and both zones, Stash first.
    @Test func modelShowsTheListAndBothZones() {
        let model = Self.model(3)
        #expect(model.targets.map(\.id) == ["shelf.stash", "agents.sessions.ask"])
        #expect(model.target("agents.sessions.ask")?.zone.style == .target)
        #expect(model.items.count == 3)
        let view = ShelfHomeCardView(model: { model })
        #expect(view.modelValue().items.map(\.id) == model.items.map(\.id))
        #expect(Self.model(2, ask: false).targets.map(\.id) == ["shelf.stash"])
    }

    /// AC 2: the expiring item is first with its tag; the warning line is set.
    @Test func expiringItemFirstWithTagAndWarning() {
        let model = Self.model(4)
        #expect(model.items.first?.tag == "5H" && model.items.first?.isExpiring == true)
        #expect(model.items.dropFirst().allSatisfy { $0.tag == nil })
        #expect(model.warning == "1 EXPIRES IN 5H")
        #expect(Self.model(4).items.first?.row.name == "mock-usage-tab.png")
    }

    /// AC 3 (gating): a Finder file goes to either zone; a stash item from the list goes to Ask AI but never
    /// back onto the Stash.
    @Test func dropGatingAndHover() {
        let stash = Self.stashTarget()
        let ask = Self.askTarget
        #expect(ShelfHomeCardModel.accepts(stash, contentTypes: [.data], isStashItem: false))
        #expect(ShelfHomeCardModel.accepts(ask, contentTypes: [.data], isStashItem: false))
        #expect(!ShelfHomeCardModel.accepts(stash, contentTypes: [.plainText], isStashItem: true))
        #expect(ShelfHomeCardModel.accepts(ask, contentTypes: [.plainText], isStashItem: true))
        let hover = ShelfHomeHover(zoneID: stash.id, accepts: true)
        #expect(hover.phase(of: stash.id) == .hovered && hover.phase(of: ask.id) == .idle)
        #expect(ShelfHomeHover(zoneID: stash.id, accepts: false).phase(of: stash.id) == .disabled)
        #expect(ShelfHomeHover(optionHeld: true).modifiers == .option)
    }

    /// AC 3 (wiring): what the drop closure receives reaches the module unchanged.
    @Test func actionsCarryTheDrop() {
        var received: [(String, SendToDrop, EventModifiers)] = []
        let actions = ShelfHomeCardActions(drop: { received.append(($0, $1, $2)) })
        let file = URL(fileURLWithPath: "/tmp/a.txt")
        actions.drop("shelf.stash", .files([file]), .option)
        #expect(received.count == 1 && received[0].0 == "shelf.stash" && received[0].1 == .files([file]))
    }

    /// AC 4: rows that do not fit fade under the bottom mask; no scrolling.
    @Test func overflowTurnsTheMaskOn() {
        let row = ShelfHomeCardMetrics.rowHeight
        #expect(!ShelfHomeCardMetrics.overflows(count: 2, height: 2 * row))
        #expect(ShelfHomeCardMetrics.overflows(count: 3, height: 2 * row + 4))
        #expect(!ShelfHomeCardMetrics.overflows(count: 0, height: 0))
    }

    @Test func privacyMasksTheNames() {
        let masked = Self.model(2).privacy(true)
        #expect(masked.items.allSatisfy { $0.row.name == PrivacyMask.text })
        #expect(masked.items.first?.tag == "5H")
        #expect(Self.model(2).privacy(false).items.first?.row.name == "mock-usage-tab.png")
    }

    enum State: String, CaseIterable { case empty, two, overflow, noAsk, hoverStash, refusedStash, hoverAsk }

    static func card(_ state: State) -> ShelfHomeCardView {
        let model: ShelfHomeCardModel =
            switch state {
            case .empty: model(0)
            case .two: model(2)
            case .noAsk: model(2, ask: false)
            case .overflow, .hoverStash, .refusedStash, .hoverAsk: model(10)
            }
        let hover: ShelfHomeHover =
            switch state {
            case .hoverStash: ShelfHomeHover(zoneID: "shelf.stash", accepts: true)
            case .refusedStash: ShelfHomeHover(zoneID: "shelf.stash", accepts: false)
            case .hoverAsk: ShelfHomeHover(zoneID: "agents.sessions.ask", accepts: true)
            default: ShelfHomeHover()
            }
        var card = ShelfHomeCardView(hover: hover, model: { model })
        card.interactive = false
        return card
    }

    /// AC 4 and rendering: every state keeps the fixed 222 × 138 cell (an overflowing list included), in A and
    /// C, dark and light. Set `VIGIE_HOME_RENDER_DIR` to keep the PNGs.
    @Test(arguments: [
        (Look.dark, ThemeLibrary.defaultVariantID), (.light, ThemeLibrary.defaultVariantID),
        (.dark, "twin-metal-tactical"), (.light, "twin-metal-tactical"),
    ])
    func rendersInsideTheCell(look: Look, variant: String) throws {
        let theme = SessionsTabTests.theme(look, variant: variant)
        let size = HomeMetrics.cardSize(theme)
        #expect(size == CGSize(width: 222, height: 138))
        for state in State.allCases {
            let view = Self.card(state)
                .frame(width: size.width, height: size.height)
                .padding(20)
                .background(theme.color(.surfacePanel))
                .vigieTheme(theme)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: size.width + 40, height: size.height + 40)
            hosting.layoutSubtreeIfNeeded()
            #expect(hosting.fittingSize.height <= size.height + 40 + 0.5, "\(state) grew the card")
            #expect(hosting.fittingSize.width <= size.width + 40 + 0.5, "\(state) grew the card")
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            #expect(image.width == Int((size.width + 40) * 2) && image.height == Int((size.height + 40) * 2))
            #expect(SessionGlyphTests.inkedPixels(image) > 1000)
            if let dir = ProcessInfo.processInfo.environment["VIGIE_HOME_RENDER_DIR"] {
                let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(
                    to: URL(fileURLWithPath: dir).appendingPathComponent(
                        "shelf-card-\(variant)-\(look.rawValue)-\(state.rawValue).png"))
            }
        }
    }

    /// AC 4: the mask is opaque at the top and fades to clear at the bottom when on; fully opaque when off.
    @Test func bottomMaskFadesOnlyWhenOn() throws {
        func alphas(_ isOn: Bool) throws -> (top: UInt8, bottom: UInt8) {
            let view = Rectangle().fill(Color.white).mask { ShelfHomeFadeMask(isOn: isOn) }
                .frame(width: 20, height: 60)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try #require(
                CGContext(
                    data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let column = image.width / 2
            return (
                pixels[(2 * image.width + column) * 4 + 3], pixels[((image.height - 1) * image.width + column) * 4 + 3]
            )
        }
        let on = try alphas(true)
        let off = try alphas(false)
        #expect(on.top == 255 && on.bottom < 40, "faded under the bottom mask")
        #expect(off.top == 255 && off.bottom == 255)
    }
}
