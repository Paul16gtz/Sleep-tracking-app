import XCTest
@testable import SleepTracker

final class CSVExporterTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)

    func testHeaderAndRows() {
        // The dB average is -42.26 and not -42.25: -42.25 is exactly representable and "%.1f"
        // rounds an exact half to even ("-42.2"), while -42.26 rounds to "-42.3" unambiguously.
        let epoch = EpochExportRow(
            timestamp: t0,
            motionIntensity: 1.5,
            isRestless: true,
            averageDecibels: -42.26,
            peakDecibels: -30
        )
        let event = EventExportRow(
            type: .speech,
            start: t0 + 10,
            end: t0 + 20,
            maxConfidence: 0.9,
            averageConfidence: 0.75,
            clipRelativePath: "Clips/a/b.m4a"
        )

        let csv = CSVExporter.makeCSV(events: [event], epochs: [epoch])

        let expected = [
            "record_type,timestamp,end,type,max_confidence,avg_confidence,clip,motion_intensity,is_restless,db_avg,db_peak",
            "epoch,1970-01-01T00:00:00Z,,,,,,1.500,true,-42.3,-30.0",
            "event,1970-01-01T00:00:10Z,1970-01-01T00:00:20Z,speech,0.900,0.750,Clips/a/b.m4a,,,,"
        ].joined(separator: "\n") + "\n"
        XCTAssertEqual(csv, expected)
    }

    func testEmptyYieldsHeaderOnly() {
        let csv = CSVExporter.makeCSV(events: [], epochs: [])

        XCTAssertEqual(csv, CSVExporter.header + "\n")
    }

    func testRowsAreSorted() {
        let laterEpoch = EpochExportRow(
            timestamp: t0 + 30,
            motionIntensity: 0.5,
            isRestless: false,
            averageDecibels: -50,
            peakDecibels: -40
        )
        let earlierEpoch = EpochExportRow(
            timestamp: t0,
            motionIntensity: 2,
            isRestless: true,
            averageDecibels: -60,
            peakDecibels: -45.5
        )
        let laterEvent = EventExportRow(
            type: .cough,
            start: t0 + 50,
            end: t0 + 55,
            maxConfidence: 0.8,
            averageConfidence: 0.7,
            clipRelativePath: nil
        )
        let earlierEvent = EventExportRow(
            type: .snoring,
            start: t0 + 10,
            end: t0 + 40,
            maxConfidence: 1,
            averageConfidence: 0.5,
            clipRelativePath: nil
        )

        let csv = CSVExporter.makeCSV(events: [laterEvent, earlierEvent], epochs: [laterEpoch, earlierEpoch])

        let expected = [
            CSVExporter.header,
            "epoch,1970-01-01T00:00:00Z,,,,,,2.000,true,-60.0,-45.5",
            "epoch,1970-01-01T00:00:30Z,,,,,,0.500,false,-50.0,-40.0",
            "event,1970-01-01T00:00:10Z,1970-01-01T00:00:40Z,snoring,1.000,0.500,,,,,",
            "event,1970-01-01T00:00:50Z,1970-01-01T00:00:55Z,cough,0.800,0.700,,,,,"
        ].joined(separator: "\n") + "\n"
        XCTAssertEqual(csv, expected)
    }

    func testFileName() {
        XCTAssertEqual(CSVExporter.fileName(for: t0), "schlafprotokoll-19700101.csv")
    }

    func testFieldWithCommaIsQuoted() {
        let withComma = EventExportRow(
            type: .cough,
            start: t0,
            end: t0 + 5,
            maxConfidence: 0.5,
            averageConfidence: 0.25,
            clipRelativePath: "Clips/a,b.m4a"
        )
        let withQuote = EventExportRow(
            type: .cough,
            start: t0,
            end: t0 + 5,
            maxConfidence: 0.5,
            averageConfidence: 0.25,
            clipRelativePath: "Clips/\"x\".m4a"
        )

        let commaCSV = CSVExporter.makeCSV(events: [withComma], epochs: [])
        let quoteCSV = CSVExporter.makeCSV(events: [withQuote], epochs: [])

        let prefix = CSVExporter.header + "\nevent,1970-01-01T00:00:00Z,1970-01-01T00:00:05Z,cough,0.500,0.250,"
        XCTAssertEqual(commaCSV, prefix + "\"Clips/a,b.m4a\",,,,\n")
        XCTAssertEqual(quoteCSV, prefix + "\"Clips/\"\"x\"\".m4a\",,,,\n")
    }

    func testWriteTemporaryFileRoundTrip() throws {
        let name = "schlafprotokoll-test-\(UUID().uuidString).csv"
        let csv = CSVExporter.makeCSV(events: [], epochs: [])

        let url = try CSVExporter.writeTemporaryFile(csv: csv, fileName: name)
        defer { try? FileManager.default.removeItem(at: url) }

        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(url.lastPathComponent, name)
        XCTAssertEqual(written, csv)
    }
}
