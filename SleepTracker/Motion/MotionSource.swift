import CoreMotion
import Foundation

/// Receives the samples of a `MotionSource`.
protocol MotionSourceDelegate: AnyObject {
    /// One acceleration magnitude in g. `time` is in seconds since the reference date
    /// passed to `start(referenceDate:)` (the session start). Called on any queue.
    func motionSource(_ source: MotionSource, didSample magnitude: Double, at time: TimeInterval)
}

/// A stream of acceleration magnitudes for the motion analysis.
protocol MotionSource: AnyObject {
    /// Set before `start(referenceDate:)`; it is read on the queue that delivers the samples.
    var delegate: MotionSourceDelegate? { get set }
    /// Whether the device has the sensor; `start(referenceDate:)` throws without it.
    var isAvailable: Bool { get }
    func start(referenceDate: Date) throws
    func stop()
}

/// Why motion capture could not be started.
enum MotionError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Kein Bewegungssensor verfügbar."
        }
    }
}

/// Accelerometer samples from `CMMotionManager`, about 20 per second with the default
/// interval (spec A7). The handler runs on a private serial operation queue.
final class CoreMotionSource: MotionSource {
    /// Fallback for a non-positive or non-finite update interval.
    private static let defaultUpdateInterval: TimeInterval = 0.05

    weak var delegate: MotionSourceDelegate?

    private let updateInterval: TimeInterval
    private let manager = CMMotionManager()
    private let operationQueue: OperationQueue

    /// `updateInterval` is the time between two samples in seconds; a non-positive or
    /// non-finite value falls back to 0.05.
    init(updateInterval: TimeInterval = 0.05) {
        if updateInterval.isFinite && updateInterval > 0 {
            self.updateInterval = updateInterval
        } else {
            self.updateInterval = CoreMotionSource.defaultUpdateInterval
        }
        let queue = OperationQueue()
        queue.name = "sleeptracker.motion.updates"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        operationQueue = queue
    }

    var isAvailable: Bool {
        manager.isAccelerometerAvailable
    }

    /// Starts the accelerometer updates. Each sample's time is the wall-clock time
    /// since `referenceDate`. Throws `MotionError.unavailable` without an accelerometer.
    func start(referenceDate: Date) throws {
        guard manager.isAccelerometerAvailable else {
            throw MotionError.unavailable
        }
        manager.accelerometerUpdateInterval = updateInterval
        manager.startAccelerometerUpdates(to: operationQueue) { [weak self] data, _ in
            guard let self = self, let data = data else {
                return
            }
            let acceleration = data.acceleration
            let magnitude = sqrt(
                acceleration.x * acceleration.x
                    + acceleration.y * acceleration.y
                    + acceleration.z * acceleration.z
            )
            let time = Date().timeIntervalSince(referenceDate)
            self.delegate?.motionSource(self, didSample: magnitude, at: time)
        }
    }

    /// Stops the updates. A handler that is already queued may still deliver one sample.
    func stop() {
        manager.stopAccelerometerUpdates()
    }
}
