import Foundation

/// Loudness and movement of one epoch of the night, as stored in an `EpochSample`.
struct EpochRecord: Equatable {
    /// Zero-based epoch number, shared by the level and the motion epoch.
    let index: Int
    /// Start of the epoch in seconds since session start.
    let start: TimeInterval
    let averageDecibels: Double
    let peakDecibels: Double
    let motionIntensity: Double
    let isRestless: Bool
}

/// Joins the level epochs of the audio pipeline and the motion epochs of the motion
/// analyzer by epoch index and emits one `EpochRecord` per index.
///
/// The two halves of an epoch may arrive in either order. A record is emitted as soon
/// as both halves are there, or at once for a level epoch when no motion is expected.
/// A half whose partner does not come (a motion pause, an audio interruption) is not
/// held forever: once the stream that delivered it is more than `lagTolerance`
/// indices further, it is emitted with defaults for the missing half (dB
/// `LevelMeter.silenceFloor`, motion 0 and not restless). `finish()` emits all such
/// halves that are left. Every index is emitted at most once; a half that arrives
/// after its index was emitted is dropped.
struct EpochMerger {
    /// Whether motion epochs are expected; without, level epochs are emitted at once.
    let expectsMotion: Bool
    /// How many indices a half may lie behind the newest index of its own stream
    /// before it is emitted with defaults. Never negative.
    let lagTolerance: Int

    /// One half of an epoch that is waiting for the other.
    private enum Half {
        case level(LevelEpoch)
        case motion(MotionEpoch)
    }

    private var pending: [Int: Half] = [:]
    /// Indices emitted so far (one `Int` per epoch, about a thousand per night).
    private var emitted: Set<Int> = []
    private var newestLevelIndex: Int?
    private var newestMotionIndex: Int?

    /// Creates an empty merger. A negative `lagTolerance` counts as 0.
    init(expectsMotion: Bool, lagTolerance: Int = 1) {
        self.expectsMotion = expectsMotion
        self.lagTolerance = max(lagTolerance, 0)
    }

    /// Adds a level epoch and returns the records it completed or flushed, by index.
    mutating func add(level: LevelEpoch) -> [EpochRecord] {
        let index = level.index
        newestLevelIndex = max(newestLevelIndex ?? index, index)

        var records: [EpochRecord] = []
        if !emitted.contains(index) {
            if case .motion(let motion)? = pending[index] {
                pending[index] = nil
                records.append(markEmitted(EpochMerger.record(level: level, motion: motion)))
            } else if !expectsMotion {
                pending[index] = nil
                records.append(markEmitted(EpochMerger.record(level: level, motion: nil)))
            } else {
                pending[index] = .level(level)
            }
        }
        records += flushLagging()
        return records.sorted { $0.index < $1.index }
    }

    /// Adds a motion epoch and returns the records it completed or flushed, by index.
    mutating func add(motion: MotionEpoch) -> [EpochRecord] {
        let index = motion.index
        newestMotionIndex = max(newestMotionIndex ?? index, index)

        var records: [EpochRecord] = []
        if !emitted.contains(index) {
            if case .level(let level)? = pending[index] {
                pending[index] = nil
                records.append(markEmitted(EpochMerger.record(level: level, motion: motion)))
            } else {
                pending[index] = .motion(motion)
            }
        }
        records += flushLagging()
        return records.sorted { $0.index < $1.index }
    }

    /// Emits every half that is still waiting, with defaults for its missing half,
    /// sorted by index.
    mutating func finish() -> [EpochRecord] {
        var records: [EpochRecord] = []
        for index in pending.keys.sorted() {
            if let half = pending.removeValue(forKey: index) {
                records.append(markEmitted(EpochMerger.record(for: half)))
            }
        }
        return records
    }

    // MARK: - Private

    /// Removes and returns, by index, every waiting half whose own stream is more than
    /// `lagTolerance` indices further.
    private mutating func flushLagging() -> [EpochRecord] {
        var lagging: [Int] = []
        for (index, half) in pending where isLagging(half, at: index) {
            lagging.append(index)
        }
        var records: [EpochRecord] = []
        for index in lagging.sorted() {
            if let half = pending.removeValue(forKey: index) {
                records.append(markEmitted(EpochMerger.record(for: half)))
            }
        }
        return records
    }

    private func isLagging(_ half: Half, at index: Int) -> Bool {
        let newest: Int?
        switch half {
        case .level:
            newest = newestLevelIndex
        case .motion:
            newest = newestMotionIndex
        }
        guard let newest = newest else { return false }
        // `newest` is at least `index`, so only a huge positive distance can overflow.
        let (distance, overflow) = newest.subtractingReportingOverflow(index)
        return overflow || distance > lagTolerance
    }

    private mutating func markEmitted(_ record: EpochRecord) -> EpochRecord {
        emitted.insert(record.index)
        return record
    }

    private static func record(for half: Half) -> EpochRecord {
        switch half {
        case .level(let level):
            return record(level: level, motion: nil)
        case .motion(let motion):
            return EpochRecord(
                index: motion.index,
                start: motion.start,
                averageDecibels: LevelMeter.silenceFloor,
                peakDecibels: LevelMeter.silenceFloor,
                motionIntensity: motion.intensity,
                isRestless: motion.isRestless
            )
        }
    }

    private static func record(level: LevelEpoch, motion: MotionEpoch?) -> EpochRecord {
        EpochRecord(
            index: level.index,
            start: level.start,
            averageDecibels: level.averageDecibels,
            peakDecibels: level.peakDecibels,
            motionIntensity: motion?.intensity ?? 0,
            isRestless: motion?.isRestless ?? false
        )
    }
}
