import AVFoundation
import XCTest
@testable import SleepTracker

/// Scripted `AudioSource` for pipeline tests. Nothing is captured; the test drives
/// the delegate with the `emit...` helpers, which call it synchronously on
/// `callbackQueue` (the same queue the real sources use for their callbacks).
final class FakeAudioSource: AudioSource {
    weak var delegate: AudioSourceDelegate?
    let callbackQueue: DispatchQueue

    var startCount = 0
    var stopCount = 0

    init(callbackQueue: DispatchQueue = DispatchQueue(label: "test.audio")) {
        self.callbackQueue = callbackQueue
    }

    func start() throws {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    // MARK: - Test helpers

    /// Begins a new stream segment with `format`.
    func emitSegment(format: AVAudioFormat) {
        callbackQueue.sync {
            self.delegate?.audioSource(self, didBeginSegmentWith: format)
        }
    }

    /// Delivers `samples` as one buffer in `format` (mono Float32 expected).
    func emitBuffer(samples: [Float], format: AVAudioFormat, framePosition: AVAudioFramePosition) {
        guard let buffer = MonoDownmix.makeBuffer(samples: samples, format: format) else {
            XCTFail("FakeAudioSource could not build a buffer in format \(format)")
            return
        }
        callbackQueue.sync {
            self.delegate?.audioSource(self, didProduce: buffer, framePosition: framePosition)
        }
    }

    func emitInterruption(_ reason: AudioInterruptionReason) {
        callbackQueue.sync {
            self.delegate?.audioSource(self, didInterruptWith: reason)
        }
    }

    /// Simulates a source that reached its end by itself (like a file source).
    func emitFinish() {
        callbackQueue.sync {
            self.delegate?.audioSourceDidFinish(self)
        }
    }
}
