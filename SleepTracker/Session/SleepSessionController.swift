import AVFoundation
import Combine
import Foundation
import UIKit

/// What a session records.
enum SessionMode: Equatable {
    /// A night with the microphone.
    case night
    /// An audio file run through the same pipeline (test mode).
    case test(fileURL: URL)
}

/// Why a session could not be started.
enum ControllerError: LocalizedError {
    case alreadyRunning
    case microphoneDenied
    /// The built-in sound classifier could not be loaded; carries the underlying message.
    case classifierUnavailable(String)
    case unsupported

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Es läuft bereits eine Aufnahme."
        case .microphoneDenied:
            return "Kein Zugriff auf das Mikrofon. Bitte in den Einstellungen erlauben."
        case .classifierUnavailable(let message):
            return "Die Geräuscherkennung ist nicht verfügbar: \(message)"
        case .unsupported:
            return "Dieser Modus wird noch nicht unterstützt."
        }
    }
}

/// Orchestrates one night: starts the audio pipeline, stores its epochs, events and
/// gaps as they arrive, publishes the live state for the UI and finishes the session.
///
/// Threading (spec B4): the controller and every repository call run on the main
/// actor. The pipeline calls its delegate on its analysis queue; the delegate methods
/// are `nonisolated` and only hand their arguments to the main queue with
/// `DispatchQueue.main.async`. The main queue is serial, so results are handled in the
/// order the pipeline reported them, and a block that `stop()` enqueues runs after the
/// results the pipeline reported while stopping.
///
/// Results are matched to their session by the pipeline that reported them. `stop()`
/// waits for the pipeline to finish, but the last events and the partial epoch it
/// reports then reach the main queue only after `stop()` has returned, so the stopped
/// session is kept until they are stored.
@MainActor
final class SleepSessionController: ObservableObject {
    /// Seconds of audio the pre-roll ring buffer holds.
    private static let ringBufferDuration: TimeInterval = 10
    /// Minimum stream time between two live level updates (at most 5 per second).
    private static let levelUpdateInterval: TimeInterval = 0.2
    /// Length of one level epoch in seconds.
    private static let epochDuration: TimeInterval = 30
    /// Minimum wall-clock time between two `topLabels` updates (at most 2 per second).
    private static let topLabelsMinInterval: TimeInterval = 0.5
    /// Interval of the timer that updates `elapsed` and `isInFallAsleepDelay`.
    private static let tickInterval: TimeInterval = 1
    /// Interval of the safety save (spec A8: at the latest every 2 minutes).
    private static let saveInterval: TimeInterval = 120

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isTestRun: Bool = false
    @Published private(set) var startDate: Date? = nil
    /// Seconds since `startDate` by the wall clock, updated once per second.
    @Published private(set) var elapsed: TimeInterval = 0
    /// Live level in dBFS.
    @Published private(set) var liveLevel: Double = LevelMeter.silenceFloor
    /// Events per type confirmed in the running session.
    @Published private(set) var eventCounts: [SoundEventType: Int] = [:]
    @Published private(set) var isInFallAsleepDelay: Bool = false
    /// Raw top labels of the latest classifier window, for the Debug screen.
    @Published private(set) var topLabels: [RankedLabel] = []
    /// Message for an alert (German); nil means no error. Views set it to nil to dismiss.
    @Published var errorMessage: String? = nil

    /// `true` when the iPhone is connected to power (charging or full). Battery
    /// monitoring is enabled in `init`.
    var isCharging: Bool {
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    /// A session together with the pipeline that records it.
    private struct Recording {
        let session: SleepSession
        let pipeline: AudioPipeline
    }

    private let repository: SessionRepository
    private let fileStore: FileStore
    private let settingsStore: SettingsStore
    private let sourceFactory: (DispatchQueue) -> AudioSource
    private let classifierFactoryProvider: (LabelMapping) -> SoundClassifierFactory
    private let knownLabelsProvider: () throws -> [String]

    /// The running session; nil when idle.
    private var current: Recording?
    /// The session `stop()` ended last, kept until the results its pipeline reported
    /// while stopping have been stored.
    private var stopped: Recording?
    /// `true` while `start` waits for the permission and sets up the pipeline.
    private var isStarting = false
    /// Gaps of the running session closed so far, in the order they were reported.
    private var gaps: [InterruptionGap] = []
    private var fallAsleepDelay: TimeInterval = 0
    private var lastTopLabelsUpdate: Date?
    private var tickTimer: Timer?
    private var saveTimer: Timer?

    init(
        repository: SessionRepository,
        fileStore: FileStore,
        settingsStore: SettingsStore,
        sourceFactory: @escaping (DispatchQueue) -> AudioSource,
        classifierFactoryProvider: @escaping (LabelMapping) -> SoundClassifierFactory,
        knownLabelsProvider: @escaping () throws -> [String]
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.settingsStore = settingsStore
        self.sourceFactory = sourceFactory
        self.classifierFactoryProvider = classifierFactoryProvider
        self.knownLabelsProvider = knownLabelsProvider
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    /// Asks for microphone access; returns at once when it was already granted or denied.
    static func requestMicrophonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Start and stop

    /// Starts a session. Throws `ControllerError` when a session is running or starting,
    /// for the test mode (not supported yet), without microphone access and when the
    /// classifier is unavailable; rethrows repository and audio start errors. If the
    /// audio start fails, the new session is stored as ended unexpectedly.
    func start(mode: SessionMode) async throws {
        guard !isRunning, !isStarting else {
            throw ControllerError.alreadyRunning
        }
        guard case .night = mode else {
            throw ControllerError.unsupported
        }
        // `start` suspends while it waits for the permission; a second call meanwhile
        // must not start another session.
        isStarting = true
        defer { isStarting = false }

        guard await SleepSessionController.requestMicrophonePermission() else {
            throw ControllerError.microphoneDenied
        }

        let labels: [String]
        do {
            labels = try knownLabelsProvider()
        } catch {
            throw ControllerError.classifierUnavailable(error.localizedDescription)
        }
        let mapping = LabelMapping(knownLabels: labels)

        let settings = settingsStore.settings
        let now = Date()
        let session = try repository.createSession(startDate: now, settings: settings, isTest: false)

        let queue = DispatchQueue(label: "sleeptracker.analysis", qos: .userInitiated)
        let source = sourceFactory(queue)
        // The pipeline passes the sample rate with `prepare(sampleRate:)` at every segment begin.
        let clipWriter = ClipWriter(fileStore: fileStore, sessionID: session.id)
        let config = AudioPipeline.Config(
            settings: settings,
            countingStart: settings.fallAsleepDelay,
            ringBufferDuration: SleepSessionController.ringBufferDuration,
            levelUpdateInterval: SleepSessionController.levelUpdateInterval,
            epochDuration: SleepSessionController.epochDuration,
            sessionStart: now
        )
        let pipeline = AudioPipeline(
            source: source,
            config: config,
            mapping: mapping,
            clipWriter: clipWriter,
            classifierFactory: classifierFactoryProvider(mapping),
            clock: SleepSessionController.makeClock(since: now)
        )
        pipeline.delegate = self

        // Set before the start, so the pipeline's results are matched to this session.
        current = Recording(session: session, pipeline: pipeline)
        gaps = []
        fallAsleepDelay = settings.fallAsleepDelay
        lastTopLabelsUpdate = nil
        do {
            try pipeline.start()
        } catch {
            current = nil
            pipeline.delegate = nil
            // If this fails too, the session is marked at the next launch (spec B12).
            try? repository.finishSession(session, endDate: Date(), status: .endedUnexpectedly, gaps: [])
            resetLiveState()
            throw error
        }

        startTimers()
        isTestRun = false
        startDate = now
        tick()
        isRunning = true
    }

    /// Ends the running session: stops the timers and the pipeline, stores the end date
    /// and the final gaps and resets the live state. Does nothing when no session runs.
    func stop() {
        guard let recording = current else {
            return
        }
        tickTimer?.invalidate()
        tickTimer = nil
        saveTimer?.invalidate()
        saveTimer = nil

        // Returns when the pipeline has finished on its queue. The last events, the
        // partial epoch and a gap that ends now are reported during this call; their
        // main-queue hops run after `stop()` and are stored for `stopped`.
        recording.pipeline.stop()
        // The pipeline has finished, so its gaps no longer change.
        let finalGaps = recording.pipeline.gaps
        current = nil
        stopped = recording
        do {
            try repository.finishSession(recording.session, endDate: Date(), status: .ended, gaps: finalGaps)
        } catch {
            reportStorageError(error)
        }
        resetLiveState()
        isRunning = false

        // Runs after the hops queued during `pipeline.stop()`: the main queue is serial.
        let stoppedPipeline = recording.pipeline
        DispatchQueue.main.async { [weak self] in
            self?.releaseStopped(stoppedPipeline)
        }
    }

    // MARK: - Private

    /// Seconds since `sessionStart` by the wall clock. Built outside the main actor
    /// because the pipeline calls it on its queue.
    private nonisolated static func makeClock(since sessionStart: Date) -> () -> TimeInterval {
        return { Date().timeIntervalSince(sessionStart) }
    }

    /// Schedules the 1 s tick and the 120 s safety save on the main run loop
    /// (`start` runs on the main actor, i.e. on the main thread).
    private func startTimers() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: SleepSessionController.tickInterval, repeats: true) { [weak self] _ in
            // The timer fires on the main thread; the hop makes the main-actor access explicit.
            DispatchQueue.main.async { [weak self] in
                self?.tick()
            }
        }
        saveTimer = Timer.scheduledTimer(withTimeInterval: SleepSessionController.saveInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.saveNow()
            }
        }
    }

    private func tick() {
        guard let start = startDate else {
            return
        }
        let value = Date().timeIntervalSince(start)
        elapsed = value
        isInFallAsleepDelay = value < fallAsleepDelay
    }

    private func saveNow() {
        try? repository.save()
    }

    /// Resets the published live values and the per-session bookkeeping. `isRunning`
    /// is set by the caller; `errorMessage` stays until a view dismisses it.
    private func resetLiveState() {
        isTestRun = false
        startDate = nil
        elapsed = 0
        liveLevel = LevelMeter.silenceFloor
        eventCounts = [:]
        isInFallAsleepDelay = false
        topLabels = []
        gaps = []
        fallAsleepDelay = 0
        lastTopLabelsUpdate = nil
    }

    private func releaseStopped(_ pipeline: AudioPipeline) {
        guard stopped?.pipeline === pipeline else {
            return
        }
        stopped = nil
    }

    /// The session `pipeline` records: the running one, or the one `stop()` just ended.
    private func recordedSession(for pipeline: AudioPipeline) -> SleepSession? {
        if let current = current, current.pipeline === pipeline {
            return current.session
        }
        if let stopped = stopped, stopped.pipeline === pipeline {
            return stopped.session
        }
        return nil
    }

    /// `true` when `pipeline` records the running session. Live values come only from it.
    private func isCurrent(_ pipeline: AudioPipeline) -> Bool {
        current?.pipeline === pipeline
    }

    private func reportStorageError(_ error: Error) {
        errorMessage = "Die Daten konnten nicht gespeichert werden: \(error.localizedDescription)"
    }

    // MARK: - Pipeline results (main actor)

    private func handleLevel(_ decibels: Double, from pipeline: AudioPipeline) {
        guard isCurrent(pipeline) else {
            return
        }
        liveLevel = decibels
    }

    private func handleEpoch(_ epoch: LevelEpoch, from pipeline: AudioPipeline) {
        guard let session = recordedSession(for: pipeline) else {
            return
        }
        do {
            _ = try repository.addEpoch(
                to: session,
                timestamp: session.startDate.addingTimeInterval(epoch.start),
                averageDecibels: epoch.averageDecibels,
                peakDecibels: epoch.peakDecibels,
                motionIntensity: 0,
                isRestless: false
            )
        } catch {
            reportStorageError(error)
        }
    }

    private func handleEventStart(_ type: SoundEventType, from pipeline: AudioPipeline) {
        guard isCurrent(pipeline) else {
            return
        }
        eventCounts[type, default: 0] += 1
    }

    private func handleFinalizedEvent(_ event: DetectedEvent, clipRelativePath: String?, from pipeline: AudioPipeline) {
        guard let session = recordedSession(for: pipeline) else {
            return
        }
        do {
            _ = try repository.addEvent(
                to: session,
                type: event.type,
                startDate: session.startDate.addingTimeInterval(event.start),
                endDate: session.startDate.addingTimeInterval(event.end),
                maxConfidence: event.maxConfidence,
                averageConfidence: event.averageConfidence,
                clipRelativePath: clipRelativePath
            )
        } catch {
            reportStorageError(error)
        }
    }

    private func handleTopLabels(_ labels: [RankedLabel], from pipeline: AudioPipeline) {
        guard isCurrent(pipeline) else {
            return
        }
        let now = Date()
        if let last = lastTopLabelsUpdate, now.timeIntervalSince(last) < SleepSessionController.topLabelsMinInterval {
            return
        }
        lastTopLabelsUpdate = now
        topLabels = labels
    }

    private func handleGap(_ gap: InterruptionGap, from pipeline: AudioPipeline) {
        // A gap reported while stopping is already in the final list that `stop()` stored.
        guard isCurrent(pipeline), let session = current?.session else {
            return
        }
        gaps.append(gap)
        do {
            try repository.updateGaps(gaps, for: session)
        } catch {
            reportStorageError(error)
        }
    }

    private func handleError(_ message: String, from pipeline: AudioPipeline) {
        guard recordedSession(for: pipeline) != nil else {
            return
        }
        errorMessage = message
    }

    private func handlePipelineFinished(_ pipeline: AudioPipeline) {
        guard isCurrent(pipeline) else {
            return
        }
        stop()
    }
}

// MARK: - AudioPipelineDelegate

/// Called on the pipeline's queue. Each method only moves its arguments to the main
/// queue; all state is touched in the main-actor handlers above.
extension SleepSessionController: AudioPipelineDelegate {
    nonisolated func pipeline(_ pipeline: AudioPipeline, didUpdateLevel decibels: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.handleLevel(decibels, from: pipeline)
        }
    }

    nonisolated func pipeline(_ pipeline: AudioPipeline, didCompleteLevelEpoch epoch: LevelEpoch) {
        DispatchQueue.main.async { [weak self] in
            self?.handleEpoch(epoch, from: pipeline)
        }
    }

    nonisolated func pipeline(_ pipeline: AudioPipeline, didStartEvent type: SoundEventType, at start: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.handleEventStart(type, from: pipeline)
        }
    }

    nonisolated func pipeline(_ pipeline: AudioPipeline, didFinalizeEvent event: DetectedEvent, clipRelativePath: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.handleFinalizedEvent(event, clipRelativePath: clipRelativePath, from: pipeline)
        }
    }

    nonisolated func pipeline(_ pipeline: AudioPipeline, didProduceTopLabels labels: [RankedLabel], at time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.handleTopLabels(labels, from: pipeline)
        }
    }

    nonisolated func pipeline(_ pipeline: AudioPipeline, didRecordGap gap: InterruptionGap) {
        DispatchQueue.main.async { [weak self] in
            self?.handleGap(gap, from: pipeline)
        }
    }

    nonisolated func pipeline(_ pipeline: AudioPipeline, didReportError message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.handleError(message, from: pipeline)
        }
    }

    nonisolated func pipelineDidFinish(_ pipeline: AudioPipeline) {
        DispatchQueue.main.async { [weak self] in
            self?.handlePipelineFinished(pipeline)
        }
    }
}
