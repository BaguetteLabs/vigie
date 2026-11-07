import Foundation
import ModuleKit
import os

/// Turns ``SoundProblem``s into `setup.problem` alerts (Story 10.2, FR16): "Sound file for sounds.blocked not
/// found: ~/x.aiff", category `SOUND`, opening Settings › Sounds.
///
/// One alert per key and problem: the same problem again posts nothing; a different problem for the key replaces
/// the alert; ``clear(key:)`` (the key played again) resolves it. The App posts through the notifier made for
/// ``SetupProblemReporter/manifest``.
@MainActor
public final class SoundProblemReporter {
    private let notifier: any Notifier
    private let log: Logger
    private var posted: [String: (problem: SoundProblem, handle: AlertHandle)] = [:]

    public init(
        notifier: any Notifier, log: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "sounds")
    ) {
        self.notifier = notifier
        self.log = log
    }

    /// Keys with an open problem alert.
    public var openKeys: Set<String> { Set(posted.keys) }

    public func report(_ problem: SoundProblem) {
        if posted[problem.key]?.problem == problem { return }
        posted[problem.key]?.handle.resolve()
        posted[problem.key] = (problem, notifier.post(Self.event(for: problem)))
        log.info("Sound setup problem alert posted")
    }

    public func clear(key: String) {
        posted.removeValue(forKey: key)?.handle.resolve()
    }

    static func event(for problem: SoundProblem) -> NotifierEvent {
        NotifierEvent(
            kind: SetupProblemReporter.alertKind, severity: .warn, title: SoundProblemText.title(problem),
            body: SoundProblemText.string("vigiecore.setup.body.sound"), action: .openSettings(pane: "sounds"),
            dedupeKey: "sound:\(problem.key)", category: SoundProblemText.string("vigiecore.setup.category.sound"))
    }
}

/// Catalog text for sound problems (setup alerts and the Sounds pane's inline errors).
enum SoundProblemText {
    /// `sounds.<key>`, as the user finds it in `config.toml`.
    static func keyName(_ key: String) -> String { "sounds.\(key)" }

    static func title(_ problem: SoundProblem) -> String {
        let key = keyName(problem.key)
        switch problem.reason {
        case .fileNotFound(let path): return format("vigiecore.setup.title.soundNotFound", key, abbreviate(path))
        case .unreadable(let path): return format("vigiecore.setup.title.soundUnreadable", key, abbreviate(path))
        case .unknownBuiltIn(let name): return format("vigiecore.setup.title.soundUnknownBuiltIn", key, name)
        case .invalidValue(let raw): return format("vigiecore.setup.title.soundInvalid", key, raw)
        }
    }

    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func format(_ key: String, _ args: String...) -> String {
        String(format: string(key), arguments: args)
    }

    private static func abbreviate(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
}
