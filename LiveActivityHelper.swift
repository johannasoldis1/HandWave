//
//  LiveActivityIntegration.swift
//  HandWave
//

import SwiftUI
import Foundation
import ActivityKit




// MARK: - Start Live Activity
func startEMGLiveActivity(with values: [CGFloat]) {
    let attributes = EMGAttributes(name: "EMG")
    let contentState = EMGAttributes.ContentState(graphValues: values)
    let content = ActivityContent(state: contentState, staleDate: nil)

    do {
        _ = try Activity<EMGAttributes>.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        print("✅ EMG Live Activity started.")
    } catch {
        print("❌ Failed to start Live Activity: \(error)")
    }
}

// MARK: - Manual Update
func updateEMGActivity(values: [CGFloat]) async {
    guard let current = Activity<EMGAttributes>.activities.first else { return }

    let content = ActivityContent(state: EMGAttributes.ContentState(graphValues: values), staleDate: nil)
    await current.update(content)
}

// MARK: - Persistent Live Activity Handler
class LiveActivityController {
    private(set) var isRunning = false
    static let shared = LiveActivityController()

    private var liveActivityTimer: Timer?
    private var lastSentValues: [CGFloat] = [] // ✅ <<< PLACE HERE

    private init() {}
    func shouldUpdateActivity(with newValues: [CGFloat]) -> Bool {
            guard let last = lastSentValues.last, let new = newValues.last else {
                lastSentValues = newValues
                return true
            }
            let difference = abs(new - last)
            if difference > 5.0 {
                lastSentValues = newValues
                return true
            }
            return false
        }
    
    
    func start(with values: [CGFloat]) {
        guard !isRunning else {
            print("⏭️ Widget already active — skipping start.")
            return
        }

        UserDefaults.standard.set(true, forKey: "isLiveActivityActive")
        saveGraphValuesForResume(values)

        let attributes = EMGAttributes(name: "EMG")
        let contentState = EMGAttributes.ContentState(graphValues: values)
        let content = ActivityContent(state: contentState, staleDate: nil)

        do {
            _ = try Activity<EMGAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            isRunning = true
            print("✅ Live Activity started")
        } catch {
            print("❌ Live Activity failed: \(error)")
            isRunning = false
        }

        if liveActivityTimer == nil {
            startUpdateLoop()
        }
    }

    func update(with values: [CGFloat]) async {
  //      print("🔄 Updating with values: \(values)")
        guard let activity = Activity<EMGAttributes>.activities.first else { return }

        let content = ActivityContent(state: EMGAttributes.ContentState(graphValues: values), staleDate: nil)
        await activity.update(content)
        saveGraphValuesForResume(values)
    }

    func startUpdateLoop() {
        stopUpdateLoop()
        let interval = UIApplication.shared.applicationState == .active ? 5.0 : 15.0

        liveActivityTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task {
                let newValues = LiveActivityController.shared.loadLastSavedGraphValues()
                if LiveActivityController.shared.shouldUpdateActivity(with: newValues) {
                    await LiveActivityController.shared.update(with: newValues)
                }
            }
        }
    }

    func stopUpdateLoop() {
        liveActivityTimer?.invalidate()
        liveActivityTimer = nil
    }

    func end() {
        Task {
            if let activity = Activity<EMGAttributes>.activities.first {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            isRunning = false
            UserDefaults.standard.set(false, forKey: "isLiveActivityActive")
            stopUpdateLoop()
        }
    }

    func endWithError() {
        Task {
            if let activity = Activity<EMGAttributes>.activities.first {
                let content = ActivityContent(state: EMGAttributes.ContentState(graphValues: [-1]), staleDate: nil)
                await activity.update(content)
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            isRunning = false
            UserDefaults.standard.set(false, forKey: "isLiveActivityActive")
            stopUpdateLoop()
            print("🛑 Live Activity sent disconnect signal and ended.")
        }
    }

    func resumeIfNeeded() {
        let wasRecording = UserDefaults.standard.bool(forKey: "wasRecordingEMG")
        let wasLiveActive = UserDefaults.standard.bool(forKey: "isLiveActivityActive")

        if wasLiveActive && wasRecording {
            print("🔁 Resuming Live Activity from stored state")
            let values = loadLastSavedGraphValues()
            start(with: values)
        } else {
            print("🚫 Skipping Live Activity resume. Recording flag is false.")
        }
    }

    func saveGraphValuesForResume(_ values: [CGFloat]) {
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: "lastGraphValues")
        }
    }

    func loadLastSavedGraphValues() -> [CGFloat] {
        if let data = UserDefaults.standard.data(forKey: "lastGraphValues"),
           let values = try? JSONDecoder().decode([CGFloat].self, from: data) {
            return values
        }
        return Array(repeating: 0.0, count: 50)
    }
}



