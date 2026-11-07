import AgentKit
import CryptoKit
import Foundation

/// Plans the hook edits to one Claude Code `settings.json` (SPEC §8.3, AD-22). Pure apart from reading the file
/// through the injected reader; never writes (`IntegrationInstaller`, Story 4.7, applies the diff).
///
/// A managed entry is identified only by its exact command (`IntegrationInputs.hookCommand(for:)`). Install appends
/// `{"hooks": [{"type": "command", "command": …}]}` to each of the 8 events that lacks it; remove deletes only hook
/// objects with that exact command (then a group it emptied, then an event array it emptied). Every other key,
/// entry and key order is kept.
struct ClaudeHooksPlan {
    let settingsURL: URL
    let command: String
    let reader: any ConfigFileReader

    private struct Current {
        let oldText: String
        let baseHash: String?
        let root: [(key: String, value: OrderedJSON)]
    }

    func install() throws -> [ConfigDiff] {
        let current = try read()
        var hooks = try hooksSection(of: current.root)
        var added = 0
        for event in ClaudeAdapter.hookEvents {
            let index = hooks.firstIndex { $0.key == event }
            var groups: [OrderedJSON] = []
            if let index {
                guard case .array(let existing) = hooks[index].value else { throw invalid }
                groups = existing
            }
            guard !groups.contains(where: containsManagedHook) else { continue }
            groups.append(managedGroup)
            added += 1
            if let index {
                hooks[index].value = .array(groups)
            } else {
                hooks.append((event, .array(groups)))
            }
        }
        guard added > 0 else { return [] }
        let summary = String(
            format: String(localized: "claude.plan.install.summary", bundle: .module), added, displayPath)
        return [diff(current, root: replacingHooks(in: current.root, with: hooks), summary: summary)]
    }

    func remove() throws -> [ConfigDiff] {
        let current = try read()
        guard current.baseHash != nil else { return [] }
        var hooks = try hooksSection(of: current.root)
        var removed = 0
        var events: [(key: String, value: OrderedJSON)] = []
        for (event, value) in hooks {
            guard case .array(let groups) = value else {
                events.append((event, value))
                continue
            }
            var kept: [OrderedJSON] = []
            var changed = false
            for group in groups {
                guard case .object(var members) = group,
                    let hooksIndex = members.firstIndex(where: { $0.key == "hooks" }),
                    case .array(let entries) = members[hooksIndex].value
                else {
                    kept.append(group)
                    continue
                }
                let remaining = entries.filter { !isManagedHook($0) }
                guard remaining.count < entries.count else {
                    kept.append(group)
                    continue
                }
                removed += entries.count - remaining.count
                changed = true
                if !remaining.isEmpty {
                    members[hooksIndex].value = .array(remaining)
                    kept.append(.object(members))
                }
            }
            if !changed {
                events.append((event, value))
            } else if !kept.isEmpty {
                events.append((event, .array(kept)))
            }
        }
        guard removed > 0 else { return [] }
        hooks = events
        let summary = String(
            format: String(localized: "claude.plan.remove.summary", bundle: .module), removed, displayPath)
        return [diff(current, root: replacingHooks(in: current.root, with: hooks), summary: summary)]
    }

    // MARK: Helpers

    private var invalid: ClaudeAdapterError { .invalidSettings(path: settingsURL.path) }

    private var displayPath: String { (settingsURL.path as NSString).abbreviatingWithTildeInPath }

    private var managedGroup: OrderedJSON {
        .object([("hooks", .array([.object([("type", .string("command")), ("command", .string(command))])]))])
    }

    private func isManagedHook(_ entry: OrderedJSON) -> Bool {
        entry["command"]?.stringValue == command
    }

    private func containsManagedHook(_ group: OrderedJSON) -> Bool {
        guard case .array(let entries) = group["hooks"] else { return false }
        return entries.contains(where: isManagedHook)
    }

    private func read() throws -> Current {
        guard let data = try reader.read(settingsURL) else {
            return Current(oldText: "", baseHash: nil, root: [])
        }
        let text = String(decoding: data, as: UTF8.self)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Current(oldText: text, baseHash: hash, root: [])
        }
        guard case .object(let root) = try? OrderedJSON.parse(text) else { throw invalid }
        return Current(oldText: text, baseHash: hash, root: root)
    }

    private func hooksSection(of root: [(key: String, value: OrderedJSON)]) throws -> [(
        key: String, value: OrderedJSON
    )] {
        guard let value = root.first(where: { $0.key == "hooks" })?.value else { return [] }
        guard case .object(let hooks) = value else { throw invalid }
        return hooks
    }

    private func replacingHooks(
        in root: [(key: String, value: OrderedJSON)], with hooks: [(key: String, value: OrderedJSON)]
    ) -> [(key: String, value: OrderedJSON)] {
        var root = root
        if let index = root.firstIndex(where: { $0.key == "hooks" }) {
            root[index].value = .object(hooks)
        } else {
            root.append(("hooks", .object(hooks)))
        }
        return root
    }

    /// Keeps the file's trailing-newline convention; a new file ends with one.
    private func diff(_ current: Current, root: [(key: String, value: OrderedJSON)], summary: String) -> ConfigDiff {
        let trailingNewline = current.oldText.isEmpty || current.oldText.hasSuffix("\n")
        let newText = OrderedJSON.object(root).serialized() + (trailingNewline ? "\n" : "")
        return ConfigDiff(
            path: settingsURL, baseHash: current.baseHash, oldText: current.oldText, newText: newText,
            summary: summary)
    }
}
