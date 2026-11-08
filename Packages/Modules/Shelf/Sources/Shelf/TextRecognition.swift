import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// What Image to Text reads: an image or PDF file, or dragged image bytes (Story 9.9).
public enum TextSource: Sendable, Equatable {
    case file(URL)
    case imageData(Data)
}

/// Recognizes the text of an image or PDF, on the Mac (NFR7: no network). Called off the main actor.
public protocol TextRecognizing: Sendable {
    /// The text lines in reading order (top to bottom, then left to right); empty when there is none.
    func lines(in source: TextSource) throws -> [String]
}

public enum TextRecognitionError: Error, Equatable {
    /// The file or bytes are not a readable image or PDF.
    case unreadable
}

/// On-device Vision text recognition (`VNRecognizeTextRequest`, `.accurate`, language correction on) and PDFKit:
/// a PDF's embedded text when it has any, else each page rendered at 144 dpi and recognized.
public struct VisionTextRecognizer: TextRecognizing {
    /// PDF pages are rendered at 2 × 72 dpi.
    public static let pdfScale: CGFloat = 2

    public init() {}

    public func lines(in source: TextSource) throws -> [String] {
        switch source {
        case .imageData(let data):
            guard let image = Self.image(CGImageSourceCreateWithData(data as CFData, nil)) else {
                throw TextRecognitionError.unreadable
            }
            return try Self.recognize(image)
        case .file(let url):
            if Self.isPDF(url) { return try pdfLines(url) }
            guard let image = Self.image(CGImageSourceCreateWithURL(url as CFURL, nil)) else {
                throw TextRecognitionError.unreadable
            }
            return try Self.recognize(image)
        }
    }

    static func isPDF(_ url: URL) -> Bool {
        let type =
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        return type?.conforms(to: .pdf) ?? false
    }

    private static func image(_ source: CGImageSource?) -> CGImage? {
        guard let source, CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func pdfLines(_ url: URL) throws -> [String] {
        guard let document = PDFDocument(url: url) else { throw TextRecognitionError.unreadable }
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
        let embedded = pages.flatMap { Self.split($0.string ?? "") }
        if !embedded.isEmpty { return embedded }
        return try pages.flatMap { page -> [String] in
            guard let image = Self.render(page) else { return [] }
            return try Self.recognize(image)
        }
    }

    /// The page on white at ``pdfScale``.
    static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int((bounds.width * pdfScale).rounded())
        let height = Int((bounds.height * pdfScale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: pdfScale, y: pdfScale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    /// One recognized piece of text and where it sits (Vision's normalized, bottom-left-origin box).
    struct Piece: Equatable {
        let text: String
        let box: CGRect
    }

    static func recognize(_ image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let pieces = (request.results ?? []).compactMap { observation -> Piece? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return Piece(text: text, box: observation.boundingBox)
        }
        return readingOrder(pieces)
    }

    /// Top to bottom; pieces whose vertical centres sit within half a line height of a row's first piece
    /// share that row and are joined left to right with a space.
    static func readingOrder(_ pieces: [Piece]) -> [String] {
        let sorted = pieces.sorted { $0.box.midY > $1.box.midY }
        var rows: [[Piece]] = []
        for piece in sorted {
            if let first = rows.last?.first,
                abs(first.box.midY - piece.box.midY) < min(first.box.height, piece.box.height) / 2
            {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.compactMap { row in
            let line = row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? nil : line
        }
    }

    /// Non-empty lines of embedded PDF text.
    static func split(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
