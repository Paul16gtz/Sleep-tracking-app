import XCTest
@testable import SleepTracker

final class EpochMergerTests: XCTestCase {
    private func level(_ index: Int, average: Double = -42, peak: Double = -30) -> LevelEpoch {
        LevelEpoch(index: index, start: Double(index) * 30, averageDecibels: average, peakDecibels: peak)
    }

    private func motion(_ index: Int, intensity: Double = 0.8, isRestless: Bool = true) -> MotionEpoch {
        MotionEpoch(index: index, start: Double(index) * 30, intensity: intensity, isRestless: isRestless)
    }

    func testEmitsWhenBothHalvesPresent() {
        var merger = EpochMerger(expectsMotion: true)

        XCTAssertEqual(merger.add(level: level(0)), [])

        XCTAssertEqual(
            merger.add(motion: motion(0)),
            [EpochRecord(index: 0, start: 0, averageDecibels: -42, peakDecibels: -30, motionIntensity: 0.8, isRestless: true)]
        )
    }

    func testOrderIndependent() {
        var merger = EpochMerger(expectsMotion: true)

        XCTAssertEqual(merger.add(motion: motion(0, intensity: 0.3, isRestless: false)), [])

        XCTAssertEqual(
            merger.add(level: level(0, average: -50, peak: -35)),
            [EpochRecord(index: 0, start: 0, averageDecibels: -50, peakDecibels: -35, motionIntensity: 0.3, isRestless: false)]
        )
    }

    func testWithoutMotionEmitsImmediately() {
        var merger = EpochMerger(expectsMotion: false)

        XCTAssertEqual(
            merger.add(level: level(0)),
            [EpochRecord(index: 0, start: 0, averageDecibels: -42, peakDecibels: -30, motionIntensity: 0, isRestless: false)]
        )
    }

    func testFlushesLaggingLevelEntries() {
        var merger = EpochMerger(expectsMotion: true, lagTolerance: 1)

        XCTAssertEqual(merger.add(level: level(0)), [])
        XCTAssertEqual(merger.add(level: level(1, average: -45, peak: -33)), [])

        XCTAssertEqual(
            merger.add(level: level(2)),
            [EpochRecord(index: 0, start: 0, averageDecibels: -42, peakDecibels: -30, motionIntensity: 0, isRestless: false)]
        )
        XCTAssertEqual(
            merger.add(motion: motion(1)),
            [EpochRecord(index: 1, start: 30, averageDecibels: -45, peakDecibels: -33, motionIntensity: 0.8, isRestless: true)]
        )
    }

    func testFinishFlushesAllSorted() {
        var merger = EpochMerger(expectsMotion: true)

        XCTAssertEqual(merger.add(level: level(3)), [])
        XCTAssertEqual(merger.add(motion: motion(1)), [])

        XCTAssertEqual(
            merger.finish(),
            [
                EpochRecord(
                    index: 1,
                    start: 30,
                    averageDecibels: LevelMeter.silenceFloor,
                    peakDecibels: LevelMeter.silenceFloor,
                    motionIntensity: 0.8,
                    isRestless: true
                ),
                EpochRecord(index: 3, start: 90, averageDecibels: -42, peakDecibels: -30, motionIntensity: 0, isRestless: false),
            ]
        )
    }
}
