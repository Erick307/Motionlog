//
//  AccelerometerService.swift
//  Motionlog
//
//  Created by Erick on 26/03/2026.
//

import Foundation

// MARK: - AccelerometerServicing

/// Dependency-inversion protocol used by `DashboardViewModel`.
/// Keeping the ViewModel decoupled from the concrete actor makes it
/// trivially testable with a lightweight mock.
protocol AccelerometerServicing: AnyObject {
    var isAvailable: Bool { get async }
    func start(
        interval: TimeInterval,
        onReading: @escaping @Sendable (SensorReading) -> Void
    ) async
    func stop() async
    func collectBurst(duration: TimeInterval) async -> [SensorReading]
}

// MARK: - AccelerometerService

/// Manages live accelerometer streaming and time-bounded burst collection.
///
/// Conforms to the Swift actor model so all mutable state is protected
/// without manual locking.  Inject a `MotionManagerProtocol` (defaults to
/// the real `CMMotionManagerAdapter`) to enable full unit testing.
actor AccelerometerService {

    // MARK: Types

    /// Callback type delivered on the internal operation queue.
    typealias ReadingHandler = @Sendable (SensorReading) -> Void

    // MARK: Properties

    private let motionManager: any MotionManagerProtocol
    private let updateQueue = OperationQueue()
    private var isRunning = false

    // MARK: Init

    init(motionManager: any MotionManagerProtocol = CMMotionManagerAdapter()) {
        self.motionManager = motionManager
        updateQueue.name = "com.ericksilva.motionlog.accelerometer"
        updateQueue.maxConcurrentOperationCount = 1
    }

    // MARK: Availability

    /// `true` when the device hardware supports accelerometry.
    var isAvailable: Bool {
        motionManager.isAccelerometerAvailable
    }

    // MARK: Continuous streaming

    /// Starts continuous accelerometer updates at the given interval.
    ///
    /// Calling `start` while already running is a no-op.
    ///
    /// - Parameters:
    ///   - interval: Desired sample interval in seconds (default 0.02 = 50 Hz).
    ///   - onReading: Closure called on the internal serial queue for every sample.
    func start(
        interval: TimeInterval = 0.02,
        onReading: @escaping @Sendable (SensorReading) -> Void
    ) {
        guard !isRunning, motionManager.isAccelerometerAvailable else { return }

        isRunning = true
        motionManager.accelerometerUpdateInterval = interval

        motionManager.startAccelerometerUpdates(to: updateQueue) { x, y, z, _ in
            // CMLogItem.timestamp is seconds since last reboot, not a wall-clock
            // value — use Date() here to capture the correct current time.
            let reading = SensorReading(timestamp: Date(), x: x, y: y, z: z)
            onReading(reading)
        }
    }

    /// Stops continuous accelerometer updates.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        motionManager.stopAccelerometerUpdates()
    }

    // MARK: AccelerometerServicing conformance

    /// Explicit conformance declared in the extension below.

    // MARK: Burst collection

    /// Collects accelerometer readings for a fixed duration and returns them.
    ///
    /// Uses `AsyncStream` so callers can `await` the result without blocking
    /// the actor.  An inner `Task` finishes the stream after `duration` seconds.
    ///
    /// - Parameter duration: Collection window in seconds (default 10).
    /// - Returns: All readings gathered during the window, sorted by timestamp.
    func collectBurst(duration: TimeInterval = 10.0) async -> [SensorReading] {
        guard motionManager.isAccelerometerAvailable else { return [] }

        let (stream, continuation) = AsyncStream<SensorReading>.makeStream()

        // Start updates, pushing each reading into the stream.
        motionManager.accelerometerUpdateInterval = 0.02
        motionManager.startAccelerometerUpdates(to: updateQueue) { x, y, z, _ in
            let reading = SensorReading(timestamp: Date(), x: x, y: y, z: z)
            continuation.yield(reading)
        }

        // Finish the stream after the requested duration.
        let stopTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            continuation.finish()
        }

        // Accumulate all readings until the stream ends.
        var readings: [SensorReading] = []
        for await reading in stream {
            readings.append(reading)
        }

        stopTask.cancel()
        motionManager.stopAccelerometerUpdates()

        return readings
    }
}

// MARK: - AccelerometerServicing conformance

extension AccelerometerService: AccelerometerServicing {}
