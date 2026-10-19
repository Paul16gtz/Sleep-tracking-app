import SwiftUI

/// Shared colors for the dark, night-friendly UI.
enum Theme {
    static let background: Color = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let card: Color = Color(red: 0.11, green: 0.12, blue: 0.16)
    static let accent: Color = Color(red: 0.55, green: 0.65, blue: 1.0)
    static let nightDim: Color = Color.black

    static func color(for type: SoundEventType) -> Color {
        switch type {
        case .snoring: return .orange
        case .speech: return .teal
        case .cough: return .red
        case .whispering: return .purple
        }
    }
}
