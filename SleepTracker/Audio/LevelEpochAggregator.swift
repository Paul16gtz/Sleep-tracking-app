import Foundation

/// Loudness summary of one fixed-length slice of the night.
struct LevelEpoch: Equatable {
    /// Zero-based epoch number: `floor(time / epochDuration)`.
    let index: Int
    /// Start of the epoch in seconds since session start: `index * epochDuration`.
    let start: TimeInterval
    /// Arithmetic mean of the dB values added to the epoch (not a power-domain mean).
    let averageDecibels: Double
    /// Highest dB value added to the epoch.
    let peakDecibels: Double
}

/// Groups dB values into fixed-length epochs keyed by stream time (seconds since
/// session start) and emits each epoch once it is complete.
///
/// An epoch is complete when a value arrives whose time falls into a later epoch.
/// Epochs that received no values are never emitted. Time may jump backwards a
/// little (e.g. after an audio-interruption restart); such a value is counted in
/// the current epoch instead of reopening an earlier one.
struct LevelEpochAggregator {
    /// Length of one epoch in seconds. Always greater than zero.
    let epochDuration: TimeInterval

    /// Upper bound for the epoch index, keeping the Double-to-Int conversion safe.
    private static let maxEpochIndex: Double = 1_000_000_000_000

    private var currentIndex: Int
    private var sum: Double
    private var count: Int
    private var peak: Double

    /// Creates an empty aggregator. A non-positive or non-finite `epochDuration`
    /// falls back to the 30 s default.
    init(epochDuration: TimeInterval = 30) {
        if epochDuration.isFinite && epochDuration > 0 {
            self.epochDuration = epochDuration
        } else {
            self.epochDuration = 30
        }
        self.currentIndex = 0
        self.sum = 0
        self.count = 0
        self.peak = LevelMeter.silenceFloor
    }

    /// Adds one dB value measured at `time` (seconds since session start).
    ///
    /// Returns the epochs completed by this call: empty while `time` stays in the
    /// current epoch, otherwise the finished current epoch (if it holds any value).
    /// A non-finite `decibels` counts as `LevelMeter.silenceFloor`; a non-finite
    /// `time` counts as being in the current epoch.
    mutating func add(decibels: Double, at time: TimeInterval) -> [LevelEpoch] {
        let value = decibels.isFinite ? decibels : LevelMeter.silenceFloor
        let index = epochIndex(for: time)

        var completed: [LevelEpoch] = []
        if index > currentIndex {
            if let epoch = makeEpoch() {
                completed.append(epoch)
            }
            sum = 0
            count = 0
            currentIndex = index
        }

        sum += value
        peak = count == 0 ? value : max(peak, value)
        count += 1
        return completed
    }

    /// Flushes the epoch in progress. Returns `nil` if nothing was added since the
    /// last flush, so calling it repeatedly yields the epoch only once.
    mutating func finish() -> LevelEpoch? {
        guard let epoch = makeEpoch() else { return nil }
        sum = 0
        count = 0
        return epoch
    }

    /// Epoch index for `time`, never lower than the current one.
    private func epochIndex(for time: TimeInterval) -> Int {
        guard time.isFinite else { return currentIndex }
        let raw = floor(time / epochDuration)
        let bounded = min(max(raw, 0), LevelEpochAggregator.maxEpochIndex)
        return max(Int(bounded), currentIndex)
    }

    /// Summary of the values collected so far, or `nil` if there are none.
    private func makeEpoch() -> LevelEpoch? {
        guard count > 0 else { return nil }
        return LevelEpoch(
            index: currentIndex,
            start: Double(currentIndex) * epochDuration,
            averageDecibels: sum / Double(count),
            peakDecibels: peak
        )
    }
}
