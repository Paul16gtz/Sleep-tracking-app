import Foundation
import SwiftData

extension SleepSession {
    /// Statistics of this session for the nights list and the detail view. A session
    /// without end date (still running) is measured until `now`. The SwiftData arrays
    /// `events` and `epochs` are unordered, so both are sorted by time before they are
    /// reduced to summaries.
    func statistics(now: Date = Date()) -> NightStatistics {
        let eventSummaries = events
            .sorted { $0.startDate < $1.startDate }
            .map { EventSummary(type: $0.type, start: $0.startDate, end: $0.endDate) }
        let epochSummaries = epochs
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
}
