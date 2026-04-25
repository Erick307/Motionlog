//
//  BackgroundTaskScheduler.swift
//  Motionlog
//
//  Created by Erick on 26/03/2026.
//

import Foundation
import BackgroundTasks

// MARK: - BackgroundTaskScheduler

/// Registers and handles the `BGAppRefreshTask` that collects a short burst of
/// accelerometer data while the app is in the background.
///
/// **Lifecycle:**
/// 1. Call `registerTasks()` exactly once, before the first `SceneDelegate`
///    callback fires (i.e. in `App.init` or as an `@UIApplicationDelegateAdaptor`).
/// 2. Call `scheduleAppRefresh()` whenever the app moves to the background so
///    iOS queues the next wake-up.
final class BackgroundTaskScheduler {

    // MARK: Constants

    /// Must match the value in `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let taskIdentifier = "com.ericksilva.motionlog.refresh"

    /// How long the burst collection runs before iOS is likely to terminate us.
    /// 20 s leaves a comfortable buffer inside the typical ~30 s background window.
    private static let burstDuration: TimeInterval = 20

    /// Minimum delay before iOS may wake the app again.
    private static let refreshInterval: TimeInterval = 15 * 60  // 15 minutes

    // MARK: Dependencies

    private let accelerometerService: AccelerometerService
    private let storageManager: StorageManager

    // MARK: Init

    init(
        accelerometerService: AccelerometerService,
        storageManager: StorageManager
    ) {
        self.accelerometerService = accelerometerService
        self.storageManager = storageManager
    }

    // MARK: Registration

    /// Registers the app-refresh task handler with `BGTaskScheduler`.
    ///
    /// Must be called before the application finishes launching.
    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil          // nil = main queue dispatch
        ) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleAppRefresh(task: refreshTask)
        }
    }

    // MARK: Scheduling

    /// Asks the system to wake the app for a background refresh no sooner than
    /// `refreshInterval` seconds from now.
    ///
    /// Safe to call multiple times — subsequent calls replace any pending request.
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // BGTaskScheduler throws when running in Simulator or when the
            // identifier is not registered — log but do not crash.
            print("[BackgroundTaskScheduler] Could not schedule refresh: \(error)")
        }
    }

    // MARK: Private — task handler

    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh immediately so we never miss a window.
        scheduleAppRefresh()

        // Kick off the burst collection on a detached Task so the actor
        // hop doesn't block the main queue.
        let collectionTask = Task {
            let readings = await accelerometerService.collectBurst(
                duration: Self.burstDuration
            )
            do {
                try await storageManager.save(readings)
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        // If iOS decides to kill the task early, cancel our work promptly.
        task.expirationHandler = {
            collectionTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
