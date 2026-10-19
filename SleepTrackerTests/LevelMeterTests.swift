import XCTest
@testable import SleepTracker

final class LevelMeterTests: XCTestCase {
    func testEmptyIsFloor() {
        XCTAssertEqual(LevelMeter.rmsDecibels([]), -120)
    }

    func testSilenceIsFloor() {
        let samples = [Float](repeating: 0, count: 1000)

        XCTAssertEqual(LevelMeter.rmsDecibels(samples), -120)
    }

    func testConstantHalfIsMinusSix() {
        let samples = [Float](repeating: 0.5, count: 1000)

        XCTAssertEqual(LevelMeter.rmsDecibels(samples), -6.02, accuracy: 0.01)
    }

    func testFullScaleSineIsMinusThree() {
        var samples = [Float]()
        samples.reserveCapacity(4800)
        for i in 0..<4800 {
            let phase = 2.0 * Double.pi * Double(i) * 100.0 / 4800.0
            samples.append(Float(sin(phase)))
        }

        XCTAssertEqual(LevelMeter.rmsDecibels(samples), -3.01, accuracy: 0.05)
    }

    func testNonFiniteSamplesAreTreatedAsSilence() {
        XCTAssertEqual(LevelMeter.rmsDecibels([Float.nan, Float.infinity, 0, 0]), -120)

        let value = LevelMeter.rmsDecibels([Float.nan, 0.5, 0.5, 0.5])
        XCTAssertTrue(value.isFinite)
        XCTAssertGreaterThan(value, -7)
        XCTAssertLessThan(value, -5)
    }

    func testThrottle() {
        var throttle = LevelThrottle(minInterval: 0.2)

        XCTAssertTrue(throttle.shouldEmit(at: 0))
        XCTAssertFalse(throttle.shouldEmit(at: 0.1))
        XCTAssertTrue(throttle.shouldEmit(at: 0.2))
        XCTAssertFalse(throttle.shouldEmit(at: 0.35))
        XCTAssertTrue(throttle.shouldEmit(at: 0.4))
    }
}
