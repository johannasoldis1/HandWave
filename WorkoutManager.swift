//
//  BLEManager.swift
//  EMG-ble-kth
//
// WorkoutManager.swift
import Foundation
import HealthKit

class WorkoutManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()

    private var startDate: Date?
    private var endDate: Date?

    @Published var isWorkoutActive = false

    func requestHealthKitAuthorization() {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }

        let shareTypes: Set = [HKObjectType.workoutType(), hrType]
        let readTypes: Set = [HKObjectType.workoutType(), hrType]

        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
            if success {
                print("✅ HealthKit authorization granted")
            } else {
                print("❌ Authorization failed: \(error?.localizedDescription ?? "Unknown")")
            }
        }
    }

    func startWorkout() {
        startDate = Date()
        isWorkoutActive = true
        print("🏁 Workout manually started")
    }

    func stopWorkout() {
        endDate = Date()
        isWorkoutActive = false
        print("🏁 Workout Stopped")
        saveManualWorkout()
    }

    private func saveManualWorkout() {
        guard let start = startDate, let end = endDate else {
            print("❌ Invalid workout time range")
            return
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown

        do {
            let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: nil)

            builder.beginCollection(withStart: start) { success, error in
                if success {
                    builder.endCollection(withEnd: end) { success, error in
                        builder.finishWorkout { workout, error in
                            if let workout = workout {
                                print("✅ Workout saved manually from \(start) to \(end)")
                            } else {
                                print("❌ Failed to finish workout: \(error?.localizedDescription ?? "Unknown")")
                            }
                        }
                    }
                } else {
                    print("❌ Failed to begin collection: \(error?.localizedDescription ?? "Unknown")")
                }
            }
        }
    }

    func saveEMGSample(_ value: Double) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let quantity = HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: value)
        let now = Date()

        let sample = HKQuantitySample(type: hrType, quantity: quantity, start: now, end: now)

        healthStore.save(sample) { success, error in
        //    print(success ? "✅ EMG saved as HR" : "❌ Save failed: \(error?.localizedDescription ?? "Unknown")")
        }
    }
}
