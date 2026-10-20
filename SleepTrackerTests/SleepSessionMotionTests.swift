import XCTest
import SwiftData
@testable import SleepTracker

@MainActor
final class SleepSessionMotionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_900_000)

    private var container: ModelContainer?

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: SessionRepository.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    /// Inserts and saves a session with one epoch per intensity, 30 s apart, linked the
    /// same way `SessionRepository.addEpoch` links them.
    private func makeSession(motionIntensities: [Double]) throws -> SleepSession {
        let context = try XCTUnwrap(container).mainContext
        let session = SleepSession(startDate: t0, settings: AppSettings())
        context.insert(session)
        for (index, intensity) in motionIntensities.enumerated() {
            let epoch = EpochSample(
                timestamp: t0.addingTimeInterval(Double(index) * 30),
                motionIntensity: intensity,
                isRestless: false,
                averageDecibels: -50,
                peakDecibels: -40
            )
            context.insert(epoch)
            session.epochs.append(epoch)
        }
        try context.save()
        return session
    }

    func testNoEpochsMeansNoMotionData() throws {
        let session = try makeSession(motionIntensities: [])

        XCTAssertTrue(session.epochs.isEmpty)
        XCTAssertFalse(session.hasMotionData)
    }

    func testZeroIntensityMeansNoMotionData() throws {
        let session = try makeSession(motionIntensities: [0, 0, 0])

        XCTAssertEqual(session.epochs.count, 3)
        XCTAssertFalse(session.hasMotionData)
    }

    func testPositiveIntensityMeansMotionData() throws {
        let session = try makeSession(motionIntensities: [0, 0.2, 0])

        XCTAssertEqual(session.epochs.count, 3)
        XCTAssertTrue(session.hasMotionData)
    }
}
