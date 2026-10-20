import Foundation

/// One sound event of a night as exported to CSV.
struct EventExportRow: Equatable {
    let type: SoundEventType
    let start: Date
    let end: Date
    let maxConfidence: Double
    let averageConfidence: Double
    let clipRelativePath: String?
}

/// One 30 s epoch of a night as exported to CSV.
struct EpochExportRow: Equatable {
    let timestamp: Date
    let motionIntensity: Double
    let isRestless: Bool
    let averageDecibels: Double
    let peakDecibels: Double
}

/// Builds the CSV export of one night: a header, then the epochs, then the events.
enum CSVExporter {
    static let header = "record_type,timestamp,end,type,max_confidence,avg_confidence,clip,motion_intensity,is_restless,db_avg,db_peak"

    /// Header, then all epochs sorted by timestamp, then all events sorted by start (events that
    /// start together are ordered by type name). Lines end with "\n", including the last one.
    static func makeCSV(events: [EventExportRow], epochs: [EpochExportRow]) -> String {
        var lines = [header]
        for epoch in epochs.sorted(by: { $0.timestamp < $1.timestamp }) {
            lines.append(line([
                "epoch",
                Formatters.csvTimestamp(epoch.timestamp),
                "",
                "",
                "",
                "",
                "",
                threeDecimals(epoch.motionIntensity),
                epoch.isRestless ? "true" : "false",
                oneDecimal(epoch.averageDecibels),
                oneDecimal(epoch.peakDecibels)
            ]))
        }
        let sortedEvents = events.sorted { lhs, rhs in
            if lhs.start != rhs.start {
                return lhs.start < rhs.start
            }
            return lhs.type.rawValue < rhs.type.rawValue
        }
        for event in sortedEvents {
            lines.append(line([
                "event",
                Formatters.csvTimestamp(event.start),
                Formatters.csvTimestamp(event.end),
                event.type.rawValue,
                threeDecimals(event.maxConfidence),
                threeDecimals(event.averageConfidence),
                event.clipRelativePath ?? "",
                "",
                "",
                "",
                ""
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the CSV (UTF-8, atomically) to `fileName` in the temporary directory and returns its URL.
    static func writeTemporaryFile(csv: String, fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// "schlafprotokoll-yyyyMMdd.csv" with the date of `start` in UTC.
    static func fileName(for start: Date) -> String {
        "schlafprotokoll-\(fileNameDateFormatter.string(from: start)).csv"
    }

    // MARK: - Private

    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private static let fieldsNeedingQuotes = CharacterSet(charactersIn: ",\"\r\n")

    /// `String(format:)` without a locale argument formats `%f` with the POSIX conventions
    /// (decimal point, no grouping), so the output does not depend on the device's region.
    private static func threeDecimals(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    /// Same POSIX formatting as `threeDecimals`, with one decimal place (decibels).
    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func line(_ fields: [String]) -> String {
        fields.map(escaped).joined(separator: ",")
    }

    /// A field with a comma, a quote or a line break is wrapped in double quotes and its quotes are doubled.
    private static func escaped(_ field: String) -> String {
        guard field.rangeOfCharacter(from: fieldsNeedingQuotes) != nil else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
