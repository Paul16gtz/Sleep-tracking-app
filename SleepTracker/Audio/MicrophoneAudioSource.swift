import AVFoundation
import UIKit

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
/// Restart: at the end of an interruption (with or without `.shouldResume`), on a
/// relevant route change, a media services reset or an engine configuration change, the
/// interruption is reported once, the engine is torn down, the session is reconfigured
/// and a new segment begins. A failed restart is retried after 1, 2, 5, 10 and 30 s;
/// when the last retry fails, `didFailWith` reports `MicrophoneError.restartFailed`. The
/// observers stay registered, so a later notification can still bring capture back.
///
/// While retries are pending the app neither records nor plays, so iOS may suspend it
/// and the retry timers would not fire. A background task assertion keeps it running
/// from the first failed attempt until success, the final failure, an interruption's
/// `.began` or `stop()`. If the assertion expires first, the failure is reported at once.
final class MicrophoneAudioSource: AudioSource {
    /// Delays before the retries that follow a failed immediate restart attempt.
    private static let retryDelays: [TimeInterval] = [1, 2, 5, 10, 30]

    weak var delegate: AudioSourceDelegate?
    let callbackQueue: DispatchQueue

    private let sessionManager: AudioSessionManager
    private let tapBufferSize: AVAudioFrameCount

    // MARK: Main-thread state

    private var engine: AVAudioEngine?
    /// The engine removed by the last teardown. It is released only at the next teardown
    /// (or in deinit), never in the teardown itself: that may run inside the engine's own
    /// configuration-change handler, where deallocating the engine can deadlock
    /// (see the note on `AVAudioEngineConfigurationChangeNotification` in AVAudioEngine.h).
    private var retiredEngine: AVAudioEngine?
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
    /// Held while restart retries are pending; `.invalid` otherwise.
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// Error of the latest failed attempt in the current restart chain.
    private var lastRestartError: Error?
    /// `true` once the current restart chain has reported its failure.
    private var restartFailureReported = false

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
        // Ends a pending assertion; its expiration handler cannot do it once self is gone.
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
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
        endBackgroundTask()
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

    /// Removes the tap and stops the engine; the current segment is closed. The engine is
    /// kept as `retiredEngine`, which releases the engine retired one teardown earlier.
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
        retiredEngine = engine
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
        lastRestartError = nil
        restartFailureReported = false
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
            endBackgroundTask()
        } catch {
            lastRestartError = error
            guard retryIndex < MicrophoneAudioSource.retryDelays.count else {
                reportRestartFailure(error)
                endBackgroundTask()
                return
            }
            beginBackgroundTaskIfNeeded()
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

    /// Reports the failure of the current restart chain once. A retry that is still
    /// scheduled may succeed later; it then simply begins a new segment.
    private func reportRestartFailure(_ error: Error) {
        guard !restartFailureReported else {
            return
        }
        restartFailureReported = true
        let failure = MicrophoneError.restartFailed(error)
        callbackQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.audioSource(self, didFailWith: failure)
        }
    }

    // MARK: - Background time (main thread)

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTask == .invalid else {
            return
        }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "MicrophoneRestart") { [weak self] in
            self?.backgroundTimeExpired()
        }
    }

    /// Called on the main thread when the background time runs out (about 30 s, which
    /// covers the retries after 1, 2, 5 and 10 s but not the one after 30 s). The failure
    /// is reported now, so the outage is not silent while the app is suspended.
    private func backgroundTimeExpired() {
        if let lastRestartError {
            reportRestartFailure(lastRestartError)
        }
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
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
            // fail while the interruption lasts, so they and their assertion end here.
            isSystemInterrupted = true
            restartGeneration += 1
            endBackgroundTask()
            reportInterruptionIfNeeded(.systemInterruption)
            tearDownEngine()
        case .ended:
            // Restart on every end, with or without `.shouldResume`: a night recording
            // must always resume. If another app still holds the session, activation
            // fails and the retry chain takes over.
            isSystemInterrupted = false
            restart(reason: .systemInterruption)
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
