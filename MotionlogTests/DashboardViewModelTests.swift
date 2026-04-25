//
//  DashboardViewModelTests.swift
//  MotionlogTests
//
//  Created by Erick on 26/03/2026.
//

import Testing
import Foundation
@testable import Motionlog

// MARK: - MockAccelerometerService

/// Lightweight actor mock.  `deliver(_:)` pushes a reading to whatever
/// handler was registered by the last `start` call.
actor MockAccelerometerService: AccelerometerServicing {

    var isAvailable = true
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastInterval: TimeInterval = 0

    private var readingContinuation: AsyncStream<SensorReading>.Continuation?

    func start(
        interval: TimeInterval,
        onReading: @escaping @Sendable (SensorReading) -> Void
    ) {
        startCallCount += 1
        lastInterval = interval

        let (stream, continuation) = AsyncStream<SensorReading>.makeStream()
        readingContinuation = continuation

        // Forward every value yielded into the stream to the registered handler.
        Task {
            for await reading in stream {
                onReading(reading)
            }
        }
    }

    func stop() {
        stopCallCount += 1
        readingContinuation?.finish()
        readingContinuation = nil
    }

    func collectBurst(duration: TimeInterval) async -> [SensorReading] { [] }

    /// Simulates a hardware sample arriving.
    func deliver(_ reading: SensorReading) {
        readingContinuation?.yield(reading)
    }
}

// MARK: - MockStorageManager

/// Lightweight actor mock.  Stubs can be set before each test.
actor MockStorageManager: StorageManaging {

    private(set) var savedBatches: [[SensorReading]] = []
    var stubbedReadings: [SensorReading] = []
    var stubbedFirstDate: Date? = nil
    var stubbedLastDate: Date? = nil

    var saveCallCount: Int { savedBatches.count }

    func save(_ readings: [SensorReading]) throws {
        savedBatches.append(readings)
    }

    func fetchReadings(since date: Date?) throws -> [SensorReading] {
        stubbedReadings
    }

    func firstReadingDate() throws -> Date? { stubbedFirstDate }
    func lastReadingDate() throws -> Date?  { stubbedLastDate }
}

// MARK: - Helpers

private func makeReading(
    secondsOffset: TimeInterval = 0,
    x: Double = 0.1, y: Double = 0.2, z: Double = 0.3
) -> SensorReading {
    SensorReading(
        timestamp: Date(timeIntervalSinceReferenceDate: 1_000_000 + secondsOffset),
        x: x, y: y, z: z
    )
}

// MARK: - Suite

@Suite("DashboardViewModel")
struct DashboardViewModelTests {

    // MARK: init — UserDefaults restore

    @Test("lastExportTime is nil when UserDefaults has no stored value")
    @MainActor
    func lastExportTimeNilOnFreshInstall() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let vm = DashboardViewModel(
            accelerometerService: MockAccelerometerService(),
            storageManager: MockStorageManager(),
            userDefaults: defaults
        )
        #expect(vm.lastExportTime == nil)
    }

    @Test("lastExportTime is restored from UserDefaults on init")
    @MainActor
    func lastExportTimeRestoredFromDefaults() {
        let defaults = UserDefaults(suiteName: #function)!
        let stored = Date(timeIntervalSince1970: 1_000_000)
        defaults.set(stored.timeIntervalSince1970, forKey: "lastExportTimestamp")
        defer { defaults.removePersistentDomain(forName: #function) }

        let vm = DashboardViewModel(
            accelerometerService: MockAccelerometerService(),
            storageManager: MockStorageManager(),
            userDefaults: defaults
        )
        #expect(abs(vm.lastExportTime!.timeIntervalSince(stored)) < 0.001)
    }

    // MARK: startCollection — initial state

    @Test("startCollection seeds firstCollectionTime from storage")
    @MainActor
    func startCollectionSeedsFirstCollectionTime() async throws {
        let mockAccel   = MockAccelerometerService()
        let mockStorage = MockStorageManager()
        let expected    = Date(timeIntervalSinceReferenceDate: 500_000)
        await mockStorage.set(stubbedFirstDate: expected)

        let vm = DashboardViewModel(
            accelerometerService: mockAccel,
            storageManager: mockStorage
        )

        let task = Task { @MainActor in await vm.startCollection() }
        try await Task.sleep(for: .milliseconds(100))
        vm.stopCollection()
        await task.value

        #expect(vm.firstCollectionTime == expected)
    }

    @Test("startCollection seeds lastCollectionTime from storage")
    @MainActor
    func startCollectionSeedsLastCollectionTime() async throws {
        let mockAccel   = MockAccelerometerService()
        let mockStorage = MockStorageManager()
        let expected    = Date(timeIntervalSinceReferenceDate: 600_000)
        await mockStorage.set(stubbedLastDate: expected)

        let vm = DashboardViewModel(
            accelerometerService: mockAccel,
            storageManager: mockStorage
        )

        let task = Task { @MainActor in await vm.startCollection() }
        try await Task.sleep(for: .milliseconds(100))
        vm.stopCollection()
        await task.value

        #expect(vm.lastCollectionTime == expected)
    }

    @Test("startCollection sets isCollecting to true while running")
    @MainActor
    func startCollectionSetsIsCollecting() async throws {
        let vm = DashboardViewModel(
            accelerometerService: MockAccelerometerService(),
            storageManager: MockStorageManager()
        )

        let task = Task { @MainActor in await vm.startCollection() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.isCollecting == true)

        vm.stopCollection()
        await task.value
    }

    // MARK: startCollection — reading delivery

    @Test("lastCollectionTime updates when a reading is delivered")
    @MainActor
    func lastCollectionTimeUpdatesOnReading() async throws {
        let mockAccel   = MockAccelerometerService()
        let mockStorage = MockStorageManager()
        let vm = DashboardViewModel(
            accelerometerService: mockAccel,
            storageManager: mockStorage
        )

        let task = Task { @MainActor in await vm.startCollection() }
        try await Task.sleep(for: .milliseconds(100))

        let reading = makeReading(secondsOffset: 1)
        await mockAccel.deliver(reading)
        try await Task.sleep(for: .milliseconds(100))

        #expect(vm.lastCollectionTime == reading.timestamp)

        vm.stopCollection()
        await task.value
    }

    @Test("firstCollectionTime is set on first reading when storage was empty")
    @MainActor
    func firstCollectionTimeSetOnFirstReading() async throws {
        let mockAccel   = MockAccelerometerService()
        let mockStorage = MockStorageManager()
        // Storage returns nil for both dates (empty store)

        let vm = DashboardViewModel(
            accelerometerService: mockAccel,
            storageManager: mockStorage
        )

        let task = Task { @MainActor in await vm.startCollection() }
        try await Task.sleep(for: .milliseconds(100))

        let reading = makeReading(secondsOffset: 1)
        await mockAccel.deliver(reading)
        try await Task.sleep(for: .milliseconds(100))

        #expect(vm.firstCollectionTime == reading.timestamp)

        vm.stopCollection()
        await task.value
    }

    @Test("readings are forwarded to StorageManager.save")
    @MainActor
    func readingsAreSaved() async throws {
        let mockAccel   = MockAccelerometerService()
        let mockStorage = MockStorageManager()
        let vm = DashboardViewModel(
            accelerometerService: mockAccel,
            storageManager: mockStorage
        )

        let task = Task { @MainActor in await vm.startCollection() }
        try await Task.sleep(for: .milliseconds(100))

        await mockAccel.deliver(makeReading(secondsOffset: 1))
        await mockAccel.deliver(makeReading(secondsOffset: 2))
        try await Task.sleep(for: .milliseconds(100))

        let count = await mockStorage.saveCallCount
        #expect(count == 2)

        vm.stopCollection()
        await task.value
    }

    // MARK: stopCollection

    @Test("stopCollection sets isCollecting to false")
    @MainActor
    func stopCollectionSetsIsCollectingFalse() async throws {
        let vm = DashboardViewModel(
            accelerometerService: MockAccelerometerService(),
            storageManager: MockStorageManager()
        )

        let task = Task { @MainActor in await vm.startCollection() }
        try await Task.sleep(for: .milliseconds(100))

        vm.stopCollection()
        await task.value

        #expect(vm.isCollecting == false)
    }

    // MARK: exportData — no data

    @Test("exportData sets showNoDataAlert when no readings exist")
    @MainActor
    func exportDataNoDataShowsAlert() async {
        let mockStorage = MockStorageManager()
        // stubbedReadings is empty by default

        let vm = DashboardViewModel(
            accelerometerService: MockAccelerometerService(),
            storageManager: mockStorage
        )

        await vm.exportData()

        #expect(vm.showNoDataAlert == true)
        #expect(vm.showExportSheet == false)
        #expect(vm.exportFileURL == nil)
    }

    // MARK: exportData — with data

    @Test("exportData sets exportFileURL and showExportSheet when data exists")
    @MainActor
    func exportDataWithDataShowsSheet() async {
        let mockStorage = MockStorageManager()
        await mockStorage.set(stubbedReadings: [makeReading()])

        let vm = DashboardViewModel(
            accelerometerService: MockAccelerometerService(),
            storageManager: mockStorage
        )

        await vm.exportData()

        #expect(vm.showExportSheet == true)
        #expect(vm.exportFileURL != nil)
        #expect(vm.showNoDataAlert == false)

        // Cleanup temp file
        if let url = vm.exportFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test("exportData persists lastExportTime to UserDefaults")
    @MainActor
    func exportDataPersistsLastExportTime() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let mockStorage = MockStorageManager()
        await mockStorage.set(stubbedReadings: [makeReading()])

        let vm = DashboardViewModel(
            accelerometerService: MockAccelerometerService(),
            storageManager: mockStorage,
            userDefaults: defaults
        )

        let before = Date()
        await vm.exportData()
        let after = Date()

        let stored = defaults.double(forKey: "lastExportTimestamp")
        let storedDate = Date(timeIntervalSince1970: stored)
        #expect(storedDate >= before)
        #expect(storedDate <= after)

        if let url = vm.exportFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test("exportData updates lastExportTime on the ViewModel")
    @MainActor
    func exportDataUpdatesLastExportTime() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let mockStorage = MockStorageManager()
        await mockStorage.set(stubbedReadings: [makeReading()])

        let vm = DashboardViewModel(
            accelerometerService: MockAccelerometerService(),
            storageManager: mockStorage,
            userDefaults: defaults
        )

        #expect(vm.lastExportTime == nil)

        let before = Date()
        await vm.exportData()

        #expect(vm.lastExportTime != nil)
        #expect(vm.lastExportTime! >= before)

        if let url = vm.exportFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: startCollection — unavailable

    @Test("startCollection is a no-op when accelerometer is unavailable")
    @MainActor
    func startCollectionUnavailable() async throws {
        let mockAccel = MockAccelerometerService()
        await mockAccel.set(isAvailable: false)

        let vm = DashboardViewModel(
            accelerometerService: mockAccel,
            storageManager: MockStorageManager()
        )

        await vm.startCollection()  // should return immediately

        #expect(vm.isCollecting == false)
        let count = await mockAccel.startCallCount
        #expect(count == 0)
    }
}

// MARK: - Mock setters (actor-isolated helpers for tests)

extension MockAccelerometerService {
    func set(isAvailable value: Bool) { isAvailable = value }
}

extension MockStorageManager {
    func set(stubbedReadings value: [SensorReading]) { stubbedReadings = value }
    func set(stubbedFirstDate value: Date?)          { stubbedFirstDate = value }
    func set(stubbedLastDate value: Date?)           { stubbedLastDate = value }
}
