import XCTest
@testable import SleepTracker

/// Builds `n` silent samples.
private func z(_ n: Int) -> [Float] {
    [Float](repeating: 0, count: n)
}

/// Pre-roll 5 s, post-roll 5 s, max 60 s at 10 Hz:
/// pre-roll = 50 samples, post-roll = 50 samples, cap = 600 samples.
final class ClipRecorderTests: XCTestCase {
    private func makeRecorder() -> ClipRecorder {
        ClipRecorder(preRoll: 5, postRoll: 5, maxDuration: 60, sampleRate: 10)
    }

    func testPreRollSampleCount() {
        let recorder = makeRecorder()

        XCTAssertEqual(recorder.preRollSampleCount(eventStart: 10, now: 12), 70)
        XCTAssertEqual(recorder.preRollSampleCount(eventStart: 10, now: 9), 50)
    }

    func testBeginEmitsOpenAndPreRoll() {
        var recorder = makeRecorder()

        let actions = recorder.begin(type: .speech, eventStart: 10, preRollSamples: z(70))

        XCTAssertEqual(actions, [.open(type: .speech, clipStart: 5), .write(z(70))])
        XCTAssertTrue(recorder.isActive)

        var early = makeRecorder()
        let earlyActions = early.begin(type: .speech, eventStart: 2, preRollSamples: z(70))
        XCTAssertEqual(earlyActions, [.open(type: .speech, clipStart: 0), .write(z(70))])
    }

    func testBeginWhileActiveIsIgnored() {
        var recorder = makeRecorder()
        _ = recorder.begin(type: .speech, eventStart: 10, preRollSamples: z(70))

        let second = recorder.begin(type: .cough, eventStart: 20, preRollSamples: z(70))

        XCTAssertEqual(second, [])
        XCTAssertTrue(recorder.isActive)
    }

    func testAppendWhileActiveWrites() {
        var recorder = makeRecorder()

        XCTAssertEqual(recorder.append(z(20)), [])

        _ = recorder.begin(type: .speech, eventStart: 10, preRollSamples: z(70))

        XCTAssertEqual(recorder.append(z(20)), [.write(z(20))])
    }

    func testPostRollClosesAfterPostRollSamples() {
        var recorder = makeRecorder()
        _ = recorder.begin(type: .speech, eventStart: 10, preRollSamples: z(70))

        XCTAssertEqual(recorder.eventEnded(), [])
        XCTAssertEqual(recorder.append(z(30)), [.write(z(30))])
        XCTAssertEqual(recorder.append(z(30)), [.write(z(20)), .close])
        XCTAssertFalse(recorder.isActive)
        XCTAssertEqual(recorder.append(z(5)), [])
    }

    func testMaxDurationTruncates() {
        var recorder = makeRecorder()
        _ = recorder.begin(type: .speech, eventStart: 10, preRollSamples: z(70))

        let actions = recorder.append(z(600))

        XCTAssertEqual(actions, [.write(z(530)), .close])
        XCTAssertFalse(recorder.isActive)
    }

    func testEventResumedCancelsPostRoll() {
        var recorder = makeRecorder()
        _ = recorder.begin(type: .speech, eventStart: 10, preRollSamples: z(70))

        XCTAssertEqual(recorder.eventEnded(), [])
        XCTAssertEqual(recorder.append(z(30)), [.write(z(30))])
        recorder.eventResumed()

        XCTAssertEqual(recorder.append(z(100)), [.write(z(100))])
        XCTAssertTrue(recorder.isActive)
    }

    func testFinishClosesActiveClip() {
        var recorder = makeRecorder()
        _ = recorder.begin(type: .speech, eventStart: 10, preRollSamples: z(70))

        XCTAssertEqual(recorder.finish(), [.close])
        XCTAssertFalse(recorder.isActive)
        XCTAssertEqual(recorder.finish(), [])
    }

    func testPreRollLargerThanMaxIsTruncated() {
        var recorder = makeRecorder()

        let actions = recorder.begin(type: .speech, eventStart: 10, preRollSamples: z(700))

        XCTAssertEqual(actions, [.open(type: .speech, clipStart: 5), .write(z(600)), .close])
        XCTAssertFalse(recorder.isActive)
    }

    func testBeginAfterCloseStartsFreshClip() {
        var recorder = makeRecorder()
        _ = recorder.begin(type: .speech, eventStart: 10, preRollSamples: z(70))
        _ = recorder.eventEnded()
        XCTAssertEqual(recorder.append(z(50)), [.write(z(50)), .close])

        let actions = recorder.begin(type: .cough, eventStart: 30, preRollSamples: z(70))

        XCTAssertEqual(actions, [.open(type: .cough, clipStart: 25), .write(z(70))])
        // Neither the earlier post-roll budget nor the earlier sample count may carry over.
        XCTAssertEqual(recorder.append(z(100)), [.write(z(100))])
        XCTAssertEqual(recorder.append(z(430)), [.write(z(430)), .close])
    }

    func testEmptyAppendWhileActiveEmitsNothing() {
        var recorder = makeRecorder()
        _ = recorder.begin(type: .speech, eventStart: 10, preRollSamples: z(70))

        XCTAssertEqual(recorder.append([]), [])
        XCTAssertTrue(recorder.isActive)
    }
}
