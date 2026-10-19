import Foundation
@testable import SleepTracker

enum FakeError: Error {
    case openFailed
}

/// Recording `ClipWriting` for pipeline tests. Writes nothing to disk; it only
/// counts what the pipeline asked for.
final class FakeClipWriter: ClipWriting {
    var preparedSampleRate: Double?
    var openedTypes: [SoundEventType] = []
    var writtenSampleCount = 0
    var closeCount = 0
    /// When `true`, `open` throws `FakeError.openFailed` (disk full and similar).
    var shouldFailOnOpen = false
    var nextRelativePath = "Clips/test/clip.m4a"

    func prepare(sampleRate: Double) {
        preparedSampleRate = sampleRate
    }

    /// Mirrors the real writer's contract: opening before `prepare` throws
    /// `ClipWriterError.notPrepared`.
    func open(type: SoundEventType, clipStart: Date) throws -> String {
        guard preparedSampleRate != nil else {
            throw ClipWriterError.notPrepared
        }
        if shouldFailOnOpen {
            throw FakeError.openFailed
        }
        openedTypes.append(type)
        return nextRelativePath
    }

    func write(_ samples: [Float]) throws {
        writtenSampleCount += samples.count
    }

    func close() {
        closeCount += 1
    }
}
