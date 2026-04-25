//
//  AccelerometerReading+CoreData.swift
//  Motionlog
//
//  Created by Erick on 26/03/2026.
//

import Foundation
import CoreData

/// A single accelerometer sample persisted in Core Data.
///
/// The `@objc` name must match the `representedClassName` in the
/// `.xcdatamodeld` file so Core Data can resolve the class at runtime.
@objc(AccelerometerReading)
final class AccelerometerReading: NSManagedObject {

    /// When the sample was recorded.
    @NSManaged var timestamp: Date

    /// Acceleration along the x-axis (in g).
    @NSManaged var x: Double

    /// Acceleration along the y-axis (in g).
    @NSManaged var y: Double

    /// Acceleration along the z-axis (in g).
    @NSManaged var z: Double

    // MARK: - Convenience initialiser

    /// Creates and inserts a new reading into the given context.
    convenience init(
        context: NSManagedObjectContext,
        timestamp: Date,
        x: Double,
        y: Double,
        z: Double
    ) {
        let entity = NSEntityDescription.entity(
            forEntityName: "AccelerometerReading",
            in: context
        )!
        self.init(entity: entity, insertInto: context)
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.z = z
    }
}

// MARK: - Fetch request

extension AccelerometerReading {

    /// A typed fetch request for `AccelerometerReading` entities.
    @nonobjc class func fetchRequest() -> NSFetchRequest<AccelerometerReading> {
        NSFetchRequest<AccelerometerReading>(entityName: "AccelerometerReading")
    }
}
