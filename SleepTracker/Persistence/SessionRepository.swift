import Foundation
import SwiftData

/// Single gateway for SwiftData reads and writes. Runs on the main actor with the
/// main context, and keeps the clip files on disk in step with the stored events.
@MainActor
final class SessionRepository {
    static let schema = Schema([SleepSession.self, SoundEvent.self, EpochSample.self])

    private let context: ModelContext
    private let fileStore: FileStore

    init(context: ModelContext, fileStore: FileStore) {
        self.context = context
        self.fileStore = fileStore
    }

    /// Inserts a new running session and saves it.
    func createSession(startDate: Date, settings: AppSettings, isTest: Bool) throws -> SleepSession {
        let session = SleepSession(startDate: startDate, settings: settings, isTest: isTest)
        context.insert(session)
        try save()
        return session
    }

    func addEvent(
        to session: SleepSession,
        type: SoundEventType,
        startDate: Date,
        endDate: Date,
        maxConfidence: Double,
        averageConfidence: Double,
        clipRelativePath: String?
    ) throws -> SoundEvent {
        let event = SoundEvent(
            type: type,
            startDate: startDate,
            endDate: endDate,
            maxConfidence: maxConfidence,
            averageConfidence: averageConfidence,
            clipRelativePath: clipRelativePath
        )
        // Insert before linking, then set the to-many side so `session.events` holds the event at once.
        context.insert(event)
        session.events.append(event)
        try save()
        return event
    }

    func addEpoch(
        to session: SleepSession,
        timestamp: Date,
        averageDecibels: Double,
        peakDecibels: Double,
        motionIntensity: Double,
        isRestless: Bool
    ) throws -> EpochSample {
        let epoch = EpochSample(
            timestamp: timestamp,
            motionIntensity: motionIntensity,
            isRestless: isRestless,
            averageDecibels: averageDecibels,
            peakDecibels: peakDecibels
        )
        context.insert(epoch)
        session.epochs.append(epoch)
        try save()
        return epoch
    }

    func updateGaps(_ gaps: [InterruptionGap], for session: SleepSession) throws {
        session.interruptionGaps = gaps
        try save()
    }

    func finishSession(_ session: SleepSession, endDate: Date, status: SessionStatus, gaps: [InterruptionGap]) throws {
        session.endDate = endDate
        session.status = status
        session.interruptionGaps = gaps
        try save()
    }

    /// Marks every session still `running` (left over from a terminated app) as `endedUnexpectedly`.
    /// Its end date becomes the latest epoch timestamp or event end, or its start date without data.
    /// Returns the number of sessions changed.
    func markStaleRunningSessions() throws -> Int {
        let runningRaw = SessionStatus.running.rawValue
        let descriptor = FetchDescriptor<SleepSession>(
            predicate: #Predicate<SleepSession> { session in session.statusRaw == runningRaw }
        )
        let staleSessions = try context.fetch(descriptor)
        guard !staleSessions.isEmpty else {
            return 0
        }
        for session in staleSessions {
            session.endDate = lastDataDate(of: session) ?? session.startDate
            session.status = .endedUnexpectedly
        }
        try save()
        return staleSessions.count
    }

    /// All sessions, newest first.
    func fetchSessions() throws -> [SleepSession] {
        let descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Deletes the session's clip folder, then the session; events and epochs go with it (cascade).
    func deleteSession(_ session: SleepSession) throws {
        try fileStore.deleteClips(for: session.id)
        context.delete(session)
        try save()
    }

    /// Deletes the event's clip file (if any), then the event.
    func deleteEvent(_ event: SoundEvent) throws {
        if let relativePath = event.clipRelativePath {
            try fileStore.deleteClip(relativePath: relativePath)
        }
        context.delete(event)
        try save()
    }

    /// Deletes every session (with its events and epochs) and every clip file.
    func deleteAllData() throws {
        let sessions = try context.fetch(FetchDescriptor<SleepSession>())
        for session in sessions {
            context.delete(session)
        }
        try fileStore.deleteAllClips()
        try save()
    }

    func save() throws {
        try context.save()
    }

    // MARK: - Private

    /// Latest of the last epoch timestamp and the last event end; nil when the session has neither.
    private func lastDataDate(of session: SleepSession) -> Date? {
        let lastEpoch = session.epochs.map(\.timestamp).max()
        let lastEventEnd = session.events.map(\.endDate).max()
        return [lastEpoch, lastEventEnd].compactMap { $0 }.max()
    }
}
