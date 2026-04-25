//
//  StorageManager.swift
//  Motionlog
//
//  Created by Erick on 26/03/2026.
//

import Foundation
import CoreData

// MARK: - StorageManaging

/// Dependency-inversion protocol used by `DashboardViewModel` and
/// `BackgroundTaskScheduler`.  All methods are `async throws` so both
/// actor conformances and lightweight test mocks satisfy them.
protocol StorageManaging: AnyObject {
    func save(_ readings: [SensorReading]) async throws
    func fetchReadings(since date: Date?) async throws -> [SensorReading]
    func firstReadingDate() async throws -> Date?
    func lastReadingDate() async throws -> Date?
}

// MARK: - StorageManager

/// Owns the Core Data stack and provides an async interface for persisting
/// and querying accelerometer readings.
///
/// All public methods run on the actor's executor and dispatch Core Data
/// work to background contexts, keeping NSManagedObject threading rules
/// satisfied without touching the main thread.
actor StorageManager {

    // MARK: - Properties

    private let container: NSPersistentContainer

    // MARK: - Init

    /// - Parameter inMemory: When `true` a unique temp SQLite file is used
    ///   instead of the default app store.  Each call produces an isolated
    ///   database, so every test starts completely clean.
    ///
    ///   **Why not `NSInMemoryStoreType`?**
    ///   `NSBatchInsertRequest` and `NSBatchDeleteRequest` require a SQLite
    ///   backing store — they crash with an `NSInternalInconsistencyException`
    ///   on in-memory stores on iOS 26.  A temp SQLite file gives us batch-
    ///   operation support while still keeping tests fully isolated.
    init(inMemory: Bool = false) {
        let container = NSPersistentContainer(name: "Motionlog")
        if inMemory {
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("sqlite")
            let description = NSPersistentStoreDescription(url: url)
            container.persistentStoreDescriptions = [description]
        }
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("StorageManager failed to load persistent stores: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        self.container = container
    }

    // MARK: - Write

    /// Batch-inserts an array of sensor readings into the persistent store.
    ///
    /// Uses `NSBatchInsertRequest` for efficiency — bypasses the
    /// NSManagedObjectContext overhead on large bursts from background tasks.
    func save(_ readings: [SensorReading]) async throws {
        guard !readings.isEmpty else { return }

        let dicts: [[String: Any]] = readings.map {
            ["timestamp": $0.timestamp, "x": $0.x, "y": $0.y, "z": $0.z]
        }

        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        try await context.perform {
            let request = NSBatchInsertRequest(
                entityName: "AccelerometerReading",
                objects: dicts
            )
            request.resultType = .statusOnly
            let result = try context.execute(request) as? NSBatchInsertResult
            guard result?.result as? Bool == true else {
                throw StorageError.batchInsertFailed
            }
        }
    }

    // MARK: - Read

    /// Returns all readings recorded after `date`, sorted by timestamp ascending.
    ///
    /// - Parameter date: Exclusive lower bound. Pass `nil` to fetch every
    ///   reading ever stored (used on the first export).
    func fetchReadings(since date: Date? = nil) async throws -> [SensorReading] {
        let context = container.newBackgroundContext()
        return try await context.perform {
            let request = AccelerometerReading.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: "timestamp", ascending: true)
            ]
            if let date {
                request.predicate = NSPredicate(
                    format: "timestamp > %@", date as NSDate
                )
            }
            return try context.fetch(request).map {
                SensorReading(timestamp: $0.timestamp, x: $0.x, y: $0.y, z: $0.z)
            }
        }
    }

    /// Returns the timestamp of the earliest reading in the store, or `nil`
    /// if the store is empty.
    func firstReadingDate() async throws -> Date? {
        let context = container.newBackgroundContext()
        return try await context.perform {
            let request = AccelerometerReading.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: "timestamp", ascending: true)
            ]
            request.fetchLimit = 1
            return try context.fetch(request).first?.timestamp
        }
    }

    /// Returns the timestamp of the most recent reading in the store, or `nil`
    /// if the store is empty.
    func lastReadingDate() async throws -> Date? {
        let context = container.newBackgroundContext()
        return try await context.perform {
            let request = AccelerometerReading.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: "timestamp", ascending: false)
            ]
            request.fetchLimit = 1
            return try context.fetch(request).first?.timestamp
        }
    }

    // MARK: - Test helpers

    /// Deletes every reading from the store.  Intended for test teardown only.
    func deleteAll() async throws {
        let context = container.newBackgroundContext()
        let viewContext = container.viewContext
        try await context.perform {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(
                entityName: "AccelerometerReading"
            )
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeObjectIDs
            let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
            let ids = result?.result as? [NSManagedObjectID] ?? []
            // Propagate deletes into the view context so it stays consistent.
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                into: [viewContext]
            )
        }
    }

    // MARK: - Errors

    enum StorageError: Error {
        case batchInsertFailed
    }
}

// MARK: - StorageManaging conformance

extension StorageManager: StorageManaging {}
