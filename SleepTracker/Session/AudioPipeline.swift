import AVFoundation

/// Receives the results of an `AudioPipeline`.
///
/// Every method is called on `pipeline.queue`, including the calls made while
/// `stop()` runs. `stop()` blocks its caller (the main thread) until the pipeline has
/// finished on that queue, so implementations hand results to the main actor
/// asynchronously and never wait synchronously for the main thread.
protocol AudioPipelineDelegate: AnyObject {
    /// Live level in dBFS, at most once per `Config.levelUpdateInterval` of stream time.
    func pipeline(_ pipeline: AudioPipeline, didUpdateLevel decibels: Double)
    /// A completed loudness epoch; when the session ends, also the last partial one.
    func pipeline(_ pipeline: AudioPipeline, didCompleteLevelEpoch epoch: LevelEpoch)
    /// An event was confirmed; `start` is in seconds since session start.
    func pipeline(_ pipeline: AudioPipeline, didStartEvent type: SoundEventType, at start: TimeInterval)
    /// An event is complete. `clipRelativePath` is the clip recorded for it, if any.
    func pipeline(_ pipeline: AudioPipeline, didFinalizeEvent event: DetectedEvent, clipRelativePath: String?)
    /// Raw top labels of one classifier window for the Debug screen; `time` is the window end.
    func pipeline(_ pipeline: AudioPipeline, didProduceTopLabels labels: [RankedLabel], at time: TimeInterval)
    /// An interruption gap was closed: capture resumed, or the session ended during the gap.
    func pipeline(_ pipeline: AudioPipeline, didRecordGap gap: InterruptionGap)
    /// A message for the user (German).
    func pipeline(_ pipeline: AudioPipeline, didReportError message: String)
    /// The source ended by itself (end of the test file); the session is finished.
    func pipelineDidFinish(_ pipeline: AudioPipeline)
}

/// Connects an `AudioSource` with the classifier, the level meter, the ring buffer,
/// the event detector and the clip recorder.
///
/// Time (spec B2): seconds since session start. A segment begins at
/// `segmentBase = clock()`; a buffer ends at `segmentBase + frames / sampleRate`.
/// Detector, epochs, clip policy and clip recorder live for the whole session; the
/// classifier and the ring buffer are rebuilt for every segment.
///
/// Threading (spec B4): all mutable state lives on `queue`, the source's callback
/// queue. The source calls its delegate there. The classifier is expected to call
/// back synchronously inside `analyze` / `completeAnalysis`, i.e. on `queue` as well;
/// a result that arrives on another thread is moved to `queue` asynchronously.
/// `start()` and `stop()` are called from the main thread.
final class AudioPipeline: AudioSourceDelegate, SoundClassifierDelegate {
    struct Config {
        var settings: AppSettings
        /// Fall-asleep delay in seconds: windows starting earlier are ignored (0 in test mode).
        var countingStart: TimeInterval
        /// Length of the pre-roll ring buffer in seconds (10).
        var ringBufferDuration: TimeInterval
        /// Minimum stream time between two live level updates in seconds (0.2).
        var levelUpdateInterval: TimeInterval
        /// Length of one level epoch in seconds (30).
        var epochDuration: TimeInterval
        /// Wall-clock start of the session; turns relative clip start times into dates.
        var sessionStart: Date
    }

    /// The source's callback queue. Every delegate method is called on it.
    let queue: DispatchQueue
    weak var delegate: AudioPipelineDelegate?
    /// Interruption gaps so far. While capture is interrupted, the last one is open
    /// (`end == nil`). Read it on `queue` or after `stop()` has returned.
    private(set) var gaps: [InterruptionGap] = []
    /// The label mapping the classifier factory was built with. Windows arrive
    /// already mapped to event types.
    let mapping: LabelMapping

    private let source: AudioSource
    private let config: Config
    private let clipWriter: ClipWriting
    private let classifierFactory: SoundClassifierFactory
    private let clock: () -> TimeInterval
    /// Marks `queue`, so a callback can tell whether it runs on it.
    private let queueKey = DispatchSpecificKey<Void>()

    // MARK: Segment state (queue)

    private var segmentBase: TimeInterval = 0
    /// Sample rate of the current segment; 0 before the first usable segment.
    private var sampleRate: Double = 0
    private var currentClassifier: SoundClassifying?
    /// Replaced at every segment begin with a buffer of `ringBufferDuration` seconds.
    private var ringBuffer = RingBuffer(capacity: 1)
    private var levelThrottle: LevelThrottle
    /// End of the latest buffer in seconds since session start.
    private var lastBufferEnd: TimeInterval = 0

    // MARK: Session state (queue)

    /// Created with the first segment; set to nil when the session finishes, so
    /// windows that arrive later are dropped.
    private var detector: EventDetector?
    private var epochs: LevelEpochAggregator
    private var clipPolicy: ClipPolicy
    /// Created with the first segment because it counts samples at the segment's rate.
    /// Kept across segments, so a clip can continue over a segment boundary.
    private var recorder: ClipRecorder?
    private var recorderSampleRate: Double = 0
    /// Type of the clip that is open in `clipWriter`; nil while none is open.
    private var activeClipType: SoundEventType?
    /// Clip path per event type, set when the clip is opened and handed out with the
    /// finalized event.
    private var clipPathByType: [SoundEventType: String] = [:]
    /// Clip errors are reported once per session; later clips fail silently.
    private var hasReportedClipError = false
    /// `true` once the session is finished; later callbacks are ignored.
    private var isFinished = false

    init(
        source: AudioSource,
        config: Config,
        mapping: LabelMapping,
        clipWriter: ClipWriting,
        classifierFactory: @escaping SoundClassifierFactory,
        clock: @escaping () -> TimeInterval
    ) {
        self.source = source
        self.queue = source.callbackQueue
        self.config = config
        self.mapping = mapping
        self.clipWriter = clipWriter
        self.classifierFactory = classifierFactory
        self.clock = clock
        self.levelThrottle = LevelThrottle(minInterval: config.levelUpdateInterval)
        // Both only count per session and do not depend on the sample rate.
        self.epochs = LevelEpochAggregator(epochDuration: config.epochDuration)
        self.clipPolicy = ClipPolicy(config: ClipPolicy.Config(settings: config.settings))
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        queue.setSpecific(key: queueKey, value: nil)
    }

    /// Becomes the source's delegate and starts the source. Call on the main thread.
    func start() throws {
        source.delegate = self
        try source.start()
    }

    /// Stops the source, then finishes the session on `queue` and returns when that is
    /// done: the classifier's last windows are processed, active and pending events
    /// are finalized, an open clip is closed, the partial epoch is reported and an
    /// open gap ends now. The session is finished only once, also when the source has
    /// already finished by itself. Call on the main thread.
    func stop() {
        source.stop()
        if isOnQueue {
            // Called from a delegate method: waiting for the queue would deadlock.
            finishSegment()
        } else {
            queue.sync {
                self.finishSegment()
            }
        }
    }

    // MARK: - AudioSourceDelegate (queue)

    func audioSource(_ source: AudioSource, didBeginSegmentWith format: AVAudioFormat) {
        guard !isFinished else { return }
        let base = clock()
        let rate = format.sampleRate
        // Normally already done by the interruption that ended the previous segment.
        completeClassifier()
        guard rate.isFinite, rate > 0 else {
            // Buffers are dropped until a segment with a usable format begins.
            sampleRate = 0
            report("Das Audioformat der Aufnahme wird nicht unterstützt.")
            return
        }

        segmentBase = base
        lastBufferEnd = max(lastBufferEnd, base)

        // The clip writer ends an open clip when the sample rate changes, so the
        // recorder, which counts samples at the old rate, is closed and replaced.
        if recorder != nil, recorderSampleRate != rate {
            if let actions = recorder?.finish() {
                perform(actions)
            }
            recorder = nil
        }
        if recorder == nil {
            recorder = ClipRecorder(
                preRoll: config.settings.clipPreRoll,
                postRoll: config.settings.clipPostRoll,
                maxDuration: config.settings.clipMaxDuration,
                sampleRate: rate
            )
            recorderSampleRate = rate
        }
        if detector == nil {
            detector = EventDetector(
                config: DetectorConfig(settings: config.settings, countingStart: config.countingStart)
            )
        }

        sampleRate = rate
        clipWriter.prepare(sampleRate: rate)
        ringBuffer = RingBuffer(capacity: Int(config.ringBufferDuration * rate))
        levelThrottle = LevelThrottle(minInterval: config.levelUpdateInterval)

        do {
            let newClassifier = try classifierFactory(format, base)
            newClassifier.delegate = self
            currentClassifier = newClassifier
        } catch {
            // Levels, epochs and an open clip keep running without classification.
            report(error.localizedDescription)
        }

        closeOpenGap(at: base)
    }

    func audioSource(_ source: AudioSource, didProduce buffer: AVAudioPCMBuffer, framePosition: AVAudioFramePosition) {
        guard !isFinished, sampleRate > 0 else { return }
        let samples = MonoDownmix.samples(of: buffer)
        let bufferEnd = segmentBase + Double(framePosition + Int64(buffer.frameLength)) / sampleRate
        lastBufferEnd = bufferEnd

        let decibels = LevelMeter.rmsDecibels(samples)
        if levelThrottle.shouldEmit(at: bufferEnd) {
            delegate?.pipeline(self, didUpdateLevel: decibels)
        }
        for epoch in epochs.add(decibels: decibels, at: bufferEnd) {
            delegate?.pipeline(self, didCompleteLevelEpoch: epoch)
        }

        ringBuffer.write(samples)
        if let actions = recorder?.append(samples) {
            perform(actions)
        }
        // Windows completed by this buffer arrive during this call (see SoundClassifying).
        currentClassifier?.analyze(buffer, atFramePosition: framePosition)
    }

    func audioSource(_ source: AudioSource, didInterruptWith reason: AudioInterruptionReason) {
        guard !isFinished else { return }
        // One open gap at a time; a further report before capture resumes adds nothing.
        if !hasOpenGap {
            gaps.append(InterruptionGap(start: lastBufferEnd, end: nil, reason: reason.rawValue))
        }
        completeClassifier()
    }

    func audioSource(_ source: AudioSource, didFailWith error: Error) {
        guard !isFinished else { return }
        report(error.localizedDescription)
    }

    func audioSourceDidFinish(_ source: AudioSource) {
        guard !isFinished else { return }
        finishSegment()
        delegate?.pipelineDidFinish(self)
    }

    // MARK: - SoundClassifierDelegate

    func classifier(_ classifier: SoundClassifying, didProduce window: ClassificationWindow, topLabels: [RankedLabel]) {
        runOnQueue { [weak self] in
            self?.handleWindow(window, topLabels: topLabels)
        }
    }

    func classifier(_ classifier: SoundClassifying, didFailWith error: Error) {
        let message = error.localizedDescription
        runOnQueue { [weak self] in
            guard let self, !self.isFinished else { return }
            self.report(message)
        }
    }

    // MARK: - Analysis (queue)

    private func handleWindow(_ window: ClassificationWindow, topLabels: [RankedLabel]) {
        // No detector before the first segment and after the session finished.
        guard detector != nil else { return }
        delegate?.pipeline(self, didProduceTopLabels: topLabels, at: window.end)
        if let outputs = detector?.process(window) {
            handle(outputs)
        }
    }

    private func handle(_ outputs: [DetectorOutput]) {
        for output in outputs {
            switch output {
            case let .eventStarted(type, start, detectedAt):
                delegate?.pipeline(self, didStartEvent: type, at: start)
                beginClipIfAllowed(type: type, start: start, detectedAt: detectedAt)
            case let .eventResumed(type):
                if activeClipType == type {
                    recorder?.eventResumed()
                }
            case let .eventEnded(type, _):
                if activeClipType == type, let actions = recorder?.eventEnded() {
                    perform(actions)
                }
            case let .eventFinalized(event):
                // The path is known since the clip was opened, so the event can be
                // delivered at once, even while its clip is still in the post-roll.
                delegate?.pipeline(self, didFinalizeEvent: event, clipRelativePath: clipPathByType[event.type])
                clipPathByType[event.type] = nil
            }
        }
    }

    /// Opens a clip for a newly started event when no clip is open and the clip policy
    /// grants one. The pre-roll reaches back to `start - preRoll` (spec B7), limited to
    /// what the ring buffer holds.
    private func beginClipIfAllowed(type: SoundEventType, start: TimeInterval, detectedAt: TimeInterval) {
        guard let idleRecorder = recorder, !idleRecorder.isActive,
              clipPolicy.shouldRecordClip(for: type, at: detectedAt) else {
            return
        }
        let preRoll = ringBuffer.latest(idleRecorder.preRollSampleCount(eventStart: start, now: detectedAt))
        if let actions = recorder?.begin(type: type, eventStart: start, preRollSamples: preRoll) {
            perform(actions)
        }
    }

    /// Executes the recorder's actions in order. When the clip writer throws, the clip
    /// is given up and the remaining actions are dropped; the session goes on.
    private func perform(_ actions: [ClipRecorderAction]) {
        for action in actions {
            do {
                switch action {
                case let .open(type, clipStart):
                    let path = try clipWriter.open(
                        type: type,
                        clipStart: config.sessionStart.addingTimeInterval(clipStart)
                    )
                    clipPathByType[type] = path
                    activeClipType = type
                case let .write(samples):
                    try clipWriter.write(samples)
                case .close:
                    clipWriter.close()
                    activeClipType = nil
                }
            } catch {
                abandonClip(after: error)
                return
            }
        }
    }

    /// Resets the recorder after a clip writer error and closes the clip if it was
    /// opened. A clip that was opened keeps its path: the file holds what was written
    /// before the error. The first clip error of the session is reported.
    private func abandonClip(after error: Error) {
        // The recorder's own close action is not used: a failed `open` left nothing open.
        _ = recorder?.finish()
        if activeClipType != nil {
            clipWriter.close()
            activeClipType = nil
        }
        guard !hasReportedClipError else { return }
        hasReportedClipError = true
        report("Ein Clip konnte nicht gespeichert werden: \(error.localizedDescription)")
    }

    /// Ends the current classifier's segment and releases it. Its final windows
    /// arrive during `completeAnalysis()` and still reach the detector.
    private func completeClassifier() {
        guard let finishing = currentClassifier else { return }
        currentClassifier = nil
        finishing.completeAnalysis()
    }

    /// Finishes the session once: the classifier's last windows are processed, the
    /// detector ends active and pending events, the open clip is closed, the partial
    /// epoch is reported and an open gap ends at `clock()`.
    private func finishSegment() {
        guard !isFinished else { return }
        isFinished = true

        // First, so the classifier's final windows still reach the detector.
        completeClassifier()
        if let outputs = detector?.finish(at: lastBufferEnd) {
            handle(outputs)
        }
        detector = nil
        if let actions = recorder?.finish() {
            perform(actions)
        }
        if let epoch = epochs.finish() {
            delegate?.pipeline(self, didCompleteLevelEpoch: epoch)
        }
        closeOpenGap(at: clock())
    }

    // MARK: - Gaps (queue)

    private var hasOpenGap: Bool {
        guard let last = gaps.last else { return false }
        return last.end == nil
    }

    /// Closes the open gap, if any, at `time` (never before its start) and reports it.
    private func closeOpenGap(at time: TimeInterval) {
        guard let index = gaps.indices.last, gaps[index].end == nil else { return }
        gaps[index].end = max(time, gaps[index].start)
        delegate?.pipeline(self, didRecordGap: gaps[index])
    }

    // MARK: - Helpers

    private var isOnQueue: Bool {
        DispatchQueue.getSpecific(key: queueKey) != nil
    }

    /// Runs `work` at once when called on `queue` (the expected case for classifier
    /// callbacks), otherwise asynchronously on `queue`.
    private func runOnQueue(_ work: @escaping () -> Void) {
        if isOnQueue {
            work()
        } else {
            queue.async(execute: work)
        }
    }

    private func report(_ message: String) {
        delegate?.pipeline(self, didReportError: message)
    }
}
