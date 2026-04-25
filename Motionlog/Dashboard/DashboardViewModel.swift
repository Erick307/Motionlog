//
//  DashboardViewModel.swift
//  Motionlog
//
//  Created by Erick on 26/03/2026.
//

import Foundation

// MARK: - DashboardViewModel

/// Single ViewModel for the app.  Bridges the service layer to `DashboardView`.
///
/// All published state lives on the main actor so SwiftUI can observe it
/// without extra `Task { @MainActor }` hops.
///
/// **Foreground collection** is driven by a `for await` loop fed via
/// `AsyncStream`.  The loop runs on the main actor but suspends cooperatively
/// between readings, keeping the UI fully responsive.
@Observable
@MainActor
final class DashboardViewModel {

    // MARK: Observable state

    var firstCollectionTime: Date?
    var lastCollectionTime: Date?
    var lastExportTime: Date?
    var isCollecting = false
    var showExportSheet = false
    var exportFileURL: URL?
    var showNoDataAlert = false

    // MARK: Private

    private let accelerometerService: any AccelerometerServicing
    private let storageManager: any StorageManaging
    private let csvExportService: CSVExportService
    private let userDefaults: UserDefaults

    /// Continuation that feeds the active reading stream.
    /// Finishing it (in `stopCollection`) terminates the `for await` loop.
    private var readingContinuation: AsyncStream<SensorReading>.Continuation?

    private static let lastExportKey = "lastExportTimestamp"

    // MARK: Init

    init(
        accelerometerService: any AccelerometerServicing = AccelerometerService(),
        storageManager: any StorageManaging = StorageManager(),
        csvExportService: CSVExportService = CSVExportService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.accelerometerService = accelerometerService
        self.storageManager = storageManager
        self.csvExportService = csvExportService
        self.userDefaults = userDefaults

        // Restore persisted last-export timestamp across launches.
        if let interval = userDefaults.object(forKey: Self.lastExportKey) as? Double {
            self.lastExportTime = Date(timeIntervalSince1970: interval)
        }
    }

    // MARK: Collection

    /// Loads persisted timestamps, starts the accelerometer, and processes
    /// every incoming reading until `stopCollection()` is called or the
    /// enclosing `.task` modifier is cancelled.
    ///
    /// Call this from `.task { await viewModel.startCollection() }` in the
    /// View — the modifier automatically cancels the task when the view
    /// disappears.
    func startCollection() async {
        // Seed the display with whatever is already in storage.
        firstCollectionTime = try? await storageManager.firstReadingDate()
        lastCollectionTime = try? await storageManager.lastReadingDate()

        guard await accelerometerService.isAvailable else { return }

        isCollecting = true

        // The stream decouples the Sendable callback from `self`:
        // the closure captures only the Sendable continuation, not the ViewModel.
        let (stream, continuation) = AsyncStream<SensorReading>.makeStream()
        readingContinuation = continuation

        await accelerometerService.start(interval: 0.1) { reading in
            continuation.yield(reading)
        }

        // Process each reading on the main actor, suspending cooperatively
        // between iterations so the UI loop is never starved.
        for await reading in stream {
            try? await storageManager.save([reading])
            lastCollectionTime = reading.timestamp
            if firstCollectionTime == nil {
                firstCollectionTime = reading.timestamp
            }
        }

        // Reached when stopCollection() finishes the continuation
        // or when the enclosing Task is cancelled.
        await accelerometerService.stop()
        isCollecting = false
    }

    /// Stops the reading stream, which causes `startCollection` to return.
    func stopCollection() {
        readingContinuation?.finish()
        readingContinuation = nil
    }

    // MARK: Export

    /// Fetches all readings since the last export, writes them to a CSV
    /// temp file, and presents the share sheet.
    ///
    /// Shows a "no new data" alert if there is nothing to export.
    func exportData() async {
        do {
            let readings = try await storageManager.fetchReadings(since: lastExportTime)

            guard !readings.isEmpty else {
                showNoDataAlert = true
                return
            }

            let url = try csvExportService.exportToFile(readings: readings)
            exportFileURL = url
            showExportSheet = true

            let now = Date()
            lastExportTime = now
            userDefaults.set(now.timeIntervalSince1970, forKey: Self.lastExportKey)

        } catch {
            showNoDataAlert = true
        }
    }
}
