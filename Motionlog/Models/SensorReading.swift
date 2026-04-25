//
//  SensorReading.swift
//  Motionlog
//
//  Created by Erick on 26/03/2026.
//

import Foundation

/// A lightweight, Sendable value type representing a single accelerometer sample.
///
/// Used across the service layer (AccelerometerService → StorageManager →
/// CSVExportService) to avoid passing NSManagedObject instances across
/// actor boundaries.
struct SensorReading: Sendable, Equatable {
    let timestamp: Date
    let x: Double
    let y: Double
    let z: Double
}
