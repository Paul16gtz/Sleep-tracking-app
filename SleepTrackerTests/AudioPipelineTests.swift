import AVFoundation
import XCTest
@testable import SleepTracker

/// Pipeline tests at 100 Hz: every buffer holds 100 samples (1 s), so buffer `k` of a
/// segment ends at `segmentBase + k + 1`. Default settings: threshold 0.6, two hit
/// windows, end gap 4 s, merge gap 10 s, pre-/post-roll 5 s (500 samples), clip max 60 s.
/// The ring buffer holds 10 s (1000 samples).
final class AudioPipelineTests: XCTestCase {
    private let clipPath = "Clips/test/clip.m4a"

    func testLevelEpochAfterThirtySeconds() throws {
        let harness = try makeHarness()
        harness.beginSegment(at: 0)

        // Buffers end at 1 ... 31 s; the one ending at 30 s opens epoch 1.
        harness.pushBuffers(31)

        XCTAssertEqual(harness.spy.epochs.count, 1)
        let epoch = try XCTUnwrap(harness.spy.epochs.first)
        XCTAssertEqual(epoch.index, 0)
        // 20 * log10(0.5) = -6.0206
        XCTAssertEqual(epoch.averageDecibels, -6.02, accuracy: 0.05)
        XCTAssertEqual(epoch.peakDecibels, epoch.averageDecibels, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(harness.spy.levels.count, 1)
        XCTAssertLessThanOrEqual(harness.spy.levels.count, 31)
        XCTAssertEqual(harness.clipWriter.preparedSampleRate, 100)
        XCTAssertEqual(harness.classifier.analyzedFrameCount, 3100)
        XCTAssertEqual(harness.factoryLog.timeOffsets, [0])
        XCTAssertEqual(harness.source.startCount, 1)
    }

    func testEventWithClipFlow() throws {
        let harness = try makeHarness()
        harness.beginSegment(at: 0)
        harness.pushBuffers(1)

        harness.emit(w(0, [.speech: 0.9]))
        harness.emit(w(0.75, [.speech: 0.9]))

        XCTAssertEqual(harness.spy.startedEvents, [PipelineSpy.StartedEvent(type: .speech, start: 0)])
        XCTAssertEqual(harness.clipWriter.openedTypes, [.speech])
        // The pre-roll asks for (5 + 2.25) * 100 = 725 samples; the ring buffer holds only 100.
        XCTAssertEqual(harness.clipWriter.writtenSampleCount, 100)

        harness.pushBuffers(3)
        XCTAssertEqual(harness.clipWriter.writtenSampleCount, 400)

        // Misses; the window at 5.25 s ends at 6.75 s >= 2.25 s + 4 s and ends the event.
        for start in [1.5, 2.25, 3.0, 3.75, 4.5, 5.25] {
            harness.emit(w(start))
        }
        XCTAssertEqual(harness.clipWriter.closeCount, 0)

        // Post-roll: 500 more samples, then the clip closes; the last 5 buffers are not written.
        harness.pushBuffers(10)
        XCTAssertEqual(harness.clipWriter.writtenSampleCount, 900)
        XCTAssertEqual(harness.clipWriter.closeCount, 1)
        XCTAssertTrue(harness.spy.finalizedEvents.isEmpty)

        // Window start 12.75 s >= 2.25 s + 10 s merge gap: the pending event is final.
        harness.emit(w(12.75))

        XCTAssertEqual(harness.spy.finalizedEvents.count, 1)
        let finalized = try XCTUnwrap(harness.spy.finalizedEvents.first)
        XCTAssertEqual(finalized.clipRelativePath, clipPath)
        XCTAssertEqual(finalized.event.type, .speech)
        XCTAssertEqual(finalized.event.start, 0)
        XCTAssertEqual(finalized.event.end, 2.25)
        XCTAssertEqual(harness.spy.errors, [])
    }

    func testSnoringClipPolicyApplied() throws {
        let harness = try makeHarness()
        harness.beginSegment(at: 0)
        harness.pushBuffers(1)

        // First snoring event 0 ... 2.25 s, detected at 2.25 s: it gets the clip.
        harness.emit(w(0, [.snoring: 0.9]))
        harness.emit(w(0.75, [.snoring: 0.9]))
        harness.emit(w(5.25))        // ends it: 6.75 s >= 2.25 s + 4 s
        harness.pushBuffers(5)       // the 500-sample post-roll closes the clip
        harness.emit(w(12.75))       // finalizes it: 12.75 s >= 2.25 s + 10 s
        XCTAssertEqual(harness.clipWriter.closeCount, 1)
        XCTAssertEqual(harness.spy.finalizedEvents.count, 1)

        // Second snoring event 20 ... 22.25 s, detected 20 s after the first clip (< 600 s).
        // The recorder is idle, so only the clip policy can refuse the clip.
        harness.emit(w(20, [.snoring: 0.9]))
        harness.emit(w(20.75, [.snoring: 0.9]))
        harness.emit(w(25))          // ends it: 26.5 s >= 22.25 s + 4 s
        harness.emit(w(32.5))        // finalizes it: 32.5 s >= 22.25 s + 10 s

        XCTAssertEqual(harness.clipWriter.openedTypes, [.snoring])
        XCTAssertEqual(
            harness.spy.startedEvents,
            [
                PipelineSpy.StartedEvent(type: .snoring, start: 0),
                PipelineSpy.StartedEvent(type: .snoring, start: 20)
            ]
        )
        let finalized = harness.spy.finalizedEvents
        XCTAssertEqual(finalized.map(\.event.type), [.snoring, .snoring])
        XCTAssertEqual(finalized.map(\.event.start), [0, 20])
        XCTAssertEqual(finalized.map(\.event.end), [2.25, 22.25])
        XCTAssertEqual(finalized.map(\.clipRelativePath), [clipPath, nil])
    }

    func testClipOpenFailureKeepsPipelineRunning() throws {
        let harness = try makeHarness()
        harness.clipWriter.shouldFailOnOpen = true
        harness.beginSegment(at: 0)
        harness.pushBuffers(1)

        harness.emit(w(0, [.speech: 0.9]))
        harness.emit(w(0.75, [.speech: 0.9]))   // event starts; the clip cannot be opened
        harness.pushBuffers(2)
        harness.emit(w(5.25))                   // ends it
        harness.emit(w(12.75))                  // finalizes it

        // A second event runs into the same failure; it is not reported again.
        harness.emit(w(20, [.speech: 0.9]))
        harness.emit(w(20.75, [.speech: 0.9]))

        let levelsBefore = harness.spy.levels.count
        harness.pushBuffers(3)

        XCTAssertEqual(harness.spy.startedEvents.count, 2)
        XCTAssertEqual(harness.spy.finalizedEvents.count, 1)
        let finalized = try XCTUnwrap(harness.spy.finalizedEvents.first)
        XCTAssertEqual(finalized.event.start, 0)
        XCTAssertEqual(finalized.event.end, 2.25)
        XCTAssertNil(finalized.clipRelativePath)
        XCTAssertEqual(harness.spy.errors.count, 1)
        XCTAssertEqual(harness.clipWriter.openedTypes, [])
        XCTAssertEqual(harness.clipWriter.writtenSampleCount, 0)
        XCTAssertEqual(harness.clipWriter.closeCount, 0)
        XCTAssertEqual(harness.spy.levels.count, levelsBefore + 3)
        XCTAssertEqual(harness.classifier.analyzedFrameCount, 600)
    }

    func testInterruptionRecordsGap() throws {
        let harness = try makeHarness()
        harness.beginSegment(at: 0)
        harness.pushBuffers(10)      // the last buffer ends at 10 s

        harness.source.emitInterruption(.systemInterruption)

        XCTAssertEqual(harness.pipeline.gaps, [InterruptionGap(start: 10, end: nil, reason: "systemInterruption")])
        XCTAssertTrue(harness.spy.gaps.isEmpty)
        XCTAssertEqual(harness.classifier.completeCount, 1)

        harness.beginSegment(at: 25)

        let gap = InterruptionGap(start: 10, end: 25, reason: "systemInterruption")
        XCTAssertEqual(harness.spy.gaps, [gap])
        XCTAssertEqual(harness.pipeline.gaps, [gap])
        XCTAssertEqual(harness.factoryLog.timeOffsets, [0, 25])

        // The new segment counts from 25 s: its buffers end at 26, 27, 28, 29 and 30 s,
        // so only the fifth one moves into epoch 1 and completes epoch 0.
        harness.pushBuffers(4)
        XCTAssertTrue(harness.spy.epochs.isEmpty)
        harness.pushBuffers(1)
        XCTAssertEqual(harness.spy.epochs.map(\.index), [0])
    }

    func testFallAsleepDelaySuppressesEvents() throws {
        let harness = try makeHarness(countingStart: 100)
        harness.beginSegment(at: 0)
        harness.pushBuffers(1)

        harness.emit(w(0, [.speech: 0.9]))
        harness.emit(w(0.75, [.speech: 0.9]))

        XCTAssertTrue(harness.spy.startedEvents.isEmpty)
        XCTAssertEqual(harness.clipWriter.openedTypes, [])

        let labels = [RankedLabel(label: "speech", confidence: 0.9)]
        harness.emit(w(100, [.speech: 0.9]))
        harness.emit(w(100.75, [.speech: 0.9]), topLabels: labels)

        XCTAssertEqual(harness.spy.startedEvents, [PipelineSpy.StartedEvent(type: .speech, start: 100)])
        // Top labels are reported for every window, also during the delay; time is the window end.
        XCTAssertEqual(harness.spy.topLabels.map(\.time), [1.5, 2.25, 101.5, 102.25])
        XCTAssertEqual(harness.spy.topLabels.last?.labels, labels)
    }

    func testStopFlushesPartialEpochAndActiveEvent() throws {
        let harness = try makeHarness()
        harness.beginSegment(at: 0)
        harness.pushBuffers(5)
        harness.emit(w(0, [.speech: 0.9]))
        harness.emit(w(0.75, [.speech: 0.9]))
        XCTAssertEqual(harness.clipWriter.openedTypes, [.speech])
        XCTAssertTrue(harness.spy.epochs.isEmpty)
        XCTAssertTrue(harness.spy.finalizedEvents.isEmpty)

        harness.clock.now = 6
        harness.pipeline.stop()

        XCTAssertEqual(harness.source.stopCount, 1)
        XCTAssertEqual(harness.spy.epochs.count, 1)
        let epoch = try XCTUnwrap(harness.spy.epochs.first)
        XCTAssertEqual(epoch.index, 0)
        XCTAssertEqual(epoch.averageDecibels, -6.02, accuracy: 0.05)
        XCTAssertEqual(harness.spy.finalizedEvents.count, 1)
        let finalized = try XCTUnwrap(harness.spy.finalizedEvents.first)
        XCTAssertEqual(finalized.event.type, .speech)
        XCTAssertEqual(finalized.event.start, 0)
        XCTAssertEqual(finalized.event.end, 2.25)
        XCTAssertEqual(finalized.clipRelativePath, clipPath)
        XCTAssertEqual(harness.clipWriter.closeCount, 1)
        // Pre-roll: all 5 buffered seconds (725 samples requested).
        XCTAssertEqual(harness.clipWriter.writtenSampleCount, 500)
        XCTAssertEqual(harness.classifier.completeCount, 1)
        XCTAssertFalse(harness.spy.didFinish)
    }

    func testFinishFromSourceReportsPipelineDidFinish() throws {
        let harness = try makeHarness()
        harness.beginSegment(at: 0)
        harness.pushBuffers(3)

        harness.source.emitFinish()

        XCTAssertTrue(harness.spy.didFinish)
        XCTAssertEqual(harness.spy.epochs.map(\.index), [0])
        XCTAssertEqual(harness.classifier.completeCount, 1)

        // The controller answers with stop(); the session is not finished a second time.
        harness.pipeline.stop()

        XCTAssertEqual(harness.source.stopCount, 1)
        XCTAssertEqual(harness.spy.epochs.count, 1)
        XCTAssertEqual(harness.classifier.completeCount, 1)
    }

    // MARK: - Helpers

    /// A started pipeline at 100 Hz with default settings.
    private func makeHarness(countingStart: TimeInterval = 0) throws -> PipelineHarness {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 100, channels: 1))
        let harness = PipelineHarness(format: format, countingStart: countingStart)
        try harness.pipeline.start()
        return harness
    }

    /// A 1.5 s classifier window starting at `start`; no confidences means a miss for every type.
    private func w(_ start: TimeInterval, _ confidences: [SoundEventType: Double] = [:]) -> ClassificationWindow {
        ClassificationWindow(start: start, end: start + 1.5, confidences: confidences)
    }
}

// MARK: - Test doubles

/// Records every delegate call. The pipeline calls it on its queue while the test
/// thread waits in `callbackQueue.sync` or in `stop()`, so plain arrays are safe.
private final class PipelineSpy: AudioPipelineDelegate {
    struct StartedEvent: Equatable {
        let type: SoundEventType
        let start: TimeInterval
    }

    struct FinalizedEvent: Equatable {
        let event: DetectedEvent
        let clipRelativePath: String?
    }

    struct TopLabels: Equatable {
        let labels: [RankedLabel]
        let time: TimeInterval
    }

    private(set) var levels: [Double] = []
    private(set) var epochs: [LevelEpoch] = []
    private(set) var startedEvents: [StartedEvent] = []
    private(set) var finalizedEvents: [FinalizedEvent] = []
    private(set) var topLabels: [TopLabels] = []
    private(set) var gaps: [InterruptionGap] = []
    private(set) var errors: [String] = []
    private(set) var didFinish = false

    func pipeline(_ pipeline: AudioPipeline, didUpdateLevel decibels: Double) {
        levels.append(decibels)
    }

    func pipeline(_ pipeline: AudioPipeline, didCompleteLevelEpoch epoch: LevelEpoch) {
        epochs.append(epoch)
    }

    func pipeline(_ pipeline: AudioPipeline, didStartEvent type: SoundEventType, at start: TimeInterval) {
        startedEvents.append(StartedEvent(type: type, start: start))
    }

    func pipeline(_ pipeline: AudioPipeline, didFinalizeEvent event: DetectedEvent, clipRelativePath: String?) {
        finalizedEvents.append(FinalizedEvent(event: event, clipRelativePath: clipRelativePath))
    }

    func pipeline(_ pipeline: AudioPipeline, didProduceTopLabels labels: [RankedLabel], at time: TimeInterval) {
        topLabels.append(TopLabels(labels: labels, time: time))
    }

    func pipeline(_ pipeline: AudioPipeline, didRecordGap gap: InterruptionGap) {
        gaps.append(gap)
    }

    func pipeline(_ pipeline: AudioPipeline, didReportError message: String) {
        errors.append(message)
    }

    func pipelineDidFinish(_ pipeline: AudioPipeline) {
        didFinish = true
    }
}

/// The value the pipeline's `clock` returns, in seconds since session start.
private final class TestClock {
    var now: TimeInterval = 0
}

/// The `timeOffset` of every classifier factory call, one per segment.
private final class FactoryLog {
    var timeOffsets: [TimeInterval] = []
}

/// One pipeline with its fakes. The classifier factory always returns the shared
/// `classifier`; the clock reads `clock.now`.
private final class PipelineHarness {
    let format: AVAudioFormat
    let source: FakeAudioSource
    let clipWriter: FakeClipWriter
    let classifier: FakeSoundClassifier
    let spy: PipelineSpy
    let clock: TestClock
    let factoryLog: FactoryLog
    let pipeline: AudioPipeline

    /// Frame position of the next buffer within the current segment.
    private var framePosition: AVAudioFramePosition = 0

    init(format: AVAudioFormat, countingStart: TimeInterval) {
        let source = FakeAudioSource()
        let clipWriter = FakeClipWriter()
        let classifier = FakeSoundClassifier(timeOffset: 0)
        let spy = PipelineSpy()
        let testClock = TestClock()
        let factoryLog = FactoryLog()
        let config = AudioPipeline.Config(
            settings: AppSettings(),
            countingStart: countingStart,
            ringBufferDuration: 10,
            levelUpdateInterval: 0.2,
            epochDuration: 30,
            sessionStart: Date(timeIntervalSince1970: 0)
        )
        let pipeline = AudioPipeline(
            source: source,
            config: config,
            mapping: LabelMapping(knownLabels: SoundEventType.allCases.map { $0.rawValue }),
            clipWriter: clipWriter,
            classifierFactory: { _, timeOffset in
                factoryLog.timeOffsets.append(timeOffset)
                return classifier
            },
            clock: { testClock.now }
        )
        pipeline.delegate = spy

        self.format = format
        self.source = source
        self.clipWriter = clipWriter
        self.classifier = classifier
        self.spy = spy
        self.clock = testClock
        self.factoryLog = factoryLog
        self.pipeline = pipeline
    }

    /// Begins a new segment at `time`; its frame positions start at 0 again.
    func beginSegment(at time: TimeInterval) {
        clock.now = time
        framePosition = 0
        source.emitSegment(format: format)
    }

    /// Delivers `count` buffers of 100 samples (1 s) with constant `value`.
    func pushBuffers(_ count: Int, value: Float = 0.5) {
        for _ in 0..<count {
            source.emitBuffer(
                samples: [Float](repeating: value, count: 100),
                format: format,
                framePosition: framePosition
            )
            framePosition += 100
        }
    }

    /// Delivers one classifier window on the pipeline's queue, like the real classifier.
    func emit(_ window: ClassificationWindow, topLabels: [RankedLabel] = []) {
        let classifier = self.classifier
        source.callbackQueue.sync {
            classifier.emit(window: window, topLabels: topLabels)
        }
    }
}
