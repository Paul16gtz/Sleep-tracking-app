import AVFoundation

/// Why a test file cannot be analyzed.
enum FileAudioSourceError: LocalizedError {
    /// The file could not be opened as audio; carries the underlying message.
    case cannotOpen(String)
    /// The file has no usable sample rate or channel count, or a buffer could not be allocated.
    case unsupportedFormat
    /// Reading stopped before the end of the file; carries the underlying message.
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let message):
            return "Die Audiodatei konnte nicht geöffnet werden: \(message)"
        case .unsupportedFormat:
            return "Das Format der Audiodatei wird nicht unterstützt."
        case .readFailed(let message):
            return "Die Audiodatei konnte nicht vollständig gelesen werden: \(message)"
        }
    }
}

/// Reads an audio file in chunks and delivers it as mono Float32 buffers, as fast as the
/// delegate processes them (test mode, spec B8). Stream time comes from the frame
/// counter, so the file runs faster than real time (spec B2).
///
/// Segment protocol: the file is one segment. `didBeginSegmentWith` comes before the
/// first buffer, frame positions count from 0, and `audioSourceDidFinish` comes exactly
/// once, at the end of the file or after a read error, never after `stop()`.
///
/// Threading: `start()` opens the file on the calling thread (the main thread); all
/// mutable state is then touched only on `callbackQueue`, where every delegate method is
/// called. Each chunk is read in its own `callbackQueue.async` block, so other work on the
/// queue (the pipeline's `stop()`) runs between two chunks and the stack does not grow.
/// `stop()` sets the stop flag on `callbackQueue` with `sync` (directly when called on
/// it), so once it has returned no delegate method is called any more.
final class FileAudioSource: AudioSource {
    weak var delegate: AudioSourceDelegate?
    let callbackQueue: DispatchQueue

    private let fileURL: URL
    private let chunkFrames: AVAudioFrameCount
    /// Marks `callbackQueue`, so `stop()` can tell whether it runs on it.
    private let queueKey = DispatchSpecificKey<Void>()

    // MARK: callbackQueue state

    /// The file being read; nil before the segment begins and after the end or the stop.
    private var file: AVAudioFile?
    private var monoFormat: AVAudioFormat?
    /// Frames delivered so far in the segment.
    private var framePosition: AVAudioFramePosition = 0
    private var hasBegun = false
    private var isStopped = false
    private var isFinished = false

    /// `chunkFrames` is the number of file frames read per buffer (at least 1).
    init(fileURL: URL, callbackQueue: DispatchQueue, chunkFrames: AVAudioFrameCount = 4096) {
        self.fileURL = fileURL
        self.callbackQueue = callbackQueue
        self.chunkFrames = max(chunkFrames, 1)
        callbackQueue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        callbackQueue.setSpecific(key: queueKey, value: nil)
    }

    // MARK: - AudioSource

    /// Opens the file and begins the segment on `callbackQueue`. Call once. Throws when
    /// the file cannot be opened or its format has no mono Float32 equivalent; nothing
    /// is delivered then.
    func start() throws {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw FileAudioSourceError.cannotOpen(error.localizedDescription)
        }
        let fileFormat = audioFile.processingFormat
        guard fileFormat.sampleRate.isFinite, fileFormat.sampleRate > 0, fileFormat.channelCount > 0,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: fileFormat.sampleRate,
                  channels: 1,
                  interleaved: false
              ) else {
            throw FileAudioSourceError.unsupportedFormat
        }
        callbackQueue.async { [weak self] in
            self?.begin(reading: audioFile, monoFormat: format)
        }
    }

    /// Stops reading and releases the file. Once this returns, no delegate method is
    /// called any more. Off `callbackQueue` it waits for the chunk in progress (one
    /// chunk at most), so it must not be called from a queue that `callbackQueue` waits for.
    func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            markStopped()
        } else {
            callbackQueue.sync {
                self.markStopped()
            }
        }
    }

    // MARK: - Reading (callbackQueue)

    private func begin(reading audioFile: AVAudioFile, monoFormat format: AVAudioFormat) {
        guard !isStopped, !hasBegun else {
            return
        }
        hasBegun = true
        file = audioFile
        monoFormat = format
        framePosition = 0
        delegate?.audioSource(self, didBeginSegmentWith: format)
        scheduleNextChunk()
    }

    /// Each chunk runs as its own block, never as a nested call.
    private func scheduleNextChunk() {
        callbackQueue.async { [weak self] in
            self?.readNextChunk()
        }
    }

    /// Reads one chunk and delivers it in mono, then schedules the next. An empty read
    /// is the end of the file.
    private func readNextChunk() {
        guard !isStopped, !isFinished, let audioFile = file, let format = monoFormat else {
            return
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: chunkFrames) else {
            fail(with: FileAudioSourceError.unsupportedFormat)
            return
        }
        do {
            try audioFile.read(into: buffer)
        } catch {
            // A reader that reports the end of the file as an error ends normally.
            if audioFile.framePosition >= audioFile.length {
                finish()
            } else {
                fail(with: FileAudioSourceError.readFailed(error.localizedDescription))
            }
            return
        }
        guard buffer.frameLength > 0 else {
            finish()
            return
        }
        guard let mono = MonoDownmix.makeMonoBuffer(from: buffer, monoFormat: format) else {
            fail(with: FileAudioSourceError.unsupportedFormat)
            return
        }
        delegate?.audioSource(self, didProduce: mono, framePosition: framePosition)
        framePosition += AVAudioFramePosition(buffer.frameLength)
        scheduleNextChunk()
    }

    /// Reports `error`; a file that cannot be read further is then finished.
    private func fail(with error: Error) {
        delegate?.audioSource(self, didFailWith: error)
        finish()
    }

    /// Ends the stream once and releases the file; reports the end unless stopped.
    private func finish() {
        guard !isFinished else {
            return
        }
        isFinished = true
        file = nil
        guard !isStopped else {
            return
        }
        delegate?.audioSourceDidFinish(self)
    }

    private func markStopped() {
        isStopped = true
        file = nil
    }
}
