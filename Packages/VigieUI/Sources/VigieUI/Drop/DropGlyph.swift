import SwiftUI

/// A drop zone glyph: the tray (`drop.stash`), AirDrop waves (`drop.airdrop`) and the image-with-T
/// (`drop.image-to-text`) drawn from the DESIGN mock on a 16-unit grid; any other name is an SF Symbol.
struct DropGlyph: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            switch name {
            case "drop.stash":
                TrayShape().stroke(style: StrokeStyle(lineWidth: size * 1.2 / 16, lineJoin: .round))
            case "drop.airdrop":
                ZStack {
                    AirDropDot().fill()
                    AirDropWaves().stroke(style: StrokeStyle(lineWidth: size * 1.2 / 16, lineCap: .round))
                }
            case "drop.image-to-text":
                ZStack {
                    PictureFrame().stroke(lineWidth: size * 1.2 / 16)
                    TextMark().stroke(style: StrokeStyle(lineWidth: size * 1.3 / 16, lineCap: .round))
                }
            default:
                Image(systemName: name).resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Maps a 16-unit mock coordinate into `rect`.
private func unit(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + x * rect.width / 16, y: rect.minY + y * rect.height / 16)
}

private struct TrayShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: unit(2, 9, in: rect))
        p.addLine(to: unit(4.4, 3.5, in: rect))
        p.addLine(to: unit(11.6, 3.5, in: rect))
        p.addLine(to: unit(14, 9, in: rect))
        p.addLine(to: unit(14, 13, in: rect))
        p.addLine(to: unit(2, 13, in: rect))
        p.closeSubpath()
        p.move(to: unit(2, 9, in: rect))
        p.addLine(to: unit(5.6, 9, in: rect))
        p.addLine(to: unit(6.6, 10.6, in: rect))
        p.addLine(to: unit(9.4, 10.6, in: rect))
        p.addLine(to: unit(10.4, 9, in: rect))
        p.addLine(to: unit(14, 9, in: rect))
        return p
    }
}

private struct AirDropDot: Shape {
    func path(in rect: CGRect) -> Path {
        let c = unit(8, 9.5, in: rect)
        let r = 1.4 * rect.width / 16
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
}

/// Two open arcs over the dot (radius 3.6 and 6.2), open at the bottom.
private struct AirDropWaves: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (radius, start, end) in [(3.6, 142.0, 398.0), (6.2, 138.0, 402.0)] {
            let steps = 48
            for step in 0...steps {
                let degrees = start + (end - start) * Double(step) / Double(steps)
                let angle = degrees * .pi / 180
                let point = unit(8 + radius * cos(angle), 9.5 + radius * sin(angle), in: rect)
                if step == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
        }
        return p
    }
}

private struct PictureFrame: Shape {
    func path(in rect: CGRect) -> Path {
        let origin = unit(1.8, 2.8, in: rect)
        let s = rect.width / 16
        return Path(
            roundedRect: CGRect(x: origin.x, y: origin.y, width: 12.4 * s, height: 10.4 * s), cornerRadius: 1.6 * s)
    }
}

private struct TextMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: unit(5.2, 6, in: rect))
        p.addLine(to: unit(10.8, 6, in: rect))
        p.move(to: unit(8, 6, in: rect))
        p.addLine(to: unit(8, 10.6, in: rect))
        return p
    }
}

/// The plus inside the round Ask AI target.
struct PlusMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let arm = rect.width * 0.28
        p.move(to: CGPoint(x: rect.midX - arm, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX + arm, y: rect.midY))
        p.move(to: CGPoint(x: rect.midX, y: rect.midY - arm))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.midY + arm))
        return p
    }
}
