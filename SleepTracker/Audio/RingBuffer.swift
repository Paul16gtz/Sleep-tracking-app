import Foundation

/// Fixed-capacity buffer of mono audio samples that keeps only the most recent
/// `capacity` values. Used as clip pre-roll: every captured sample is written
/// in, and the last N seconds are read back oldest-first.
struct RingBuffer {
    /// Maximum number of samples held. Always at least 1.
    let capacity: Int

    /// Number of valid samples currently held, never more than `capacity`.
    private(set) var count: Int

    /// Preallocated storage of length `capacity`; slots are overwritten in place.
    private var storage: [Float]

    /// Index of the slot the next sample is written to. When the buffer is full
    /// this is also the slot of the oldest sample.
    private var writeIndex: Int

    /// Creates an empty buffer. A `capacity` below 1 is treated as 1.
    init(capacity: Int) {
        let resolved = max(capacity, 1)
        self.capacity = resolved
        self.count = 0
        self.storage = [Float](repeating: 0, count: resolved)
        self.writeIndex = 0
    }

    /// Appends samples, overwriting the oldest ones once the buffer is full.
    /// If `samples` holds more than `capacity` values, only the last `capacity`
    /// values are kept.
    mutating func write(_ samples: [Float]) {
        guard !samples.isEmpty else { return }

        let tail = samples.suffix(capacity)
        let tailCount = tail.count

        // Copy in at most two contiguous chunks: up to the end of the storage,
        // then wrapped around to the start.
        let firstChunk = min(tailCount, capacity - writeIndex)
        storage.replaceSubrange(writeIndex..<(writeIndex + firstChunk), with: tail.prefix(firstChunk))
        if firstChunk < tailCount {
            storage.replaceSubrange(0..<(tailCount - firstChunk), with: tail.dropFirst(firstChunk))
        }

        writeIndex = (writeIndex + tailCount) % capacity
        count = min(capacity, count + tailCount)
    }

    /// Returns the most recent `min(requested, count)` samples, oldest first.
    /// Returns an empty array when `requested` is zero or negative or the buffer is empty.
    func latest(_ requested: Int) -> [Float] {
        let length = min(requested, count)
        guard length > 0 else { return [] }

        // `length <= count <= capacity`, so the sum is never negative.
        let start = (writeIndex - length + capacity) % capacity
        var result = [Float]()
        result.reserveCapacity(length)

        if start + length <= capacity {
            result.append(contentsOf: storage[start..<(start + length)])
        } else {
            result.append(contentsOf: storage[start..<capacity])
            result.append(contentsOf: storage[0..<(length - (capacity - start))])
        }
        return result
    }

    /// Discards all samples. The preallocated storage is kept.
    mutating func clear() {
        count = 0
        writeIndex = 0
    }
}
