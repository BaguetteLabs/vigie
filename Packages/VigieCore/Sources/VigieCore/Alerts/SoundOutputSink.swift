import Foundation
import ModuleKit
import os

/// The real sound output of `AlertCenter` (Story 10.1, FR98, AD-13).
///
/// `AlertCenter` calls it once when an alert with the `sound` output is delivered and once more when its reminder
/// replays; it already withholds both under a Focus mode (Story 3.5), so this sink does not check Focus. Here the
/// kind maps to its `[sounds]` key through ``SoundTable``; nothing plays when `enabled` is false, the key is
/// `"off"`, or the kind has no key. A value that cannot play goes to `onProblem` instead.
@MainActor
public final class NotifierSoundSink: SoundSink {
    private let config: @MainActor () -> SoundSettings
    private let player: any SoundPlayer
    private let catalog: SoundCatalog
    private let onProblem: @MainActor (SoundProblem) -> Void
    private let log: Logger
    /// The last playback started (tests await it).
    private(set) var pending: Task<Void, Never>?

    /// - Parameters:
    ///   - config: `[sounds]` as it is now; the App passes `{ SoundSettings.read(from: configStore) }`.
    ///   - onProblem: a value that cannot play (missing file, unknown built-in, bad value, undecodable file).
    public init(
        config: @escaping @MainActor () -> SoundSettings,
        player: any SoundPlayer,
        catalog: SoundCatalog = .bundled,
        onProblem: @escaping @MainActor (SoundProblem) -> Void = { _ in },
        log: Logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "sounds")
    ) {
        self.config = config
        self.player = player
        self.catalog = catalog
        self.onProblem = onProblem
        self.log = log
    }

    public func play(for alert: ActiveAlert) {
        guard let key = SoundTable.key(for: alert.kind) else { return }
        let settings = config()
        guard settings.enabled, let value = settings.value(for: key) else { return }
        switch catalog.resolve(value) {
        case .silent:
            return
        case .problem(let reason):
            report(SoundProblem(key: key, reason: reason))
        case .play(let url):
            let player = player
            pending = Task { @MainActor [weak self] in
                do {
                    try await player.play(url: url)
                } catch {
                    self?.report(SoundProblem(key: key, reason: .unreadable(url.path)))
                }
            }
        }
    }

    private func report(_ problem: SoundProblem) {
        log.error("Sound for \(problem.key, privacy: .public) cannot play")
        onProblem(problem)
    }
}
