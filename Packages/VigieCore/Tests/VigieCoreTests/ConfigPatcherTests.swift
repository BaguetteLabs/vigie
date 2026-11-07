import Foundation
import Testing

@testable import VigieCore

@Suite struct TOMLScalarTests {
    @Test(arguments: [
        (0.5, "0.5"), (2.0, "2.0"), (-1.25, "-1.25"), (1e-5, "0.00001"), (1.5e20, "150000000000000000000.0"),
        (0.1, "0.1"), (123_456.789, "123456.789"), (-0.0, "-0.0"),
    ])
    func formatsDoublesWithoutExponent(value: Double, text: String) throws {
        #expect(TOMLScalar.double(value).tomlText == text)
        let document = try ConfigDocument.parse("x = \(text)\n")
        #expect(document.value(at: "x") == .double(value))
    }

    @Test func specialDoubles() {
        #expect(TOMLScalar.double(.nan).tomlText == "nan")
        #expect(TOMLScalar.double(.infinity).tomlText == "inf")
        #expect(TOMLScalar.double(-.infinity).tomlText == "-inf")
    }

    @Test func quotesAndEscapesStrings() throws {
        let raw = "a \"b\" \\ c\nd\te\u{01}é"
        let text = TOMLScalar.string(raw).tomlText
        #expect(text == #""a \"b\" \\ c\nd\te\u0001é""#)
        #expect(try ConfigDocument.parse("x = \(text)\n").value(at: "x") == .string(raw))
    }

    @Test func durationsArraysAndOthers() {
        #expect(TOMLScalar.duration(.seconds(5400)).tomlText == #""1h30m""#)
        #expect(TOMLScalar.duration(.seconds(5400)).configValue == .string("1h30m"))
        #expect(TOMLScalar.array([.string("a"), .string("b")]).tomlText == #"["a", "b"]"#)
        #expect(TOMLScalar.array([]).tomlText == "[]")
        #expect(TOMLScalar.bool(true).tomlText == "true")
        #expect(TOMLScalar.int(-3).tomlText == "-3")
    }
}

@Suite struct TOMLPatcherTests {
    @Test(arguments: [
        // A key inside an inline table.
        ("[modules.time]\npomodoro = { work = \"25m\" }\n", "modules.time.pomodoro.work"),
        // A new key inside an inline table.
        ("[modules.time]\npomodoro = { work = \"25m\" }\n", "modules.time.pomodoro.long_every"),
        // A key in an array of tables, or a sub-table of one.
        ("[[modules.scripts.items]]\nname = \"a\"\n", "modules.scripts.items.name"),
        ("[[modules.scripts.items]]\nname = \"a\"\n", "modules.scripts.items.extra.x"),
        // A path that names a table.
        ("[general]\nx = 1\n", "general"),
        ("a.b = 1\n", "a"),
        // Under a non-table value.
        ("[general]\nx = 1\n", "general.x.y"),
    ])
    func unsupportedLocationsThrow(text: String, key: String) {
        let path = ConfigKeyPath(stringLiteral: key)
        #expect(throws: TOMLPatchError.unsupportedLocation(path)) {
            try TOMLPatcher.set(text, path: path, value: .int(1))
        }
        #expect(throws: TOMLPatchError.unsupportedLocation(path)) { try TOMLPatcher.remove(text, path: path) }
    }

    @Test(arguments: ["[general\nx = 1\n", "x = \"open\n", "x = [1, 2\n", "= 1\n", "x = \"\"\"\nnever closed\n"])
    func malformedTextThrows(text: String) {
        #expect(throws: TOMLPatchError.self) { try TOMLPatcher.set(text, path: "y", value: .int(1)) }
    }

    @Test func emptyFileGetsTableAndNewline() throws {
        #expect(try TOMLPatcher.set("", path: "general.x", value: .int(1)) == "[general]\nx = 1\n")
        #expect(try TOMLPatcher.set("", path: "x", value: .int(1)) == "x = 1\n")
    }

    @Test func emptyTableGetsKeyRightAfterHeader() throws {
        let text = "[general]\n\n# about closed\n[closed]\n"
        #expect(
            try TOMLPatcher.set(text, path: "general.x", value: .bool(true))
                == "[general]\nx = true\n\n# about closed\n[closed]\n")
    }

    @Test func insertKeepsIndentationOfTheTable() throws {
        let text = "[general]\n    a = 1\n    b = 2\n"
        #expect(
            try TOMLPatcher.set(text, path: "general.c", value: .int(3))
                == "[general]\n    a = 1\n    b = 2\n    c = 3\n")
    }

    @Test func quotedSegmentsAreWrittenQuoted() throws {
        let out = try TOMLPatcher.set("", path: #"modules."a.b".local."x y""#, value: .string("v"))
        #expect(out == "[modules.\"a.b\".local]\n\"x y\" = \"v\"\n")
        #expect(try ConfigDocument.parse(out).value(at: #"modules."a.b".local."x y""#) == .string("v"))
    }

    @Test func literalQuotedHeadersMatch() throws {
        let text = "[modules.'agents.sessions']\npriority = 1\n"
        #expect(
            try TOMLPatcher.set(text, path: #"modules."agents.sessions".priority"#, value: .int(2))
                == "[modules.'agents.sessions']\npriority = 2\n")
    }

    @Test func removeOfAbsentKeyReturnsTextUnchanged() throws {
        let text = "# c\n[general]\nx = 1"
        #expect(try TOMLPatcher.remove(text, path: "general.y") == text)
        #expect(try TOMLPatcher.remove(text, path: "general.x") == "# c\n[general]")
    }
}
