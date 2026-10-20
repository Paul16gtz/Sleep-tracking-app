import XCTest
@testable import SleepTracker

final class MotionTests: XCTestCase {
    // MARK: - MotionEpochAggregator

    func testConstantMagnitudeHasZeroIntensity() {
        var aggregator = MotionEpochAggregator()

        var completed: [RawMotionEpoch] = []
        for second in 0...31 {
            completed += aggregator.add(magnitude: 1.0, at: TimeInterval(second))
        }

        XCTAssertEqual(completed, [RawMotionEpoch(index: 0, start: 0, intensity: 0)])
    }

    func testDeviationAccumulates() {
        var aggregator = MotionEpochAggregator(epochDuration: 30, highPassAlpha: 0.5)

        XCTAssertTrue(aggregator.add(magnitude: 1.0, at: 0).isEmpty)
        XCTAssertTrue(aggregator.add(magnitude: 2.0, at: 1).isEmpty)
        XCTAssertTrue(aggregator.add(magnitude: 1.0, at: 2).isEmpty)

        let completed = aggregator.add(magnitude: 1.25, at: 31)
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.index, 0)
        XCTAssertEqual(completed.first?.start, 0)
        // Deviations 0 (first sample), 1.0 and 0.5.
        XCTAssertEqual(completed.first?.intensity ?? .nan, 1.5, accuracy: 1e-9)
    }

    func testAggregatorFinishFlushes() {
        var aggregator = MotionEpochAggregator()

        XCTAssertTrue(aggregator.add(magnitude: 1.0, at: 1).isEmpty)

        XCTAssertEqual(
            aggregator.finish(),
            RawMotionEpoch(index: 0, start: 0, intensity: 0)
        )
        XCTAssertNil(aggregator.finish())
    }

    // MARK: - MotionBaselineCalibrator

    func testCalibratorUsesMedianAfterEnoughEpochs() {
        var calibrator = MotionBaselineCalibrator(
            calibrationDuration: 90,
            epochDuration: 30,
            minimumBaseline: 0.01
        )

        calibrator.add(RawMotionEpoch(index: 0, start: 0, intensity: 1))
        calibrator.add(RawMotionEpoch(index: 1, start: 30, intensity: 5))
        XCTAssertFalse(calibrator.isCalibrated)
        XCTAssertNil(calibrator.baseline)

        calibrator.add(RawMotionEpoch(index: 2, start: 60, intensity: 2))
        XCTAssertTrue(calibrator.isCalibrated)
        XCTAssertEqual(calibrator.baseline, 2)
    }

    func testCalibratorAppliesMinimum() {
        var calibrator = MotionBaselineCalibrator(
            calibrationDuration: 90,
            epochDuration: 30,
            minimumBaseline: 0.01
        )

        calibrator.add(RawMotionEpoch(index: 0, start: 0, intensity: 0))
        calibrator.add(RawMotionEpoch(index: 1, start: 30, intensity: 0))
        calibrator.add(RawMotionEpoch(index: 2, start: 60, intensity: 0))

        XCTAssertEqual(calibrator.baseline, 0.01)
    }

    func testCalibratorMedianOfEvenCount() {
        var calibrator = MotionBaselineCalibrator(
            calibrationDuration: 60,
            epochDuration: 30,
            minimumBaseline: 0.01
        )

        calibrator.add(RawMotionEpoch(index: 0, start: 0, intensity: 1))
        calibrator.add(RawMotionEpoch(index: 1, start: 30, intensity: 3))

        XCTAssertEqual(calibrator.baseline, 2)
    }

    // MARK: - MotionAnalyzer

    func testAnalyzerFlagsRestlessAfterCalibration() {
        var config = MotionConfig()
        config.calibrationDuration = 60
        config.epochDuration = 30
        config.restlessFactor = 3
        config.highPassAlpha = 1.0
        var analyzer = MotionAnalyzer(config: config)
        XCTAssertNil(analyzer.baseline)

        // With alpha 1.0 the deviation is the difference to the previous sample. Each
        // epoch holds 0 at 30k, x at 30k + 1 and 0 at 30k + 2, so its intensity is 2x.
        let jumps: [Double] = [0.5, 0.5, 5, 1]
        var epochs: [MotionEpoch] = []
        for (k, jump) in jumps.enumerated() {
            let base = TimeInterval(k) * 30
            epochs += analyzer.add(magnitude: 0, at: base)
            epochs += analyzer.add(magnitude: jump, at: base + 1)
            epochs += analyzer.add(magnitude: 0, at: base + 2)
        }
        if let last = analyzer.finish() {
            epochs.append(last)
        }

        XCTAssertEqual(epochs.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(epochs.map(\.start), [0, 30, 60, 90])
        XCTAssertEqual(epochs.map(\.intensity), [1, 1, 10, 2])
        XCTAssertEqual(epochs.map(\.isRestless), [false, false, true, false])
        XCTAssertEqual(analyzer.baseline, 1)
    }

    // Additional cases beyond the brief: epoch boundaries, gaps, clock jumps,
    // non-finite inputs, the calibration edge and the flush path of the analyzer.

    func testAggregatorBoundaryBelongsToNextEpoch() {
        var aggregator = MotionEpochAggregator()

        XCTAssertTrue(aggregator.add(magnitude: 1.0, at: 29.9).isEmpty)

        let completed = aggregator.add(magnitude: 2.0, at: 30)
        XCTAssertEqual(completed, [RawMotionEpoch(index: 0, start: 0, intensity: 0)])

        // The sample at exactly 30 s opened epoch 1 and deviates by 1.0 from the first one.
        XCTAssertEqual(
            aggregator.finish(),
            RawMotionEpoch(index: 1, start: 30, intensity: 1)
        )
    }

    func testAggregatorSkipsEmptyEpochs() {
        var aggregator = MotionEpochAggregator()

        XCTAssertTrue(aggregator.add(magnitude: 1.0, at: 1).isEmpty)

        let completed = aggregator.add(magnitude: 1.0, at: 95)
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.index, 0)

        let last = aggregator.finish()
        XCTAssertEqual(last?.index, 3)
        XCTAssertEqual(last?.start, 90)
    }

    func testAggregatorTimeGoingBackwardsStaysInCurrentEpoch() {
        var aggregator = MotionEpochAggregator(epochDuration: 30, highPassAlpha: 0.5)

        XCTAssertTrue(aggregator.add(magnitude: 1.0, at: 65).isEmpty)
        XCTAssertTrue(aggregator.add(magnitude: 3.0, at: 55).isEmpty)

        let last = aggregator.finish()
        XCTAssertEqual(last?.index, 2)
        XCTAssertEqual(last?.start, 60)
        XCTAssertEqual(last?.intensity ?? .nan, 2, accuracy: 1e-9)
    }

    func testAggregatorNonFiniteInputsAreSanitized() {
        var aggregator = MotionEpochAggregator(epochDuration: 30, highPassAlpha: 0.5)

        // A non-finite magnitude counts as no deviation and does not seed the average.
        XCTAssertTrue(aggregator.add(magnitude: Double.nan, at: 1).isEmpty)
        XCTAssertTrue(aggregator.add(magnitude: 1.0, at: 2).isEmpty)
        // A non-finite time counts as being in the current epoch.
        XCTAssertTrue(aggregator.add(magnitude: 3.0, at: Double.infinity).isEmpty)
        XCTAssertTrue(aggregator.add(magnitude: Double.infinity, at: 4).isEmpty)

        let last = aggregator.finish()
        XCTAssertEqual(last?.index, 0)
        XCTAssertEqual(last?.intensity ?? .nan, 2, accuracy: 1e-9)
    }

    func testCalibratorIgnoresEpochsAfterCalibration() {
        var calibrator = MotionBaselineCalibrator(
            calibrationDuration: 60,
            epochDuration: 30,
            minimumBaseline: 0.01
        )

        calibrator.add(RawMotionEpoch(index: 0, start: 0, intensity: 1))
        calibrator.add(RawMotionEpoch(index: 1, start: 30, intensity: 3))
        calibrator.add(RawMotionEpoch(index: 2, start: 60, intensity: 100))
        calibrator.add(RawMotionEpoch(index: 3, start: 90, intensity: 100))

        XCTAssertEqual(calibrator.baseline, 2)
    }

    func testCalibratorNeedsAtLeastOneEpoch() {
        var calibrator = MotionBaselineCalibrator(
            calibrationDuration: 10,
            epochDuration: 30,
            minimumBaseline: 0.01
        )

        calibrator.add(RawMotionEpoch(index: 0, start: 0, intensity: 4))

        XCTAssertEqual(calibrator.baseline, 4)
    }

    func testAnalyzerFinishAppliesRestlessRule() {
        var config = MotionConfig()
        config.calibrationDuration = 60
        config.highPassAlpha = 1.0
        var analyzer = MotionAnalyzer(config: config)

        // Epochs 0 and 1 have intensity 1 (baseline 1); epoch 2 has intensity 10.
        var epochs: [MotionEpoch] = []
        for (k, jump) in [0.5, 0.5, 5.0].enumerated() {
            let base = TimeInterval(k) * 30
            epochs += analyzer.add(magnitude: 0, at: base)
            epochs += analyzer.add(magnitude: jump, at: base + 1)
            epochs += analyzer.add(magnitude: 0, at: base + 2)
        }
        XCTAssertEqual(epochs.map(\.isRestless), [false, false])

        let flushed = analyzer.finish()
        XCTAssertEqual(
            flushed,
            MotionEpoch(index: 2, start: 60, intensity: 10, isRestless: true)
        )
        XCTAssertNil(analyzer.finish())
    }

    func testAnalyzerNeverFlagsCalibrationEpochs() {
        // A factor below 1 would flag the last calibration epoch if it were judged
        // against the baseline it has just produced.
        var config = MotionConfig()
        config.calibrationDuration = 30
        config.restlessFactor = 0.5
        config.highPassAlpha = 1.0
        var analyzer = MotionAnalyzer(config: config)

        var epochs: [MotionEpoch] = []
        for k in 0..<2 {
            let base = TimeInterval(k) * 30
            epochs += analyzer.add(magnitude: 0, at: base)
            epochs += analyzer.add(magnitude: 5, at: base + 1)
            epochs += analyzer.add(magnitude: 0, at: base + 2)
        }
        if let last = analyzer.finish() {
            epochs.append(last)
        }

        XCTAssertEqual(epochs.map(\.intensity), [10, 10])
        XCTAssertEqual(epochs.map(\.isRestless), [false, true])
        XCTAssertEqual(analyzer.baseline, 10)
    }

    // MARK: - MotionConfig

    func testConfigTakesRestlessFactorAndCalibrationFromSettings() {
        var settings = AppSettings()
        settings.restlessFactor = 4.5
        settings.motionCalibrationDuration = 120

        var expected = MotionConfig()
        expected.restlessFactor = 4.5
        expected.calibrationDuration = 120

        XCTAssertEqual(MotionConfig(settings: settings), expected)
        XCTAssertEqual(MotionConfig(settings: AppSettings()), MotionConfig())
    }

    func testConfigDefaults() {
        let config = MotionConfig()

        XCTAssertEqual(config.epochDuration, 30)
        XCTAssertEqual(config.calibrationDuration, 300)
        XCTAssertEqual(config.restlessFactor, 3.0)
        XCTAssertEqual(config.highPassAlpha, 0.05)
        XCTAssertEqual(config.minimumBaseline, 0.01)
    }
}
