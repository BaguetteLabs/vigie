import Foundation
import TOML

/// One untyped TOML value, as decoded by swift-toml (decode only, AD-16).
public enum ConfigValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    /// Offset date-time, local date-time or local date.
    case date(Date)
    case localTime(hour: Int, minute: Int, second: Int)
    case array([ConfigValue])
    case table([String: ConfigValue])

    /// TOML type name, for problem messages.
    public var typeName: String {
        switch self {
        case .string: "string"
        case .int: "integer"
        case .double: "float"
        case .bool: "boolean"
        case .date: "date"
        case .localTime: "time"
        case .array: "array"
        case .table: "table"
        }
    }
}

extension ConfigValue: Decodable {
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: any Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: AnyKey.self) {
            var table: [String: ConfigValue] = [:]
            for key in keyed.allKeys {
                table[key.stringValue] = try keyed.decode(ConfigValue.self, forKey: key)
            }
            self = .table(table)
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var array: [ConfigValue] = []
            while !unkeyed.isAtEnd {
                array.append(try unkeyed.decode(ConfigValue.self))
            }
            self = .array(array)
            return
        }
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Int64.self) {
            self = .int(Int(clamping: value))
        } else if let value = try? single.decode(Double.self) {
            self = .double(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else if let value = try? single.decode(LocalTime.self) {
            self = .localTime(hour: value.hour, minute: value.minute, second: value.second)
        } else {
            self = .date(try single.decode(Date.self))
        }
    }
}

/// A TOML parse failure. swift-toml reports a line and column for syntax errors only.
public struct ConfigParseError: Error, Sendable, Equatable {
    public let line: Int?
    public let column: Int?
    public let message: String
}

/// A parsed config file: an untyped tree of tables, addressed by `ConfigKeyPath`.
public struct ConfigDocument: Sendable, Equatable {
    public let root: [String: ConfigValue]

    public static let empty = ConfigDocument(root: [:])

    public init(root: [String: ConfigValue]) {
        self.root = root
    }

    /// Parses TOML text. Throws `ConfigParseError` on a syntax error.
    public static func parse(_ text: String) throws(ConfigParseError) -> ConfigDocument {
        do {
            let value = try TOMLDecoder().decode(ConfigValue.self, from: text)
            guard case .table(let root) = value else {
                throw ConfigParseError(line: nil, column: nil, message: "top level is not a table")
            }
            return ConfigDocument(root: root)
        } catch let error as ConfigParseError {
            throw error
        } catch let TOMLDecodingError.invalidSyntax(line, column, message) {
            throw ConfigParseError(line: line, column: column, message: message)
        } catch {
            throw ConfigParseError(line: nil, column: nil, message: String(describing: error))
        }
    }

    /// The value at `path`, or nil when any segment is missing or crosses a non-table value.
    public func value(at path: ConfigKeyPath) -> ConfigValue? {
        guard let first = path.segments.first, var current = root[first] else { return nil }
        for segment in path.segments.dropFirst() {
            guard case .table(let table) = current, let next = table[segment] else { return nil }
            current = next
        }
        return current
    }

    /// Every non-table value's path (arrays are leaves), depth first in key order. Recursion stops at any
    /// path for which `stop` returns true; that path is returned as a leaf.
    public func leafPaths(stoppingAt stop: (ConfigKeyPath) -> Bool = { _ in false }) -> [ConfigKeyPath] {
        var out: [ConfigKeyPath] = []
        func walk(_ table: [String: ConfigValue], _ prefix: [String]) {
            for key in table.keys.sorted() {
                let path = ConfigKeyPath(prefix + [key])
                if case .table(let child) = table[key], !stop(path) {
                    walk(child, path.segments)
                } else {
                    out.append(path)
                }
            }
        }
        walk(root, [])
        return out
    }
}
