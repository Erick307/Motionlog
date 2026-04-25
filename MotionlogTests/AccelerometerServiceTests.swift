//
//  AccelerometerServiceTests.swift
//  MotionlogTests
//
//  Created by Erick on 26/03/2026.
//

import Testing
import Foundation
@testable import Motionlog

// MARK: - Mock

/// A thread-safe fake `MotionManagerProtocol` for unit tests.
///
/// Uses `NSLock` so the mock is safe to call from both the actor's executor
/// and the `updateQueue` operation queue without data races.
final class MockMotionManager: MotionManagerProtocol, @unchecked Sendable {

    // MARK: Configuration

    var isAccelerometerAvailable: Bool
    var accelerometerUpdateInterval: TimeInterval = 0

    // MARK: Recorded calls

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    // MARK: State

    private let lock = NSLock()
    private var handler: ((Double, Double, Double, TimeInterval) -> Void)?

    init(available: Bool = true) {
        self.isAccelerometerAvailable = available
    }

    // MARK: MotionManagerProtocol

    func startAccelerometerUpdates(
        to queue: OperationQueue,
        withHandler handler: @escaping (Double, Double, Double, TimeInterval) -> Void
    ) {
        lock.withLock {
            startCallCount += 1
            self.handler = handler
        }
    }

    func stopAccelerometerUpdates() {
        lock.withLock {
            stopCallCount += 1
            handler = nil
        }
    }

    // MARK: Test helpers

    /// Synchronously pushes a simulated accelerometer sample to the registered handler.
    func deliver(x: Double, y: Double, z: Double, timestamp: TimeInterval = 0) {
        lock.withLock { handler }?(x, y, z, timestamp)
    }
}

// MARK: - Suite

@Suite("AccelerometerService")
struct AccelerometerServiceTests {

    // MARK: isAvailable

    @Test("isAvailable reflects the underlying motion manager")
    func isAvailableTrue() async {
        let mock = MockMotionManager(available: true)
        let service = AccelerometerService(motionManager: mock)
        let available = await service.isAvailable
        #expect(available == true)
    }

    @Test("isAvailable is false when hardware is absent")
    func isAvailableFalse() async {
        let mock = MockMotionManager(available: false)
        let service = AccelerometerService(motionManager: mock)
        let available = await service.isAvailable
        #expect(available == false)
    }

    // MARK: start / stop

    @Test("start calls startAccelerometerUpdates exactly once")
    func startCallsManager() async {
        let mock = MockMotionManager()
        let service = AccelerometerService(motionManager: mock)
        await service.start { _ in }
        #expect(mock.startCallCount == 1)
    }

    @Test("start sets the accelerometer update interval")
    func startSetsInterval() async {
        let mock = MockMotionManager()
        let service = AccelerometerService(motionManager: mock)
        await service.start(interval: 0.05) { _ in }
        #expect(mock.accelerometerUpdateInterval == 0.05)
    }

    @Test("calling start twice is a no-op (only one start sent to hardware)")
    func startIsIdempotent() async {
        let mock = MockMotionManager()
        let service = AccelerometerService(motionManager: mock)
        await service.start { _ in }
        await service.start { _ in }
        #expect(mock.startCallCount == 1)
    }

    @Test("stop calls stopAccelerometerUpdates")
    func stopCallsManager() async {
        let mock = MockMotionManager()
        let service = AccelerometerService(motionManager: mock)
        await service.start { _ in }
        await service.stop()
        #expect(mock.stopCallCount == 1)
    }

    @Test("stop without prior start is a no-op")
    func stopWithoutStart() async {
        let mock = MockMotionManager()
        let service = AccelerometerService(motionManager: mock)
        await service.stop()
        #expect(mock.stopCallCount == 0)
    }

    @Test("start does nothing when accelerometer is unavailable")
    func startUnavailable() async {
        let mock = MockMotionManager(available: false)
        let service = AccelerometerService(motionManager: mock)
        await service.start { _ in }
        #expect(mock.startCallCount == 0)
    }

    // MARK: live reading delivery

    @Test("readings delivered by mock are forwarded to the onReading handler")
    func readingsDelivered() async {
        let mock = MockMotionManager()
        let service = AccelerometerService(motionManager: mock)

        var received: [SensorReading] = []
        await service.start { reading in
            received.append(reading)
        }

        mock.deliver(x: 1.0, y: 2.0, z: 3.0, timestamp: 1000)
        mock.deliver(x: 4.0, y: 5.0, z: 6.0, timestamp: 2000)

        // Give the serial operation queue a moment to flush.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(received.count == 2)
        #expect(received[0].x == 1.0)
        #expect(received[1].z == 6.0)
    }

    // MARK: collectBurst

    @Test("collectBurst returns empty array when accelerometer is unavailable")
    func collectBurstUnavailable() async {
        let mock = MockMotionManager(available: false)
        let service = AccelerometerService(motionManager: mock)
        let readings = await service.collectBurst(duration: 0.1)
        #expect(readings.isEmpty)
    }

    @Test("collectBurst collects all readings delivered within the window")
    func collectBurstCollectsReadings() async {
        let mock = MockMotionManager()
        let service = AccelerometerService(motionManager: mock)

        // Deliver 5 samples from a background task while collectBurst is running.
        Task {
            try? await Task.sleep(for: .milliseconds(10))
            for i in 0..<5 {
                mock.deliver(x: Double(i), y: 0, z: 0, timestamp: TimeInterval(i))
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        // Use a short burst window so the test finishes quickly.
        let readings = await service.collectBurst(duration: 0.2)
        #expect(readings.count == 5)
    }

    @Test("collectBurst stops the motion manager after the window ends")
    func collectBurstStopsManager() async {
        let mock = MockMotionManager()
        let service = AccelerometerService(motionManager: mock)

        _ = await service.collectBurst(duration: 0.05)

        #expect(mock.stopCallCount == 1)
    }
}
