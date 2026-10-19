import Foundation

/// Writes the samples of one clip at a time to a file. Used by the audio pipeline
/// on its queue; `ClipWriter` is the AAC implementation.
protocol ClipWriting: AnyObject {
    /// Called by the pipeline at every segment begin, before a clip is opened.
    func prepare(sampleRate: Double)
    /// Opens a new clip file and returns its path relative to the file store base.
    /// Throws `ClipWriterError.notPrepared` if `prepare` has not been called yet.
    func open(type: SoundEventType, clipStart: Date) throws -> String
    func write(_ samples: [Float]) throws
    func close()
}
