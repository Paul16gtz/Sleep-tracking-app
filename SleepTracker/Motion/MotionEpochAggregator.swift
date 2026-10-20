import Foundation

/// Movement summary of one fixed-length slice of the night, before it is judged
/// against the calibrated baseline.
struct RawMotionEpoch: Equatable {
    /// Zero-based epoch number: `floor(time / epochDuration)`.
    let index: Int
    /// Start of the epoch in seconds since session start: `index * epochDuration`.
    let start: TimeInterval
    /// Sum of the high-pass deviations of all samples in the epoch.
    let intensity: Double
}

/// Turns accelerometer magnitudes into movement intensities per fixed-length epoch.
///
/// Each magnitude is compared with a slow exponential moving average (the baseline
/// of the signal, e.g. gravity), which acts as a high-pass filter. The deviation of
/// a sample is its absolute distance from that average; the intensity of an epoch
/// is the sum of the deviations of its samples.
///
/// Epochs are keyed by stream time (seconds since session start) like
/// `LevelEpochAggregator`: an epoch is complete when a sample arrives whose time
/// falls into a later epoch, epochs without samples are never emitted, and time
/// that jumps backwards is counted in the current epoch.
struct MotionEpochAggregator {
    /// Length of one epoch in seconds. Always greater than zero.
    let epochDuration: TimeInterval
    /// Smoothing factor of the moving average, in `0...1`. Higher values follow
    /// the signal faster and therefore yield smaller deviations.
    let highPassAlpha: Double

    /// Upper bound for the epoch index, keeping the Double-to-Int conversion safe.
    private static let maxEpochIndex: Double = 1_000_000_000_000

    private var currentIndex: Int
    private var sum: Double
    private var count: Int
    private var ema: Double?

    /// Creates an empty aggregator. A non-positive or non-finite `epochDuration`
    /// falls back to the 30 s default, a non-finite `highPassAlpha` to 0.05; other
    /// alpha values are limited to `0...1`.
    init(epochDuration: TimeInterval = 30, highPassAlpha: Double = 0.05) {
        if epochDuration.isFinite && epochDuration > 0 {
            self.epochDuration = epochDuration
        } else {
            self.epochDuration = 30
        }
        if highPassAlpha.isFinite {
            self.highPassAlpha = min(max(highPassAlpha, 0), 1)
        } else {
            self.highPassAlpha = 0.05
        }
        self.currentIndex = 0
        self.sum = 0
        self.count = 0
        self.ema = nil
    }

    /// Adds one acceleration magnitude (in g) measured at `time` (seconds since
    /// session start).
    ///
    /// Returns the epochs completed by this call: empty while `time` stays in the
    /// current epoch, otherwise the finished current epoch (if it holds any sample).
    /// A non-finite `magnitude` counts as a sample without deviation and leaves the
    /// moving average untouched; a non-finite `time` counts as being in the
    /// current epoch.
    mutating func add(magnitude: Double, at time: TimeInterval) -> [RawMotionEpoch] {
        let index = epochIndex(for: time)

        var completed: [RawMotionEpoch] = []
        if index > currentIndex {
            if let epoch = makeEpoch() {
                completed.append(epoch)
            }
            sum = 0
            count = 0
            currentIndex = index
        }

        let step = deviation(of: magnitude)
        sum += step
        count += 1
        return completed
    }

    /// Flushes the epoch in progress. Returns `nil` if nothing was added since the
    /// last flush, so calling it repeatedly yields the epoch only once.
    mutating func finish() -> RawMotionEpoch? {
        guard let epoch = makeEpoch() else { return nil }
        sum = 0
        count = 0
        return epoch
    }

    /// Deviation of `magnitude` from the moving average, which is then updated.
    /// The first finite sample seeds the average and deviates by zero.
    private mutating func deviation(of magnitude: Double) -> Double {
        guard magnitude.isFinite else { return 0 }
        guard let average = ema else {
            ema = magnitude
            return 0
        }
        let difference = magnitude - average
        ema = average + highPassAlpha * difference
        return abs(difference)
    }

    /// Epoch index for `time`, never lower than the current one.
    private func epochIndex(for time: TimeInterval) -> Int {
        guard time.isFinite else { return currentIndex }
        let raw = floor(time / epochDuration)
        let bounded = min(max(raw, 0), MotionEpochAggregator.maxEpochIndex)
        return max(Int(bounded), currentIndex)
    }

    /// Summary of the samples collected so far, or `nil` if there are none.
    private func makeEpoch() -> RawMotionEpoch? {
        guard count > 0 else { return nil }
        return RawMotionEpoch(
            index: currentIndex,
            start: Double(currentIndex) * epochDuration,
            intensity: sum
        )
    }
}
