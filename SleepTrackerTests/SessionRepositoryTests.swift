import XCTest
import SwiftData
@testable import SleepTracker

@MainActor
final class SessionRepositoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_900_000)

    private var baseDirectory: URL?
    private var container: ModelContainer?
    private var fileStore: FileStore?
    private var repository: SessionRepository?

    override func setUp() async throws {
        try await super.setUp()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let container = try ModelContainer(
            for: SessionRepository.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let fileStore = FileStore(baseDirectory: directory)
        baseDirectory = directory
        self.container = container
        self.fileStore = fileStore
        repository = SessionRepository(context: container.mainContext, fileStore: fileStore)
    }

    override func tearDown() async throws {
        if let directory = baseDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
        repository = nil
        fileStore = nil
        container = nil
        baseDirectory = nil
        try await super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        try XCTUnwrap(container).mainContext
    }

    func testCreateAndFetchNewestFirst() throws {
        let repository = try XCTUnwrap(self.repository)
        _ = try repository.createSession(startDate: t0, settings: AppSettings(), isTest: false)
        _ = try repository.createSession(startDate: t0.addingTimeInterval(3600), settings: AppSettings(), isTest: false)

        let sessions = try repository.fetchSessions()

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.startDate, t0.addingTimeInterval(3600))
        XCTAssertEqual(sessions.last?.startDate, t0)
        XCTAssertEqual(sessions.first?.status, .running)
    }

    func testMarkStaleRunningSessions() throws {
        let repository = try XCTUnwrap(self.repository)
        let running = try repository.createSession(startDate: t0, settings: AppSettings(), isTest: false)
        _ = try repository.addEpoch(
            to: running,
            timestamp: t0.addingTimeInterval(60),
            averageDecibels: -40,
            peakDecibels: -30,
            motionIntensity: 0,
            isRestless: false
        )
        _ = try repository.addEvent(
            to: running,
            type: .speech,
            startDate: t0.addingTimeInterval(10),
            endDate: t0.addingTimeInterval(20),
            maxConfidence: 0.9,
            averageConfidence: 0.8,
            clipRelativePath: nil
        )
        let finishedEnd = t0.addingTimeInterval(-3600)
        let finished = try repository.createSession(
            startDate: t0.addingTimeInterval(-7200),
            settings: AppSettings(),
            isTest: false
        )
        try repository.finishSession(finished, endDate: finishedEnd, status: .ended, gaps: [])

        let marked = try repository.markStaleRunningSessions()

        XCTAssertEqual(marked, 1)
        XCTAssertEqual(running.status, .endedUnexpectedly)
        XCTAssertEqual(running.endDate, t0.addingTimeInterval(60))
        XCTAssertEqual(finished.status, .ended)
        XCTAssertEqual(finished.endDate, finishedEnd)
    }

    func testMarkStaleWithoutDataUsesStartDate() throws {
        let repository = try XCTUnwrap(self.repository)
        let session = try repository.createSession(startDate: t0, settings: AppSettings(), isTest: false)

        let marked = try repository.markStaleRunningSessions()

        XCTAssertEqual(marked, 1)
        XCTAssertEqual(session.status, .endedUnexpectedly)
        XCTAssertEqual(session.endDate, t0)
    }

    func testMarkStaleUsesLatestEventEndWhenAfterLastEpoch() throws {
        let repository = try XCTUnwrap(self.repository)
        let session = try repository.createSession(startDate: t0, settings: AppSettings(), isTest: false)
        _ = try repository.addEpoch(
            to: session,
            timestamp: t0.addingTimeInterval(30),
            averageDecibels: -45,
            peakDecibels: -35,
            motionIntensity: 0,
            isRestless: false
        )
        _ = try repository.addEvent(
            to: session,
            type: .snoring,
            startDate: t0.addingTimeInterval(40),
            endDate: t0.addingTimeInterval(90),
            maxConfidence: 0.95,
            averageConfidence: 0.7,
            clipRelativePath: nil
        )

        XCTAssertEqual(try repository.markStaleRunningSessions(), 1)
        XCTAssertEqual(session.endDate, t0.addingTimeInterval(90))
        XCTAssertEqual(try repository.markStaleRunningSessions(), 0)
    }

    func testFinishSessionStoresGaps() throws {
        let repository = try XCTUnwrap(self.repository)
        let session = try repository.createSession(startDate: t0, settings: AppSettings(), isTest: false)
        let gaps = [InterruptionGap(start: 10, end: 25, reason: "systemInterruption")]
        let endDate = t0.addingTimeInterval(8 * 3600)

        try repository.finishSession(session, endDate: endDate, status: .ended, gaps: gaps)

        XCTAssertEqual(session.interruptionGaps, gaps)
        XCTAssertEqual(session.status, .ended)
        XCTAssertEqual(session.endDate, endDate)
    }

    func testUpdateGapsStoresOpenGap() throws {
        let repository = try XCTUnwrap(self.repository)
        let session = try repository.createSession(startDate: t0, settings: AppSettings(), isTest: false)
        XCTAssertEqual(session.interruptionGaps, [])
        let gaps = [
            InterruptionGap(start: 10, end: 25, reason: "systemInterruption"),
            InterruptionGap(start: 300, end: nil, reason: "routeChange"),
        ]

        try repository.updateGaps(gaps, for: session)

        XCTAssertEqual(session.interruptionGaps, gaps)
        XCTAssertNil(session.interruptionGaps.last?.end)
        XCTAssertEqual(session.status, .running)
    }

    func testDeleteSessionRemovesEventsAndClipFolder() throws {
        let repository = try XCTUnwrap(self.repository)
        let fileStore = try XCTUnwrap(self.fileStore)
        let context = try makeContext()
        let session = try repository.createSession(startDate: t0, settings: AppSettings(), isTest: false)
        let directory = try fileStore.clipDirectory(for: session.id)
        let relativePath = fileStore.makeClipRelativePath(
            sessionID: session.id,
            clipStart: t0.addingTimeInterval(5),
            type: .speech
        )
        try Data(repeating: 1, count: 16).write(to: fileStore.clipURL(relativePath: relativePath))
        _ = try repository.addEvent(
            to: session,
            type: .speech,
            startDate: t0.addingTimeInterval(10),
            endDate: t0.addingTimeInterval(20),
            maxConfidence: 0.9,
            averageConfidence: 0.8,
            clipRelativePath: relativePath
        )
        _ = try repository.addEpoch(
            to: session,
            timestamp: t0.addingTimeInterval(30),
            averageDecibels: -40,
            peakDecibels: -30,
            motionIntensity: 0,
            isRestless: false
        )

        try repository.deleteSession(session)

        XCTAssertTrue(try repository.fetchSessions().isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SoundEvent>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<EpochSample>()).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDeleteEventRemovesClipFile() throws {
        let repository = try XCTUnwrap(self.repository)
        let fileStore = try XCTUnwrap(self.fileStore)
        let context = try makeContext()
        let session = try repository.createSession(startDate: t0, settings: AppSettings(), isTest: false)
        _ = try fileStore.clipDirectory(for: session.id)
        let relativePath = fileStore.makeClipRelativePath(
            sessionID: session.id,
            clipStart: t0.addingTimeInterval(5),
            type: .cough
        )
        let clipURL = fileStore.clipURL(relativePath: relativePath)
        try Data(repeating: 1, count: 16).write(to: clipURL)
        let event = try repository.addEvent(
            to: session,
            type: .cough,
            startDate: t0.addingTimeInterval(10),
            endDate: t0.addingTimeInterval(12),
            maxConfidence: 0.8,
            averageConfidence: 0.7,
            clipRelativePath: relativePath
        )

        try repository.deleteEvent(event)

        XCTAssertFalse(FileManager.default.fileExists(atPath: clipURL.path))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SoundEvent>()).isEmpty)
        XCTAssertEqual(try repository.fetchSessions().count, 1)
    }

    func testDeleteAllDataRemovesSessionsAndClips() throws {
        let repository = try XCTUnwrap(self.repository)
        let fileStore = try XCTUnwrap(self.fileStore)
        let first = try repository.createSession(startDate: t0, settings: AppSettings(), isTest: false)
        _ = try repository.createSession(startDate: t0.addingTimeInterval(86_400), settings: AppSettings(), isTest: true)
        let directory = try fileStore.clipDirectory(for: first.id)
        try Data(repeating: 1, count: 16).write(to: directory.appendingPathComponent("clip.m4a"))

        try repository.deleteAllData()

        XCTAssertTrue(try repository.fetchSessions().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(fileStore.clipsTotalSize(), 0)
    }

    func testSettingsSnapshotRoundTrip() throws {
        let repository = try XCTUnwrap(self.repository)
        var settings = AppSettings()
        settings.mergeGap = 42

        let session = try repository.createSession(startDate: t0, settings: settings, isTest: true)

        XCTAssertEqual(session.settingsSnapshot.mergeGap, 42, accuracy: 0.0001)
        XCTAssertEqual(session.settingsSnapshot, settings)
        XCTAssertTrue(session.isTest)
    }

    func testUnknownRawValuesFallBack() throws {
        let repository = try XCTUnwrap(self.repository)
        let session = try repository.createSession(startDate: t0, settings: AppSettings(), isTest: false)
        let event = try repository.addEvent(
            to: session,
            type: .whispering,
            startDate: t0.addingTimeInterval(10),
            endDate: t0.addingTimeInterval(13),
            maxConfidence: 0.7,
            averageConfidence: 0.65,
            clipRelativePath: nil
        )
        XCTAssertEqual(event.type, .whispering)
        XCTAssertEqual(event.duration, 3, accuracy: 0.0001)

        session.statusRaw = "paused"
        event.typeRaw = "dog"
        session.settingsSnapshotData = Data("not json".utf8)
        session.interruptionGapsData = Data()

        XCTAssertEqual(session.status, .endedUnexpectedly)
        XCTAssertEqual(event.type, .speech)
        XCTAssertEqual(session.settingsSnapshot, AppSettings())
        XCTAssertEqual(session.interruptionGaps, [])
    }

    func testStatusGermanNames() {
        XCTAssertEqual(SessionStatus.running.germanName, "Läuft")
        XCTAssertEqual(SessionStatus.ended.germanName, "Beendet")
        XCTAssertEqual(SessionStatus.endedUnexpectedly.germanName, "Unerwartet beendet")
    }
}
