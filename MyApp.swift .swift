//
//  EMG_ble_kthApp.swift
//  EMG-ble-kth
//

import SwiftUI

@main
struct EMGApp: App {
    @Environment(\.scenePhase) var scenePhase  // 👈 Add this

    // Shared instances
    let emgGraphInstance = emgGraph(firstValues: [])
    let bleManagerInstance: BLEManager
    let workoutManager = WorkoutManager()

    init() {
        UIApplication.shared.isIdleTimerDisabled = false
        let workoutManager = WorkoutManager()
        workoutManager.requestHealthKitAuthorization()

        let bleManager = BLEManager(emg: emgGraphInstance)
        bleManager.workoutManager = workoutManager
        self.bleManagerInstance = bleManager

        LiveActivityController.shared.resumeIfNeeded()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("✅ Notification permission granted.")
            } else {
                print("❌ Notification permission denied.")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            StartView(
                emgGraph: emgGraphInstance,
                bleManager: bleManagerInstance,
                workoutManager: workoutManager
            )
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                print("📥 App entered background — starting background task")
                bleManagerInstance.beginBackgroundTask()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                print("💥 App will terminate — triggering emergency save")
                bleManagerInstance.endRecordingSafely()
            }
            .onChange(of: scenePhase) { newPhase in      // 👈 ADD THIS
                if newPhase == .active {
                    print("🟢 App became active again — forcing UI refresh")
                    emgGraphInstance.objectWillChange.send() // 👈 Trigger redraw of chart
                }
            }
        }
    }
}
