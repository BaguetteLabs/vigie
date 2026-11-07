@preconcurrency import AVFoundation
import Foundation

/// Plays one sound file at a time (Story 10.1).
public protocol SoundPlayer: Sendable {
    /// Starts `url`, stopping whatever played before. Throws when the file cannot be opened or decoded.
    func play(url: URL) async throws
    func stop() async
}

/// `AVAudioPlayer` on its own actor: one player at a time, at the system output volume.
public actor AVAudioPlayerSoundPlayer: SoundPlayer {
    private var player: AVAudioPlayer?

    public init() {}

    public func play(url: URL) throws {
        player?.stop()
        let next = try AVAudioPlayer(contentsOf: url)
        guard next.prepareToPlay(), next.play() else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
        }
        player = next
    }

    public func stop() {
        player?.stop()
        player = nil
    }
}
