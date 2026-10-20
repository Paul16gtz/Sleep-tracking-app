import XCTest
@testable import SleepTracker

final class NightStatisticsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)

    private func event(_ type: SoundEventType, at offset: TimeInterval, length: TimeInterval) -> EventSummary {
        EventSummary(
            type: type,
            start: t0.addingTimeInterval(offset),
            end: t0.addingTimeInterval(offset + length)
        )
    }

    func testSnoringDurationAndPercentage() {
        let eightHours: TimeInterval = 8 * 3600
        let events = [
            event(.snoring, at: 600, length: 1800),
            event(.snoring, at: 7200, length: 1800)
        ]

        let stats = NightStatistics.compute(
            start: t0,
            end: t0.addingTimeInterval(eightHours),
            now: t0.addingTimeInterval(eightHours + 100),
            events: events,
            epochs: [],
            gaps: []
        )

        XCTAssertEqual(stats.duration, eightHours, accuracy: 0.0001)
        XCTAssertEqual(stats.snoringDuration, 3600, accuracy: 0.0001)
        XCTAssertEqual(stats.snoringPercentage, 12.5, accuracy: 0.0001)
        XCTAssertEqual(stats.snoringCount, 2)
    }

    func testCountsByType() {
        let events = [
            event(.speech, at: 10, length: 5),
            event(.cough, at: 20, length: 2),
            event(.speech, at: 30, length: 5),
            event(.whispering, at: 40, length: 3),
            event(.speech, at: 50, length: 5),
            event(.whispering, at: 60, length: 3)
        ]

        let stats = NightStatistics.compute(
            start: t0,
            end: t0.addingTimeInterval(3600),
            now: t0.addingTimeInterval(3600),
            events: events,
            epochs: [],
            gaps: []
        )

        XCTAssertEqual(stats.speechCount, 3)
        XCTAssertEqual(stats.coughCount, 1)
        XCTAssertEqual(stats.whisperingCount, 2)
        XCTAssertEqual(stats.snoringCount, 0)
        XCTAssertEqual(stats.snoringDuration, 0, accuracy: 0.0001)
    }

    func testRestlessPhases() {
        // Time order: F, T, T, F, T, F, F, T, T, T -> 6 restless epochs in 3 phases.
        let flags = [false, true, true, false, true, false, false, true, true, true]
        let ordered = flags.enumerated().map { index, restless in
            EpochSummary(timestamp: t0.addingTimeInterval(Double(index) * 30), isRestless: restless)
        }
        // Handed over in scrambled order: compute must sort by timestamp itself.
        // Read as given, this order is T,F,T,F,T,F,F,T,T,T (4 runs); only the sorted
        // order has 3 runs, so a missing sort inside compute fails this test.
        let scrambledIndices = [1, 3, 2, 0, 4, 5, 6, 7, 8, 9]
        let scrambled = scrambledIndices.map { ordered[$0] }

        let stats = NightStatistics.compute(
            start: t0,
            end: t0.addingTimeInterval(300),
            now: t0.addingTimeInterval(300),
            events: [],
            epochs: scrambled,
            gaps: []
        )

        XCTAssertEqual(stats.totalEpochCount, 10)
        XCTAssertEqual(stats.restlessEpochCount, 6)
        XCTAssertEqual(stats.restlessPercentage, 60.0, accuracy: 0.0001)
        XCTAssertEqual(stats.restlessPhaseCount, 3)
    }

    func testOpenSessionUsesNow() {
        let stats = NightStatistics.compute(
            start: t0,
            end: nil,
            now: t0.addingTimeInterval(3600),
            events: [],
            epochs: [],
            gaps: []
        )

        XCTAssertEqual(stats.duration, 3600, accuracy: 0.0001)
    }

    func testZeroDurationYieldsZeroPercentages() {
        let events = [event(.snoring, at: 0, length: 10)]

        let stats = NightStatistics.compute(
            start: t0,
            end: t0,
            now: t0,
            events: events,
            epochs: [],
            gaps: []
        )

        XCTAssertEqual(stats.duration, 0, accuracy: 0.0001)
        XCTAssertEqual(stats.snoringDuration, 10, accuracy: 0.0001)
        XCTAssertEqual(stats.snoringPercentage, 0, accuracy: 0.0001)
        XCTAssertEqual(stats.restlessPercentage, 0, accuracy: 0.0001)
        XCTAssertFalse(stats.snoringPercentage.isNaN)
        XCTAssertFalse(stats.restlessPercentage.isNaN)
        XCTAssertEqual(stats.totalEpochCount, 0)
        XCTAssertEqual(stats.restlessPhaseCount, 0)
    }

    func testInterruptionCount() {
        let gaps = [
            InterruptionGap(start: 100, end: 160, reason: "began"),
            InterruptionGap(start: 500, end: nil, reason: "began")
        ]

        let stats = NightStatistics.compute(
            start: t0,
            end: t0.addingTimeInterval(3600),
            now: t0.addingTimeInterval(3600),
            events: [],
            epochs: [],
            gaps: gaps
        )

        XCTAssertEqual(stats.interruptionCount, 2)
    }
}
