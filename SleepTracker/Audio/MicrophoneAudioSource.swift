import AVFoundation

enum MicrophoneError: LocalizedError {
    /// The input node reports no usable format (session not active or no microphone permission).
    case noInputFormat
    /// The engine could not be restarted after an interruption, not even after all retries.
    case restartFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noInputFormat:
            return "Kein Mikrofon-Eingang verfügbar."
        case .restartFailed:
            return "Aufnahme konnte nach einer Unterbrechung nicht fortgesetzt werden."
        }
    }
}

/// Live microphone capture with `AVAudioEngine` for a whole night.
///
/// Threading: `start()`, `stop()` and all engine, session and notification handling
/// run on the main thread. Delegate methods are called only on `callbackQueue`.
/// The tap block does nothing but copy the buffer into mono and dispatch it.
///
/// Segments: every successful start or restart builds a new engine and begins a new
/// segment; its frame counter starts at 0. Each tap buffer carries the number of its
/// segment, so a buffer still in flight when a segment is torn down is dropped
/// instead of being counted in the next segment (which may run at another sample rate).
///
/// Restart: on an interruption, a relevant route change, a media services reset or an
/// engine configuration change, the interruption is reported once, the engine is torn
/// down, the session is reconfigured and a new segment begins. A failed restart is
/// retried after 1, 2, 5, 10 and 30 s; when the last retry fails, `didFailWith` reports
/// `MicrophoneError.restartFailed`. The observers stay registered, so a later
/// notification can still bring capture back.
final class MicrophoneAudioSource: AudioSource {
    /// Delays before the retries that follow a failed immediate restart attempt.
    private static let retryDelays: [TimeInterval] = [1, 2, 5, 10, 30]

    weak var delegate: AudioSourceDelegate?
    let callbackQueue: DispatchQueue

    private let sessionManager: AudioSessionManager
    private let tapBufferSize: AVAudioFrameCount

    // MARK: Main-thread state

    private var engine: AVAudioEngine?
    /// `true` between `start()` and `stop()`.
    private var isRunning = false
    /// `true` between an interruption's `.began` and its `.ended`.
    private var isSystemInterrupted = false
    /// `true` once the current outage has been reported; reset when a segment begins.
    private var interruptionReported = false
    /// Number of the most recently created segment.
    private var segmentCounter = 0
    /// Incremented to cancel pending retries.
    private var restartGeneration = 0
    private var sessionObservers: [NSObjectProtocol] = []
    private var engineObserver: NSObjectProtocol?

    // MARK: callbackQueue state

    /// Segment last announced with `didBeginSegmentWith`.
    private var announcedSegment = 0
    /// Every segment up to this number is closed; its buffers are dropped.
    private var closedSegment = 0
    /// Frames delivered in the announced segment.
    private var framePosition: AVAudioFramePosition = 0

    init(callbackQueue: DispatchQueue, sessionManager: AudioSessionManager = .shared, tapBufferSize: AVAudioFrameCount = 4096) {
        self.callbackQueue = callbackQueue
        self.sessionManager = sessionManager
        self.tapBufferSize = tapBufferSize
    }

    deinit {
        for observer in sessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let engineObserver {
            NotificationCenter.default.removeObserver(engineObserver)
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
    }

    // MARK: - AudioSource

    /// Configures the session, registers the observers and begins the first segment.
    /// Call on the main thread. On failure everything is undone and the error rethrown.
    func start() throws {
        guard !isRunning else {
            return
        }
        isRunning = true
        isSystemInterrupted = false
        interruptionReported = false
        do {
            try sessionManager.configureForRecording()
            addSessionObservers()
            try beginSegment()
        } catch {
            stop()
            throw error
        }
    }

    /// Removes the observers and the tap, stops the engine, deactivates the session and
    /// cancels pending retries. Call on the main thread.
    func stop() {
        guard isRunning else {
            return
        }
        isRunning = false
        restartGeneration += 1
        removeSessionObservers()
        tearDownEngine()
        sessionManager.deactivate()
    }

    // MARK: - Segments (main thread)

    private func beginSegment() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        if inputFormat.sampleRate == 0 || inputFormat.channelCount == 0 {
            throw MicrophoneError.noInputFormat
        }
        // Right after a route change the node can briefly report a stale rate. A tap
        // whose rate differs from the hardware rate raises an exception, so this
        // attempt fails here and the retry picks up the settled format.
        let hardwareSampleRate = inputNode.inputFormat(forBus: 0).sampleRate
        if hardwareSampleRate > 0 && hardwareSampleRate != inputFormat.sampleRate {
            throw MicrophoneError.noInputFormat
        }
        guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false) else {
            throw MicrophoneError.noInputFormat
        }

        segmentCounter += 1
        let segment = segmentCounter
        let queue = callbackQueue

        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) { [weak self] buffer, _ in
            // Engine thread. The tap buffer is only valid inside this block, so it is
            // copied (downmixed) before it leaves.
            guard let mono = MonoDownmix.makeMonoBuffer(from: buffer, monoFormat: monoFormat) else {
                return
            }
            queue.async { [weak self] in
                self?.deliver(mono, segment: segment, format: monoFormat)
            }
        }

        // Registered before the start so that no change is missed.
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] notification in
            self?.handleConfigurationChange(notification)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            NotificationCenter.default.removeObserver(observer)
            inputNode.removeTap(onBus: 0)
            throw error
        }

        self.engine = engine
        engineObserver = observer
        interruptionReported = false
        queue.async { [weak self] in
            self?.announce(segment, format: monoFormat)
        }
    }

    /// Removes the tap and stops the engine; the current segment is closed.
    private func tearDownEngine() {
        if let engineObserver {
            NotificationCenter.default.removeObserver(engineObserver)
            self.engineObserver = nil
        }
        guard let engine else {
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil

        let segment = segmentCounter
        callbackQueue.async { [weak self] in
            self?.closeSegment(segment)
        }
    }

    // MARK: - Restart (main thread)

    private func restart(reason: AudioInterruptionReason) {
        guard isRunning else {
            return
        }
        reportInterruptionIfNeeded(reason)
        tearDownEngine()
        restartGeneration += 1
        attemptRestart(retryIndex: 0, generation: restartGeneration)
    }

    /// `retryIndex` 0 is the immediate attempt; 1 to 5 follow the delays in `retryDelays`.
    private func attemptRestart(retryIndex: Int, generation: Int) {
        guard isRunning, !isSystemInterrupted, generation == restartGeneration else {
            return
        }
        do {
            try sessionManager.configureForRecording()
            try beginSegment()
        } catch {
            guard retryIndex < MicrophoneAudioSource.retryDelays.count else {
                reportFailure(MicrophoneError.restartFailed(error))
                return
            }
            let delay = MicrophoneAudioSource.retryDelays[retryIndex]
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.attemptRestart(retryIndex: retryIndex + 1, generation: generation)
            }
        }
    }

    private func reportInterruptionIfNeeded(_ reason: AudioInterruptionReason) {
        guard !interruptionReported else {
            return
        }
        interruptionReported = true
        let segment = segmentCounter
        callbackQueue.async { [weak self] in
            guard let self else {
                return
            }
            // Closed first, so no late buffer of this segment follows the report.
            self.closeSegment(segment)
            self.delegate?.audioSource(self, didInterruptWith: reason)
        }
    }

    private func reportFailure(_ error: Error) {
        callbackQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.audioSource(self, didFailWith: error)
        }
    }

    // MARK: - Notifications (main thread)

    private func addSessionObservers() {
        removeSessionObservers()
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        sessionObservers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
                self?.handleInterruption(notification)
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] notification in
                self?.handleRouteChange(notification)
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
                self?.handleMediaServicesReset()
            }
        ]
    }

    private func removeSessionObservers() {
        for observer in sessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionObservers = []
    }

    private func handleInterruption(_ notification: Notification) {
        guard isRunning,
              let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        switch type {
        case .began:
            // The system has already stopped the engine. Pending retries would only
            // fail while the interruption lasts.
            isSystemInterrupted = true
            restartGeneration += 1
            reportInterruptionIfNeeded(.systemInterruption)
            tearDownEngine()
        case .ended:
            isSystemInterrupted = false
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                restart(reason: .systemInterruption)
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard isRunning,
              !isSystemInterrupted,
              let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable:
            restart(reason: .routeChange)
        default:
            break
        }
    }

    private func handleMediaServicesReset() {
        guard isRunning else {
            return
        }
        // All audio objects are invalid after a reset; restart builds a new engine
        // and reconfigures the session. A pending interruption is void as well.
        isSystemInterrupted = false
        restart(reason: .mediaServicesReset)
    }

    private func handleConfigurationChange(_ notification: Notification) {
        // Ignore a late notification of an engine that has already been replaced.
        guard isRunning,
              !isSystemInterrupted,
              let current = engine,
              (notification.object as? AVAudioEngine) === current else {
            return
        }
        restart(reason: .engineConfigurationChange)
    }

    // MARK: - Delivery (callbackQueue)

    private func announce(_ segment: Int, format: AVAudioFormat) {
        guard segment > closedSegment, segment > announcedSegment else {
            return
        }
        announcedSegment = segment
        framePosition = 0
        delegate?.audioSource(self, didBeginSegmentWith: format)
    }

    private func deliver(_ buffer: AVAudioPCMBuffer, segment: Int, format: AVAudioFormat) {
        // Normally a no-op; announces the segment if its first buffer overtook the
        // announcement dispatched after `engine.start()`.
        announce(segment, format: format)
        guard segment > closedSegment, segment == announcedSegment else {
            return
        }
        delegate?.audioSource(self, didProduce: buffer, framePosition: framePosition)
        framePosition += AVAudioFramePosition(buffer.frameLength)
    }

    private func closeSegment(_ segment: Int) {
        closedSegment = max(closedSegment, segment)
    }
}
