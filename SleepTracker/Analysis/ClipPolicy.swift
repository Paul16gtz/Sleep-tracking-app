import Foundation

/// Decides, per detected event start, whether an audio clip may be recorded.
///
/// Speech, cough and whispering each get a clip per event up to `perEventLimit` per night
/// (separate counter per type). Snoring can last for hours, so its clips are rate-limited by
/// `snoringMinInterval` and capped at `snoringLimit` per night.
struct ClipPolicy {
    struct Config: Equatable {
        /// Clips per night for each of speech, cough and whispering (counted per type).
        var perEventLimit: Int
        /// Snoring clips per night.
        var snoringLimit: Int
        /// Minimum time between the starts of two snoring clips.
        var snoringMinInterval: TimeInterval

        init(perEventLimit: Int, snoringLimit: Int, snoringMinInterval: TimeInterval) {
            self.perEventLimit = perEventLimit
            self.snoringLimit = snoringLimit
            self.snoringMinInterval = snoringMinInterval
        }

        /// Builds the configuration from the user settings.
        init(settings: AppSettings) {
            self.init(
                perEventLimit: settings.speechClipLimitPerNight,
                snoringLimit: settings.snoringClipLimitPerNight,
                snoringMinInterval: settings.snoringClipMinInterval
            )
        }
    }

    private let config: Config
    private var counts: [SoundEventType: Int] = [:]
    private var lastSnoringClipTime: TimeInterval?

    init(config: Config) {
        self.config = config
    }

    /// Asks whether a clip may be opened for a new event of `type` starting at `time`
    /// (seconds since session start). A `true` answer consumes one unit of the night's budget
    /// and, for snoring, restarts the interval timer. A `false` answer changes nothing.
    mutating func shouldRecordClip(for type: SoundEventType, at time: TimeInterval) -> Bool {
        let count = clipCount(for: type)

        switch type {
        case .snoring:
            guard count < config.snoringLimit else { return false }
            if let last = lastSnoringClipTime, time - last < config.snoringMinInterval {
                return false
            }
            lastSnoringClipTime = time
        case .speech, .cough, .whispering:
            guard count < config.perEventLimit else { return false }
        }

        counts[type] = count + 1
        return true
    }

    /// Number of clips granted so far for `type`; 0 for a type that was never granted a clip.
    func clipCount(for type: SoundEventType) -> Int {
        counts[type] ?? 0
    }
}
