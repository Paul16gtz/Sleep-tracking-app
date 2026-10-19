import XCTest
@testable import SleepTracker

final class AppSettingsTests: XCTestCase {
    func testDefaultsMatchSpec() {
        let settings = AppSettings()
        XCTAssertEqual(settings.fallAsleepDelay, 900, accuracy: 0.0001)
        XCTAssertEqual(settings.threshold(for: .snoring), 0.6, accuracy: 0.0001)
        XCTAssertEqual(settings.minConsecutiveWindows, 2)
        XCTAssertEqual(settings.eventEndGap, 4, accuracy: 0.0001)
        XCTAssertEqual(settings.mergeGap, 10, accuracy: 0.0001)
        XCTAssertEqual(settings.maxEventDuration, 600, accuracy: 0.0001)
        XCTAssertEqual(settings.clipPreRoll, 5, accuracy: 0.0001)
        XCTAssertEqual(settings.clipPostRoll, 5, accuracy: 0.0001)
        XCTAssertEqual(settings.clipMaxDuration, 60, accuracy: 0.0001)
        XCTAssertEqual(settings.speechClipLimitPerNight, 50)
        XCTAssertEqual(settings.snoringClipMinInterval, 600, accuracy: 0.0001)
        XCTAssertEqual(settings.snoringClipLimitPerNight, 20)
        XCTAssertEqual(settings.restlessFactor, 3.0, accuracy: 0.0001)
        XCTAssertEqual(settings.motionCalibrationDuration, 300, accuracy: 0.0001)
    }

    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.setThreshold(0.8, for: .speech)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.threshold(for: .speech), 0.8, accuracy: 0.0001)
    }

    // Review Focus 5: an older or partial JSON payload must fall back to defaults per field.
    func testMissingKeysUseDefaults() throws {
        let data = Data("{\"fallAsleepDelay\": 60}".utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.fallAsleepDelay, 60, accuracy: 0.0001)
        XCTAssertEqual(decoded.mergeGap, 10, accuracy: 0.0001)
        XCTAssertEqual(decoded.threshold(for: .cough), 0.6, accuracy: 0.0001)
    }

    @MainActor
    func testSettingsStorePersists() {
        let suiteName = "SettingsStoreTests"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storeA = SettingsStore(userDefaults: defaults)
        storeA.settings.mergeGap = 20

        let storeB = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(storeB.settings.mergeGap, 20, accuracy: 0.0001)
    }
}
