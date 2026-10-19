import XCTest
@testable import SleepTracker

final class LevelEpochAggregatorTests: XCTestCase {
    func testAverageAndPeakWithinEpoch() {
        var aggregator = LevelEpochAggregator()

        let first = aggregator.add(decibels: -40, at: 1)
        let second = aggregator.add(decibels: -20, at: 2)
        let third = aggregator.add(decibels: -60, at: 3)
        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)
        XCTAssertTrue(third.isEmpty)

        let completed = aggregator.add(decibels: -50, at: 31)
        XCTAssertEqual(
            completed,
            [LevelEpoch(index: 0, start: 0, averageDecibels: -40, peakDecibels: -20)]
        )
    }

    func testSkipsEmptyEpochs() {
        var aggregator = LevelEpochAggregator()

        let first = aggregator.add(decibels: -40, at: 1)
        XCTAssertTrue(first.isEmpty)

        let completed = aggregator.add(decibels: -40, at: 95)
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.index, 0)

        let last = aggregator.finish()
        XCTAssertEqual(last?.index, 3)
        XCTAssertEqual(last?.start, 90)
    }

    func testBoundaryBelongsToNextEpoch() {
        var aggregator = LevelEpochAggregator()

        let first = aggregator.add(decibels: -40, at: 29.9)
        XCTAssertTrue(first.isEmpty)

        let completed = aggregator.add(decibels: -30, at: 30)
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.index, 0)
        XCTAssertEqual(completed.first?.averageDecibels, -40)

        let last = aggregator.finish()
        XCTAssertEqual(last?.index, 1)
        XCTAssertEqual(last?.averageDecibels, -30)
    }

    func testFinishFlushesOnce() {
        var aggregator = LevelEpochAggregator()

        let completed = aggregator.add(decibels: -40, at: 1)
        XCTAssertTrue(completed.isEmpty)

        XCTAssertEqual(
            aggregator.finish(),
            LevelEpoch(index: 0, start: 0, averageDecibels: -40, peakDecibels: -40)
        )
        XCTAssertNil(aggregator.finish())
    }

    func testTimeGoingBackwardsStaysInCurrentEpoch() {
        var aggregator = LevelEpochAggregator()

        let first = aggregator.add(decibels: -40, at: 50)
        let second = aggregator.add(decibels: -20, at: 45)
        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)

        let last = aggregator.finish()
        XCTAssertEqual(last?.index, 1)
        XCTAssertEqual(last?.averageDecibels, -30)
        XCTAssertEqual(last?.peakDecibels, -20)
    }

    // Additional cases beyond the brief: the clamp must also hold when the earlier
    // timestamp falls into a previous epoch, and non-finite inputs must not poison
    // an epoch or trap in the Double-to-Int conversion.

    func testTimeGoingBackwardsAcrossBoundaryClampsToCurrentEpoch() {
        var aggregator = LevelEpochAggregator()

        let first = aggregator.add(decibels: -40, at: 65)
        let second = aggregator.add(decibels: -20, at: 55)
        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)

        let last = aggregator.finish()
        XCTAssertEqual(last?.index, 2)
        XCTAssertEqual(last?.start, 60)
        XCTAssertEqual(last?.averageDecibels, -30)
        XCTAssertEqual(last?.peakDecibels, -20)
    }

    func testNonFiniteInputsAreSanitized() {
        var aggregator = LevelEpochAggregator()

        let first = aggregator.add(decibels: Double.nan, at: 1)
        let second = aggregator.add(decibels: -60, at: Double.infinity)
        XCTAssertTrue(first.isEmpty)
        XCTAssertTrue(second.isEmpty)

        let last = aggregator.finish()
        XCTAssertEqual(last?.index, 0)
        XCTAssertEqual(last?.averageDecibels, -90)
        XCTAssertEqual(last?.peakDecibels, -60)
    }
}
