//
//  BLEManager.swift
//  EMG-ble-kth
//

import Foundation
import CoreBluetooth
import QuartzCore // for time
import SwiftUI // Required for Alert
import UIKit  // Required for background execution
var workoutManager: WorkoutManager?  // Optional, injected externally




struct TimestampedData: Comparable {
    let timestamp: CFTimeInterval
    let values: [Float]
    
    // Conform to Comparable
    static func < (lhs: TimestampedData, rhs: TimestampedData) -> Bool {
        return lhs.timestamp < rhs.timestamp
    }

    static func == (lhs: TimestampedData, rhs: TimestampedData) -> Bool {
        return lhs.timestamp == rhs.timestamp
    }
}

struct Peripheral: Identifiable {
    let id: Int
    let name: String
    var rssi: Int
}

// Priority Queue Implementation
struct PriorityQueue<T: Comparable> {
    private var heap: [T]
    private let ordered: (T, T) -> Bool

    init(ascending: Bool = true, startingValues: [T] = []) {
        self.ordered = ascending ? { $0 < $1 } : { $0 > $1 }
        self.heap = startingValues
        buildHeap()
    }

    private mutating func buildHeap() {
        for index in stride(from: (heap.count / 2 - 1), through: 0, by: -1) {
            heapifyDown(from: index)
        }
    }

    var count: Int { heap.count }
    var isEmpty: Bool { heap.isEmpty }

    mutating func push(_ element: T) {
        heap.append(element)
        heapifyUp(from: heap.count - 1)
    }

    mutating func pop() -> T? {
        guard !heap.isEmpty else { return nil }
        heap.swapAt(0, heap.count - 1)
        let popped = heap.removeLast()
        heapifyDown(from: 0)
        return popped
    }

    private mutating func heapifyUp(from index: Int) {
        var child = index
        var parent = (child - 1) / 2
        while child > 0 && ordered(heap[child], heap[parent]) {
            heap.swapAt(child, parent)
            child = parent
            parent = (child - 1) / 2
        }
    }

    private mutating func heapifyDown(from index: Int) {
        var parent = index
        while true {
            let left = 2 * parent + 1
            let right = 2 * parent + 2
            var candidate = parent

            if left < heap.count && ordered(heap[left], heap[candidate]) {
                candidate = left
            }
            if right < heap.count && ordered(heap[right], heap[candidate]) {
                candidate = right
            }
            if candidate == parent { return }
            heap.swapAt(parent, candidate)
            parent = candidate
        }
    }

    func peek() -> T? {
        return heap.first
    }
}

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    var myCentral: CBCentralManager!
    @Published var BLEisOn = false
    @Published var BLEPeripherals = [Peripheral]()
    @Published var isConnected = false
    
    // flag for ios killing app
    private var hasAutoSaved = false
    
    // Track when the last log was printed
    private var lastSkippedLogTime: CFTimeInterval = CACurrentMediaTime()
    
    var CBPeripherals = [CBPeripheral]()
    var emgCharacteristic: CBCharacteristic?
    var emg: emgGraph
    private var droppedPackets: Int = 0
    private var totalPackets: Int = 0
    private let packetLossThreshold: Float = 0.1 // 10% packet loss threshold
    
    
    // RMS Buffers and Calculation
    private var emgBuffer: [Float] = [] // Buffer for 0.1-second RMS calculation
    private let windowSize = 1 // 0.1 seconds at 10 Hz sampling rate
    @Published var currentRMS: Float = 0.0 // Latest 0.1-second RMS
    @Published var rmsHistory: [Float] = [] // Store historical 0.1-second RMS values
    
    private var oneSecondBuffer: [Float] = [] // Buffer for 1-second RMS calculation
    private let oneSecondWindowSize = 10 // 1 second at 10 Hz sampling rate
    @Published var oneSecondRMS: Float = 0.0 // Latest 1-second RMS
    
    ///process BLE data in the background
    private let dataQueue = DispatchQueue(label: "com.emg.ble.data")
    
    var notificationTimestamps: [CFTimeInterval] = [] // Stores timestamps for debugging
    var notificationSamples: [Int] = [] // Stores sample counts per notification
    
    var firstSampleTimestamp: CFTimeInterval? // Stores first timestamp as reference
    var expectedNextTimestamp: CFTimeInterval? // Expected timestamp for next sample
    
    private var receivedValuesPerTimestamp: [CFTimeInterval: [Float]] = [:] // Rolling buffer for tracking received values
    private let rollingBufferLimit = 700 // Stores data for the last 10 seconds (assuming 10 Hz updates)
    
    var reconnectionAttempts: Int = 0
    let maxReconnectionAttempts = 2
    
    // Declare total packets received and expected
    private var totalPacketsReceived = 0
    private var totalPacketsExpected = 0
    
    // calculaate adquisiton ratio variables
    private var lastSARUpdateTime: CFTimeInterval = CACurrentMediaTime()
    private var lastPrintTime: CFTimeInterval = CACurrentMediaTime()
    private var lastSARValue: Double = 100.0
    
    // Buffer for storing EMG data with timestamps (each entry includes data and the timestamp)
    private var timestampBuffer = PriorityQueue<TimestampedData>(ascending: true, startingValues: [])
    private let bufferLimit = 500 // Limit the buffer size to 500 values, in case  data comes in bursts
    
    ///process BLE data in the background
    private let emgProcessingQueue = DispatchQueue(label: "com.emg.processing", qos: .userInitiated)
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    //disconnect device
    @Published var connectionErrorMessage: String? = nil
    @Published var showAlert = false // Controls the visibility of the alert
    @Published var alertMessage = "" // Stores the alert message
    //moving average timestamp normalization
    private var timestampOffsetBuffer: [CFTimeInterval] = []
  
    
    var startTime: CFTimeInterval? // Holds the timestamp when first packet arrives
    
    
    var workoutManager: WorkoutManager?  // healthkit
   
    // Flag to trigger recalibration after reconnection
    var forceRecalibration: Bool = false
    
    @Published var batteryLevel: Int? = nil

    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelUUID = CBUUID(string: "2A19")
    
    @Published var isScanning: Bool = false // my add

    


    
    init(emg: emgGraph) {
        self.emg = emg
        super.init()
        
        // Create a background queue for BLE operations
        let backgroundQueue = DispatchQueue.global(qos: .background)
        myCentral = CBCentralManager(delegate: self, queue: backgroundQueue)
    }
    // background task app for maintaining connections active after locking down cellphone
    func beginBackgroundTask() {
        hasAutoSaved = false  // ✅ Reset flag when task starts
        self.sendBackgroundTimeoutNotification()


        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "EMGRecording") {
            print("⚠️ Background task expired. Auto-saving...")

            DispatchQueue.main.async {
                // ✅ Make sure this only runs once!
                if !self.hasAutoSaved && self.emg.isRecording {
                    self.hasAutoSaved = true
                    print("💾 Auto-saving due to background timeout")
                    let _ = self.emg.stop_recording_and_save()
                    self.emg.isRecording = false
                    LiveActivityController.shared.end()
                    self.workoutManager?.stopWorkout()
                    self.sendBackgroundTimeoutNotification()
                }
            }
            
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
    }

    
    func endBackgroundTask() {
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.BLEisOn = (central.state == .poweredOn)
            
            if central.state == .poweredOn {
                // ✅ Restart scanning in the background
                self.startScanning()
            } else {
                print("⚠️ Bluetooth is off, cannot scan.")
            }
        }
    }
    
    func checkBluetoothStatus() {
        if !BLEisOn {
            print("⚠️ Bluetooth is not on. Please enable Bluetooth.")
            return
        }
    }
    
    func checkBluetoothPermissions() {
        switch CBManager.authorization {
        case .allowedAlways:
            print("Bluetooth is allowed")
        case .restricted, .denied:
            print("Bluetooth access denied")
        default:
            print("Bluetooth authorization pending")
        }
    }
    
    func startScanning() {
        guard !isConnected else {
            print("🔹 Already connected, skipping scanning.")
            return
        }
        print("🔍 Start Scanning")
        
        DispatchQueue.main.async {
            self.BLEPeripherals.removeAll()  // ✅ Clear ghost sensors before scanning
            self.CBPeripherals.removeAll()
        }
        
        myCentral.scanForPeripherals(withServices: nil, options: nil)
    }
    
    
    func stopScanning() {
        print("Stop Scanning")
        myCentral.stopScan()
    }
    
    func connectSensor(p: Peripheral) {
        // Check Bluetooth status before attempting connection
        checkBluetoothStatus()
        
        // Ensure we're not already connected and the peripheral exists
        guard p.id < CBPeripherals.count, !isConnected else {
            print("🔹 Already connected, skipping connection attempt.")
            return
        }
        // Reset the reconnection attempts when manually reconnecting
        self.reconnectionAttempts = 0
        
        // Stop scanning if we're currently scanning
        if myCentral.isScanning {
            myCentral.stopScan()
        }
        
        // Debugging log for the connection attempt
        print("🔄 Connecting to: \(CBPeripherals[p.id].name ?? "Unknown")")
        
        // Get the peripheral we're trying to connect to
        let peripheral = CBPeripherals[p.id]
        myCentral.connect(peripheral, options: nil)
        
        // ✅ Ensure the second attempt is properly triggered,If the connection hasn't succeeded in 5 seconds, cancel and retry
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if self.reconnectionAttempts < self.maxReconnectionAttempts {
                            self.reconnectionAttempts += 1
                            print("🔄 Retrying connection (\(self.reconnectionAttempts)/\(self.maxReconnectionAttempts))...")
                            self.myCentral.connect(peripheral, options: nil)
                            
                            // ✅ FIX: Ensure the counter moves to the second attempt and resets properly
                            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 10.0) {
                                if !self.isConnected && self.reconnectionAttempts == self.maxReconnectionAttempts {
                                    print("🔴 Second attempt failed. Stopping reconnection.")

                                    DispatchQueue.main.async {
                                        self.alertMessage = "Check device battery and Bluetooth stability."
                                        self.showAlert = true
                                    }
                                    
                                    self.reconnectionAttempts = 0 // ✅ Only reset after two failed attempts
                    }
                }
            }
        }
    }
    
    
    // Connecting to the correct device - ANR Corp
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           manufacturerData.count >= 2 {
            let companyID = UInt16(manufacturerData[1]) << 8 | UInt16(manufacturerData[0]) // Little-endian
            if companyID != 0x05DA {
                let now = CACurrentMediaTime()
                if now - lastSkippedLogTime > 5.0 {  // ✅ Print log only every 5 seconds
                    print("Skipping non-ANR device")
                    lastSkippedLogTime = now  // Update last log time
                }
                return
            }
        } else {
            let now = CACurrentMediaTime()
            if now - lastSkippedLogTime > 5.0 {  // ✅ Print log only every 5 seconds
                print("No Manufacturer Specific Data found, skipping device.")
                lastSkippedLogTime = now
            }
            return
        }
        
        let peripheralName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        print("Discovered device: \(peripheralName) with RSSI: \(RSSI.intValue)")
        
        // ✅ Check if the device is already in the list (prevents duplicates)
            if let existingIndex = BLEPeripherals.firstIndex(where: { $0.name == peripheralName }) {
                DispatchQueue.main.async {
                    self.BLEPeripherals[existingIndex].rssi = RSSI.intValue  // ✅ Update RSSI instead of duplicating
                }
                return  // ✅ Stop further processing to prevent duplicates
            }

            // ✅ Check if CBPeripheral is already stored (avoids duplicate connections)
            if !CBPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                CBPeripherals.append(peripheral)  // ✅ Only add if it's new
            }
        
        let newPeripheral = Peripheral(id: BLEPeripherals.count, name: peripheralName, rssi: RSSI.intValue)
        DispatchQueue.main.async {
            self.BLEPeripherals.append(newPeripheral)
        }
        CBPeripherals.append(peripheral)
    }
    
    
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to \(peripheral.name ?? "Unknown Device")")

        // Stop scanning now that we're connected
        myCentral.stopScan()

        // Assign delegate and start discovering services
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        peripheral.discoverServices([batteryServiceUUID])

        // Ensure UI updates
        DispatchQueue.main.async {
            self.isConnected = true
            print("🔁 Forcing EMG graph redraw after reconnect.")
            self.emg.objectWillChange.send()
        }

        // If recording was active before disconnect, handle that logic here
        DispatchQueue.main.async {
            if self.emg.isRecording {
                print("⚠️ Unexpected recording state on reconnect. Forcing stop.")
                self.emg.isRecording = false
                self.emg.recording = false
            }

            // 🔄 Always reset buffers and MVE recalibration flag on reconnect
            self.resetAfterReconnect()
            self.emg.forceMVERecalculation = true
            self.emg.calibrationBuffer.removeAll()
            self.emg.calibrationMVEHistory.removeAll()
        }

        // ✅ Enable EMG notifications if characteristic is already discovered
        if let emgCharacteristic = self.emgCharacteristic {
            peripheral.setNotifyValue(true, for: emgCharacteristic)
            print("✅ Notifications re-enabled for \(emgCharacteristic.uuid)")

            DispatchQueue.main.async {
                self.emg.objectWillChange.send()
                print("🔄 Triggered graph redraw after BLE reconnection")
            }
        } else {
            print("⚠️ No EMG characteristic found yet. Waiting for discovery...")
        }
    }
    
    // if the device is disconnected wait 1 second and try to restablish connection
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("❌ Disconnected from \(peripheral.name ?? "Unknown Device")")
        
        // ✅ Check if calibration is active. If so, do NOT attempt to reconnect.
        if emg.isCalibrating {
            print("⚠️ Device disconnected during calibration. Skipping reconnection attempts.")
            return
        }
        
        // Update UI to reflect the disconnected state
        DispatchQueue.main.async {
            self.isConnected = false
        }
        
        
        // ✅ Check if maximum reconnection attempts reached
        DispatchQueue.global(qos: .background).async {
            self.receivedValuesPerTimestamp = self.receivedValuesPerTimestamp.filter { CACurrentMediaTime() - $0.key < 5 }
            print("🔄 Keeping only recent timestamps to prevent data loss after reconnection")
        }
        
        // ✅ Check if maximum reconnection attempts reached
        if reconnectionAttempts >= maxReconnectionAttempts {
            print("🔴 Max reconnection attempts reached. Stopping reconnection.")

            // ✅ Update alert on max failures
            DispatchQueue.main.async {
                self.alertMessage = "Max reconnection attempts reached. Verify Bluetooth connection and device battery."
                self.showAlert = true
            }
            return
        }
        

    

        // ✅ Start first reconnection attempt
           reconnectionAttempts += 1
           print("🔄 Attempting to reconnect (\(reconnectionAttempts)/\(maxReconnectionAttempts))...")

           DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3.0) {
               if !self.isConnected {
                   print("🔄 First reconnection attempt in progress...")
                   self.myCentral.connect(peripheral, options: nil)
               }
           }
        
        
        // ✅ If first attempt fails, schedule a second attempt
           DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 7.0) {
               DispatchQueue.main.async {
                   if !self.isConnected && self.reconnectionAttempts < self.maxReconnectionAttempts {
                       self.reconnectionAttempts += 1
                       print("⚠️ First reconnection attempt failed. Trying again (\(self.reconnectionAttempts)/\(self.maxReconnectionAttempts))...")

                       // ✅ Update alert for second attempt
                       self.alertMessage = "Device disconnected. Reconnecting... (\(self.reconnectionAttempts)/\(self.maxReconnectionAttempts))"
                       self.showAlert = true

                       DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 4.0) {
                           if !self.isConnected {
                               print("🔄 Second reconnection attempt in progress...")
                               self.myCentral.connect(peripheral, options: nil)
                           }
                       }
                   }
               }
           }

           // ✅ If second attempt fails, update alert with failure message
           DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 10.0) {
               DispatchQueue.main.async {
                   if !self.isConnected {
                       print("🔴 Both reconnection attempts failed.")
                       self.alertMessage = "Check device battery and Bluetooth stability."
                       self.showAlert = true
                       
                       if self.emg.isRecording {
                           print("💾 Auto-saving due to disconnection...")
                           let _ = self.emg.stop_recording_and_save()
                           self.emg.isRecording = false
                       }
                       
                       // ✅ Stop automatic reconnections
                                 self.reconnectionAttempts = 0  // Reset attempt counter
                                  
                       //  Stop widget with alert
                       LiveActivityController.shared.end()  // ⛔ Stop Live Activity here
                                   print("🛑 Live Activity Stopped due to failed reconnection.")
                       
                       //  Show notification to user
                           DispatchQueue.main.async {
                               self.sendDisconnectNotification()
                           }
                       
                       // ✅ CLEAR OLD BUFFERED DATA (Prevents old data from being processed on next connection)
                                   //self.receivedValuesPerTimestamp.removeAll()   // ✅ Clear stored BLE data
                                   //self.timestampBuffer = PriorityQueue<TimestampedData>(ascending: true)  // ✅ Reset priority queue
                                   //self.totalPacketsReceived = 0
                                   //self.totalPacketsExpected = 0
                                   //self.droppedPackets = 0
                                   //self.emg.timestamps.removeAll()  // ✅ Clear timestamps
                                   //self.emg.recorded_values.removeAll()  // ✅ Remove old recorded values
                                   //self.emg.recorded_rms.removeAll()  // ✅ Remove old RMS values
                                   //self.emg.shortTermRMSValues.removeAll()  // ✅ Remove old short-term RMS

                                   //print("🗑️ Cleared old data. Only fresh data will be processed when sensor reconnects.")
                                 
                                 // ✅ Optionally restart scanning so the device appears again in the list
                                 self.startScanning()
                   }
               }
           }
       }
    
    //  Stop widget with alert
    func sendDisconnectNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Sensor Disconnected"
        content.body = "HandWave lost connection to your EMG sensor. Please reconnect to continue."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "SensorDisconnect", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    func resetAfterReconnect() {
      
            self.startTime = CACurrentMediaTime()
            self.firstSampleTimestamp = nil
            self.expectedNextTimestamp = nil

            self.emg.shortTermRMSValues.removeAll()
            self.rmsHistory.removeAll()
            self.oneSecondBuffer.removeAll()
            self.emgBuffer.removeAll()
            self.currentRMS = 0.0
            self.oneSecondRMS = 0.0
            self.emg.percentMVEHistory.removeAll()

            self.emg.timestamps.removeAll()
            self.emg.recorded_values.removeAll()
            self.emg.recorded_rms.removeAll()

            // 🔁 Also reset calibration if needed
            self.emg.calibrationBuffer.removeAll()
            self.emg.calibrationMVEHistory.removeAll()
        
        // 🔁 Force MVE recalculation on reconnect
           self.emg.forceMVERecalculation = true

         
        print("🧼 Reset state after reconnect.")
    }

    
    // SAR
    func calculateSignalAcquisitionRatio() {
        let now = CACurrentMediaTime()
        
        // Ensure SAR calculation only happens once per second
        if now - lastSARUpdateTime < 1.0 { return }
        
        let sar = (totalPacketsReceived > 0) ? (Double(totalPacketsReceived) / Double(totalPacketsExpected)) * 100 : 0.0
        lastSARUpdateTime = now
        
        // Print logic based on SAR value:
        if sar == 100.0 {
            if lastSARValue != 100.0 || now - lastPrintTime >= 10.0 {
                print("📡 Signal Acquisition Ratio (SAR): \(sar)% ✅ (Perfect signal)")
                lastPrintTime = now
            }
        } else if sar < 10.0 {
            // If SAR is below 10%, print every cycle until it reaches 80%
            print("⚠️ Low Signal Acquisition Ratio (SAR): \(sar)% ❌ - Check connection")
            lastPrintTime = now
        } else if sar < 80.0 {
            // Continue printing every cycle until SAR is 80%
            print("⚠️ SAR Recovering: \(sar)%")
            lastPrintTime = now
        } else {
            // Normal case: Print every second
            if now - lastPrintTime >= 1.0 {
                print("📡 Signal Acquisition Ratio (SAR): \(sar)%")
                lastPrintTime = now
            }
        }
        
        lastSARValue = sar
    }
    func normalizeTimestamp(_ timestamp: CFTimeInterval, precision: Int = 1) -> CFTimeInterval {
        let multiplier = pow(10.0, Double(precision))
        let roundedTimestamp = round(timestamp * multiplier) / multiplier
        
        // ✅ Moving average timestamp correction
        timestampOffsetBuffer.append(roundedTimestamp)
        if timestampOffsetBuffer.count > 10 {
            timestampOffsetBuffer.removeFirst()
        }
        
        let correctedTimestamp = timestampOffsetBuffer.reduce(0, +) / Double(timestampOffsetBuffer.count)
        return correctedTimestamp
    }
    
    func processAndAppendEMGData(_ rawEMGData: [Float], timestamp: CFTimeInterval) {
        totalPackets += 1
        if rawEMGData.isEmpty {
            droppedPackets += 1
        }
        
        // ✅ Use a larger rolling buffer to prevent early removals
        timestampBuffer.push(TimestampedData(timestamp: timestamp, values: rawEMGData.isEmpty ? [0.001] : rawEMGData))
        
        // ✅ Only remove excess timestamps beyond `bufferLimit`
        while timestampBuffer.count > bufferLimit {
            _ = timestampBuffer.pop() // Remove oldest data only if exceeding safe limit
        }
        
        // ✅ Ensure the data is sanitized before appending
        let sanitizedData: [Float] = rawEMGData.isEmpty ? [0.001] : rawEMGData.map { $0.isFinite ? $0 : 0.0 }
        let sanitizedCGFloatData = sanitizedData.map { CGFloat($0) }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let normalizedTimestamp = self.normalizeTimestamp(timestamp)
            
                    if self.emg.isCalibrating {
                        print("📡 Collecting Calibration Data: \(sanitizedCGFloatData.count) values")
                        self.emg.calibrationBuffer.append(contentsOf: sanitizedCGFloatData)
                        self.emg.calibrationMVEHistory.append(sanitizedCGFloatData.max() ?? 0.0)

                        // ✅ Also append to show data on graph
                        self.emg.append(values: sanitizedCGFloatData, timestamp: normalizedTimestamp, isInterpolated: false)

                        // ✅ Stop Calibration after 10 seconds
                        if let start = self.emg.calibrationStartTime, CACurrentMediaTime() - start >= 10 {
                            print("⏳ Calibration complete. Stopping MVE calibration.")
                            self.emg.endMVECalibration()
                        }
                        return
                    }


                    // ✅ Check for large gaps in timestamps
                    if let lastTimestamp = self.emg.timestamps.last {
                        let timeGap = normalizedTimestamp - lastTimestamp
                        if timeGap > 0.2 {
                            print("⚠️ Large gap detected in timestamps! Filling missing data.")
                            var tempTimestamp = lastTimestamp + 0.1
                            while tempTimestamp < normalizedTimestamp {
                                self.emg.append(values: [0.001], timestamp: tempTimestamp)
                                tempTimestamp += 0.1
                            }
                }
            }
            
            
            // ✅ Append sanitized data only once (fixed potential duplicate call)
            // print("📡 BLE Data Received: \(sanitizedCGFloatData.count) values, latest timestamp: \(timestamp)")
            
            if !self.emg.timestamps.isEmpty {
            }
            
           // self.emg.append(values: sanitizedCGFloatData, timestamp: normalizedTimestamp)
        self.emg.append(values: sanitizedCGFloatData, timestamp: normalizedTimestamp, isInterpolated: false)
                
            if let emgValue = sanitizedCGFloatData.first {
                self.workoutManager?.saveEMGSample(Double(emgValue))
                    
                // 🧹 Trim Old EMG Buffers (keep last 30 seconds @ 10 Hz = 1000 samples)
                let keepLastN = 1000
                    
                if self.emg.timestamps.count > keepLastN {
                    let dropCount = self.emg.timestamps.count - keepLastN
                        
                    self.emg.timestamps.removeFirst(dropCount)
                    self.emg.recorded_values.removeFirst(dropCount)
                    self.emg.recorded_rms.removeFirst(dropCount)
                        
                    if self.emg.percentMVEHistory.count > keepLastN {
                        self.emg.percentMVEHistory.removeFirst(self.emg.percentMVEHistory.count - keepLastN)
                    }
                        
                    print("🧹 Trimmed EMG buffers to last \(keepLastN) samples")
                }
            }
        }
    }
   
    
    // interpolation when packet lost and under adquisiton ratio is 10%
    func reconstructDataStream() {
        guard droppedPackets > 0, Float(droppedPackets) / Float(totalPackets) > packetLossThreshold else {
            return
        }
        print("🔄 Buffer before reconstruction: \(timestampBuffer.count) samples")

        var reconstructedData: [TimestampedData] = []
        while let entry = timestampBuffer.pop() {
            if !reconstructedData.isEmpty {
                let previous = reconstructedData.last!
                let gap = entry.timestamp - previous.timestamp
                
                if gap > 0.1 { // Missing data detected
                    let interpolatedValue = (entry.values.first! + previous.values.first!) / 2
                    let interpolatedTimestamp = previous.timestamp + 0.1
                    reconstructedData.append(TimestampedData(timestamp: interpolatedTimestamp, values: [interpolatedValue]))
                }
            }
            reconstructedData.append(entry)
        }

        // Push reconstructed data back
        for entry in reconstructedData {
            timestampBuffer.push(entry)
        }
    }

    func updateShortTermRMS(with newValues: [Float]) {
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            let validValues = newValues.filter { $0.isFinite }
            self.emgBuffer.append(contentsOf: validValues)
            let rmsDelta = self.calculateRMS(from: validValues)
            self.currentRMS = sqrt(pow(self.currentRMS, 2) * Float(self.emgBuffer.count - validValues.count) + pow(rmsDelta, 2)) / Float(self.emgBuffer.count)
        }
    }


    func calculateRMS(from samples: [Float]) -> Float {
        let validSamples = samples.filter { $0.isFinite }
        guard !validSamples.isEmpty else { return 0.0 }
        let squaredSum = validSamples.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(squaredSum / Float(validSamples.count))
    }
    
    func endRecordingSafely() {
        if emg.isRecording {
            let _ = emg.stop_recording_and_save()
            emg.isRecording = false
            LiveActivityController.shared.end()
            workoutManager?.stopWorkout()
            endBackgroundTask() // This must be accessible inside the class
            print("💾 Emergency save completed due to app termination")
        }
    }
    
    func sendBackgroundTimeoutNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Recording Stopped"
        content.body = "HandWave auto-saved your EMG session before the app was suspended."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "AutoSaveNotification",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Notification failed: \(error.localizedDescription)")
            } else {
                print("✅ Auto-save notification scheduled.")
            }
        }
    }


}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == batteryServiceUUID {
                peripheral.discoverCharacteristics([batteryLevelUUID], for: service)
            } else {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == CBUUID(string: "2A58") { // Change to the actual UUID of your EMG characteristic
                    self.emgCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic) // Enable notifications
                    print("✅ EMG Characteristic Found: \(characteristic.uuid)")
                }
                else if characteristic.uuid == batteryLevelUUID {
                    peripheral.readValue(for: characteristic) // Battery Level
                }
            }
        }
    }

    func detectLostPackets(currentTimestamp: CFTimeInterval, previousTimestamp: CFTimeInterval?) {
        guard let lastTimestamp = previousTimestamp else { return }
        let expectedNextTimestamp = lastTimestamp + 0.1

        let timeDifference = abs(currentTimestamp - expectedNextTimestamp)

        // ✅ Adaptive packet loss detection
        let adjustedThreshold = max(0.05, min(0.2, Float(droppedPackets) / Float(totalPackets))) // Adjust threshold dynamically

        if timeDifference > Double(adjustedThreshold) {
            print("⚠️ Packet loss detected! Expected: \(expectedNextTimestamp), Received: \(currentTimestamp)")
            fillMissingPackets(from: lastTimestamp, to: currentTimestamp)
        }
    }


    func fillMissingPackets(from lastTimestamp: CFTimeInterval, to newTimestamp: CFTimeInterval) {
        var missingTimestamp = lastTimestamp + 0.1
        while missingTimestamp < newTimestamp {
            print("⚠️ Filling missing packet at \(missingTimestamp)")
           // emg.append(values: [0.0], timestamp: missingTimestamp)
            emg.append(values: [0.0], timestamp: missingTimestamp, isInterpolated: true)
            missingTimestamp += 0.1
        }
    }

    func fillMissingPacketsWithInterpolation(from lastTimestamp: CFTimeInterval, lastValue: CGFloat,
                                             to newTimestamp: CFTimeInterval, newValue: CGFloat) {
        var missingTimestamps: [CFTimeInterval] = []
        var tempTimestamp = lastTimestamp + 0.1

        while tempTimestamp < newTimestamp {
            missingTimestamps.append(tempTimestamp)
            tempTimestamp += 0.1
        }

        var interpolatedValues: [CGFloat]

        if missingTimestamps.count < 10 {
            // ✅ Use smooth interpolation for small gaps
            interpolatedValues = cubicHermiteInterpolation(from: lastValue, to: newValue, timestamps: missingTimestamps)
        } else {
            // ✅ Use last known value for large gaps to prevent artificial drift
            interpolatedValues = Array(repeating: lastValue, count: missingTimestamps.count)
        }

        for (index, timestamp) in missingTimestamps.enumerated() {
            print("🔄 Interpolating Data: \(timestamp) -> \(interpolatedValues[index])")
       //     emg.append(values: [interpolatedValues[index]], timestamp: timestamp)
            emg.append(values: [interpolatedValues[index]], timestamp: timestamp, isInterpolated: true)
        }
    }

    /// 🔹 Cubic Hermite Interpolation for Smooth Packet Loss Handling
    func cubicHermiteInterpolation(from previousValue: CGFloat, to nextValue: CGFloat, timestamps: [CFTimeInterval]) -> [CGFloat] {
        let tRange = timestamps.count + 1
        let step = 1.0 / CGFloat(tRange)

        return (1..<tRange).map { i in
            let t = CGFloat(i) * step
            let t2 = t * t
            let t3 = t2 * t

            return (2 * t3 - 3 * t2 + 1) * previousValue + (t3 - 2 * t2 + t) * 0 + (-2 * t3 + 3 * t2) * nextValue + (t3 - t2) * 0
        }
    }

    // **Improved Interpolation Function**
    func interpolateData(from previousValue: CGFloat, to nextValue: CGFloat, timestamps: [CFTimeInterval]) -> [CGFloat] {
        let step = (nextValue - previousValue) / CGFloat(timestamps.count + 1)
        return (1...timestamps.count).map { previousValue + (step * CGFloat($0)) }
    }

    
    

    // Packet loss handling and timastamps
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // ✅ Background task to allow processing when the app is in the background
        var backgroundTask: UIBackgroundTaskIdentifier?
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "BLEDataProcessing")
        {
            print("⚠️ Background task expired.")
            if let task = backgroundTask {
                UIApplication.shared.endBackgroundTask(task)
            }
            backgroundTask = .invalid
        }

        guard let task = backgroundTask, task != .invalid else {
            print("⚠️ Failed to start background task.")
            return
        }

        defer {
            UIApplication.shared.endBackgroundTask(task)
            backgroundTask = .invalid
        }

        // ✅ Error handling
        if let error = error {
            print("❌ Error updating value for characteristic: \(error.localizedDescription)")
            return
        }
        
        // ✅ Reset reconnection attempts when data is successfully received
            DispatchQueue.main.async {
                self.isConnected = true
                self.reconnectionAttempts = 0  // ✅ Prevents unnecessary reconnections
            }
        
        // 🔄 Restart Live Activity with latest data
        DispatchQueue.main.async {
            let recentMVE = Array(self.emg.percentMVEHistory.suffix(50))
                if !LiveActivityController.shared.isRunning && !recentMVE.isEmpty {
                    LiveActivityController.shared.start(with: recentMVE)
                    print("✅ Widget Live Activity restarted after reconnection.")
            }
        }

        // ✅ Track first timestamp when data arrives
        if startTime == nil {
            startTime = CACurrentMediaTime() // Save first timestamp
        }

        // ✅ Check if we are within the first 5 seconds
        //if let startTime = startTime, CACurrentMediaTime() - startTime < 5 {
         //   print("⏳ Stabilization period active: Ignoring data for first 5 seconds.")
        //    return // Skip processing
      //  }

        // ✅ Battery Level Handling
        if characteristic.uuid == batteryLevelUUID,
           let value = characteristic.value,
           let battery = value.first {
            DispatchQueue.main.async {
                self.batteryLevel = Int(battery)
                print("🔋 Battery Level Updated: \(battery)%")
            }
            return // Stop here; don't fall through to EMG switch
        }

        switch characteristic.uuid {
        case CBUUID(string: "2A58"): // ✅ EMG Data
            guard let characteristicData = characteristic.value, characteristicData.count % 2 == 0 else {
                print("❌ Error: Invalid EMG data length")
                return
            }

            let systemTimestamp = normalizeTimestamp(CACurrentMediaTime()) // ✅ Ensure timestamp precision

            // ✅ Extract EMG values efficiently
            var rawValues: [Float] = stride(from: 0, to: characteristicData.count, by: 2).map {
                let rawValue = UInt16(characteristicData[$0]) | (UInt16(characteristicData[$0 + 1]) << 8)
                return Float(rawValue) / 1000.0
            }

            // ✅ Replace NaN values with 0.0
            rawValues = rawValues.map { $0.isFinite ? $0 : 0.0 }

            // ✅ Initialize timestamps on first-time connection
            if firstSampleTimestamp == nil || expectedNextTimestamp == nil {
                firstSampleTimestamp = systemTimestamp
                expectedNextTimestamp = firstSampleTimestamp
                print("✅ Initialized firstSampleTimestamp: \(firstSampleTimestamp!)")
            } else if abs(systemTimestamp - expectedNextTimestamp!) > 1.0 {
                print("⚠️ Large gap detected at start-up. Resetting expected timestamp.")
                expectedNextTimestamp = systemTimestamp
            }


            // ✅ Detect & realign large timestamp gaps
            if abs(systemTimestamp - expectedNextTimestamp!) > 1.0 {
                print("⚠️ Large timestamp gap detected. Realigning...")
                expectedNextTimestamp = systemTimestamp
            }

            var timestamp: CFTimeInterval
            if let expectedTime = expectedNextTimestamp {
                
                let timeDifference = systemTimestamp - expectedTime
                if abs(timeDifference) > 0.8 {
                    print("⚠️ Packet loss detected! Performing interpolation.")
                    fillMissingPacketsWithInterpolation(from: expectedTime,
                                                        lastValue: CGFloat(rawValues.first ?? 0.0),
                                                        to: systemTimestamp,
                                                        newValue: CGFloat(rawValues.first ?? 0.0))

                }

                timestamp = normalizeTimestamp(expectedTime)
                expectedNextTimestamp = expectedTime + 0.1
            } else {
                timestamp = normalizeTimestamp(systemTimestamp)
                expectedNextTimestamp = systemTimestamp + 0.1
            }

            // ✅ Store received values in the buffer
            receivedValuesPerTimestamp[timestamp] = rawValues
            totalPacketsReceived += 1
            totalPacketsExpected += 1

            // ✅ More efficient buffer cleanup (prevents overflow)
            if receivedValuesPerTimestamp.count >= rollingBufferLimit {
                receivedValuesPerTimestamp.removeValue(forKey: receivedValuesPerTimestamp.keys.min()!)
            }

         //   print("📊 Timestamp: \(timestamp) | Received \(rawValues.count) EMG samples")
            
            // ✅ Process & Append EMG data
            calculateSignalAcquisitionRatio()
            reconstructDataStream()
            DispatchQueue.main.async {
                self.processAndAppendEMGData(rawValues, timestamp: timestamp)
            }

        default:
            print("⚠️ Unhandled characteristic UUID: \(characteristic.uuid)")
        }
    }
}




