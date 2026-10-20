import AVFoundation

/// Why an audio source stopped delivering buffers for a while. The raw value is
/// stored as `InterruptionGap.reason`.
enum AudioInterruptionReason: String, Codable {
    case systemInterruption
    case routeChange
    case mediaServicesReset
    case engineConfigurationChange

    /// German display name shown in the UI.
    var germanName: String {
        switch self {
        case .systemInterruption: return "Unterbrechung durch das System"
        case .routeChange: return "Audio-Gerät gewechselt"
        case .mediaServicesReset: return "Audiodienste neu gestartet"
        case .engineConfigurationChange: return "Audio-Konfiguration geändert"
        }
    }
}

/// Receives the stream of an `AudioSource`. Every method runs on the source's `callbackQueue`.
protocol AudioSourceDelegate: AnyObject {
    /// A new stream segment begins (first start or restart). Called before the
    /// first buffer of the segment. Runs on `callbackQueue`.
    func audioSource(_ source: AudioSource, didBeginSegmentWith format: AVAudioFormat)
    /// A mono Float32 buffer. `framePosition` counts frames since the segment began.
    /// Runs on `callbackQueue`.
    func audioSource(_ source: AudioSource, didProduce buffer: AVAudioPCMBuffer, framePosition: AVAudioFramePosition)
    func audioSource(_ source: AudioSource, didInterruptWith reason: AudioInterruptionReason)
    func audioSource(_ source: AudioSource, didFailWith error: Error)
    /// The source ended by itself (end of file). Not called after `stop()`.
    func audioSourceDidFinish(_ source: AudioSource)
}

/// A producer of mono Float32 audio: the microphone at night, a file in test mode.
protocol AudioSource: AnyObject {
    var delegate: AudioSourceDelegate? { get set }
    /// Serial queue on which all delegate methods are called.
    var callbackQueue: DispatchQueue { get }
    func start() throws
    func stop()
}
