import Foundation

/// A raw classifier result: label name with its confidence.
struct RankedLabel: Equatable {
    let label: String
    let confidence: Double
}

/// Classification result for one analysis window.
/// Times are seconds since session start.
struct ClassificationWindow: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    /// Highest confidence per mapped event type.
    let confidences: [SoundEventType: Double]

    init(start: TimeInterval, end: TimeInterval, confidences: [SoundEventType: Double]) {
        self.start = start
        self.end = end
        self.confidences = confidences
    }

    /// Builds a window from ranked labels. Labels without a mapped type are ignored;
    /// when several labels share a type, the maximum confidence is kept.
    static func make(
        from ranked: [RankedLabel],
        mapping: LabelMapping,
        start: TimeInterval,
        end: TimeInterval
    ) -> ClassificationWindow {
        var confidences: [SoundEventType: Double] = [:]
        for item in ranked {
            guard let type = mapping.type(for: item.label) else { continue }
            if let existing = confidences[type] {
                confidences[type] = max(existing, item.confidence)
            } else {
                confidences[type] = item.confidence
            }
        }
        return ClassificationWindow(start: start, end: end, confidences: confidences)
    }
}
