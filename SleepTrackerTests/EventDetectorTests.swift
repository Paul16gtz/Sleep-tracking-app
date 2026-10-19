import XCTest
@testable import SleepTracker

final class EventDetectorTests: XCTestCase {
    /// Event A from the standard sequence: hits at 0 s (0.9) and 0.75 s (0.8), last hit window ends at 2.25 s.
    private let eventA = DetectedEvent(
        type: .snoring,
        start: 0,
        end: 2.25,
        maxConfidence: 0.9,
        averageConfidence: 0.85
    )

    // MARK: - Single-type detection

    func testSingleOutlierDoesNotStartEvent() {
        var detector = EventDetector(config: makeConfig())

        XCTAssertEqual(detector.process(w(0, 0.9)), [])
        XCTAssertEqual(detector.process(w(0.75, 0.1)), [])
        XCTAssertEqual(detector.process(w(1.5, 0.1)), [])
    }

    func testTwoConsecutiveHitsStartEvent() {
        var detector = EventDetector(config: makeConfig())

        XCTAssertEqual(detector.process(w(0, 0.9)), [])
        XCTAssertEqual(
            detector.process(w(0.75, 0.8)),
            [.eventStarted(type: .snoring, start: 0, detectedAt: 2.25)]
        )
    }

    func testThresholdIsInclusive() {
        var atThreshold = EventDetector(config: makeConfig())
        XCTAssertEqual(atThreshold.process(w(0, 0.6)), [])
        XCTAssertEqual(
            atThreshold.process(w(0.75, 0.6)),
            [.eventStarted(type: .snoring, start: 0, detectedAt: 2.25)]
        )

        var belowThreshold = EventDetector(config: makeConfig())
        XCTAssertEqual(belowThreshold.process(w(0, 0.59)), [])
        XCTAssertEqual(belowThreshold.process(w(0.75, 0.59)), [])
    }

    func testEventEndsAfterEndGap() {
        var detector = EventDetector(config: makeConfig())

        XCTAssertEqual(detector.process(w(0, 0.9)), [])
        XCTAssertEqual(
            detector.process(w(0.75, 0.8)),
            [.eventStarted(type: .snoring, start: 0, detectedAt: 2.25)]
        )
        for start in [1.5, 2.25, 3.0, 3.75, 4.5] {
            XCTAssertEqual(detector.process(w(start, 0.1)), [], "miss at \(start)")
        }
        // Window end 6.75 >= last hit end 2.25 + end gap 4.
        XCTAssertEqual(
            detector.process(w(5.25, 0.1)),
            [.eventEnded(type: .snoring, end: 2.25)]
        )
    }

    func testShortGapKeepsEventActive() {
        var detector = EventDetector(config: makeConfig())

        XCTAssertEqual(detector.process(w(0, 0.9)), [])
        XCTAssertEqual(
            detector.process(w(0.75, 0.8)),
            [.eventStarted(type: .snoring, start: 0, detectedAt: 2.25)]
        )
        XCTAssertEqual(detector.process(w(1.5, 0.1)), [])
        XCTAssertEqual(detector.process(w(2.25, 0.1)), [])
        XCTAssertEqual(detector.process(w(3.0, 0.7)), [])

        assertOutputs(detector.finish(at: 10), [
            .eventEnded(type: .snoring, end: 4.5),
            .eventFinalized(DetectedEvent(
                type: .snoring,
                start: 0,
                end: 4.5,
                maxConfidence: 0.9,
                averageConfidence: 0.8
            ))
        ])
    }

    // MARK: - Pending and merging

    func testEventFinalizedAfterMergeGap() {
        var detector = EventDetector(config: makeConfig())
        runEventAUntilEnded(&detector)

        // Window start 12.0 < event end 2.25 + merge gap 10.
        XCTAssertEqual(detector.process(w(12.0, 0.1)), [])
        // Window start 12.75 >= 12.25.
        assertOutputs(detector.process(w(12.75, 0.1)), [.eventFinalized(eventA)])
        XCTAssertEqual(detector.finish(at: 20), [])
    }

    func testEventsWithinMergeGapAreMerged() {
        var detector = EventDetector(config: makeConfig())
        runEventAUntilEnded(&detector)

        XCTAssertEqual(detector.process(w(8.25, 0.7)), [])
        XCTAssertEqual(detector.process(w(9.0, 0.7)), [.eventResumed(type: .snoring)])

        assertOutputs(detector.finish(at: 30), [
            .eventEnded(type: .snoring, end: 10.5),
            .eventFinalized(DetectedEvent(
                type: .snoring,
                start: 0,
                end: 10.5,
                maxConfidence: 0.9,
                averageConfidence: (0.9 + 0.8 + 0.7 + 0.7) / 4
            ))
        ])
    }

    func testEventsBeyondMergeGapStaySeparate() {
        var detector = EventDetector(config: makeConfig())
        runEventAUntilEnded(&detector)

        // Expiry of A comes first, then the window starts a new candidate.
        assertOutputs(detector.process(w(13.5, 0.9)), [.eventFinalized(eventA)])
        XCTAssertEqual(
            detector.process(w(14.25, 0.9)),
            [.eventStarted(type: .snoring, start: 13.5, detectedAt: 15.75)]
        )
    }

    func testResumeRequiresMinConsecutiveWindows() {
        var detector = EventDetector(config: makeConfig())
        runEventAUntilEnded(&detector)

        var outputs: [DetectorOutput] = []
        outputs += detector.process(w(8.25, 0.95))
        for start in [9.0, 9.75, 10.5, 11.25, 12.0, 12.75] {
            outputs += detector.process(w(start, 0.1))
        }

        XCTAssertFalse(outputs.contains(.eventResumed(type: .snoring)))
        // The lone hit at 8.25 is not part of the event: end and statistics stay those of A.
        assertOutputs(outputs, [.eventFinalized(eventA)])
    }

    // MARK: - Maximum duration

    func testMaxDurationSplitsEvent() {
        var detector = EventDetector(config: makeConfig(maxEventDuration: 3.0))

        XCTAssertEqual(detector.process(w(0, 0.9)), [])
        XCTAssertEqual(
            detector.process(w(0.75, 0.8)),
            [.eventStarted(type: .snoring, start: 0, detectedAt: 2.25)]
        )
        assertOutputs(detector.process(w(1.5, 0.7)), [
            .eventEnded(type: .snoring, end: 3.0),
            .eventFinalized(DetectedEvent(
                type: .snoring,
                start: 0,
                end: 3.0,
                maxConfidence: 0.9,
                averageConfidence: 0.8
            )),
            .eventStarted(type: .snoring, start: 3.0, detectedAt: 3.0)
        ])
        XCTAssertEqual(detector.process(w(2.25, 0.65)), [])

        // The second part carries the confidence of the splitting window (0.7).
        assertOutputs(detector.finish(at: 10), [
            .eventEnded(type: .snoring, end: 3.75),
            .eventFinalized(DetectedEvent(
                type: .snoring,
                start: 3.0,
                end: 3.75,
                maxConfidence: 0.7,
                averageConfidence: 0.675
            ))
        ])
    }

    // MARK: - Finish

    func testFinishFinalizesActiveEvent() {
        var detector = EventDetector(config: makeConfig())

        XCTAssertEqual(detector.process(w(0, 0.9)), [])
        XCTAssertEqual(
            detector.process(w(0.75, 0.8)),
            [.eventStarted(type: .snoring, start: 0, detectedAt: 2.25)]
        )

        assertOutputs(detector.finish(at: 5), [
            .eventEnded(type: .snoring, end: 2.25),
            .eventFinalized(eventA)
        ])
    }

    func testFinishFinalizesPendingEvent() {
        var detector = EventDetector(config: makeConfig())
        runEventAUntilEnded(&detector)

        assertOutputs(detector.finish(at: 7), [.eventFinalized(eventA)])
    }

    func testFinishDropsCandidate() {
        var detector = EventDetector(config: makeConfig())

        XCTAssertEqual(detector.process(w(0, 0.9)), [])
        XCTAssertEqual(detector.finish(at: 5), [])
    }

    // MARK: - Configuration and robustness

    func testWindowsBeforeCountingStartAreIgnored() {
        var detector = EventDetector(config: makeConfig(countingStart: 10))

        XCTAssertEqual(detector.process(w(0, 0.9)), [])
        XCTAssertEqual(detector.process(w(0.75, 0.9)), [])
        XCTAssertEqual(detector.process(w(1.5, 0.9)), [])

        XCTAssertEqual(detector.process(w(10.0, 0.9)), [])
        XCTAssertEqual(
            detector.process(w(10.75, 0.9)),
            [.eventStarted(type: .snoring, start: 10.0, detectedAt: 12.25)]
        )
    }

    func testTypesAreIndependentAndOrdered() {
        var detector = EventDetector(config: makeConfig())
        let both: [SoundEventType: Double] = [.speech: 0.9, .snoring: 0.9]

        XCTAssertEqual(
            detector.process(ClassificationWindow(start: 0, end: 1.5, confidences: both)),
            []
        )
        XCTAssertEqual(
            detector.process(ClassificationWindow(start: 0.75, end: 2.25, confidences: both)),
            [
                .eventStarted(type: .snoring, start: 0, detectedAt: 2.25),
                .eventStarted(type: .speech, start: 0, detectedAt: 2.25)
            ]
        )

        // Only snoring hits; speech keeps its own last hit end.
        XCTAssertEqual(detector.process(w(1.5, 0.9, .snoring)), [])
        assertOutputs(detector.finish(at: 10), [
            .eventEnded(type: .snoring, end: 3.0),
            .eventFinalized(DetectedEvent(
                type: .snoring,
                start: 0,
                end: 3.0,
                maxConfidence: 0.9,
                averageConfidence: 0.9
            )),
            .eventEnded(type: .speech, end: 2.25),
            .eventFinalized(DetectedEvent(
                type: .speech,
                start: 0,
                end: 2.25,
                maxConfidence: 0.9,
                averageConfidence: 0.9
            ))
        ])
    }

    func testMissingThresholdNeverHits() {
        var detector = EventDetector(config: DetectorConfig(thresholds: [.snoring: 0.6]))

        XCTAssertEqual(detector.process(w(0, 0.99, .speech)), [])
        XCTAssertEqual(detector.process(w(0.75, 0.99, .speech)), [])
        XCTAssertEqual(detector.finish(at: 5), [])
    }

    func testWindowOutOfOrderDoesNotCrash() {
        var detector = EventDetector(config: makeConfig())

        XCTAssertEqual(detector.process(w(0, 0.9)), [])
        XCTAssertEqual(
            detector.process(w(0.75, 0.9)),
            [.eventStarted(type: .snoring, start: 0, detectedAt: 2.25)]
        )
        XCTAssertEqual(detector.process(w(0.5, 0.9)), [])
        XCTAssertEqual(detector.process(w(0.2, 0.9)), [])

        // Windows without time progress stay hits of the active event; its end never moves backwards.
        assertOutputs(detector.finish(at: 10), [
            .eventEnded(type: .snoring, end: 2.25),
            .eventFinalized(DetectedEvent(
                type: .snoring,
                start: 0,
                end: 2.25,
                maxConfidence: 0.9,
                averageConfidence: 0.9
            ))
        ])
    }

    func testSingleRequiredWindowStartsAndResumesImmediately() {
        var config = makeConfig()
        config.minConsecutiveWindows = 1
        var detector = EventDetector(config: config)

        XCTAssertEqual(
            detector.process(w(0, 0.9)),
            [.eventStarted(type: .snoring, start: 0, detectedAt: 1.5)]
        )
        XCTAssertEqual(
            detector.process(w(4.5, 0.1)),
            [.eventEnded(type: .snoring, end: 1.5)]
        )
        XCTAssertEqual(detector.process(w(6.0, 0.7)), [.eventResumed(type: .snoring)])

        assertOutputs(detector.finish(at: 10), [
            .eventEnded(type: .snoring, end: 7.5),
            .eventFinalized(DetectedEvent(
                type: .snoring,
                start: 0,
                end: 7.5,
                maxConfidence: 0.9,
                averageConfidence: 0.8
            ))
        ])
    }

    func testConfigFromSettingsCoversAllTypes() {
        var settings = AppSettings()
        settings.setThreshold(0.7, for: .cough)
        settings.minConsecutiveWindows = 3
        settings.eventEndGap = 5
        settings.mergeGap = 12
        settings.maxEventDuration = 300

        let config = DetectorConfig(settings: settings, countingStart: 900)

        XCTAssertEqual(
            config,
            DetectorConfig(
                thresholds: [.snoring: 0.6, .speech: 0.6, .cough: 0.7, .whispering: 0.6],
                minConsecutiveWindows: 3,
                endGap: 5,
                mergeGap: 12,
                maxEventDuration: 300,
                countingStart: 900
            )
        )
    }

    // MARK: - Helpers

    /// A 1.5 s classifier window starting at `start` with one confidence for `type`.
    private func w(_ start: Double, _ conf: Double, _ type: SoundEventType = .snoring) -> ClassificationWindow {
        ClassificationWindow(start: start, end: start + 1.5, confidences: [type: conf])
    }

    /// Standard configuration: threshold 0.6 for every type, 2 windows, end gap 4 s, merge gap 10 s.
    private func makeConfig(
        maxEventDuration: TimeInterval = 600,
        countingStart: TimeInterval = 0
    ) -> DetectorConfig {
        DetectorConfig(
            thresholds: Dictionary(uniqueKeysWithValues: SoundEventType.allCases.map { ($0, 0.6) }),
            minConsecutiveWindows: 2,
            endGap: 4,
            mergeGap: 10,
            maxEventDuration: maxEventDuration,
            countingStart: countingStart
        )
    }

    /// Feeds event A and misses until it ends at 2.25 s (window 5.25 s); afterwards A is pending.
    private func runEventAUntilEnded(
        _ detector: inout EventDetector,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(detector.process(w(0, 0.9)), [], file: file, line: line)
        XCTAssertEqual(
            detector.process(w(0.75, 0.8)),
            [.eventStarted(type: .snoring, start: 0, detectedAt: 2.25)],
            file: file,
            line: line
        )
        for start in [1.5, 2.25, 3.0, 3.75, 4.5] {
            XCTAssertEqual(detector.process(w(start, 0.1)), [], "miss at \(start)", file: file, line: line)
        }
        XCTAssertEqual(
            detector.process(w(5.25, 0.1)),
            [.eventEnded(type: .snoring, end: 2.25)],
            file: file,
            line: line
        )
    }

    /// Compares outputs element by element. Finalized events are destructured: `averageConfidence`
    /// is compared with an accuracy of 1e-9, every other field exactly.
    private func assertOutputs(
        _ actual: [DetectorOutput],
        _ expected: [DetectorOutput],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard actual.count == expected.count else {
            XCTFail("Expected \(expected), got \(actual)", file: file, line: line)
            return
        }
        for (got, want) in zip(actual, expected) {
            guard case let .eventFinalized(wantEvent) = want, case let .eventFinalized(gotEvent) = got else {
                XCTAssertEqual(got, want, file: file, line: line)
                continue
            }
            XCTAssertEqual(gotEvent.type, wantEvent.type, file: file, line: line)
            XCTAssertEqual(gotEvent.start, wantEvent.start, file: file, line: line)
            XCTAssertEqual(gotEvent.end, wantEvent.end, file: file, line: line)
            XCTAssertEqual(gotEvent.maxConfidence, wantEvent.maxConfidence, file: file, line: line)
            XCTAssertEqual(
                gotEvent.averageConfidence,
                wantEvent.averageConfidence,
                accuracy: 1e-9,
                file: file,
                line: line
            )
        }
    }
}
