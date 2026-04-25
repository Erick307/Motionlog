//
//  MotionlogApp.swift
//  Motionlog
//
//  Created by Erick on 26/03/2026.
//

import SwiftUI

@main
struct MotionlogApp: App {

    // MARK: Background task scheduler

    /// The background scheduler owns its own service instances, independent
    /// of the foreground services owned by `DashboardViewModel`.
    private let backgroundScheduler: BackgroundTaskScheduler

    // MARK: Scene phase

    @Environment(\.scenePhase) private var scenePhase

    // MARK: Init

    init() {
        let scheduler = BackgroundTaskScheduler(
            accelerometerService: AccelerometerService(),
            storageManager: StorageManager()
        )
        // registerTasks() must be called before the first scene becomes active.
        scheduler.registerTasks()
        self.backgroundScheduler = scheduler
    }

    // MARK: Body

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                backgroundScheduler.scheduleAppRefresh()
            }
        }
    }
}
