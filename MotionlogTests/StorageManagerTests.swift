//
//  StorageManagerTests.swift
//  MotionlogTests
//
//  Created by Erick on 26/03/2026.
//

import Testing
import Foundation
@testable import Motionlog

// MARK: - Helpers

private func makeSamples(
    count: Int,
    startingAt base: Date = Date(timeIntervalSinceReferenceDate: 0),
    interval: TimeInterval = 1.0
) -> [SensorReading] {
    (0..<count).map { i in
        SensorReading(
            timestamp: base.addingTimeInterval(Double(i) * interval),
            x: Double(i) * 0.1,
            y: Double(i) * 0.2,
            z: 9.8
        )
    }
}

// MARK: - Suite

@Suite("StorageManager")
struct StorageManagerTests {

    // Each @Test function receives a fresh struct instance, so each test
    // gets its own isolated in-memory store.
    let storage = StorageManager(inMemory: true)

    // MARK: save

    @Test("save persists readings to the store")
    func savePersistsReadings() async throws {
        let readings = makeSamples(count: 3)
        try await storage.save(readings)

        let fetched = try await storage.fetchReadings()
        #expect(fetched.count == 3)
    }

    @Test("save with empty array does not throw and store stays empty")
    func saveEmptyArray() async throws {
        try await storage.save([])
        let fetched = try await storage.fetchReadings()
        #expect(fetched.isEmpty)
    }

    @Test("save preserves x, y, z values accurately")
    func savePreservesValues() async throws {
        let reading = SensorReading(
            timestamp: Date(timeIntervalSinceReferenceDate: 1000),
            x: 0.123456,
            y: -0.654321,
            z: 9.812345
        )
        try await storage.save([reading])

        let fetched = try await storage.fetchReadings()
        let result = try #require(fetched.first)
        #expect(result.x == reading.x)
        #expect(result.y == reading.y)
        #expect(result.z == reading.z)
    }

    // MARK: fetchReadings

    @Test("fetchReadings() with no argument returns all readings")
    func fetchAllReadings() async throws {
        try await storage.save(makeSamples(count: 5))
        let fetched = try await storage.fetchReadings()
        #expect(fetched.count == 5)
    }

    @Test("fetchReadings(since:) returns only readings strictly after cutoff")
    func fetchReadingsSince() async throws {
        // Readings at t=0, 1, 2, 3, 4, 5, 6, 7, 8, 9
        let base = Date(timeIntervalSinceReferenceDate: 0)
        try await storage.save(makeSamples(count: 10, startingAt: base))

        // Cutoff at t=4.5 → readings at t=5…9 qualify (strictly greater than)
        let cutoff = base.addingTimeInterval(4.5)
        let fetched = try await storage.fetchReadings(since: cutoff)
        #expect(fetched.count == 5)
    }

    @Test("fetchReadings returns results sorted by timestamp ascending")
    func fetchReadingsSortedAscending() async throws {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        try await storage.save(makeSamples(count: 5, startingAt: base))

        let fetched = try await storage.fetchReadings()
        let timestamps = fetched.map(\.timestamp)
        #expect(timestamps == timestamps.sorted())
    }

    @Test("fetchReadings returns empty array when store is empty")
    func fetchReadingsEmpty() async throws {
        let fetched = try await storage.fetchReadings()
        #expect(fetched.isEmpty)
    }

    // MARK: firstReadingDate / lastReadingDate

    @Test("firstReadingDate returns the earliest timestamp")
    func firstReadingDate() async throws {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        try await storage.save(makeSamples(count: 5, startingAt: base))

        let first = try await storage.firstReadingDate()
        #expect(first == base)
    }

    @Test("lastReadingDate returns the most recent timestamp")
    func lastReadingDate() async throws {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        try await storage.save(makeSamples(count: 5, startingAt: base))

        let last = try await storage.lastReadingDate()
        #expect(last == base.addingTimeInterval(4.0))
    }

    @Test("firstReadingDate returns nil when store is empty")
    func firstReadingDateEmpty() async throws {
        let first = try await storage.firstReadingDate()
        #expect(first == nil)
    }

    @Test("lastReadingDate returns nil when store is empty")
    func lastReadingDateEmpty() async throws {
        let last = try await storage.lastReadingDate()
        #expect(last == nil)
    }

    // MARK: deleteAll

    @Test("deleteAll removes every reading from the store")
    func deleteAll() async throws {
        try await storage.save(makeSamples(count: 5))
        try await storage.deleteAll()

        let fetched = try await storage.fetchReadings()
        #expect(fetched.isEmpty)
    }

    @Test("deleteAll on empty store does not throw")
    func deleteAllWhenEmpty() async throws {
        try await storage.deleteAll()
        let fetched = try await storage.fetchReadings()
        #expect(fetched.isEmpty)
    }
}
