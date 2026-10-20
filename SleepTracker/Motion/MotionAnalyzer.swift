import Foundation

/// Movement of one epoch of the night, judged against the calibrated baseline.
struct MotionEpoch: Equatable {
    /// Zero-based epoch number: `floor(time / epochDuration)`.
    let index: Int
    /// Start of the epoch in seconds since session start: `index * epochDuration`.
    let start: TimeInterval
    /// Sum of the high-pass deviations of all samples in the epoch.
    let intensity: Double
    /// True when the intensity exceeds the baseline times the restless factor.
    /// Always false for the epochs that make up the calibration phase.
    let isRestless: Bool
}

/// Parameters of the motion analysis.
struct MotionConfig: Equatable {
    var epochDuration: TimeInterval = 30
    var calibrationDuration: TimeInterval = 300
    var restlessFactor: Double = 3.0
    var highPassAlpha: Double = 0.05
    var minimumBaseline: Double = 0.01

    /// Takes the restless factor and the calibration duration from the user
    /// settings; everything else keeps its default.
    init(settings: AppSettings) {
        restlessFactor = settings.restlessFactor
        calibrationDuration = settings.motionCalibrationDuration
    }

    /// All values at their defaults.
    init() {}
}

/// Pure motion pipeline: accelerometer magnitudes in, restlessness per 30 s epoch out.
///
/// Magnitudes are aggregated to epoch intensities, the first epochs calibrate the
/// resting baseline, and every later epoch is flagged restless when its intensity
/// exceeds `baseline * restlessFactor`.
struct MotionAnalyzer {
    private var aggregator: MotionEpochAggregator
    private var calibrator: MotionBaselineCalibrator
    private let restlessFactor: Double

    /// Creates an analyzer. A non-finite `restlessFactor` falls back to 3.0.
    init(config: MotionConfig) {
        aggregator = MotionEpochAggregator(
            epochDuration: config.epochDuration,
            highPassAlpha: config.highPassAlpha
        )
        calibrator = MotionBaselineCalibrator(
            calibrationDuration: config.calibrationDuration,
            epochDuration: config.epochDuration,
            minimumBaseline: config.minimumBaseline
        )
        restlessFactor = config.restlessFactor.isFinite ? config.restlessFactor : 3.0
    }

    /// Resting level; `nil` while the calibration phase is still running.
    var baseline: Double? { calibrator.baseline }

    /// Adds one acceleration magnitude (in g) measured at `time` (seconds since
    /// session start) and returns the epochs it completed, oldest first.
    mutating func add(magnitude: Double, at time: TimeInterval) -> [MotionEpoch] {
        var judged: [MotionEpoch] = []
        for raw in aggregator.add(magnitude: magnitude, at: time) {
            judged.append(judge(raw))
        }
        return judged
    }

    /// Flushes the epoch in progress, judged by the same rule as every other epoch.
    /// Returns `nil` if nothing was added since the last flush.
    mutating func finish() -> MotionEpoch? {
        guard let raw = aggregator.finish() else { return nil }
        return judge(raw)
    }

    /// Feeds the epoch to the calibrator and decides whether it is restless. The
    /// decision uses the calibration state from before this epoch, so an epoch that
    /// takes part in the calibration is never restless.
    private mutating func judge(_ raw: RawMotionEpoch) -> MotionEpoch {
        let wasCalibrated = calibrator.isCalibrated
        calibrator.add(raw)

        var isRestless = false
        if wasCalibrated, let baseline = calibrator.baseline {
            isRestless = raw.intensity > baseline * restlessFactor
        }
        return MotionEpoch(
            index: raw.index,
            start: raw.start,
            intensity: raw.intensity,
            isRestless: isRestless
        )
    }
}
