import Foundation
import SwiftData

/// Lifecycle state of a recorded night. Stored as its raw value in `SleepSession.statusRaw`.
enum SessionStatus: String, Codable {
    case running
    case ended
    case endedUnexpectedly

    /// German display name shown in the UI.
    var germanName: String {
        switch self {
        case .running: return "Läuft"
        case .ended: return "Beendet"
        case .endedUnexpectedly: return "Unerwartet beendet"
        }
    }
}

/// One recorded night (or one test-mode run).
/// Status, settings snapshot and interruption gaps are stored as `String` / JSON `Data`
/// and exposed through typed computed properties.
@Model
final class SleepSession {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var statusRaw: String
    var isTest: Bool
    var settingsSnapshotData: Data
    var interruptionGapsData: Data
    @Relationship(deleteRule: .cascade, inverse: \SoundEvent.session) var events: [SoundEvent] = []
    @Relationship(deleteRule: .cascade, inverse: \EpochSample.session) var epochs: [EpochSample] = []

    init(id: UUID = UUID(), startDate: Date, settings: AppSettings, isTest: Bool = false) {
        self.id = id
        self.startDate = startDate
        self.endDate = nil
        self.statusRaw = SessionStatus.running.rawValue
        self.isTest = isTest
        self.settingsSnapshotData = (try? JSONEncoder().encode(settings)) ?? Data()
        self.interruptionGapsData = (try? JSONEncoder().encode([InterruptionGap]())) ?? Data()
        self.events = []
        self.epochs = []
    }

    /// Unknown raw values read as `.endedUnexpectedly`.
    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .endedUnexpectedly }
        set { statusRaw = newValue.rawValue }
    }

    /// Settings in effect when the session started; undecodable data reads as the defaults.
    var settingsSnapshot: AppSettings {
        (try? JSONDecoder().decode(AppSettings.self, from: settingsSnapshotData)) ?? AppSettings()
    }

    /// Undecodable data reads as no gaps. If encoding fails (non-finite times),
    /// the previously stored gaps are kept.
    var interruptionGaps: [InterruptionGap] {
        get { (try? JSONDecoder().decode([InterruptionGap].self, from: interruptionGapsData)) ?? [] }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                interruptionGapsData = data
            }
        }
    }

    /// Length of the session; a session without end date runs until now.
    var duration: TimeInterval {
        (endDate ?? Date()).timeIntervalSince(startDate)
    }
}

/// One detected (and possibly merged) sound event with an optional clip.
@Model
final class SoundEvent {
    @Attribute(.unique) var id: UUID
    var typeRaw: String
    var startDate: Date
    var endDate: Date
    var maxConfidence: Double
    var averageConfidence: Double
    /// Path relative to `FileStore.baseDirectory`; nil when no clip was recorded.
    var clipRelativePath: String?
    var session: SleepSession?

    init(
        id: UUID = UUID(),
        type: SoundEventType,
        startDate: Date,
        endDate: Date,
        maxConfidence: Double,
        averageConfidence: Double,
        clipRelativePath: String?
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.maxConfidence = maxConfidence
        self.averageConfidence = averageConfidence
        self.clipRelativePath = clipRelativePath
        self.session = nil
    }

    /// Unknown raw values read as `.speech`.
    var type: SoundEventType {
        SoundEventType(rawValue: typeRaw) ?? .speech
    }

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
}

/// Aggregated level and motion values for one 30 s epoch.
@Model
final class EpochSample {
    var timestamp: Date
    var motionIntensity: Double
    var isRestless: Bool
    var averageDecibels: Double
    var peakDecibels: Double
    var session: SleepSession?

    init(timestamp: Date, motionIntensity: Double, isRestless: Bool, averageDecibels: Double, peakDecibels: Double) {
        self.timestamp = timestamp
        self.motionIntensity = motionIntensity
        self.isRestless = isRestless
        self.averageDecibels = averageDecibels
        self.peakDecibels = peakDecibels
        self.session = nil
    }
}
