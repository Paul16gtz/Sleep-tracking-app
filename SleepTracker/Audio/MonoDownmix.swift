import AVFoundation

/// Conversions between `AVAudioPCMBuffer` and mono Float32 samples (spec B3).
/// Works for interleaved and non-interleaved Float32 buffers.
enum MonoDownmix {
    /// Averages all channels into a new mono Float32 buffer in `monoFormat`.
    /// The result is a copy, so it stays valid after `buffer` is reused (tap buffers).
    /// Returns `nil` if `buffer` is not Float32, `monoFormat` is not mono Float32,
    /// or the new buffer cannot be allocated.
    static func makeMonoBuffer(from buffer: AVAudioPCMBuffer, monoFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let source = buffer.floatChannelData,
              buffer.format.channelCount > 0,
              monoFormat.commonFormat == .pcmFormatFloat32,
              monoFormat.channelCount == 1 else {
            return nil
        }

        // A capacity of 0 is avoided; frameLength below may still be 0.
        let frameLength = buffer.frameLength
        guard let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: max(frameLength, 1)),
              let destination = mono.floatChannelData else {
            return nil
        }

        let frameCount = Int(frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let isInterleaved = buffer.format.isInterleaved
        let stride = buffer.stride
        let output = destination[0]

        if channelCount == 1 {
            let input = source[0]
            for frame in 0..<frameCount {
                output[frame] = input[frame * stride]
            }
        } else {
            let scale = 1 / Float(channelCount)
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    // Interleaved: all channels in plane 0, `stride` values per frame.
                    // Non-interleaved: one plane per channel, stride 1.
                    sum += isInterleaved ? source[0][frame * stride + channel] : source[channel][frame * stride]
                }
                output[frame] = sum * scale
            }
        }

        mono.frameLength = frameLength
        return mono
    }

    /// Channel 0 as an array; empty if `buffer` is not Float32.
    static func samples(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let data = buffer.floatChannelData else {
            return []
        }
        let frameCount = Int(buffer.frameLength)
        let stride = buffer.stride
        let channel = data[0]
        if stride == 1 {
            return Array(UnsafeBufferPointer(start: channel, count: frameCount))
        }
        return (0..<frameCount).map { channel[$0 * stride] }
    }

    /// New buffer in `format` holding `samples`; every channel gets the same samples.
    /// Returns `nil` if `format` is not Float32 or the buffer cannot be allocated.
    static func makeBuffer(samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard format.commonFormat == .pcmFormatFloat32 else {
            return nil
        }
        // A capacity of 0 is avoided; frameLength below may still be 0.
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1))),
              let data = buffer.floatChannelData else {
            return nil
        }

        let channelCount = Int(format.channelCount)
        let isInterleaved = format.isInterleaved
        let stride = buffer.stride

        for (frame, value) in samples.enumerated() {
            for channel in 0..<channelCount {
                if isInterleaved {
                    data[0][frame * stride + channel] = value
                } else {
                    data[channel][frame * stride] = value
                }
            }
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
