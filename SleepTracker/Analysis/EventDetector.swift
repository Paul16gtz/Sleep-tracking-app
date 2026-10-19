import Foundation

/// Parameters of the event state machine. All times are seconds since session start.
struct DetectorConfig: Equatable {
    /// Minimum confidence per type (inclusive). A type without a threshold never hits.
    var thresholds: [SoundEventType: Double]
    /// Consecutive hit windows needed to start or to resume an event.
    var minConsecutiveWindows: Int
    /// Time without a hit after which an active event ends (measured from the last hit window's end).
    var endGap: TimeInterval
    /// Time after an event's end during which a new detection of the same type resumes it.
    var mergeGap: TimeInterval
    /// An active event that reaches this duration is finalized and a new event starts.
    var maxEventDuration: TimeInterval
    /// Windows with `start < countingStart` are ignored entirely.
    var countingStart: TimeInterval

    init(
        thresholds: [SoundEventType: Double],
        minConsecutiveWindows: Int = 2,
        endGap: TimeInterval = 4,
        mergeGap: TimeInterval = 10,
        maxEventDuration: TimeInterval = 600,
        countingStart: TimeInterval = 0
    ) {
        self.thresholds = thresholds
        self.minConsecutiveWindows = minConsecutiveWindows
        self.endGap = endGap
        self.mergeGap = mergeGap
        self.maxEventDuration = maxEventDuration
        self.countingStart = countingStart
    }

    /// Builds the configuration from the user settings, with a threshold for every type.
    init(settings: AppSettings, countingStart: TimeInterval) {
        self.init(
            thresholds: Dictionary(
                uniqueKeysWithValues: SoundEventType.allCases.map { ($0, settings.threshold(for: $0)) }
            ),
            minConsecutiveWindows: settings.minConsecutiveWindows,
            endGap: settings.eventEndGap,
            mergeGap: settings.mergeGap,
            maxEventDuration: settings.maxEventDuration,
            countingStart: countingStart
        )
    }
}

/// A finalized event. Confidence statistics cover only the hit windows of the event,
/// including the windows of resumed parts.
struct DetectedEvent: Equatable {
    let type: SoundEventType
    let start: TimeInterval
    let end: TimeInterval
    let maxConfidence: Double
    let averageConfidence: Double
}

/// Signals of the detector.
enum DetectorOutput: Equatable {
    /// An event was confirmed; `detectedAt` is the end of the confirming window.
    case eventStarted(type: SoundEventType, start: TimeInterval, detectedAt: TimeInterval)
    /// A pending event of this type continues; a running post-roll should be cancelled.
    case eventResumed(type: SoundEventType)
    /// Tentative end of an event; it may still be resumed within the merge gap.
    case eventEnded(type: SoundEventType, end: TimeInterval)
    /// The event is complete and will not change any more.
    case eventFinalized(DetectedEvent)
}

/// Per-type state machine turning classifier windows into events.
///
/// Within one call, outputs are grouped by type in `SoundEventType.allCases` order. For each type the
/// finalization of an expired pending event comes before the effect of the current window.
struct EventDetector {
    private let config: DetectorConfig
    private var states: [SoundEventType: TypeState]

    init(config: DetectorConfig) {
        self.config = config
        states = Dictionary(uniqueKeysWithValues: SoundEventType.allCases.map { ($0, TypeState.idle) })
    }

    /// Processes one classifier window for every type.
    mutating func process(_ window: ClassificationWindow) -> [DetectorOutput] {
        guard window.start >= config.countingStart else { return [] }

        var outputs: [DetectorOutput] = []
        for type in SoundEventType.allCases {
            let state = states[type] ?? .idle
            let next = advance(state, type: type, window: window, outputs: &outputs)
            states[type] = next
        }
        return outputs
    }

    /// Ends the session: active events end at their last hit window and are finalized,
    /// pending events are finalized, unconfirmed candidates are dropped. Afterwards every type is idle.
    /// `time` is the session end; it does not change the events, which end at their last hit.
    mutating func finish(at time: TimeInterval) -> [DetectorOutput] {
        var outputs: [DetectorOutput] = []
        for type in SoundEventType.allCases {
            switch states[type] ?? .idle {
            case let .active(start, lastHitEnd, confidences):
                outputs.append(.eventEnded(type: type, end: lastHitEnd))
                outputs.append(.eventFinalized(confidences.event(type: type, start: start, end: lastHitEnd)))
            case let .pending(event, _, _):
                outputs.append(.eventFinalized(event.finalized(type: type)))
            case .idle, .candidate:
                break
            }
            states[type] = .idle
        }
        return outputs
    }

    // MARK: - Transitions

    /// Hits needed to start or resume; values below 1 behave like 1.
    private var requiredHits: Int {
        max(1, config.minConsecutiveWindows)
    }

    private func isHit(_ confidence: Double, for type: SoundEventType) -> Bool {
        guard let threshold = config.thresholds[type] else { return false }
        return confidence >= threshold
    }

    private func advance(
        _ state: TypeState,
        type: SoundEventType,
        window: ClassificationWindow,
        outputs: inout [DetectorOutput]
    ) -> TypeState {
        let confidence = window.confidences[type] ?? 0
        let hit = isHit(confidence, for: type)

        switch state {
        case .idle:
            return advanceIdle(hit: hit, confidence: confidence, type: type, window: window, outputs: &outputs)

        case let .candidate(hits, firstStart, confidences):
            guard hit else { return .idle }
            var stats = confidences
            stats.add(confidence)
            return confirmCandidate(
                hits: hits + 1,
                firstStart: firstStart,
                confidences: stats,
                type: type,
                window: window,
                outputs: &outputs
            )

        case let .active(start, lastHitEnd, confidences):
            if hit {
                return extendActive(
                    start: start,
                    lastHitEnd: lastHitEnd,
                    confidences: confidences,
                    confidence: confidence,
                    type: type,
                    window: window,
                    outputs: &outputs
                )
            }
            guard window.end >= lastHitEnd + config.endGap else { return state }
            outputs.append(.eventEnded(type: type, end: lastHitEnd))
            return .pending(
                event: EndedEvent(start: start, end: lastHitEnd, confidences: confidences),
                resumeHits: 0,
                resumeConfidences: ConfidenceStats()
            )

        case let .pending(event, resumeHits, resumeConfidences):
            if window.start >= event.end + config.mergeGap {
                outputs.append(.eventFinalized(event.finalized(type: type)))
                return advanceIdle(hit: hit, confidence: confidence, type: type, window: window, outputs: &outputs)
            }
            guard hit else {
                // A broken resume streak is not part of the event.
                return .pending(event: event, resumeHits: 0, resumeConfidences: ConfidenceStats())
            }
            var stats = resumeConfidences
            stats.add(confidence)
            let hits = resumeHits + 1
            guard hits >= requiredHits else {
                return .pending(event: event, resumeHits: hits, resumeConfidences: stats)
            }
            outputs.append(.eventResumed(type: type))
            return .active(
                start: event.start,
                lastHitEnd: max(event.end, window.end),
                confidences: event.confidences.merged(with: stats)
            )
        }
    }

    /// Adds a hit to an active event and splits it once it reaches the maximum duration.
    /// The new part starts at the splitting window's end and carries that window's confidence.
    private func extendActive(
        start: TimeInterval,
        lastHitEnd: TimeInterval,
        confidences: ConfidenceStats,
        confidence: Double,
        type: SoundEventType,
        window: ClassificationWindow,
        outputs: inout [DetectorOutput]
    ) -> TypeState {
        var stats = confidences
        stats.add(confidence)
        // A window that does not move time forward stays a hit but never moves the end backwards.
        let end = max(lastHitEnd, window.end)
        guard end - start >= config.maxEventDuration else {
            return .active(start: start, lastHitEnd: end, confidences: stats)
        }
        outputs.append(.eventEnded(type: type, end: end))
        outputs.append(.eventFinalized(stats.event(type: type, start: start, end: end)))
        outputs.append(.eventStarted(type: type, start: end, detectedAt: end))
        return .active(start: end, lastHitEnd: end, confidences: ConfidenceStats(first: confidence))
    }

    private func advanceIdle(
        hit: Bool,
        confidence: Double,
        type: SoundEventType,
        window: ClassificationWindow,
        outputs: inout [DetectorOutput]
    ) -> TypeState {
        guard hit else { return .idle }
        return confirmCandidate(
            hits: 1,
            firstStart: window.start,
            confidences: ConfidenceStats(first: confidence),
            type: type,
            window: window,
            outputs: &outputs
        )
    }

    /// Keeps counting, or starts the event once enough consecutive hits were seen.
    private func confirmCandidate(
        hits: Int,
        firstStart: TimeInterval,
        confidences: ConfidenceStats,
        type: SoundEventType,
        window: ClassificationWindow,
        outputs: inout [DetectorOutput]
    ) -> TypeState {
        guard hits >= requiredHits else {
            return .candidate(hits: hits, firstStart: firstStart, confidences: confidences)
        }
        outputs.append(.eventStarted(type: type, start: firstStart, detectedAt: window.end))
        return .active(start: firstStart, lastHitEnd: window.end, confidences: confidences)
    }
}

// MARK: - State

private enum TypeState {
    case idle
    case candidate(hits: Int, firstStart: TimeInterval, confidences: ConfidenceStats)
    case active(start: TimeInterval, lastHitEnd: TimeInterval, confidences: ConfidenceStats)
    case pending(event: EndedEvent, resumeHits: Int, resumeConfidences: ConfidenceStats)
}

/// An ended event that can still be resumed within the merge gap.
private struct EndedEvent {
    let start: TimeInterval
    let end: TimeInterval
    let confidences: ConfidenceStats

    func finalized(type: SoundEventType) -> DetectedEvent {
        confidences.event(type: type, start: start, end: end)
    }
}

/// Running confidence statistics of hit windows.
private struct ConfidenceStats {
    var count = 0
    var sum: Double = 0
    var maximum: Double = 0

    init() {}

    init(first value: Double) {
        add(value)
    }

    var average: Double {
        count > 0 ? sum / Double(count) : 0
    }

    mutating func add(_ value: Double) {
        maximum = count == 0 ? value : max(maximum, value)
        count += 1
        sum += value
    }

    func merged(with other: ConfidenceStats) -> ConfidenceStats {
        guard other.count > 0 else { return self }
        guard count > 0 else { return other }
        var result = self
        result.count += other.count
        result.sum += other.sum
        result.maximum = max(maximum, other.maximum)
        return result
    }

    func event(type: SoundEventType, start: TimeInterval, end: TimeInterval) -> DetectedEvent {
        DetectedEvent(
            type: type,
            start: start,
            end: end,
            maxConfidence: maximum,
            averageConfidence: average
        )
    }
}
