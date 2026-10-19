import AVFoundation
@testable import SleepTracker

/// Scripted `SoundClassifying` for pipeline tests. Nothing is classified; the fake
/// counts what the pipeline feeds it, and the test drives the delegate with `emit`.
final class FakeSoundClassifier: SoundClassifying {
    weak var delegate: SoundClassifierDelegate?

    /// Sum of `frameLength` over all buffers passed to `analyze`.
    var analyzedFrameCount: Int = 0
    var completeCount = 0
    /// Seconds since session start of frame 0 of the segment this fake stands for.
    let timeOffset: TimeInterval

    init(timeOffset: TimeInterval) {
        self.timeOffset = timeOffset
    }

    func analyze(_ buffer: AVAudioPCMBuffer, atFramePosition position: AVAudioFramePosition) {
        analyzedFrameCount += Int(buffer.frameLength)
    }

    func completeAnalysis() {
        completeCount += 1
    }

    // MARK: - Test helpers

    /// Delivers one classification window to the delegate, synchronously on the
    /// calling thread. The real service is assumed to call its delegate on the thread
    /// that drives the analysis as well (see docs/unverified.md). Call it from the
    /// pipeline's queue.
    func emit(window: ClassificationWindow, topLabels: [RankedLabel] = []) {
        delegate?.classifier(self, didProduce: window, topLabels: topLabels)
    }
}
