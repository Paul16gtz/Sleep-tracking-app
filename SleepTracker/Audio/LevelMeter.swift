import Foundation

/// Computes the loudness of an audio buffer as RMS in dBFS.
enum LevelMeter {
    /// Lowest value ever returned. Used for silence and for empty input.
    static let silenceFloor: Double = -120

    /// Root-mean-square level of `samples` in dBFS: `20 * log10(rms)`, never below
    /// `silenceFloor`. Full scale (amplitude 1.0) is 0 dBFS, so a full-scale sine
    /// reads about -3.01 dB.
    ///
    /// Empty input and zero energy return `silenceFloor`. Non-finite samples (NaN,
    /// +/-infinity) are ignored, so a single corrupt value cannot poison the result
    /// or the epoch averages built on top of it. A buffer made only of non-finite
    /// samples returns `silenceFloor`.
    static func rmsDecibels(_ samples: [Float]) -> Double {
        var sumOfSquares = 0.0
        var finiteCount = 0
        for sample in samples where sample.isFinite {
            let value = Double(sample)
            sumOfSquares += value * value
            finiteCount += 1
        }
        guard finiteCount > 0 else { return silenceFloor }

        let meanSquare = sumOfSquares / Double(finiteCount)
        guard meanSquare > 0 else { return silenceFloor }

        // 10 * log10(mean square) == 20 * log10(rms)
        return max(10 * log10(meanSquare), silenceFloor)
    }
}

/// Rate limiter for the live level display: lets a value through at most once per
/// `minInterval` seconds of stream time.
struct LevelThrottle {
    /// Minimum stream time between two emitted values, in seconds.
    let minInterval: TimeInterval

    private var lastEmit: TimeInterval?

    init(minInterval: TimeInterval = 0.2) {
        self.minInterval = minInterval
        self.lastEmit = nil
    }

    /// Returns `true` for the first call, then `true` again once at least
    /// `minInterval` seconds have passed since the last time it returned `true`.
    mutating func shouldEmit(at time: TimeInterval) -> Bool {
        if let last = lastEmit, time - last < minInterval {
            return false
        }
        lastEmit = time
        return true
    }
}
