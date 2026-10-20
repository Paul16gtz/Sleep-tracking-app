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

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Es läuft bereits eine Aufnahme."
        case .microphoneDenied:
            return "Kein Zugriff auf das Mikrofon. Bitte in den Einstellungen erlauben."
        case .classifierUnavailable(let message):
            return "Die Geräuscherkennung ist nicht verfügbar: \(message)"
        }
    }
}

/// Orchestrates one night: starts the audio pipeline and the motion capture, stores
/// their epochs, events and gaps as they arrive, publishes the live state for the UI
/// and finishes the session.
///
/// Test mode (spec B8): the same pipeline reads an audio file instead of the microphone,
/// without fall-asleep delay and without motion, into a session marked `isTest`. The
/// file runs faster than real time, so a test session ends no earlier than the latest
/// stream time its pipeline reported.
///
/// Threading (spec B4): the controller and every repository call run on the main
/// actor. The pipeline calls its delegate on its analysis queue; the delegate methods
/// are `nonisolated` and only hand their arguments to the main queue with
/// `DispatchQueue.main.async`. The main queue is serial, so results are handled in the
/// order the pipeline reported them, and a block that `stop()` enqueues runs after the
/// results the pipeline reported while stopping.
///
/// Motion samples arrive on the motion source's operation queue. The session's
/// `MotionProcessor` moves each one to its serial motion queue, where the analyzer
/// runs, and reports completed motion epochs and throttled live values to `nonisolated`
/// methods that hop to the main queue in the same way. On the main queue an
/// `EpochMerger` joins the level and the motion epoch of each index into one stored epoch.
///
/// Results are matched to their session by the pipeline or the motion processor that
/// reported them. `stop()` waits for the motion queue and the pipeline to finish, but
/// the last events and epochs they report then reach the main queue only after
/// `stop()` has returned, so the stopped session is kept until they are stored.
@MainActor
final class SleepSessionController: ObservableObject {
    /// Seconds of audio the pre-roll ring buffer holds.
    private static let ringBufferDuration: TimeInterval = 10
    /// Minimum stream time between two live level updates (at most 5 per second).
    private static let levelUpdateInterval: TimeInterval = 0.2
    /// Minimum sample time between two live motion updates (at most 5 per second).
    private static let motionUpdateInterval: TimeInterval = 0.2
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
    /// Latest acceleration magnitude in g (about 1 at rest), updated at most 5 times per
    /// second; 0 without motion capture.
    @Published private(set) var liveMotionMagnitude: Double = 0
    /// Resting movement level of the running night; nil until the calibration is complete.
    @Published private(set) var motionBaseline: Double? = nil
    /// `true` while the running night records motion.
    @Published private(set) var isMotionActive: Bool = false
    /// `true` while audio capture of the running session is interrupted (a gap is open).
    @Published private(set) var isCaptureInterrupted: Bool = false
    /// Message for an alert (German); nil means no error. Views set it to nil to dismiss.
    @Published var errorMessage: String? = nil

    /// `true` when the iPhone is connected to power (charging or full). Battery
    /// monitoring is enabled in `init`.
    var isCharging: Bool {
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    /// The motion source of a session together with the processor that analyzes its samples.
    private struct MotionCapture {
        let source: MotionSource
        let processor: MotionProcessor
    }

    /// A session together with what records it. A class, so that the merger of the
    /// running and of the stopped session can be updated in place.
    private final class Recording {
        let session: SleepSession
        let pipeline: AudioPipeline
        /// nil when the night records no motion.
        var motion: MotionCapture?
        /// Joins the level and the motion epochs of this session. Expects no motion
        /// until `startMotion` replaces it, which happens before the first epoch arrives.
        var merger: EpochMerger
        /// Latest stream time in seconds since session start that the pipeline reported
        /// (window ends, epoch starts, event ends). A test session ends no earlier.
        var latestStreamTime: TimeInterval = 0

        init(session: SleepSession, pipeline: AudioPipeline) {
            self.session = session
            self.pipeline = pipeline
            self.motion = nil
            self.merger = EpochMerger(expectsMotion: false)
        }
    }

    private let repository: SessionRepository
    private let fileStore: FileStore
    private let settingsStore: SettingsStore
    private let sourceFactory: (DispatchQueue) -> AudioSource
    /// Returns the source that reads a test file, calling back on the given queue.
    private let fileSourceFactory: (URL, DispatchQueue) -> AudioSource
    private let classifierFactoryProvider: (LabelMapping) -> SoundClassifierFactory
    private let knownLabelsProvider: () throws -> [String]
    /// Returns the motion source for a night, or nil to record without motion.
    private let motionSourceFactory: () -> MotionSource?

    /// The running session; nil when idle.
    private var current: Recording?
    /// The session `stop()` ended last, kept until the results its pipeline and its
    /// motion processor reported while stopping and the rest of its merger have been stored.
    private var stopped: Recording?
    /// `true` while `start` waits for the permission and sets up the pipeline.
    private var isStarting = false
    /// Gaps of the running session closed so far, in the order they were reported.
    private var gaps: [InterruptionGap] = []
    /// `true` while `errorMessage` shows the restart failure of the running session, which
    /// is withdrawn when capture resumes after all.
    private var showsRestartFailure = false
    private var fallAsleepDelay: TimeInterval = 0
    private var lastTopLabelsUpdate: Date?
    private var tickTimer: Timer?
    private var saveTimer: Timer?

    init(
        repository: SessionRepository,
        fileStore: FileStore,
        settingsStore: SettingsStore,
        sourceFactory: @escaping (DispatchQueue) -> AudioSource,
        fileSourceFactory: @escaping (URL, DispatchQueue) -> AudioSource,
        classifierFactoryProvider: @escaping (LabelMapping) -> SoundClassifierFactory,
        knownLabelsProvider: @escaping () throws -> [String],
        motionSourceFactory: @escaping () -> MotionSource?
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.settingsStore = settingsStore
        self.sourceFactory = sourceFactory
        self.fileSourceFactory = fileSourceFactory
        self.classifierFactoryProvider = classifierFactoryProvider
        self.knownLabelsProvider = knownLabelsProvider
        self.motionSourceFactory = motionSourceFactory
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    /// Asks for microphone access; returns at once when it was already granted or denied.
    static func requestMicrophonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Start and stop

    /// Starts a session. Throws `ControllerError` when a session is running or starting,
    /// for a night without microphone access and when the classifier is unavailable;
    /// rethrows repository and audio start errors (for the test mode also a file that
    /// cannot be opened). If the audio start fails, the new session is stored as ended
    /// unexpectedly. A night starts the motion capture after the audio; if that fails,
    /// only `errorMessage` is set and the night records sound without motion. The test
    /// mode (spec B8) reads the file at `fileURL` without asking for the microphone,
    /// counts events from its first second (fall-asleep delay 0), records no motion and
    /// stores a session marked `isTest`; it stops by itself at the end of the file. When
    /// the classifier knows no label for snoring or speech, `errorMessage` says so and the
    /// session starts anyway.
    func start(mode: SessionMode) async throws {
        guard !isRunning, !isStarting else {
            throw ControllerError.alreadyRunning
        }
        // `start` suspends while it waits for the permission; a second call meanwhile
        // must not start another session.
        isStarting = true
        defer { isStarting = false }

        let testFileURL: URL?
        switch mode {
        case .night:
            testFileURL = nil
        case .test(let fileURL):
            testFileURL = fileURL
        }
        let isTest = testFileURL != nil

        if !isTest {
            guard await SleepSessionController.requestMicrophonePermission() else {
                throw ControllerError.microphoneDenied
            }
        }

        let labels: [String]
        do {
            labels = try knownLabelsProvider()
        } catch {
            throw ControllerError.classifierUnavailable(error.localizedDescription)
        }
        let mapping = LabelMapping(knownLabels: labels)
        // Without a label a type would never be detected, and nothing would say so.
        if let warning = SleepSessionController.missingLabelWarning(for: mapping) {
            errorMessage = warning
        }

        var settings = settingsStore.settings
        if isTest {
            // The file is analyzed from its first second; the snapshot stores the 0.
            settings.fallAsleepDelay = 0
        }
        let now = Date()
        let session = try repository.createSession(startDate: now, settings: settings, isTest: isTest)

        let queue = DispatchQueue(label: "sleeptracker.analysis", qos: .userInitiated)
        let source: AudioSource
        if let testFileURL = testFileURL {
            source = fileSourceFactory(testFileURL, queue)
        } else {
            source = sourceFactory(queue)
        }
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
        let recording = Recording(session: session, pipeline: pipeline)
        current = recording
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

        // No suspension point since `pipeline.start()`, so no epoch has reached the
        // merger yet. The test mode (spec B8) records no motion: the motion source
        // factory is not called, the merger that expects none is kept and
        // `isMotionActive` stays false (as reset by the last stop).
        if case .night = mode {
            startMotion(for: recording, settings: settings, sessionStart: now)
        }

        startTimers()
        isTestRun = isTest
        startDate = now
        tick()
        isRunning = true
    }

    /// Ends the running session: stops the timers, the motion capture and the pipeline,
    /// stores the end date and the final gaps and resets the live state. The last
    /// epochs are stored one main-queue turn later. Does nothing when no session runs.
    func stop() {
        guard let recording = current else {
            return
        }
        tickTimer?.invalidate()
        tickTimer = nil
        saveTimer?.invalidate()
        saveTimer = nil

        // `finish()` returns when the motion queue has handled the samples queued before
        // it, so the epochs they completed are already queued for the main queue; later
        // samples are ignored. The motion queue never waits for the main queue.
        var finalMotion: MotionEpoch?
        if let motion = recording.motion {
            motion.source.stop()
            finalMotion = motion.processor.finish()
        }

        // Returns when the pipeline has finished on its queue. The last events, the
        // partial epoch and a gap that ends now are reported during this call; their
        // main-queue hops run after `stop()` and are stored for `stopped`.
        recording.pipeline.stop()
        // The pipeline has finished, so its gaps no longer change.
        let finalGaps = recording.pipeline.gaps
        current = nil
        stopped = recording
        do {
            try repository.finishSession(recording.session, endDate: endDate(of: recording), status: .ended, gaps: finalGaps)
        } catch {
            reportStorageError(error)
        }
        resetLiveState()
        isRunning = false

        // Runs after the hops queued before `processor.finish()` returned and during
        // `pipeline.stop()`: the main queue is serial. It stores the last merged epochs,
        // then releases the stopped session.
        DispatchQueue.main.async { [weak self] in
            self?.finishStopped(recording, finalMotion: finalMotion)
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

    /// The types the night screen counts; the classifier must know a label for each.
    private static let requiredTypes: [SoundEventType] = [.snoring, .speech]

    /// A German warning for every required type the classifier has no label for, or nil.
    private static func missingLabelWarning(for mapping: LabelMapping) -> String? {
        let sentences = requiredTypes
            .filter { !mapping.availableTypes.contains($0) }
            .map { type -> String in
                let label = LabelMapping.candidates[type]?.first ?? type.rawValue
                return "Der Klassifikator kennt das Label „\(label)“ nicht; \(type.germanName) wird nicht erkannt."
            }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
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
        liveMotionMagnitude = 0
        motionBaseline = nil
        isMotionActive = false
        isCaptureInterrupted = false
        showsRestartFailure = false
        gaps = []
        fallAsleepDelay = 0
        lastTopLabelsUpdate = nil
    }

    /// Starts the motion capture of `recording` when the factory returns an available
    /// source, and gives the recording a merger that expects motion only then. A failed
    /// start sets `errorMessage`; the night then records sound without motion.
    private func startMotion(for recording: Recording, settings: AppSettings, sessionStart: Date) {
        var capture: MotionCapture?
        if let source = motionSourceFactory(), source.isAvailable {
            let processor = MotionProcessor(
                config: MotionConfig(settings: settings),
                liveUpdateInterval: SleepSessionController.motionUpdateInterval
            )
            // Both set before the start: they are read on the source's queue and on the
            // motion queue.
            processor.delegate = self
            source.delegate = processor
            do {
                try source.start(referenceDate: sessionStart)
                capture = MotionCapture(source: source, processor: processor)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        recording.motion = capture
        recording.merger = EpochMerger(expectsMotion: capture != nil)
        isMotionActive = capture != nil
    }

    /// Stores what the merger of the stopped `recording` still holds and releases it.
    /// Runs after every result its motion processor and its pipeline reported, so only
    /// the motion epoch that was in progress at the stop is still to be merged.
    private func finishStopped(_ recording: Recording, finalMotion: MotionEpoch?) {
        if let finalMotion = finalMotion {
            store(recording.merger.add(motion: finalMotion), for: recording.session)
        }
        store(recording.merger.finish(), for: recording.session)
        extendTestEndDateIfNeeded(of: recording)
        if stopped === recording {
            stopped = nil
        }
    }

    /// The end date `stop()` stores: now. A test session runs faster than real time,
    /// so it ends no earlier than the latest stream time its pipeline reported; its
    /// events and epochs then lie inside the night's timeline.
    private func endDate(of recording: Recording) -> Date {
        let now = Date()
        guard recording.session.isTest else {
            return now
        }
        return max(now, recording.session.startDate.addingTimeInterval(recording.latestStreamTime))
    }

    /// A cancelled test run reports its last events and its partial epoch only after
    /// `stop()` stored the end date; when they lie beyond it, the end date moves to them.
    /// A run that reached the end of the file was stopped after all of them, so nothing
    /// changes then. Nights are not touched.
    private func extendTestEndDateIfNeeded(of recording: Recording) {
        let session = recording.session
        guard session.isTest, let storedEnd = session.endDate else {
            return
        }
        let dataEnd = session.startDate.addingTimeInterval(recording.latestStreamTime)
        guard dataEnd > storedEnd else {
            return
        }
        do {
            try repository.finishSession(session, endDate: dataEnd, status: session.status, gaps: session.interruptionGaps)
        } catch {
            reportStorageError(error)
        }
    }

    /// The recording `pipeline` belongs to: the running one, or the one `stop()` just ended.
    private func recording(for pipeline: AudioPipeline) -> Recording? {
        if let current = current, current.pipeline === pipeline {
            return current
        }
        if let stopped = stopped, stopped.pipeline === pipeline {
            return stopped
        }
        return nil
    }

    /// The recording `processor` belongs to: the running one, or the one `stop()` just ended.
    private func recording(for processor: MotionProcessor) -> Recording? {
        if let current = current, current.motion?.processor === processor {
            return current
        }
        if let stopped = stopped, stopped.motion?.processor === processor {
            return stopped
        }
        return nil
    }

    /// The session `pipeline` records: the running one, or the one `stop()` just ended.
    private func recordedSession(for pipeline: AudioPipeline) -> SleepSession? {
        recording(for: pipeline)?.session
    }

    /// `true` when `pipeline` records the running session. Live values come only from it.
    private func isCurrent(_ pipeline: AudioPipeline) -> Bool {
        current?.pipeline === pipeline
    }

    /// `true` when `processor` analyzes the running session. Live values come only from it.
    private func isCurrent(_ processor: MotionProcessor) -> Bool {
        current?.motion?.processor === processor
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
        guard let owner = recording(for: pipeline) else {
            return
        }
        noteStreamTime(epoch.start, of: owner)
        store(owner.merger.add(level: epoch), for: owner.session)
    }

    /// Remembers the latest stream time `owner`'s pipeline reported.
    private func noteStreamTime(_ time: TimeInterval, of owner: Recording) {
        guard time.isFinite else {
            return
        }
        owner.latestStreamTime = max(owner.latestStreamTime, time)
    }

    /// Stores merged epochs; each timestamp is the session start plus the epoch start.
    private func store(_ records: [EpochRecord], for session: SleepSession) {
        for record in records {
            do {
                _ = try repository.addEpoch(
                    to: session,
                    timestamp: session.startDate.addingTimeInterval(record.start),
                    averageDecibels: record.averageDecibels,
                    peakDecibels: record.peakDecibels,
                    motionIntensity: record.motionIntensity,
                    isRestless: record.isRestless
                )
            } catch {
                reportStorageError(error)
            }
        }
    }

    private func handleEventStart(_ type: SoundEventType, from pipeline: AudioPipeline) {
        guard isCurrent(pipeline) else {
            return
        }
        eventCounts[type, default: 0] += 1
    }

    private func handleFinalizedEvent(_ event: DetectedEvent, clipRelativePath: String?, from pipeline: AudioPipeline) {
        guard let owner = recording(for: pipeline) else {
            return
        }
        let session = owner.session
        noteStreamTime(event.end, of: owner)
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

    /// `time` is the end of the window in seconds since session start.
    private func handleTopLabels(_ labels: [RankedLabel], at time: TimeInterval, from pipeline: AudioPipeline) {
        if let owner = recording(for: pipeline) {
            noteStreamTime(time, of: owner)
        }
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

    private func handleGapBegin(from pipeline: AudioPipeline) {
        guard isCurrent(pipeline) else {
            return
        }
        isCaptureInterrupted = true
    }

    private func handleGap(_ gap: InterruptionGap, from pipeline: AudioPipeline) {
        // A gap reported while stopping is already in the final list that `stop()` stored.
        guard isCurrent(pipeline), let session = current?.session else {
            return
        }
        // Capture resumed, so a restart failure reported during the gap no longer holds.
        isCaptureInterrupted = false
        if showsRestartFailure, errorMessage == MicrophoneError.restartFailedMessage {
            errorMessage = nil
        }
        showsRestartFailure = false
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
        showsRestartFailure = isCurrent(pipeline) && message == MicrophoneError.restartFailedMessage
    }

    private func handlePipelineFinished(_ pipeline: AudioPipeline) {
        guard isCurrent(pipeline) else {
            return
        }
        stop()
    }

    // MARK: - Motion results (main actor)

    private func handleMotionEpochs(_ epochs: [MotionEpoch], from processor: MotionProcessor) {
        guard let owner = recording(for: processor) else {
            return
        }
        for epoch in epochs {
            store(owner.merger.add(motion: epoch), for: owner.session)
        }
    }

    private func handleMotionUpdate(_ magnitude: Double, baseline: Double?, from processor: MotionProcessor) {
        guard isCurrent(processor) else {
            return
        }
        liveMotionMagnitude = magnitude
        // The baseline changes once per night; an unchanged value is not republished.
        if motionBaseline != baseline {
            motionBaseline = baseline
        }
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
            self?.handleTopLabels(labels, at: time, from: pipeline)
        }
    }

    nonisolated func pipeline(_ pipeline: AudioPipeline, didBeginGapAt start: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.handleGapBegin(from: pipeline)
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

// MARK: - MotionProcessorDelegate

/// Called on the motion queue. Each method only moves its arguments to the main queue;
/// all state is touched in the main-actor handlers above.
extension SleepSessionController: MotionProcessorDelegate {
    fileprivate nonisolated func motionProcessor(_ processor: MotionProcessor, didCompleteEpochs epochs: [MotionEpoch]) {
        DispatchQueue.main.async { [weak self] in
            self?.handleMotionEpochs(epochs, from: processor)
        }
    }

    fileprivate nonisolated func motionProcessor(
        _ processor: MotionProcessor,
        didUpdateMagnitude magnitude: Double,
        baseline: Double?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.handleMotionUpdate(magnitude, baseline: baseline, from: processor)
        }
    }
}

// MARK: - Motion processing

/// Receives the results of a `MotionProcessor`, on its motion queue.
private protocol MotionProcessorDelegate: AnyObject {
    /// The motion epochs one sample completed, oldest first.
    func motionProcessor(_ processor: MotionProcessor, didCompleteEpochs epochs: [MotionEpoch])
    /// The latest magnitude in g and the baseline (nil while calibrating), at most once
    /// per live update interval of sample time.
    func motionProcessor(_ processor: MotionProcessor, didUpdateMagnitude magnitude: Double, baseline: Double?)
}

/// Runs the motion analysis of one session on its own serial queue.
///
/// It is the delegate of the session's motion source: each sample is moved from the
/// source's queue to `queue`, and the analyzer and the live-update state are touched
/// only there. The results go to `delegate`, called on `queue`.
private final class MotionProcessor: MotionSourceDelegate {
    /// Set before the source starts; read on `queue`.
    weak var delegate: MotionProcessorDelegate?

    private let queue = DispatchQueue(label: "sleeptracker.motion", qos: .utility)
    private let liveUpdateInterval: TimeInterval

    // Touched only on `queue`.
    private var analyzer: MotionAnalyzer
    private var lastLiveUpdate: TimeInterval?
    private var isFinished = false

    init(config: MotionConfig, liveUpdateInterval: TimeInterval) {
        self.analyzer = MotionAnalyzer(config: config)
        self.liveUpdateInterval = liveUpdateInterval
    }

    /// Called on the source's queue.
    func motionSource(_ source: MotionSource, didSample magnitude: Double, at time: TimeInterval) {
        queue.async { [weak self] in
            self?.process(magnitude, at: time)
        }
    }

    /// Ends the analysis and returns the epoch that was in progress, if any. Waits until
    /// `queue` has handled the samples queued before, so the epochs they completed have
    /// been reported; samples that arrive later are ignored. Must not be called on `queue`.
    func finish() -> MotionEpoch? {
        return queue.sync { () -> MotionEpoch? in
            guard !self.isFinished else {
                return nil
            }
            self.isFinished = true
            return self.analyzer.finish()
        }
    }

    // MARK: - Queue

    private func process(_ magnitude: Double, at time: TimeInterval) {
        guard !isFinished else {
            return
        }
        let epochs = analyzer.add(magnitude: magnitude, at: time)
        if !epochs.isEmpty {
            delegate?.motionProcessor(self, didCompleteEpochs: epochs)
        }
        if shouldUpdateLive(at: time) {
            delegate?.motionProcessor(self, didUpdateMagnitude: magnitude, baseline: analyzer.baseline)
        }
    }

    /// At most one live update per `liveUpdateInterval` of sample time. A time that
    /// jumps backwards (a wall-clock change) starts a new interval.
    private func shouldUpdateLive(at time: TimeInterval) -> Bool {
        guard time.isFinite else {
            return false
        }
        if let last = lastLiveUpdate, time >= last, time - last < liveUpdateInterval {
            return false
        }
        lastLiveUpdate = time
        return true
    }
}
