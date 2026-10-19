import Foundation

/// Display and export formatting helpers. Durations use integer arithmetic so output is locale independent.
enum Formatters {
    /// "7 h 32 min"; below one hour "32 min"; negative or non-finite input gives "0 min".
    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, wholeNumber(seconds)) / 60
        let hours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours) h \(remainingMinutes) min"
        }
        return "\(remainingMinutes) min"
    }

    /// "07:32:15" (hours:minutes:seconds, truncated to whole seconds).
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, wholeNumber(seconds))
        let hours = total / 3600
        let remainingMinutes = (total % 3600) / 60
        let remainingSeconds = total % 60
        return String(format: "%02ld:%02ld:%02ld", hours, remainingMinutes, remainingSeconds)
    }

    /// "12 min", rounded to the nearest minute; negative input gives "0 min".
    static func minutes(_ seconds: TimeInterval) -> String {
        let rounded = max(0, wholeNumber((seconds / 60).rounded()))
        return "\(rounded) min"
    }

    /// "23 %", rounded; `value` is expected in 0...100.
    static func percent(_ value: Double) -> String {
        "\(wholeNumber(value.rounded())) %"
    }

    /// "-42 dB", rounded to whole decibels.
    static func decibels(_ value: Double) -> String {
        "\(wholeNumber(value.rounded())) dB"
    }

    /// German weekday and date, e.g. "Mo., 3. Feb. 2025".
    static func nightDate(_ date: Date) -> String {
        nightDateFormatter.string(from: date)
    }

    /// Local time of day, e.g. "23:41".
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// ISO 8601 timestamp in UTC for CSV export, e.g. "1970-01-01T00:00:00Z".
    static func csvTimestamp(_ date: Date) -> String {
        csvFormatter.string(from: date)
    }

    // MARK: - Private

    private static let germanLocale = Locale(identifier: "de_DE")

    private static let nightDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Formatters.germanLocale
        formatter.dateFormat = "EE, d. MMM yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Formatters.germanLocale
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let csvFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Truncates to an integer; non-finite values become 0 and huge values are clamped to avoid a trap in `Int(_:)`.
    private static func wholeNumber(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let limit = 1e12
        return Int(max(-limit, min(limit, value)))
    }
}
