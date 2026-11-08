import AppKit
import CoreGraphics
import Foundation

/// Deterministic Image to Text fixtures drawn in the test: black text on white, 64pt, one line per row.
enum TextFixtures {
    static let lines = ["Hello world", "Second line here", "Third row of text"]
    static let lineHeight: CGFloat = 110

    static func size(_ count: Int) -> CGSize { CGSize(width: 1100, height: CGFloat(count) * lineHeight + 80) }

    /// Draws `lines` top to bottom into `context` (bottom-left origin) of `size`.
    static func draw(_ lines: [String], in context: CGContext, size: CGSize) {
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 64, weight: .medium), .foregroundColor: NSColor.black,
        ]
        for (index, line) in lines.enumerated() {
            let y = size.height - 40 - CGFloat(index + 1) * lineHeight + 20
            NSAttributedString(string: line, attributes: attributes).draw(at: CGPoint(x: 40, y: y))
        }
        NSGraphicsContext.current = previous
    }

    static func image(_ lines: [String] = lines) -> CGImage {
        let size = size(max(lines.count, 1))
        let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(lines, in: context, size: size)
        return context.makeImage()!
    }

    static func pngData(_ lines: [String] = lines) -> Data {
        NSBitmapImageRep(cgImage: image(lines)).representation(using: .png, properties: [:])!
    }

    static func png(_ lines: [String] = lines, name: String = "shot.png", in folder: URL = makeTempDirectory()) -> URL {
        let url = folder.appendingPathComponent(name)
        try! pngData(lines).write(to: url)
        return url
    }

    /// A one-page PDF whose text is embedded (selectable).
    static func textPDF(_ lines: [String] = lines) -> URL {
        let url = makeTempDirectory().appendingPathComponent("embedded.pdf")
        var box = CGRect(origin: .zero, size: size(lines.count))
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        draw(lines, in: context, size: box.size)
        context.endPDFPage()
        context.closePDF()
        return url
    }

    /// A one-page PDF holding only a picture of the text (a scan): no embedded text.
    static func scannedPDF(_ lines: [String] = lines) -> URL {
        let url = makeTempDirectory().appendingPathComponent("scan.pdf")
        let picture = image(lines)
        var box = CGRect(origin: .zero, size: CGSize(width: picture.width / 2, height: picture.height / 2))
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        context.draw(picture, in: box)
        context.endPDFPage()
        context.closePDF()
        return url
    }
}
