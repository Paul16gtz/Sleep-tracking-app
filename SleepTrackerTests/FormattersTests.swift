import XCTest
@testable import SleepTracker

final class FormattersTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(Formatters.duration(27120), "7 h 32 min")
        XCTAssertEqual(Formatters.duration(1920), "32 min")
        XCTAssertEqual(Formatters.duration(-5), "0 min")
    }

    func testClock() {
        XCTAssertEqual(Formatters.clock(27135), "07:32:15")
    }

    func testMinutes() {
        XCTAssertEqual(Formatters.minutes(725), "12 min")
    }

    func testPercent() {
        XCTAssertEqual(Formatters.percent(23.4), "23 %")
    }

    func testDecibels() {
        XCTAssertEqual(Formatters.decibels(-42.4), "-42 dB")
    }
}
