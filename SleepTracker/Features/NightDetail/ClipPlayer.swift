import AVFoundation
import Combine
import Foundation

/// Plays the clip of one event at a time (spec A9). Before a clip plays, the audio
/// session is switched to `.playback` (spec B1); it is released again when playback
/// stops or reaches the end. Clips play only outside a running night: the views
/// disable the play buttons while a night runs.
@MainActor
final class ClipPlayer: NSObject, ObservableObject {
    private static let playbackFailedMessage = "Der Clip konnte nicht abgespielt werden."

    /// Relative path of the loaded clip, playing or paused; nil when no clip is loaded.
    @Published private(set) var playingPath: String? = nil
    /// `true` while the loaded clip plays; `false` while it is paused or none is loaded.
    @Published private(set) var isPlaying: Bool = false
    /// Message for an alert (German); nil means no error. Views set it to nil to dismiss.
    @Published var errorMessage: String? = nil

    private let fileStore: FileStore
    private let sessionManager: AudioSessionManager
    private var player: AVAudioPlayer?
    /// Held here because `AVAudioPlayer.delegate` is weak.
    private var delegateProxy: PlayerDelegateProxy?
    /// `true` from a successful `configureForPlayback()` until `stop()` releases the
    /// session. `stop()` deactivates only then, so calling it while a night records
    /// (for example when the detail view disappears) never ends the recording session.
    private var hasActivatedSession = false

    init(fileStore: FileStore, sessionManager: AudioSessionManager = .shared) {
        self.fileStore = fileStore
        self.sessionManager = sessionManager
        super.init()
    }

    /// Plays or pauses the clip at `relativePath` (relative to `FileStore.baseDirectory`).
    /// The loaded clip pauses while it plays and resumes where it paused; another clip
    /// stops the loaded one and starts from the beginning. Failures set `errorMessage`.
    func toggle(relativePath: String) {
        if let current = player, playingPath == relativePath {
            if current.isPlaying {
                current.pause()
                isPlaying = false
            } else {
                resume(current)
            }
            return
        }
        start(relativePath: relativePath)
    }

    /// Stops playback, unloads the clip and releases the audio session if this player
    /// activated it. A session that is set to `.record` again belongs to a night that
    /// started meanwhile; deactivating it would stop the running capture without any
    /// notification, so it is left alone.
    func stop() {
        unloadPlayer()
        if hasActivatedSession {
            if !sessionManager.isConfiguredForRecording {
                sessionManager.deactivate()
            }
            hasActivatedSession = false
        }
    }

    // MARK: - Private

    private func start(relativePath: String) {
        unloadPlayer()
        do {
            try activatePlaybackSession()
            let newPlayer = try AVAudioPlayer(contentsOf: fileStore.clipURL(relativePath: relativePath))
            // Only the end of the loaded player counts; a late callback of a replaced one is ignored.
            let proxy = PlayerDelegateProxy { [weak self, weak newPlayer] failed in
                guard let self, let newPlayer, self.player === newPlayer else {
                    return
                }
                self.playbackEnded(failed: failed)
            }
            newPlayer.delegate = proxy
            newPlayer.prepareToPlay()
            player = newPlayer
            delegateProxy = proxy
            playingPath = relativePath
            guard newPlayer.play() else {
                fail()
                return
            }
            isPlaying = true
        } catch {
            fail()
        }
    }

    /// Resumes a paused clip. The session is configured again because it may have been
    /// released or changed since the clip was paused.
    private func resume(_ audioPlayer: AVAudioPlayer) {
        do {
            try activatePlaybackSession()
        } catch {
            fail()
            return
        }
        guard audioPlayer.play() else {
            fail()
            return
        }
        isPlaying = true
    }

    private func activatePlaybackSession() throws {
        try sessionManager.configureForPlayback()
        hasActivatedSession = true
    }

    /// Called on the main queue when the loaded clip reached its end or could not be decoded.
    private func playbackEnded(failed: Bool) {
        stop()
        if failed {
            errorMessage = ClipPlayer.playbackFailedMessage
        }
    }

    private func fail() {
        stop()
        errorMessage = ClipPlayer.playbackFailedMessage
    }

    /// Stops and releases the player and clears the published state; leaves the session as it is.
    private func unloadPlayer() {
        player?.stop()
        player?.delegate = nil
        player = nil
        delegateProxy = nil
        playingPath = nil
        isPlaying = false
    }
}

/// Receives the delegate calls of one `AVAudioPlayer` and forwards them to the main
/// queue. It is not main-actor isolated, so it conforms to the Objective-C delegate
/// protocol whatever thread AVFoundation calls it on.
private final class PlayerDelegateProxy: NSObject, AVAudioPlayerDelegate {
    /// Runs on the main queue; the argument is `true` when playback ended with a decode error.
    private let onEnd: (Bool) -> Void

    init(onEnd: @escaping (Bool) -> Void) {
        self.onEnd = onEnd
        super.init()
    }

    /// `flag` is `false` when playback stopped because the audio could not be decoded.
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        forward(failed: !flag)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        forward(failed: true)
    }

    private func forward(failed: Bool) {
        let onEnd = self.onEnd
        DispatchQueue.main.async {
            onEnd(failed)
        }
    }
}
