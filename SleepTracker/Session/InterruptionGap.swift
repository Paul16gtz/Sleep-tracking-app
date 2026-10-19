import Foundation

/// A span of a session during which audio capture was interrupted.
/// Times are seconds since the session start.
struct InterruptionGap: Codable, Equatable {
    /// Seconds since session start at which capture stopped.
    var start: TimeInterval
    /// Seconds since session start at which capture resumed; nil means the gap lasts until the session ends.
    var end: TimeInterval?
    /// Raw value of the audio interruption reason.
    var reason: String
}
