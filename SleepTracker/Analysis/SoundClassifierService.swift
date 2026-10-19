import AVFoundation
import CoreMedia
import SoundAnalysis

/// Apple's built-in sound classifier (`SNClassifySoundRequest`, `.version1`) on an
/// `SNAudioStreamAnalyzer` for one stream segment. The pipeline creates a new
/// instance per segment (spec B2); `timeOffset` turns the segment-relative result
/// times into seconds since session start.
///
/// Threading: `analyze` and `completeAnalysis` are called from the pipeline's serial
/// analysis queue only. SoundAnalysis calls the `SNResultsObserving` methods
/// synchronously on the thread that calls `analyze` / `completeAnalysis`, so the
/// delegate is called on that queue as well. Nothing is dispatched elsewhere.
final class SoundClassifierService: NSObject, SoundClassifying, SNResultsObserving {
    /// Preferred analysis window in seconds.
    static let windowDuration: TimeInterval = 1.5
    /// Overlap of consecutive windows (0.5 gives a result every 0.75 s).
    static let overlapFactor: Double = 0.5
    /// Number of raw labels passed to the delegate for the Debug screen.
    static let topLabelCount = 5

    weak var delegate: SoundClassifierDelegate?

    /// Seconds since session start of frame 0 of this segment.
    let timeOffset: TimeInterval
    private let mapping: LabelMapping
    /// The request registered with `analyzer`, kept for the analyzer's lifetime.
    private let classifyRequest: SNClassifySoundRequest
    private let analyzer: SNAudioStreamAnalyzer

    /// `format` is the format of every buffer passed to `analyze` (mono Float32 at
    /// the native sample rate). Throws when the built-in classifier is unavailable
    /// or the analyzer rejects the request.
    init(format: AVAudioFormat, mapping: LabelMapping, timeOffset: TimeInterval) throws {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        // Assigning a duration that `windowDurationConstraint` does not allow is not
        // reported as a Swift error (no do/catch possible), so the preferred 1.5 s is
        // moved to the closest allowed value first.
        let preferred = CMTime(seconds: SoundClassifierService.windowDuration, preferredTimescale: 48_000)
        request.windowDuration = SoundClassifierService.allowedWindowDuration(
            closestTo: preferred,
            constraint: request.windowDurationConstraint
        )
        request.overlapFactor = SoundClassifierService.overlapFactor
        self.classifyRequest = request
        self.analyzer = SNAudioStreamAnalyzer(format: format)
        self.mapping = mapping
        self.timeOffset = timeOffset
        super.init()
        try analyzer.add(request, withObserver: self)
    }

    /// The label set of the built-in classifier, for the label mapping and the Debug screen.
    static func knownLabels() throws -> [String] {
        try SNClassifySoundRequest(classifierIdentifier: .version1).knownClassifications
    }

    /// Factory for the pipeline: one service per stream segment. `mapping` is a value
    /// type and is captured as a copy.
    static func makeFactory(mapping: LabelMapping) -> SoundClassifierFactory {
        return { format, timeOffset in
            try SoundClassifierService(format: format, mapping: mapping, timeOffset: timeOffset)
        }
    }

    /// The window duration allowed by `constraint` that is closest to `preferred`:
    /// the nearest enumerated duration, or `preferred` clamped to the range.
    static func allowedWindowDuration(closestTo preferred: CMTime, constraint: SNTimeDurationConstraint) -> CMTime {
        let target = preferred.seconds
        if case .enumeratedDurations(let durations) = constraint {
            let closest = durations.min { abs($0.seconds - target) < abs($1.seconds - target) }
            return closest ?? preferred
        }
        if case .durationRange(let range) = constraint {
            if target < range.lowerBound.seconds {
                return range.lowerBound
            }
            if target > range.upperBound.seconds {
                return range.upperBound
            }
        }
        return preferred
    }

    // MARK: - SoundClassifying

    func analyze(_ buffer: AVAudioPCMBuffer, atFramePosition position: AVAudioFramePosition) {
        analyzer.analyze(buffer, atAudioFramePosition: position)
    }

    func completeAnalysis() {
        analyzer.completeAnalysis()
    }

    // MARK: - SNResultsObserving

    /// Runs synchronously inside `analyze` / `completeAnalysis` on the analysis queue.
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let start = timeOffset + result.timeRange.start.seconds
        let end = start + result.timeRange.duration.seconds
        // SoundAnalysis already sorts by confidence, descending; sorted again so the
        // top labels do not depend on that.
        let ranked = result.classifications
            .map { RankedLabel(label: $0.identifier, confidence: $0.confidence) }
            .sorted { $0.confidence > $1.confidence }
        let window = ClassificationWindow.make(from: ranked, mapping: mapping, start: start, end: end)
        let topLabels = Array(ranked.prefix(SoundClassifierService.topLabelCount))
        delegate?.classifier(self, didProduce: window, topLabels: topLabels)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        delegate?.classifier(self, didFailWith: error)
    }

    func requestDidComplete(_ request: SNRequest) {
        // Nothing to do: the pipeline ends a segment itself with `completeAnalysis()`.
    }
}
