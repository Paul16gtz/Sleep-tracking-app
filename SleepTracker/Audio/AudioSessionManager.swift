import AVFoundation

/// Configures the shared `AVAudioSession` (spec B1): `.record` with mode `.measurement`
/// during a night, `.playback` for clip playback outside a running night.
/// Call from the main thread.
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private let session = AVAudioSession.sharedInstance()

    /// Input only, with minimal system signal processing. Recording keeps running in
    /// the background because of `UIBackgroundModes = [audio]`.
    func configureForRecording() throws {
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)
    }

    func configureForPlayback() throws {
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    /// Releases the session so other apps can resume their audio. Errors are ignored:
    /// there is nothing left to undo when deactivation fails.
    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// `true` while the session is set to the recording category, so a night records or
    /// ended last without anything changing the category since.
    var isConfiguredForRecording: Bool {
        session.category == .record
    }
}
