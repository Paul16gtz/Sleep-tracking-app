import Foundation

/// The four sound categories the app detects and reports.
enum SoundEventType: String, Codable, CaseIterable, Identifiable {
    case snoring
    case speech
    case cough
    case whispering

    var id: String { rawValue }

    /// German display name shown in the UI.
    var germanName: String {
        switch self {
        case .snoring: return "Schnarchen"
        case .speech: return "Sprechen"
        case .cough: return "Husten"
        case .whispering: return "Flüstern"
        }
    }

    /// SF Symbols name used for this category.
    var symbolName: String {
        switch self {
        case .snoring: return "zzz"
        case .speech: return "bubble.left.fill"
        case .cough: return "wind"
        case .whispering: return "ear.fill"
        }
    }
}
