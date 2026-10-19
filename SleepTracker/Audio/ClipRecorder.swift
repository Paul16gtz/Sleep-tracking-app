import Foundation

/// A step the audio pipeline performs against the clip file writer.
enum ClipRecorderAction: Equatable {
    /// Create a new clip file. `clipStart` is the night-relative time of the first
    /// sample, i.e. `max(0, eventStart - preRoll)`.
    case open(type: SoundEventType, clipStart: TimeInterval)
    /// Append these samples to the open clip file.
    case write([Float])
    /// Finish and close the open clip file.
    case close
}

/// Decides which samples go into an audio clip. Pure state machine: it never
/// touches files or audio APIs, it only returns `ClipRecorderAction`s.
///
/// Flow: `begin` hands over the pre-roll taken from the ring buffer, every live
/// buffer is passed to `append`, `eventEnded` starts the post-roll countdown
/// (cancelled by `eventResumed`), and the clip closes once the post-roll budget
/// or the maximum duration is used up.
struct ClipRecorder {
    private let preRoll: TimeInterval
    private let sampleRate: Double

    /// Hard cap on the clip length in samples (`maxDuration * sampleRate`).
    private let maxSamples: Int

    /// Number of samples still written after the event ended (`postRoll * sampleRate`).
    private let postRollSamples: Int

    /// Samples written to the open clip so far, including the pre-roll.
    private var writtenSamples: Int

    /// Samples still to be written before the clip closes; `nil` while no
    /// post-roll countdown is running.
    private var postRollRemaining: Int?

    /// `true` while a clip is open, i.e. between `begin` and the closing action.
    private(set) var isActive: Bool

    init(preRoll: TimeInterval, postRoll: TimeInterval, maxDuration: TimeInterval, sampleRate: Double) {
        self.preRoll = preRoll
        self.sampleRate = sampleRate
        self.maxSamples = max(0, Int(maxDuration * sampleRate))
        self.postRollSamples = max(0, Int(postRoll * sampleRate))
        self.writtenSamples = 0
        self.postRollRemaining = nil
        self.isActive = false
    }

    /// Number of samples the pipeline should take from the ring buffer for the
    /// pre-roll: the configured pre-roll plus the time already elapsed since the
    /// event started.
    func preRollSampleCount(eventStart: TimeInterval, now: TimeInterval) -> Int {
        Int((preRoll + max(0, now - eventStart)) * sampleRate)
    }

    /// Opens a clip for an event and writes its pre-roll. Ignored (returns `[]`)
    /// while a clip is already open. The pre-roll is truncated to the maximum
    /// duration; if it alone reaches the maximum, the clip closes right away.
    mutating func begin(type: SoundEventType, eventStart: TimeInterval, preRollSamples: [Float]) -> [ClipRecorderAction] {
        guard !isActive else { return [] }

        isActive = true
        writtenSamples = 0
        postRollRemaining = nil

        var actions: [ClipRecorderAction] = [.open(type: type, clipStart: max(0, eventStart - preRoll))]
        actions.append(contentsOf: write(preRollSamples))
        return actions
    }

    /// Feeds the next live buffer into the open clip. Returns `[]` when no clip is
    /// open or `samples` is empty. Otherwise writes as many samples as still fit
    /// under the maximum duration and the post-roll budget, and closes the clip
    /// when either limit is reached.
    mutating func append(_ samples: [Float]) -> [ClipRecorderAction] {
        guard isActive, !samples.isEmpty else { return [] }
        return write(samples)
    }

    /// The event detector reported the end of the event: start counting down the
    /// post-roll. Has no effect without an open clip or while already counting down.
    mutating func eventEnded() -> [ClipRecorderAction] {
        if isActive && postRollRemaining == nil {
            postRollRemaining = postRollSamples
        }
        return []
    }

    /// The event resumed during the post-roll: cancel the countdown and keep recording.
    mutating func eventResumed() {
        postRollRemaining = nil
    }

    /// Closes the open clip, e.g. when the session stops. Returns `[]` when no clip is open.
    mutating func finish() -> [ClipRecorderAction] {
        guard isActive else { return [] }
        reset()
        return [.close]
    }

    /// Writes as much of `samples` as the maximum duration and the post-roll
    /// budget allow, then closes the clip if either limit has been reached.
    private mutating func write(_ samples: [Float]) -> [ClipRecorderAction] {
        var allowed = min(samples.count, maxSamples - writtenSamples)
        if let remaining = postRollRemaining {
            allowed = min(allowed, remaining)
        }
        allowed = max(0, allowed)

        var actions: [ClipRecorderAction] = []
        if allowed > 0 {
            actions.append(.write(allowed == samples.count ? samples : Array(samples.prefix(allowed))))
        }

        writtenSamples += allowed
        if let remaining = postRollRemaining {
            postRollRemaining = remaining - allowed
        }

        let capReached = writtenSamples >= maxSamples
        var postRollUsedUp = false
        if let remaining = postRollRemaining {
            postRollUsedUp = remaining <= 0
        }
        if capReached || postRollUsedUp {
            reset()
            actions.append(.close)
        }
        return actions
    }

    /// Returns the recorder to its idle state so a later `begin` starts a fresh clip.
    private mutating func reset() {
        isActive = false
        writtenSamples = 0
        postRollRemaining = nil
    }
}
