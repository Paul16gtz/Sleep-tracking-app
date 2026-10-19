import XCTest
@testable import SleepTracker

final class ClipPolicyTests: XCTestCase {
    func testSpeechAllowedUpToLimit() {
        var policy = ClipPolicy(
            config: ClipPolicy.Config(perEventLimit: 2, snoringLimit: 20, snoringMinInterval: 600)
        )

        XCTAssertTrue(policy.shouldRecordClip(for: .speech, at: 0))
        XCTAssertTrue(policy.shouldRecordClip(for: .speech, at: 10))
        XCTAssertFalse(policy.shouldRecordClip(for: .speech, at: 20))
        XCTAssertEqual(policy.clipCount(for: .speech), 2)
    }

    func testCoughAndWhisperingUsePerEventRuleWithOwnCounters() {
        var policy = ClipPolicy(
            config: ClipPolicy.Config(perEventLimit: 1, snoringLimit: 20, snoringMinInterval: 600)
        )

        XCTAssertTrue(policy.shouldRecordClip(for: .cough, at: 0))
        XCTAssertTrue(policy.shouldRecordClip(for: .whispering, at: 1))
        XCTAssertFalse(policy.shouldRecordClip(for: .cough, at: 2))
    }

    func testSnoringRespectsMinInterval() {
        var policy = ClipPolicy(
            config: ClipPolicy.Config(perEventLimit: 50, snoringLimit: 20, snoringMinInterval: 600)
        )

        XCTAssertTrue(policy.shouldRecordClip(for: .snoring, at: 0))
        XCTAssertFalse(policy.shouldRecordClip(for: .snoring, at: 300))
        XCTAssertFalse(policy.shouldRecordClip(for: .snoring, at: 599))
        XCTAssertTrue(policy.shouldRecordClip(for: .snoring, at: 600))
        XCTAssertTrue(policy.shouldRecordClip(for: .snoring, at: 1200))
    }

    func testSnoringRespectsLimit() {
        var policy = ClipPolicy(
            config: ClipPolicy.Config(perEventLimit: 50, snoringLimit: 2, snoringMinInterval: 0)
        )

        XCTAssertTrue(policy.shouldRecordClip(for: .snoring, at: 0))
        XCTAssertTrue(policy.shouldRecordClip(for: .snoring, at: 1))
        XCTAssertFalse(policy.shouldRecordClip(for: .snoring, at: 2))
    }

    // A denied request must not move the interval timer: the last clip time stays 0 until 600.
    func testDeniedSnoringDoesNotResetInterval() {
        var policy = ClipPolicy(
            config: ClipPolicy.Config(perEventLimit: 50, snoringLimit: 20, snoringMinInterval: 600)
        )

        XCTAssertTrue(policy.shouldRecordClip(for: .snoring, at: 0))
        XCTAssertFalse(policy.shouldRecordClip(for: .snoring, at: 300))
        XCTAssertTrue(policy.shouldRecordClip(for: .snoring, at: 600))
    }
}
