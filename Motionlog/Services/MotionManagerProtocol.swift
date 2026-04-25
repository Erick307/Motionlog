//
//  MotionManagerProtocol.swift
//  Motionlog
//
//  Created by Erick on 26/03/2026.
//

import Foundation
import CoreMotion

// MARK: - Protocol

/// Abstracts the CoreMotion accelerometer interface so that
/// `AccelerometerService` can be tested without hardware.
///
/// The handler deliberately uses plain `Double` / `TimeInterval` values
/// instead of `CMAccelerometerData`, because `CMAccelerometerData` cannot
/// be instantiated in unit tests.
protocol MotionManagerProtocol: AnyObject {

    /// Whether the device has an accelerometer.
    nonisolated var isAccelerometerAvailable: Bool { get }

    /// Desired sampling interval in seconds (e.g. 0.02 for 50 Hz).
    nonisolated var accelerometerUpdateInterval: TimeInterval { get set }

    /// Begins accelerometer updates, delivering each sample to `handler`.
    ///
    /// - Parameters:
    ///   - queue: The operation queue on which `handler` is called.
    ///   - handler: Receives `(x, y, z, timestamp)` for every sample.
    nonisolated func startAccelerometerUpdates(
        to queue: OperationQueue,
        withHandler handler: @escaping (Double, Double, Double, TimeInterval) -> Void
    )

    /// Stops accelerometer updates.
    nonisolated func stopAccelerometerUpdates()
}

// MARK: - Production adapter

/// Wraps `CMMotionManager` and conforms to `MotionManagerProtocol`,
/// bridging `CMAccelerometerData` to raw scalar values.
///
/// `CMMotionManager` is annotated `@MainActor` in the iOS 26 SDK, but its
/// API has always been thread-safe in practice.  `nonisolated(unsafe)` opts
/// the stored instance out of actor isolation checking so that
/// `AccelerometerService` can remain a background actor.
final class CMMotionManagerAdapter: MotionManagerProtocol {

    nonisolated(unsafe) private let manager: CMMotionManager

    /// Explicit `nonisolated` init so callers (including default argument
    /// expressions in background actors) are not forced onto the main actor.
    nonisolated init() {
        manager = CMMotionManager()
    }

    nonisolated var isAccelerometerAvailable: Bool {
        manager.isAccelerometerAvailable
    }

    nonisolated var accelerometerUpdateInterval: TimeInterval {
        get { manager.accelerometerUpdateInterval }
        set { manager.accelerometerUpdateInterval = newValue }
    }

    nonisolated func startAccelerometerUpdates(
        to queue: OperationQueue,
        withHandler handler: @escaping (Double, Double, Double, TimeInterval) -> Void
    ) {
        manager.startAccelerometerUpdates(to: queue) { data, _ in
            guard let data else { return }
            handler(
                data.acceleration.x,
                data.acceleration.y,
                data.acceleration.z,
                data.timestamp
            )
        }
    }

    nonisolated func stopAccelerometerUpdates() {
        manager.stopAccelerometerUpdates()
    }
}
