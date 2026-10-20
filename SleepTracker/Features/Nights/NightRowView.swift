import SwiftData
import SwiftUI

/// One night in the list: the date with badges, then length, snoring minutes, number
/// of speech events and restlessness.
struct NightRowView: View {
    let session: SleepSession

    var body: some View {
        let stats = session.statistics()
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(Formatters.nightDate(session.startDate))
                    .font(.headline)
                if session.isTest {
                    StatusBadge(text: "Test", color: Theme.accent)
                }
                if session.status == .endedUnexpectedly {
                    StatusBadge(text: SessionStatus.endedUnexpectedly.germanName, color: .orange)
                }
            }
            Text(NightRowView.summary(of: stats, hasMotionData: session.hasMotionData))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// "7 h 32 min · Schnarchen 23 min · Sprechen 4× · Unruhe 12 %".
    private static func summary(of stats: NightStatistics, hasMotionData: Bool) -> String {
        // As in the detail view: a night without motion data (no sensor) shows "–", because
        // its epochs are all calm and "0 %" would claim a measured calm night.
        let restlessness = hasMotionData ? Formatters.percent(stats.restlessPercentage) : "–"
        return [
            Formatters.duration(stats.duration),
            "Schnarchen \(Formatters.minutes(stats.snoringDuration))",
            "Sprechen \(stats.speechCount)×",
            "Unruhe \(restlessness)"
        ].joined(separator: " · ")
    }
}

/// Small colored capsule next to the date, e.g. "Test".
private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .fixedSize()
    }
}
