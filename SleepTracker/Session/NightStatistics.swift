import Foundation

/// A sound event reduced to the fields the statistics need.
struct EventSummary: Equatable {
    let type: SoundEventType
    let start: Date
    let end: Date
}

/// A motion epoch reduced to the fields the statistics need.
struct EpochSummary: Equatable {
    let timestamp: Date
    let isRestless: Bool
}

/// Per-night numbers shown in the nights list, the detail view and the CSV export.
struct NightStatistics: Equatable {
    /// Length of the session in seconds, never negative.
    let duration: TimeInterval
    /// Summed length of all snoring events in seconds.
    let snoringDuration: TimeInterval
    /// Share of the session spent snoring, 0 when the session has no duration.
    let snoringPercentage: Double
    let snoringCount: Int
    let speechCount: Int
    let coughCount: Int
    let whisperingCount: Int
    let totalEpochCount: Int
    let restlessEpochCount: Int
    /// Share of restless epochs, 0 when there are no epochs.
    let restlessPercentage: Double
    /// Number of maximal runs of consecutive restless epochs in time order.
    let restlessPhaseCount: Int
    let interruptionCount: Int

    /// Computes the statistics of one session.
    /// - Parameters:
    ///   - start: Session start.
    ///   - end: Session end; nil for a session that is still running, in which case `now` is used.
    ///   - now: Reference time for an open session.
    ///   - events: Detected events in any order.
    ///   - epochs: Motion epochs in any order; they are sorted by timestamp here.
    ///   - gaps: Capture interruptions of the session.
    static func compute(
        start: Date,
        end: Date?,
        now: Date,
        events: [EventSummary],
        epochs: [EpochSummary],
        gaps: [InterruptionGap]
    ) -> NightStatistics {
        let duration = max(0, (end ?? now).timeIntervalSince(start))

        var snoringDuration: TimeInterval = 0
        var snoringCount = 0
        var speechCount = 0
        var coughCount = 0
        var whisperingCount = 0
        for event in events {
            switch event.type {
            case .snoring:
                snoringCount += 1
                snoringDuration += max(0, event.end.timeIntervalSince(event.start))
            case .speech:
                speechCount += 1
            case .cough:
                coughCount += 1
            case .whispering:
                whisperingCount += 1
            }
        }
        let snoringPercentage = duration > 0 ? snoringDuration / duration * 100 : 0

        let orderedEpochs = epochs.sorted { $0.timestamp < $1.timestamp }
        var restlessEpochCount = 0
        var restlessPhaseCount = 0
        var previousWasRestless = false
        for epoch in orderedEpochs {
            if epoch.isRestless {
                restlessEpochCount += 1
                if !previousWasRestless {
                    restlessPhaseCount += 1
                }
            }
            previousWasRestless = epoch.isRestless
        }
        let totalEpochCount = orderedEpochs.count
        let restlessPercentage = totalEpochCount > 0
            ? Double(restlessEpochCount) / Double(totalEpochCount) * 100
            : 0

        return NightStatistics(
            duration: duration,
            snoringDuration: snoringDuration,
            snoringPercentage: snoringPercentage,
            snoringCount: snoringCount,
            speechCount: speechCount,
            coughCount: coughCount,
            whisperingCount: whisperingCount,
            totalEpochCount: totalEpochCount,
            restlessEpochCount: restlessEpochCount,
            restlessPercentage: restlessPercentage,
            restlessPhaseCount: restlessPhaseCount,
            interruptionCount: gaps.count
        )
    }
}
