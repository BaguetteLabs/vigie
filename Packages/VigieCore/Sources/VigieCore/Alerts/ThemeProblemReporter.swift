import Foundation
import ModuleKit
import VigieUI
import os

/// Turns ``ThemeProblem``s into `setup.problem` alerts (Story 18.2, FR95): a custom theme that reuses a built-in
/// id, a file with a newer `schema`, an unreadable file, an unknown theme id. Opens Settings › Appearance.
///
/// One alert per problem: ``reconcile(_:)`` posts the new ones and resolves those that went away, so the same
/// set again posts nothing. The App posts through the notifier made for ``SetupProblemReporter/manifest``.
@MainActor
public final class ThemeProblemReporter {
    private let notifier: any Notifier
    private let log: Logger
    private var posted: [ThemeProblem: AlertHandle] = [:]

    public init(
        notifier: any Notifier, log: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "theme")
    ) {
        self.notifier = notifier
        self.log = log
    }

    /// Problems with an open alert.
    public var openProblems: Set<ThemeProblem> { Set(posted.keys) }

    public func reconcile(_ problems: [ThemeProblem]) {
        // A theme file that failed to load also leaves its id unknown: one alert is enough.
        let failedIDs = Set(
            problems.compactMap { problem -> String? in
                switch problem {
                case .schemaTooNew(let id, _, _, _): id
                default: nil
                }
            })
        let current = problems.filter { problem in
            if case .unknownTheme(let id) = problem { return !failedIDs.contains(id) }
            return true
        }
        let wanted = Set(current)
        for (problem, handle) in posted where !wanted.contains(problem) {
            handle.resolve()
            posted[problem] = nil
        }
        for problem in current where posted[problem] == nil {
            posted[problem] = notifier.post(Self.event(for: problem))
            log.info("Theme setup problem alert posted")
        }
    }

    static func event(for problem: ThemeProblem) -> NotifierEvent {
        NotifierEvent(
            kind: SetupProblemReporter.alertKind, severity: .warn, title: ThemeProblemText.title(problem),
            body: ThemeProblemText.string("vigiecore.setup.body.theme"), action: .openSettings(pane: "appearance"),
            dedupeKey: "theme:\(problem)", category: ThemeProblemText.string("vigiecore.setup.category.theme"))
    }
}

/// Catalog text for theme problems.
enum ThemeProblemText {
    static func title(_ problem: ThemeProblem) -> String {
        switch problem {
        case .schemaTooNew(let id, let file, let found, _):
            return format("vigiecore.setup.title.themeSchemaTooNew", file ?? id, String(found))
        case .idClash(let id, let file): return format("vigiecore.setup.title.themeIdClash", file, id)
        case .unreadable(let file, _): return format("vigiecore.setup.title.themeUnreadable", file)
        case .unknownTheme(let id): return format("vigiecore.setup.title.themeUnknown", id)
        }
    }

    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func format(_ key: String, _ args: String...) -> String {
        String(format: string(key), arguments: args)
    }
}
