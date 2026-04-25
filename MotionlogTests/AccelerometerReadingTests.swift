//
//  AccelerometerReadingTests.swift
//  MotionlogTests
//
//  Created by Erick on 26/03/2026.
//

import Testing
import CoreData
@testable import Motionlog

// MARK: - Helpers

/// Builds a fresh in-memory Core Data stack for each test instance.
private func makeInMemoryContext() -> NSManagedObjectContext {
    let container = NSPersistentContainer(name: "Motionlog")
    let description = NSPersistentStoreDescription()
    description.type = NSInMemoryStoreType
    container.persistentStoreDescriptions = [description]
    container.loadPersistentStores { _, error in
        if let error { fatalError("Failed to load in-memory store: \(error)") }
    }
    return container.viewContext
}

// MARK: - Suite

@Suite("AccelerometerReading — Core Data entity")
struct AccelerometerReadingTests {

    // Each test gets its own fresh in-memory context because Swift Testing
    // creates a new struct instance per @Test function.
    let context = makeInMemoryContext()

    // MARK: Attribute initialisation

    @Test("Convenience init stores timestamp correctly")
    func initTimestamp() {
        let now = Date()
        let reading = AccelerometerReading(context: context, timestamp: now, x: 0, y: 0, z: 0)
        #expect(reading.timestamp == now)
    }

    @Test("Convenience init stores x, y, z correctly")
    func initAxes() {
        let reading = AccelerometerReading(
            context: context,
            timestamp: Date(),
            x: 0.123456,
            y: -0.234567,
            z: 9.812345
        )
        #expect(reading.x == 0.123456)
        #expect(reading.y == -0.234567)
        #expect(reading.z == 9.812345)
    }

    // MARK: Persistence round-trip

    @Test("Save and fetch returns the correct reading")
    func saveAndFetch() throws {
        let now = Date()
        _ = AccelerometerReading(context: context, timestamp: now, x: 1.1, y: 2.2, z: 3.3)
        try context.save()

        let results = try context.fetch(AccelerometerReading.fetchRequest())

        #expect(results.count == 1)
        let fetched = try #require(results.first)
        #expect(fetched.timestamp == now)
        #expect(fetched.x == 1.1)
        #expect(fetched.y == 2.2)
        #expect(fetched.z == 3.3)
    }

    @Test("Multiple readings are all persisted")
    func multipleReadings() throws {
        let base = Date()
        for i in 0..<5 {
            _ = AccelerometerReading(
                context: context,
                timestamp: base.addingTimeInterval(Double(i) * 0.1),
                x: Double(i),
                y: Double(i) * 2,
                z: Double(i) * 3
            )
        }
        try context.save()

        let results = try context.fetch(AccelerometerReading.fetchRequest())
        #expect(results.count == 5)
    }

    @Test("fetchRequest returns typed NSFetchRequest")
    func fetchRequestType() {
        let request = AccelerometerReading.fetchRequest()
        #expect(request.entityName == "AccelerometerReading")
    }
}
