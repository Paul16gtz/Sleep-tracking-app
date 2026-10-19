import Foundation

/// User-adjustable detection and recording parameters.
/// Decoding is tolerant: every missing key falls back to its default value.
struct AppSettings: Codable, Equatable {
    /// Default detection threshold applied to every category.
    static let defaultThreshold: Double = 0.6

    var fallAsleepDelay: TimeInterval = 900
    /// Detection thresholds keyed by `SoundEventType.rawValue`.
    var thresholds: [String: Double] = Dictionary(
        uniqueKeysWithValues: SoundEventType.allCases.map { ($0.rawValue, AppSettings.defaultThreshold) }
    )
    var minConsecutiveWindows: Int = 2
    var eventEndGap: TimeInterval = 4
    var mergeGap: TimeInterval = 10
    var maxEventDuration: TimeInterval = 600
    var clipPreRoll: TimeInterval = 5
    var clipPostRoll: TimeInterval = 5
    var clipMaxDuration: TimeInterval = 60
    var speechClipLimitPerNight: Int = 50
    var snoringClipMinInterval: TimeInterval = 600
    var snoringClipLimitPerNight: Int = 20
    var restlessFactor: Double = 3.0
    var motionCalibrationDuration: TimeInterval = 300

    private enum CodingKeys: String, CodingKey {
        case fallAsleepDelay
        case thresholds
        case minConsecutiveWindows
        case eventEndGap
        case mergeGap
        case maxEventDuration
        case clipPreRoll
        case clipPostRoll
        case clipMaxDuration
        case speechClipLimitPerNight
        case snoringClipMinInterval
        case snoringClipLimitPerNight
        case restlessFactor
        case motionCalibrationDuration
    }

    /// All values at their defaults.
    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        fallAsleepDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .fallAsleepDelay)
            ?? defaults.fallAsleepDelay
        thresholds = try container.decodeIfPresent([String: Double].self, forKey: .thresholds)
            ?? defaults.thresholds
        minConsecutiveWindows = try container.decodeIfPresent(Int.self, forKey: .minConsecutiveWindows)
            ?? defaults.minConsecutiveWindows
        eventEndGap = try container.decodeIfPresent(TimeInterval.self, forKey: .eventEndGap)
            ?? defaults.eventEndGap
        mergeGap = try container.decodeIfPresent(TimeInterval.self, forKey: .mergeGap)
            ?? defaults.mergeGap
        maxEventDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .maxEventDuration)
            ?? defaults.maxEventDuration
        clipPreRoll = try container.decodeIfPresent(TimeInterval.self, forKey: .clipPreRoll)
            ?? defaults.clipPreRoll
        clipPostRoll = try container.decodeIfPresent(TimeInterval.self, forKey: .clipPostRoll)
            ?? defaults.clipPostRoll
        clipMaxDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .clipMaxDuration)
            ?? defaults.clipMaxDuration
        speechClipLimitPerNight = try container.decodeIfPresent(Int.self, forKey: .speechClipLimitPerNight)
            ?? defaults.speechClipLimitPerNight
        snoringClipMinInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .snoringClipMinInterval)
            ?? defaults.snoringClipMinInterval
        snoringClipLimitPerNight = try container.decodeIfPresent(Int.self, forKey: .snoringClipLimitPerNight)
            ?? defaults.snoringClipLimitPerNight
        restlessFactor = try container.decodeIfPresent(Double.self, forKey: .restlessFactor)
            ?? defaults.restlessFactor
        motionCalibrationDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .motionCalibrationDuration)
            ?? defaults.motionCalibrationDuration
    }

    /// Detection threshold for a category; falls back to the default when none is stored.
    func threshold(for type: SoundEventType) -> Double {
        thresholds[type.rawValue] ?? AppSettings.defaultThreshold
    }

    mutating func setThreshold(_ value: Double, for type: SoundEventType) {
        thresholds[type.rawValue] = value
    }
}
