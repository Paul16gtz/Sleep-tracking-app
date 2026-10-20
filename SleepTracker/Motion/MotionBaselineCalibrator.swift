import Foundation

/// Learns the resting movement level from the first epochs of a night.
///
/// The first `calibrationDuration / epochDuration` epochs (at least one) are
/// collected; once they are complete the baseline is the median of their
/// intensities, but never lower than `minimumBaseline` so that a perfectly still
/// phone does not turn every later twitch into restlessness. Epochs added after
/// that are ignored.
struct MotionBaselineCalibrator {
    /// Number of epochs that make up the calibration phase. Always at least 1.
    let requiredEpochCount: Int
    /// Lower bound for the baseline.
    let minimumBaseline: Double

    /// Resting level; `nil` while the calibration epochs are still being collected.
    private(set) var baseline: Double?

    /// Whether the calibration phase is complete.
    var isCalibrated: Bool { baseline != nil }

    /// Upper bound for the epoch count, keeping the Double-to-Int conversion safe.
    private static let maxRequiredEpochCount: Double = 1_000_000

    private var intensities: [Double] = []

    /// Creates a calibrator. A non-finite `calibrationDuration` falls back to 300 s,
    /// a non-positive or non-finite `epochDuration` to 30 s and a negative or
    /// non-finite `minimumBaseline` to 0.01.
    init(
        calibrationDuration: TimeInterval = 300,
        epochDuration: TimeInterval = 30,
        minimumBaseline: Double = 0.01
    ) {
        let duration = calibrationDuration.isFinite ? calibrationDuration : 300
        let epoch = (epochDuration.isFinite && epochDuration > 0) ? epochDuration : 30
        let ratio = floor(duration / epoch)
        let bounded = min(max(ratio, 1), MotionBaselineCalibrator.maxRequiredEpochCount)
        self.requiredEpochCount = Int(bounded)
        self.minimumBaseline = (minimumBaseline.isFinite && minimumBaseline >= 0) ? minimumBaseline : 0.01
    }

    /// Adds one epoch to the calibration. Epochs arriving after the calibration is
    /// complete are ignored. A non-finite intensity counts as 0.
    mutating func add(_ epoch: RawMotionEpoch) {
        guard baseline == nil else { return }
        intensities.append(epoch.intensity.isFinite ? epoch.intensity : 0)
        guard intensities.count >= requiredEpochCount else { return }

        baseline = max(MotionBaselineCalibrator.median(of: intensities), minimumBaseline)
        intensities = []
    }

    /// Median of a non-empty list; the mean of the two middle values for an even count.
    private static func median(of values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[middle]
        }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
}
