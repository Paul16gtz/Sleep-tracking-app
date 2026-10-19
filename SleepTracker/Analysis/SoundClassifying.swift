import AVFoundation

/// Receives the results of a `SoundClassifying`. Every method is called
/// synchronously on the thread that called `analyze(_:atFramePosition:)` or
/// `completeAnalysis()`, which is the pipeline's serial analysis queue (for the
/// real service assumed; see docs/unverified.md).
protocol SoundClassifierDelegate: AnyObject {
    /// One analysis window. `window` times are seconds since session start;
    /// `topLabels` are the highest-ranked raw labels (at most five, confidence
    /// descending) for the Debug screen.
    func classifier(_ classifier: SoundClassifying, didProduce window: ClassificationWindow, topLabels: [RankedLabel])
    func classifier(_ classifier: SoundClassifying, didFailWith error: Error)
}

/// Classifies one stream segment of mono Float32 audio. A new instance is created
/// for every segment (spec B2); frame positions count from the segment's frame 0.
protocol SoundClassifying: AnyObject {
    var delegate: SoundClassifierDelegate? { get set }
    /// Feeds one buffer. `position` is the frame index of the buffer's first frame
    /// within the current segment.
    func analyze(_ buffer: AVAudioPCMBuffer, atFramePosition position: AVAudioFramePosition)
    /// Ends the segment. No buffers may follow. Final results, if any, are delivered
    /// to the delegate on the calling thread (for the real service assumed; see
    /// docs/unverified.md).
    func completeAnalysis()
}

/// (Audio format, timeOffset in seconds since session start of frame 0 of the
/// segment) -> classifier for that segment.
typealias SoundClassifierFactory = (AVAudioFormat, TimeInterval) throws -> SoundClassifying
