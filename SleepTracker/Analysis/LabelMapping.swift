import Foundation

/// Central place that maps classifier label strings to `SoundEventType`.
/// The mapping is built at runtime from the classifier's `knownClassifications`,
/// so only labels that really exist are ever mapped.
struct LabelMapping: Equatable {
    /// Candidate classifier labels per event type. Order = priority.
    /// Only candidates that appear in the classifier's known labels are used.
    static let candidates: [SoundEventType: [String]] = [
        .snoring: ["snoring"],
        .speech: ["speech"],
        .cough: ["cough"],
        .whispering: ["whispering"]
    ]

    /// Known classifier label -> event type.
    let labelToType: [String: SoundEventType]
    /// Event types for which at least one candidate label exists in the classifier.
    let availableTypes: Set<SoundEventType>

    /// Keeps only the candidate labels that occur in `knownLabels`.
    init(knownLabels: [String]) {
        let known = Set(knownLabels)
        var mapped: [String: SoundEventType] = [:]
        for type in SoundEventType.allCases {
            let labels = LabelMapping.candidates[type] ?? []
            for label in labels where known.contains(label) {
                mapped[label] = type
            }
        }
        labelToType = mapped
        availableTypes = Set(mapped.values)
    }

    /// The event type for a classifier label, or nil when the label is not mapped.
    func type(for label: String) -> SoundEventType? {
        labelToType[label]
    }
}
