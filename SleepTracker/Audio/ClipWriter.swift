import AVFoundation

enum ClipWriterError: LocalizedError {
    case notPrepared
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "Die Clip-Aufnahme wurde nicht vorbereitet."
        case .bufferAllocationFailed:
            return "Für den Clip konnte kein Audiopuffer angelegt werden."
        }
    }
}

/// Streams mono samples into AAC `.m4a` clip files below the session's clip folder.
/// Only one clip is open at a time. Used on the audio pipeline queue only.
final class ClipWriter: ClipWriting {
    private let fileStore: FileStore
    private let sessionID: UUID
    private let bitRate: Int

    /// Mono Float32 non-interleaved format at the sample rate passed to `prepare`;
    /// `nil` until `prepare` was called with a valid sample rate.
    private var monoFormat: AVAudioFormat?

    /// The open clip. Releasing it finalizes the file (AVAudioFile has no
    /// explicit close before iOS 18).
    private var file: AVAudioFile?

    init(fileStore: FileStore, sessionID: UUID, bitRate: Int = 48_000) {
        self.fileStore = fileStore
        self.sessionID = sessionID
        self.bitRate = bitRate
    }

    func prepare(sampleRate: Double) {
        // A clip file has one fixed sample rate. If a restarted segment runs at a
        // different rate, the open clip ends at the segment boundary; later writes
        // for it are no-ops.
        if let file, file.processingFormat.sampleRate != sampleRate {
            close()
        }
        monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
    }

    func open(type: SoundEventType, clipStart: Date) throws -> String {
        guard let monoFormat else {
            throw ClipWriterError.notPrepared
        }
        close()

        _ = try fileStore.clipDirectory(for: sessionID)
        let relativePath = fileStore.makeClipRelativePath(sessionID: sessionID, clipStart: clipStart, type: type)
        let url = fileStore.clipURL(relativePath: relativePath)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: monoFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate
        ]
        let newFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        file = newFile

        // Best effort, as in FileStore: the clip folder already carries the protection
        // class, and iOS applies the same class to app files by default.
        try? fileStore.applyProtection(to: url)
        return relativePath
    }

    /// Appends samples to the open clip. Without an open clip this is a no-op.
    func write(_ samples: [Float]) throws {
        guard let file, !samples.isEmpty else {
            return
        }
        // `write(from:)` requires a buffer in the file's own processing format.
        guard let buffer = MonoDownmix.makeBuffer(samples: samples, format: file.processingFormat) else {
            throw ClipWriterError.bufferAllocationFailed
        }
        try file.write(from: buffer)
    }

    func close() {
        file = nil
    }
}
