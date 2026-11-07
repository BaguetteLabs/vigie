import Darwin
import Foundation
import ModuleKit
import Synchronization
import Wire
import os

/// Where the CLI spools lines and where the app moves them while replaying (AD-6, AD-17).
public struct SpoolLocations: Sendable, Equatable {
    public var spoolURL: URL
    public var replayingURL: URL

    public init(spoolURL: URL, replayingURL: URL) {
        self.spoolURL = spoolURL
        self.replayingURL = replayingURL
    }

    public init(environment: AppEnvironment) {
        self.init(spoolURL: environment.spoolURL, replayingURL: environment.spoolReplayingURL)
    }
}

/// What one replay pass did.
public struct SpoolReplayReport: Sendable, Equatable {
    /// Messages published from a `spool.replaying.jsonl` left by an interrupted replay.
    public var leftoverLines: Int
    /// Messages published from `spool.jsonl`.
    public var newLines: Int
    /// Lines dropped: undecodable, unsupported version, or a trailing line without newline.
    public var dropped: Int

    public init(leftoverLines: Int = 0, newLines: Int = 0, dropped: Int = 0) {
        self.leftoverLines = leftoverLines
        self.newLines = newLines
        self.dropped = dropped
    }

    public var published: Int { leftoverLines + newLines }
}

/// Replays the CLI spool (AD-6): first a leftover `spool.replaying.jsonl` (a previous replay was
/// interrupted), then `spool.jsonl`, renamed to `spool.replaying.jsonl` under `flock(LOCK_EX)`,
/// published in file order with `replayed = true`, and deleted.
///
/// The rename is safe against concurrent CLI writers: they hold `LOCK_EX` around their single `write`
/// and, once they hold it, check that the path still names the inode they opened (reopening if not).
/// A line is therefore either in the renamed file before the rename or in a new `spool.jsonl` after it.
///
/// All file work runs on a private serial queue, never on the main actor or the cooperative pool;
/// passes never overlap. A crash between publishing and deleting replays those lines again at the
/// next launch (at least once), which `SessionStore` tolerates because `replayed` is set.
public final class SpoolReplayer: Sendable {
    public let locations: SpoolLocations
    private let decode: @Sendable (Data) -> EventMessage?
    private let publish: @Sendable (EventMessage) -> Bool
    private let logger: Logger
    private let queue = DispatchQueue(label: "EventServer.spool", qos: .utility)
    private let watch = Mutex(WatchState())

    private struct WatchState {
        var sources: [any DispatchSourceProtocol] = []
        var drainScheduled = false
        var stopped = false
    }

    public init(
        spoolURL: URL,
        replayingURL: URL,
        decode: @escaping @Sendable (Data) -> EventMessage?,
        publish: @escaping @Sendable (EventMessage) -> Bool,
        logger: Logger
    ) {
        locations = SpoolLocations(spoolURL: spoolURL, replayingURL: replayingURL)
        self.decode = decode
        self.publish = publish
        self.logger = logger
    }

    /// The launch pass (AD-6 step 4). Returns once every replayed message has been published.
    public func replayAtLaunch() async -> SpoolReplayReport {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.replayNow()) }
        }
    }

    /// The runtime pass, run whenever `spool.jsonl` appears while the app is running.
    @discardableResult
    public func drainIfPresent() async -> SpoolReplayReport {
        await replayAtLaunch()
    }

    /// Drains whenever the spool's directory changes (debounced by `debounce`) and every
    /// `safetyInterval` as a net for missed events. Idempotent until `stopWatching()`.
    public func startWatching(debounce: Duration = .milliseconds(250), safetyInterval: Duration = .seconds(30)) {
        let directory = locations.spoolURL.deletingLastPathComponent().path
        watch.withLock { state in
            guard !state.stopped, state.sources.isEmpty else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            let interval = DispatchTimeInterval.nanoseconds(Self.nanoseconds(safetyInterval))
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(1))
            timer.setEventHandler { [weak self] in self?.scheduleDrain(after: .zero) }
            timer.resume()
            state.sources.append(timer)

            let fd = open(directory, O_EVTONLY | O_CLOEXEC)
            guard fd >= 0 else {
                logger.error("spool: cannot watch its directory (\(errno)); relying on the timer")
                return
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
            source.setEventHandler { [weak self] in self?.scheduleDrain(after: debounce) }
            source.setCancelHandler { close(fd) }
            source.resume()
            state.sources.append(source)
        }
        // A spool written before watching started has no event of its own.
        scheduleDrain(after: .zero)
    }

    /// Cancels the watcher and the timer and waits for a pass in progress to finish; no pass starts
    /// afterwards. Must not be called from a `publish` callback.
    public func stopWatching() {
        let sources = watch.withLock { state in
            state.stopped = true
            defer { state.sources.removeAll() }
            return state.sources
        }
        for source in sources { source.cancel() }
        queue.sync {}
    }

    /// Coalesces bursts of directory events into one pass on `queue`.
    private func scheduleDrain(after delay: Duration) {
        let schedule = watch.withLock { state in
            guard !state.stopped, !state.drainScheduled else { return false }
            state.drainScheduled = true
            return true
        }
        guard schedule else { return }
        queue.asyncAfter(deadline: .now() + .nanoseconds(Self.nanoseconds(delay))) { [weak self] in
            guard let self else { return }
            let run = watch.withLock { state in
                state.drainScheduled = false
                return !state.stopped
            }
            if run { _ = replayNow() }
        }
    }

    private static func nanoseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1_000_000_000 + Int(attoseconds / 1_000_000_000)
    }

    /// One pass, synchronously on the caller's thread. Callers serialize through `queue`.
    func replayNow() -> SpoolReplayReport {
        var report = SpoolReplayReport()
        guard !watch.withLock({ $0.stopped }) else { return report }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: locations.replayingURL.path) {
            let (published, dropped, complete) = replayFile(at: locations.replayingURL)
            report.leftoverLines = published
            report.dropped += dropped
            logger.notice("replayed \(published) leftover spool lines")
            // Unreadable, or publishing was refused: renaming over it would lose it.
            if !complete { return report }
        }
        if fileManager.fileExists(atPath: locations.spoolURL.path), renameSpool() {
            let (published, dropped, _) = replayFile(at: locations.replayingURL)
            report.newLines = published
            report.dropped += dropped
            if published > 0 || dropped > 0 {
                logger.info("replayed \(published) spool lines, dropped \(dropped)")
            }
        }
        return report
    }

    /// Renames `spool.jsonl` to `spool.replaying.jsonl` while holding its lock. False if it vanished.
    private func renameSpool() -> Bool {
        let fd = open(locations.spoolURL.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else {
            if errno != ENOENT { logger.error("spool: open failed (\(errno))") }
            return false
        }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else {
            logger.error("spool: flock failed (\(errno))")
            return false
        }
        defer { flock(fd, LOCK_UN) }
        guard rename(locations.spoolURL.path, locations.replayingURL.path) == 0 else {
            logger.error("spool: rename failed (\(errno))")
            return false
        }
        return true
    }

    /// Publishes every complete line of `url` in order, then deletes the file. If the file cannot be
    /// read or the receiver refuses a message (it stopped), the file stays for the next launch.
    private func replayFile(at url: URL) -> (published: Int, dropped: Int, complete: Bool) {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .alwaysMapped)
        } catch {
            logger.error("spool: cannot read \(url.lastPathComponent, privacy: .public); left in place")
            return (0, 0, false)
        }
        var published = 0
        var dropped = 0
        var start = data.startIndex
        while let newline = data[start...].firstIndex(of: 0x0A) {
            let line = Data(data[start..<newline])
            start = newline + 1
            if let message = decode(line) {
                let accepted = publish(
                    EventMessage(
                        topic: message.topic, payload: message.payload, sentAt: message.sentAt,
                        receivedAt: message.receivedAt, replayed: true))
                guard accepted else {
                    logger.notice("spool: receiver stopped; \(url.lastPathComponent, privacy: .public) kept")
                    return (published, dropped, false)
                }
                published += 1
            } else {
                dropped += 1
            }
        }
        if start < data.endIndex {
            dropped += 1
            logger.notice("spool: dropped \(data.endIndex - start)-byte trailing line without newline")
        }
        if unlink(url.path) != 0, errno != ENOENT {
            logger.error("spool: cannot delete \(url.lastPathComponent, privacy: .public) (\(errno))")
        }
        return (published, dropped, true)
    }
}
