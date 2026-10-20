import AVFoundation
import XCTest
@testable import SleepTracker

/// Records the delegate calls of a source in order. Touched only on the source's
/// callback queue; the tests read it there with `queue.sync`.
private final class SourceSpy: AudioSourceDelegate {
    enum Call: Equatable {
        case begin(sampleRate: Double, channelCount: AVAudioChannelCount)
        case buffer(framePosition: AVAudioFramePosition, frameLength: AVAudioFrameCount, channelCount: AVAudioChannelCount)
        case interruption
        case failure
        case finish
    }

    var calls: [Call] = []
    /// First sample of every delivered buffer.
    var firstSamples: [Float] = []
    /// Called after each buffer was recorded.
    var onBuffer: ((AudioSource) -> Void)?
    var finishExpectation: XCTestExpectation?

    func audioSource(_ source: AudioSource, didBeginSegmentWith format: AVAudioFormat) {
        calls.append(.begin(sampleRate: format.sampleRate, channelCount: format.channelCount))
    }

    func audioSource(_ source: AudioSource, didProduce buffer: AVAudioPCMBuffer, framePosition: AVAudioFramePosition) {
        calls.append(.buffer(
            framePosition: framePosition,
            frameLength: buffer.frameLength,
            channelCount: buffer.format.channelCount
        ))
        if let first = MonoDownmix.samples(of: buffer).first {
            firstSamples.append(first)
        }
        onBuffer?(source)
    }

    func audioSource(_ source: AudioSource, didInterruptWith reason: AudioInterruptionReason) {
        calls.append(.interruption)
    }

    func audioSource(_ source: AudioSource, didFailWith error: Error) {
        calls.append(.failure)
    }

    func audioSourceDidFinish(_ source: AudioSource) {
        calls.append(.finish)
        finishExpectation?.fulfill()
    }
}

private struct UnexpectedWriterFormat: Error {}

/// Reads generated 16 kHz stereo WAV files (left 0.5, right 0.25) and checks the
/// segment protocol of `FileAudioSource`.
final class FileAudioSourceTests: XCTestCase {
    private var createdFiles: [URL] = []

    override func tearDown() {
        for url in createdFiles {
            try? FileManager.default.removeItem(at: url)
        }
        createdFiles = []
        super.tearDown()
    }

    func testDeliversWholeFileAsOneMonoSegment() throws {
        let url = try makeStereoWAV(frameCount: 4500)
        let queue = DispatchQueue(label: "test.file-source")
        let source = FileAudioSource(fileURL: url, callbackQueue: queue, chunkFrames: 1000)
        let spy = SourceSpy()
        spy.finishExpectation = expectation(description: "finish")
        source.delegate = spy

        try source.start()
        waitForExpectations(timeout: 5)
        // A second finish would be queued before this block.
        queue.sync { }

        let calls = queue.sync { spy.calls }
        XCTAssertEqual(calls.first, .begin(sampleRate: 16_000, channelCount: 1))
        XCTAssertEqual(calls.last, .finish)
        XCTAssertEqual(calls.filter { $0 == .finish }.count, 1)
        XCTAssertFalse(calls.contains(.failure))

        var expectedPosition: AVAudioFramePosition = 0
        var bufferCount = 0
        for call in calls {
            guard case let .buffer(framePosition, frameLength, channelCount) = call else {
                continue
            }
            bufferCount += 1
            XCTAssertEqual(framePosition, expectedPosition)
            XCTAssertGreaterThan(frameLength, 0)
            XCTAssertLessThanOrEqual(frameLength, 1000)
            XCTAssertEqual(channelCount, 1)
            expectedPosition += AVAudioFramePosition(frameLength)
        }
        XCTAssertGreaterThanOrEqual(bufferCount, 5)
        XCTAssertEqual(expectedPosition, 4500)

        // Mean of 0.5 and 0.25, within 16-bit quantization.
        let firstSamples = queue.sync { spy.firstSamples }
        XCTAssertEqual(firstSamples.count, bufferCount)
        for sample in firstSamples {
            XCTAssertEqual(sample, 0.375, accuracy: 0.001)
        }
    }

    func testStopInsideCallbackEndsDeliveryWithoutFinish() throws {
        let url = try makeStereoWAV(frameCount: 4500)
        let queue = DispatchQueue(label: "test.file-source")
        let source = FileAudioSource(fileURL: url, callbackQueue: queue, chunkFrames: 1000)
        let spy = SourceSpy()
        let firstBuffer = expectation(description: "first buffer")
        spy.onBuffer = { source in
            // On the callback queue: stops at once, without waiting for the queue.
            source.stop()
            firstBuffer.fulfill()
        }
        source.delegate = spy

        try source.start()
        waitForExpectations(timeout: 5)
        // Runs the chunk that was scheduled before the stop took effect, and anything after it.
        queue.sync { }
        queue.sync { }

        let calls = queue.sync { spy.calls }
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.first, .begin(sampleRate: 16_000, channelCount: 1))
        guard case let .buffer(framePosition, _, channelCount)? = calls.last else {
            XCTFail("Expected one buffer after the begin, got \(calls)")
            return
        }
        XCTAssertEqual(framePosition, 0)
        XCTAssertEqual(channelCount, 1)
    }

    func testNothingIsDeliveredAfterStopReturns() throws {
        let url = try makeStereoWAV(frameCount: 48_000)
        let queue = DispatchQueue(label: "test.file-source")
        let source = FileAudioSource(fileURL: url, callbackQueue: queue, chunkFrames: 100)
        let spy = SourceSpy()
        source.delegate = spy

        try source.start()
        source.stop()
        let callsAtStop = queue.sync { spy.calls }
        queue.sync { }
        queue.sync { }

        let callsAfterwards = queue.sync { spy.calls }
        XCTAssertEqual(callsAfterwards, callsAtStop)
    }

    func testMissingFileThrowsAndDeliversNothing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-source-missing-\(UUID().uuidString).wav")
        let queue = DispatchQueue(label: "test.file-source")
        let source = FileAudioSource(fileURL: url, callbackQueue: queue)
        let spy = SourceSpy()
        source.delegate = spy

        XCTAssertThrowsError(try source.start()) { error in
            guard let sourceError = error as? FileAudioSourceError, case .cannotOpen = sourceError else {
                XCTFail("Unexpected error \(error)")
                return
            }
        }
        queue.sync { }
        XCTAssertTrue(queue.sync { spy.calls }.isEmpty)
    }

    // MARK: - Helpers

    /// Writes a 16-bit stereo WAV at 16 kHz with `frameCount` frames: left 0.5, right 0.25.
    private func makeStereoWAV(frameCount: AVAudioFrameCount) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-source-test-\(UUID().uuidString).wav")
        createdFiles.append(url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        // The writer is released at the end of the pool, which closes the file.
        try autoreleasepool {
            let writer = try AVAudioFile(forWriting: url, settings: settings)
            let format = writer.processingFormat
            guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved, format.channelCount == 2 else {
                throw UnexpectedWriterFormat()
            }
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
            let channels = try XCTUnwrap(buffer.floatChannelData)
            for frame in 0..<Int(frameCount) {
                channels[0][frame] = 0.5
                channels[1][frame] = 0.25
            }
            buffer.frameLength = frameCount
            try writer.write(from: buffer)
        }
        return url
    }
}
