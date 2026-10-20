import Foundation
import SwiftData

extension SleepSession {
    /// Statistics of this session for the nights list and the detail view. A session
    /// without end date (still running) is measured until `now`. The SwiftData arrays
    /// `events` and `epochs` are unordered, so both are sorted by time before they are
    /// reduced to summaries. Events and epochs deleted elsewhere (a swiped event, all data
    /// removed in the settings tab) are skipped before any of their attributes is read.
    func statistics(now: Date = Date()) -> NightStatistics {
        let eventSummaries = events
            .filter { !$0.isDeletedFromContext }
            .sorted { $0.startDate < $1.startDate }
            .map { EventSummary(type: $0.type, start: $0.startDate, end: $0.endDate) }
        let epochSummaries = epochs
            .filter { !$0.isDeletedFromContext }
            .sorted { $0.timestamp < $1.timestamp }
            .map { EpochSummary(timestamp: $0.timestamp, isRestless: $0.isRestless) }
        return NightStatistics.compute(
            start: startDate,
            end: endDate,
            now: now,
            events: eventSummaries,
            epochs: epochSummaries,
            gaps: interruptionGaps
        )
    }

    /// True when at least one epoch has a motion intensity above zero, i.e. motion was
    /// recorded. Without a motion sensor (simulator, unavailable accelerometer) every epoch
    /// stores intensity 0 and is never restless, so a restlessness of "0 %" would claim a
    /// measured calm night; the UI shows "–" instead.
    var hasMotionData: Bool {
        epochs.contains { $0.motionIntensity > 0 }
    }
}

extension PersistentModel {
    /// True for a model deleted from its context: `isDeleted` marks it from `delete(_:)`
    /// until the save, and after the save it has no `modelContext` any more. The app inserts
    /// every model when it creates it, so a live model always has a context. Only these two
    /// properties may be read on such a model; reading its stored attributes may trap.
    var isDeletedFromContext: Bool {
        modelContext == nil || isDeleted
    }
}
