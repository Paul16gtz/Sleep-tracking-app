import SwiftUI
import Charts

/// One epoch of the night timeline (loudness and motion), built from an `EpochSample`.
struct TimelinePoint: Identifiable {
    /// Position in the time-sorted epoch list.
    let id: Int
    /// Start of the epoch.
    let time: Date
    /// Average level of the epoch in dBFS, already clamped to the chart floor; nil when
    /// the epoch has no measured level (its audio was lost in an interruption gap).
    let decibels: Double?
    /// Motion intensity of the epoch; 0 when no motion was recorded.
    let motion: Double
    let isRestless: Bool
}

/// One detected event on the night timeline, built from a `SoundEvent`.
struct TimelineEvent: Identifiable {
    let id: UUID
    let type: SoundEventType
    let start: Date
    /// At least `start + minimumVisibleDuration`, so a short event still shows as a bar.
    let end: Date

    /// Shortest span an event occupies on the chart. A cough of two seconds in an eight
    /// hour night would otherwise be narrower than one pixel and disappear.
    static let minimumVisibleDuration: TimeInterval = 20
}

/// Up to three charts over the same time axis: the loudness line of the epochs, one motion
/// bar per epoch (only for a night with motion data) and one row of colored bars per event type.
struct NightTimelineChart: View {
    /// Epochs sorted by time.
    let points: [TimelinePoint]
    /// Events sorted by start.
    let events: [TimelineEvent]
    /// Session start to end; all charts share it as their x domain.
    let range: ClosedRange<Date>
    /// Shows the motion chart; false for a night without motion data (no sensor).
    let showsMotion: Bool

    /// Lowest level the loudness chart shows; quieter epochs sit on this line.
    static let decibelFloor: Double = -80
    /// Longest time between two loudness points that the line still connects. Epochs are
    /// 30 s apart, so a longer distance is a gap without a measured level.
    private static let maximumLineGap: TimeInterval = 60

    private static let loudnessChartHeight: CGFloat = 120
    private static let motionChartHeight: CGFloat = 80
    /// Width of one motion bar: one epoch, starting at its timestamp.
    private static let motionBarDuration: TimeInterval = 30
    private static let eventRowHeight: CGFloat = 24
    private static let eventChartPadding: CGFloat = 16
    private static let minimumEventChartHeight: CGFloat = 40
    /// Nights shorter than this get a 15 minute axis stride instead of one hour.
    private static let shortNightDuration: TimeInterval = 2 * 3600

    var body: some View {
        if points.isEmpty && events.isEmpty {
            Text("Keine Daten für diese Nacht")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                caption("Lautstärke (dBFS)")
                loudnessChart
                if showsMotion {
                    caption("Bewegung")
                    motionChart
                    motionLegend
                }
                caption("Ereignisse")
                if events.isEmpty {
                    Text("Keine Ereignisse")
                        .foregroundStyle(.secondary)
                } else {
                    eventChart
                    legend
                }
            }
        }
    }

    private var loudnessChart: some View {
        Chart(loudnessPoints) { point in
            // On the mark, not the chart view: the view-level style would also tint the
            // axis labels, which resolve their secondary style against it. One series per
            // segment, so the line is not drawn through a gap as if it were measured.
            LineMark(
                x: .value("Zeit", point.time),
                y: .value("dB", point.decibels),
                series: .value("Abschnitt", point.segment)
            )
            .foregroundStyle(Theme.accent)
        }
        .chartYScale(domain: NightTimelineChart.decibelFloor ... 0.0)
        .sharedAxes(range: range, labelStride: axisStride)
        .frame(height: NightTimelineChart.loudnessChartHeight)
    }

    private var motionChart: some View {
        Chart(points) { point in
            // One bar over the 30 s of the epoch; the style sits on the mark as in the loudness chart.
            RectangleMark(
                xStart: .value("Start", point.time),
                xEnd: .value("Ende", point.time.addingTimeInterval(NightTimelineChart.motionBarDuration)),
                yStart: .value("Bewegung", 0.0),
                yEnd: .value("Bewegung", point.motion)
            )
            .foregroundStyle(point.isRestless ? Color.orange : Color.gray)
        }
        .sharedAxes(range: range, labelStride: axisStride)
        .frame(height: NightTimelineChart.motionChartHeight)
    }

    private var eventChart: some View {
        Chart {
            ForEach(events) { event in
                RectangleMark(
                    xStart: .value("Start", event.start),
                    xEnd: .value("Ende", event.end),
                    y: .value("Typ", event.type.germanName)
                )
                .foregroundStyle(Theme.color(for: event.type))
            }
        }
        // Rows in the legend's order instead of the order of first appearance.
        .chartYScale(domain: presentTypes.map { $0.germanName })
        .sharedAxes(range: range, labelStride: axisStride)
        .frame(height: eventChartHeight)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(presentTypes) { type in
                legendEntry(type.germanName, color: Theme.color(for: type))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .minimumScaleFactor(0.8)
    }

    private var motionLegend: some View {
        HStack(spacing: 12) {
            legendEntry("unruhig", color: .orange)
            legendEntry("ruhig", color: .gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A colored dot with its caption-size name.
    private func legendEntry(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// The points with a measured level. A new line segment begins after more than
    /// `maximumLineGap` without one, so the line breaks at an interruption.
    private var loudnessPoints: [LoudnessPoint] {
        var result: [LoudnessPoint] = []
        var segment = 0
        var previousTime: Date?
        for point in points {
            guard let decibels = point.decibels else {
                continue
            }
            if let previous = previousTime,
               point.time.timeIntervalSince(previous) > NightTimelineChart.maximumLineGap {
                segment += 1
            }
            result.append(LoudnessPoint(id: point.id, time: point.time, decibels: decibels, segment: segment))
            previousTime = point.time
        }
        return result
    }

    /// Event types of this night in `SoundEventType.allCases` order.
    private var presentTypes: [SoundEventType] {
        let present = Set(events.map { $0.type })
        return SoundEventType.allCases.filter { present.contains($0) }
    }

    private var eventChartHeight: CGFloat {
        let rows = CGFloat(presentTypes.count)
        return max(
            NightTimelineChart.minimumEventChartHeight,
            rows * NightTimelineChart.eventRowHeight + NightTimelineChart.eventChartPadding
        )
    }

    private var axisStride: TimeAxisStride {
        let duration = range.upperBound.timeIntervalSince(range.lowerBound)
        if duration < NightTimelineChart.shortNightDuration {
            return TimeAxisStride(component: .minute, count: 15)
        }
        return TimeAxisStride(component: .hour, count: 1)
    }
}

/// One point of the loudness line; `segment` numbers the parts of the line.
private struct LoudnessPoint: Identifiable {
    /// The `id` of the `TimelinePoint` it comes from.
    let id: Int
    let time: Date
    let decibels: Double
    let segment: Int
}

/// Distance between two labels on the shared time axis.
private struct TimeAxisStride {
    let component: Calendar.Component
    let count: Int
}

/// Y-axis labels of one fixed width. Swift Charts narrows the plot area by the width of
/// the y labels, so with labels of the same width in every chart all plot areas are
/// equally wide and a time lands on the same x position in each of them.
private enum FixedWidthAxisLabel {
    /// Wide enough for "Schnarchen" in the axis font; a longer text shrinks to fit.
    static let width: CGFloat = 64

    /// Numbers with at most two decimals in the device locale ("-40", "0,5").
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    /// A number for the loudness and the motion chart, the type name for the event chart.
    static func text(for value: AxisValue) -> String {
        if let number = value.as(Double.self) {
            return numberFormatter.string(from: NSNumber(value: number)) ?? ""
        }
        return value.as(String.self) ?? ""
    }
}

private extension View {
    /// The x domain and axis all charts share, and a y axis on the trailing edge with
    /// labels of one fixed width, so the time columns of all charts line up.
    func sharedAxes(range: ClosedRange<Date>, labelStride: TimeAxisStride) -> some View {
        self
            .chartXScale(domain: range)
            .chartXAxis {
                AxisMarks(values: .stride(by: labelStride.component, count: labelStride.count)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        Text(FixedWidthAxisLabel.text(for: value))
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: FixedWidthAxisLabel.width, alignment: .leading)
                    }
                }
            }
    }
}
