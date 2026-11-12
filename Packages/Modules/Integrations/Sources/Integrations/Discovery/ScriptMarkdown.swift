import Foundation
import Yams

/// Splits a script module file (SPEC §9.1) into front matter, its one fenced code block and the documentation
/// around it, and decodes the front matter (Story 12.1 types, Yams per AD-16).
///
/// Layout: the file starts with a `---` line; the front matter runs to the next `---` (or `...`) line. Fenced
/// code blocks follow CommonMark: a line indented at most three spaces opening with three or more backticks or
/// tildes and an optional info string (whose first word is the language tag), closed by a line of the same
/// character at least as long. A fence that is never closed is an error (CommonMark would run it to the end of
/// the file; for a script that is almost always a typo). Indented code blocks are documentation.
struct ScriptMarkdown: Equatable, Sendable {
    var frontMatter: ScriptFrontMatter?
    /// The front matter as written (the lines between the `---` fences), nil when it is missing or unclosed.
    var frontMatterText: String?
    var code: String?
    var language: String?
    var documentation: String
    /// The first problem found: front matter first, then the code blocks. Id rules are checked across files.
    var error: ScriptParseError?

    static func parse(_ data: Data) -> ScriptMarkdown {
        guard var text = String(data: data, encoding: .utf8) else {
            return ScriptMarkdown(documentation: "", error: .notText)
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        // "\r\n" is one Character in Swift: normalize before splitting.
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, trimmedTrailing(first) == "---" else {
            return ScriptMarkdown(documentation: "", error: .frontMatterMissing)
        }
        guard
            let close = lines.indices.dropFirst().first(where: {
                let line = trimmedTrailing(lines[$0])
                return line == "---" || line == "..."
            })
        else {
            return ScriptMarkdown(documentation: "", error: .frontMatterUnclosed)
        }

        // Body lines keep their file line number (1-based) for messages.
        let bodyStart = close + 1
        let body = Array(lines[bodyStart...])
        let blocks = fencedBlocks(in: body)

        var result = ScriptMarkdown(documentation: "")
        result.frontMatterText = lines[1..<close].joined(separator: "\n")
        if blocks.count == 1, let block = blocks.first, let end = block.end {
            result.code = block.content.joined(separator: "\n")
            result.language = block.language
            result.documentation = documentation(body, removing: block.start...end)
        } else {
            result.documentation = documentation(body, removing: nil)
        }

        do {
            result.frontMatter = try ScriptFrontMatter.decode(yaml: lines[1..<close].joined(separator: "\n"))
        } catch let error as ScriptSchemaError {
            result.error = .schema(error)
        } catch {
            // Yams' decoder wraps its parse errors in `DecodingError.dataCorrupted`. The front matter starts on
            // file line 2.
            result.error = .invalidYAML(line: yamlError(error).flatMap(yamlLine).map { $0 + 1 })
        }
        guard result.error == nil else { return result }

        if let unclosed = blocks.first(where: { $0.end == nil }) {
            result.error = .codeBlockUnclosed(line: bodyStart + unclosed.start + 1)
        } else if blocks.isEmpty {
            result.error = .noCodeBlock
        } else if blocks.count > 1 {
            result.error = .severalCodeBlocks(count: blocks.count)
        }
        return result
    }

    // MARK: - Fences

    struct Block {
        /// Body line indices of the opening and closing fences (`end` nil when unclosed).
        var start: Int
        var end: Int?
        var language: String?
        var content: [String]
    }

    private struct Fence {
        let character: Character
        let length: Int
        let indent: Int
        let info: String
    }

    static func fencedBlocks(in lines: [String]) -> [Block] {
        var blocks: [Block] = []
        var open: (fence: Fence, block: Block)?
        for (index, line) in lines.enumerated() {
            if let current = open {
                if isClosing(line, for: current.fence) {
                    var block = current.block
                    block.end = index
                    blocks.append(block)
                    open = nil
                } else {
                    open?.block.content.append(stripIndent(line, upTo: current.fence.indent))
                }
            } else if let fence = opening(line) {
                let language = fence.info.split(whereSeparator: \.isWhitespace).first.map(String.init)
                open = (fence, Block(start: index, end: nil, language: language, content: []))
            }
        }
        if let open { blocks.append(open.block) }
        return blocks
    }

    private static func opening(_ line: String) -> Fence? {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let rest = line.dropFirst(indent)
        guard let character = rest.first, character == "`" || character == "~" else { return nil }
        let length = rest.prefix { $0 == character }.count
        guard length >= 3 else { return nil }
        let info = rest.dropFirst(length).trimmingCharacters(in: .whitespaces)
        if character == "`", info.contains("`") { return nil }
        return Fence(character: character, length: length, indent: indent, info: info)
    }

    private static func isClosing(_ line: String, for fence: Fence) -> Bool {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return false }
        let rest = line.dropFirst(indent)
        let length = rest.prefix { $0 == fence.character }.count
        guard length >= fence.length else { return false }
        return rest.dropFirst(length).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func stripIndent(_ line: String, upTo count: Int) -> String {
        let spaces = min(count, line.prefix { $0 == " " }.count)
        return String(line.dropFirst(spaces))
    }

    // MARK: - Helpers

    private static func documentation(_ lines: [String], removing range: ClosedRange<Int>?) -> String {
        var kept = lines
        if let range { kept.removeSubrange(range) }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimmedTrailing(_ line: String) -> Substring {
        var end = line.endIndex
        while end > line.startIndex, line[line.index(before: end)] == " " || line[line.index(before: end)] == "\t" {
            end = line.index(before: end)
        }
        return line[..<end]
    }

    private static func yamlError(_ error: any Error) -> YamlError? {
        if let error = error as? YamlError { return error }
        if case DecodingError.dataCorrupted(let context) = error { return context.underlyingError as? YamlError }
        return nil
    }

    /// The 1-based line in the front matter text where Yams stopped, when it says.
    private static func yamlLine(_ error: YamlError) -> Int? {
        switch error {
        case .scanner(_, _, let mark, _), .parser(_, _, let mark, _), .composer(_, _, let mark, _):
            mark.line
        default:
            nil
        }
    }
}
