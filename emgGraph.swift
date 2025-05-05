import CoreGraphics
import SwiftUI

class emgGraph: ObservableObject {
    @Published var values: [CGFloat] = [] // Raw EMG values for display
    @Published var oneSecondRMSHistory: [CGFloat] = [] // 1-second RMS values for display
    @Published var shortTermRMSHistory: [CGFloat] = [] // Short-term RMS values for display
    @Published var max10SecRMSHistory: [CGFloat] = [] // Max RMS values for the last 10 seconds
    @Published var mveValue: CGFloat = 0.0  // Store Maximum Voluntary Exertion
    @Published var percentMVEHistory: [CGFloat] = [] // Store %MVE over time
    @Published var calibrationMVEHistory: [CGFloat] = [] // Store MVE during calibration
    @Published var isCalibrating: Bool = false  // Ensure calibration is OFF at startup
    //public var isCalibrating = false  //  Ensure calibration does not start by default
    @Published var forceMVERecalibration: Bool = false  // This will be triggered when the device reconnects
    
    
    
    
    public var calibrationBuffer: [CGFloat] = []
    public var calibrationStartTime: CFTimeInterval?
    
    var recorded_values: [CGFloat] = [] // Recorded raw EMG values for export
    var recorded_rms: [CGFloat] = [] // 1-second RMS values for export
    var shortTermRMSValues: [Float] = [] // Short-term RMS values for export
    var timestamps: [CFTimeInterval] = [] // Timestamps for each recorded value
    var recording_duration: CFTimeInterval = 0 // To store the recording duration
    
    
    
    var recording: Bool = false // Recording state
    var start_time: CFTimeInterval = 0 // Start time for recording
    
    private var shortTermRMSBuffer: [CGFloat] = [] // Buffer for 0.1-second RMS calculation
    private let shortTermRMSWindowSize = 10 // 10 samples for 1 second (10 Hz)
    
    private var oneSecondRMSBuffer: [CGFloat] = [] // Buffer for 1-second RMS calculation
    private let oneSecondRMSWindowSize = 100 // 100 samples for 10 seconds (10 Hz)
    
    private var longTermRMSBuffer: [CGFloat] = [] // Buffer for 10-second max RMS calculation
    private let longTermRMSWindowSize = 20 // 20 x 1-second RMS values
    
    private var shortTermSampleCounter = 0 // Counter for 0.1-second RMS updates
    var droppedPacketTimestamps: [CFTimeInterval] = [] // Stores timestamps of dropped packets
    
    
    
    // Set maximum buffer size
    private let maxBufferSize = 7000
    private var bufferLimit: Int {
        return timestamps.count < 200 ? 2000 : 5000 // Allow more samples at start
    }
    
    
    //prevent lag in UI at high frequencies, throttle UI update with timer of 300ms
    private var lastUIUpdateTime: CFTimeInterval = 0
    private var uiUpdateInterval: CFTimeInterval {
        return timestamps.count < 500 ? 0.05 : 0.1 // Faster updates for first 200 values
    }
    
    
    
    // live activity
    private var lastLoggedTimestamp: CFTimeInterval = 0.0  // Timestamp to track when data was last logged
    
    // New buffer to store recent %MVE values for widget
    public var mveBufferwidget: [CGFloat] = [] // Buffer to store recent %MVE values
    private let maxBufferSizewidget = 500 // Maximum number of %MVE values to store
    private var lastLoggedTimestampwidget: CFTimeInterval = 0.0  // Timestamp to track when data was last logged
    private var lastSentTimestampwidget: CFTimeInterval = 0.0 // Timestamp to track when the last data was sent to the widget
    private let updateIntervalwidget: CFTimeInterval = 5.0 // Time interval in seconds (5 seconds)
    
    
    // failsafe for disconnection
    @Published var isRecording: Bool = false // Changing the code from:  @Published var isRecording = false to be able to see the time that has been recorded in start view
    
    /// Used to trigger recalculation of %MVE after reconnect
    var forceMVERecalculation: Bool = false
    
    var interpolationFlags: [Int] = []
    
    // prevent too many calls for RAw signal
    private var updateThrottleTimer: Timer?
    private var needsUIRefresh: Bool = false
    
    //  Used to disable Canvas drawing when app is backgrounded or locked
    @Published var isUIUpdatesPaused: Bool = false
    
    
    init(firstValues: [CGFloat]) {
        values = firstValues
        
        // Clear the mveBufferwidget every time the app runs
        mveBufferwidget.removeAll()  // Clear the buffer to avoid sending old data
        print("✅ mveBufferwidget has been reset.")
    }
    
    
    func record() {
        print("Recorded values before clearing: \(recorded_values.count)")
        print("Timestamps before clearing: \(timestamps.count)")
        print("Short-term RMS before clearing: \(shortTermRMSValues.count)")
        
        // ✅ Prevent multiple resets
        if recording {
            print("✅ Recording is already active. No action needed.")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            
            print("🔴 Starting Recording... Current emgGraph instance: \(String(describing: self))")
            self?.recording = true
            self?.isRecording = true // Changes: For recording timer in start view
            self?.start_time = CACurrentMediaTime() // Took out the comment to use for recording on home screen
            //  self?.isCalibrating = true // ✅ Start calibration phase
            //  self?.calibrationStartTime = self?.start_time
            //self?.mveValue = 0.0 // ✅ Reset MVE before calibration
            print("🔴 Calibration started. Collecting MVE for 10 seconds...")
        }
        
        func recordMVE() {
            guard !values.isEmpty else {
                print("⚠️ No EMG data available to calculate MVE.")
                return
            }
            
            let maxValue = values.max() ?? 0.0
            mveValue = maxValue
            print("✅ MVE Recorded: \(mveValue)")
        }
        
        
        // ✅ Only clear buffers for first-time recording
        if recorded_values.isEmpty {
            print("✅ First-time recording. Clearing buffers now.")
            recorded_values.removeAll()
            recorded_rms.removeAll()
            shortTermRMSValues.removeAll()
            timestamps.removeAll()
            shortTermRMSBuffer.removeAll()
            oneSecondRMSBuffer.removeAll()
            longTermRMSBuffer.removeAll()
            shortTermSampleCounter = 0
        } else {
            print("⚠️ Buffers already contain data. Not clearing them.")
        }
    }
    
    
    func stop_recording_and_save() -> String {
        // Stop recording
        print("🔹 Stopping recording and preparing data for export...")
        recording = false
        isRecording = false // Changes: For recording timer in start view
        let stop_time = CACurrentMediaTime()
        recording_duration = stop_time - start_time // Store the duration
        print("Recording stopped. Duration: \(recording_duration) seconds")
        
        // Append any remaining short-term and one-second RMS values
        DispatchQueue.main.async {
            if !self.shortTermRMSBuffer.isEmpty {
                let remainingShortTermRMS = self.calculateRMS(from: self.shortTermRMSBuffer.map { Float($0) }) // Convert to Float
                self.shortTermRMSValues.append(remainingShortTermRMS)
            }
            
            if !self.oneSecondRMSBuffer.isEmpty {
                let remainingOneSecondRMS = self.calculateRMS(from: self.oneSecondRMSBuffer.map { Float($0) }) // Convert to Float
                self.recorded_rms.append(CGFloat(remainingOneSecondRMS)) // Convert Float to CGFloat
            }
        }
        
        
        // Debugging the recorded data
        print("Recorded Values Count: \(recorded_values.count)")
        print("Timestamps Count: \(timestamps.count)")
        
        // Start preparing the dataset
        var dataset = "Recording Duration (s):,\(recording_duration)\n"
        dataset += "Maximum MVE:,\(mveValue)\n"  // ✅ Add this line
        //   dataset += "Index,System Timestamp (s),EMG (Raw Data),0.1s RMS,1s RMS,%MVE\n" //column headers
        dataset += "Index,System Timestamp (s),EMG (Raw Data),0.1s RMS,1s RMS,%MVE,Interpolation\n"
        
        // ✅ Prevent duplicate timestamps and filter NaN values
        var seenTimestamps: Set<CFTimeInterval> = []
        
        // Iterate through recorded values to construct the dataset
        for (index, rawValue) in recorded_values.enumerated() {
            let systemTimestamp = timestamps.indices.contains(index) ? timestamps[index] : 0.0
            
            // ✅ Skip duplicate timestamps
            if seenTimestamps.contains(systemTimestamp) {
                continue
            }
            seenTimestamps.insert(systemTimestamp)
            
            var shortTermRMS: Float = 0.0
            var oneSecondRMS: Float = 0.0
            
            // Retrieve short-term RMS
            if index % self.shortTermRMSWindowSize == 0 && index / self.shortTermRMSWindowSize < self.shortTermRMSValues.count {
                shortTermRMS = self.shortTermRMSValues[index / self.shortTermRMSWindowSize]
            }
            
            // Retrieve one-second RMS
            if index % self.oneSecondRMSWindowSize == 0 && index / self.oneSecondRMSWindowSize < self.recorded_rms.count {
                oneSecondRMS = Float(self.recorded_rms[index / self.oneSecondRMSWindowSize]) // Convert CGFloat to Float
            }
            // ✅ Calculate %MVE for the recorded EMG value
            //let percentMVE = mveValue > 0 ? (rawValue / mveValue) * 100 : 0
            // let rmsValue = calculateRMS(from: values.map { Float($0) })  // Compute RMS from new values
            
            let rmsValue = recorded_rms.indices.contains(index) ? recorded_rms[index] : 0.0
            let percentMVE = percentMVEHistory.indices.contains(index) ? percentMVEHistory[index] : 0.0
            //  let percentMVE = mveValue > 0 ? (rmsValue / mveValue) * 100 : 0
            
            
            // ✅ Update max RMS dynamically during calibration
            // if isCalibrating {
            ///      mveValue = max(mveValue, CGFloat(rmsValue))  // Update max RMS only in calibration mode
            //      print("🔵 Updating RMS Max Value: \(mveValue)")
            // }
            
            // ✅ Only update MVE during calibration
            if isCalibrating {
                mveValue = max(mveValue, CGFloat(rmsValue))  // Track highest RMS during calibration
                print("🔵 Updating RMS Max Value During Calibration: \(mveValue)")
            } else {
                // ✅ Do NOT update MVE after calibration ends
                print("🔒 Calibration is over. Keeping Max MVE fixed: \(mveValue)")
            }
            
            // ✅ Compute %MVE using RMS-based calculation
            //   let percentMVE = mveValue > 0 ? (rmsValue / mveValue) * 100 : 0
            
            
            // Debug each row
            print("Row \(index): Timestamp \(systemTimestamp), Raw EMG \(rawValue), Short-Term RMS \(shortTermRMS), One-Second RMS \(oneSecondRMS)")
            
            // ✅ Replace NaN or invalid values with 0.0 for safety
            let emgData = rawValue.isNaN ? "0.0" : String(format: "%.6f", rawValue) // Format to 6 decimal places
            let rmsShortTerm = shortTermRMS.isNaN ? "0.0" : String(format: "%.6f", shortTermRMS)
            let rmsOneSecond = oneSecondRMS.isNaN ? "0.0" : String(format: "%.6f", oneSecondRMS)
            let percentMVEString = percentMVE.isNaN ? "0.0" : String(format: "%.2f", percentMVE) // Format %MVE to 2 decimal places
            
            // ✅ Append row to the dataset, now including %MVE
            let interpolationFlag = interpolationFlags.indices.contains(index) ? "\(interpolationFlags[index])" : "0"
            dataset += "\(index),\(systemTimestamp),\(emgData),\(rmsShortTerm),\(rmsOneSecond),\(percentMVEString),\(interpolationFlag)\n"
        }
        
        // Save the dataset to a file
        saveToFile(dataset)
        return dataset
    }
    
    func resetGraph() {
        print("🔄 Resetting Graph...")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                print("⚠️ Reset skipped: Self is nil.")
                return
            }
            
            // ✅ Step 1: Clear all stored data safely
            self.values.removeAll()
            self.timestamps.removeAll()
            self.oneSecondRMSHistory.removeAll()
            self.shortTermRMSHistory.removeAll()
            self.max10SecRMSHistory.removeAll()
            self.recorded_values.removeAll()
            self.recorded_rms.removeAll()
            self.shortTermRMSValues.removeAll()
            self.shortTermRMSBuffer.removeAll()
            self.oneSecondRMSBuffer.removeAll()
            self.longTermRMSBuffer.removeAll()
            self.shortTermSampleCounter = 0
            
            print("✅ Graph data cleared.")
            
            // ✅ Step 2: Prevent empty graph by adding placeholder values
            let fakeStartTime = CACurrentMediaTime()
            let resetCount = 50 // Simulate 5 seconds of fake data at 10Hz
            
            self.timestamps = (0..<resetCount).map { fakeStartTime + (Double($0) * 0.1) }
            self.values = Array(repeating: 0.001, count: resetCount)
            
            self.oneSecondRMSHistory = Array(repeating: 0.001, count: resetCount)
            self.shortTermRMSHistory = Array(repeating: 0.001, count: resetCount)
            self.max10SecRMSHistory = Array(repeating: 0.001, count: resetCount)
            
            // ✅ Step 3: Ensure values and timestamps are synchronized
            if self.values.count != self.timestamps.count {
                let diff = abs(self.values.count - self.timestamps.count)
                if self.values.count > self.timestamps.count {
                    self.values.removeFirst(diff)
                } else {
                    let lastTimestamp = self.timestamps.last ?? fakeStartTime
                    let missingTimestamps = (0..<diff).map { lastTimestamp + (Double($0) * 0.1) }
                    self.timestamps.append(contentsOf: missingTimestamps)
                }
            }
            
            print("🔍 Post-Reset Check: Values Count: \(self.values.count), Timestamps Count: \(self.timestamps.count)")
            
            // ✅ Step 4: Ensure a safe UI refresh
            DispatchQueue.main.async {
                self.values.removeAll()
                self.timestamps.removeAll()
                self.oneSecondRMSHistory.removeAll()
                self.shortTermRMSHistory.removeAll()
                self.max10SecRMSHistory.removeAll()
                
                print("✅ Graph data cleared.")
                
                let fakeStartTime = CACurrentMediaTime()
                self.timestamps = (0..<50).map { fakeStartTime + (Double($0) * 0.1) }
                self.values = Array(repeating: 0.001, count: 50)
                
                print("🔍 Post-Reset Check: Values Count: \(self.values.count), Timestamps Count: \(self.timestamps.count)")
            }
        }
    }
    
    
    func startMVECalibration() {
        if forceMVERecalibration {
            print("🔄 Starting MVE Recalibration due to reconnection...")
            
            // Clear buffers and reset MVE value
            calibrationBuffer.removeAll()
            calibrationMVEHistory.removeAll()
            mveValue = 0  // Reset to zero or the starting value
            
            // Trigger the calibration procedure
            isCalibrating = true
            calibrationStartTime = CACurrentMediaTime()  // Record the start time of calibration
            forceMVERecalculation = false  // Reset the recalibration flag
            
            print("🔄 Calibration Started: Buffer cleared. Start Time: \(calibrationStartTime ?? -1)")
            
            // Optionally handle the duration for which calibration runs (e.g., 10 seconds)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                self.endMVECalibration()  // Call end after 10 seconds or based on your needs
            }
        }
    }
    
    
    
    func endMVECalibration() {
        if isCalibrating {
            // Update the mveValue after calibration with the max RMS value recorded during the calibration
            if let maxValue = max10SecRMSHistory.max() {
                mveValue = maxValue  // Store the maximum RMS value during calibration
                print("✅ Calibration Finished. New Max MVE Stored: \(mveValue)")
            } else {
                print("⚠️ Calibration Failed! No values in buffer.")
            }
        } else {
            print("🔒 Calibration is over. Keeping previous MVE: \(mveValue)")
        }
        
        isCalibrating = false  // Ensure calibration is marked as done
    }
    
    // Change to see files no matter the name:
    private func saveToFile(_ dataset: String) -> URL? {
        guard !dataset.isEmpty else {
            print("❌ Dataset is empty. File saving aborted.")
            return nil
        }

        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH_mm_ss"

        guard let directory = documentDirectory else {
            print("❌ Unable to access the document directory.")
            return nil
        }

        let filename = directory.appendingPathComponent("emg_data_\(dateFormatter.string(from: Date())).csv")

        do {
            try dataset.write(to: filename, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                print("✅ File saved successfully at: \(filename.path)")
            }
            return filename
        } catch {
            DispatchQueue.main.async {
                print("❌ Failed to save file: \(error.localizedDescription)")
            }
            return nil
        }
    }
    
    private func prepareAndSaveToFile() {
        // Validate that we have data to save
        guard !recorded_values.isEmpty, !timestamps.isEmpty else {
            print("❌ No recorded values or timestamps to save.")
            return
        }
        
        // Start preparing the dataset
        var dataset = "Recording Duration (s):,\(recording_duration)\n"
        dataset += "Index,System Timestamp (s),EMG (Raw Data),0.1s RMS,1s RMS\n" // Column headers
        
        // Iterate through recorded values and build the CSV data
        for (index, rawValue) in recorded_values.enumerated() {
            let systemTimestamp = timestamps.indices.contains(index) ? timestamps[index] : 0.0
            let shortTermRMS = index / shortTermRMSWindowSize < shortTermRMSValues.count
            ? shortTermRMSValues[index / shortTermRMSWindowSize]
            : 0.0
            let oneSecondRMS = index / oneSecondRMSWindowSize < recorded_rms.count
            ? recorded_rms[index / oneSecondRMSWindowSize]
            : 0.0
            
            // Append a row to the dataset
            dataset += "\(index),\(systemTimestamp),\(rawValue),\(shortTermRMS),\(oneSecondRMS)\n"
        }
        
        // Log dataset preview for debugging
        print("🔍 Dataset Preview:\n\(dataset.prefix(500))") // First 500 characters of the dataset
        
        // Call saveToFile with the prepared dataset
        saveToFile(dataset)
    }
    
    func triggerDataSaving() {
        print("📁 Preparing to save EMG data to a file...")
        prepareAndSaveToFile()
    }
    
    func normalizeTimestamp(_ timestamp: CFTimeInterval, precision: Int = 1) -> CFTimeInterval {
        let multiplier = pow(10.0, Double(precision))
        return round(timestamp * multiplier) / multiplier
    }
    
    func updateMax10SecRMS(_ oneSecondRMS: CGFloat) {
        print("📊 RMS Update: Current Count =", oneSecondRMSHistory.count)
        longTermRMSBuffer.append(oneSecondRMS)
        
        if longTermRMSBuffer.count > longTermRMSWindowSize {
            longTermRMSBuffer.removeFirst()
        }
        
        let maxRMS = longTermRMSBuffer.max() ?? 0.0
        
        DispatchQueue.main.async {
            self.max10SecRMSHistory.append(maxRMS)
            if self.max10SecRMSHistory.count > 100 {
                self.max10SecRMSHistory.removeFirst()
            }
        }
    }
    
    func calculateRMS(from samples: [Float]) -> Float {
        let validSamples = samples.filter { $0.isFinite }
        
        guard !validSamples.isEmpty else {
            print("WARNING: All samples were NaN, returning 0.0 instead.")
            return 0.0
        }
        
        let squaredSum = validSamples.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(squaredSum / Float(validSamples.count))
    }
    
    
    
    func updateLiveActivity() {
        // Ensure we're passing only the most recent %MVE value from the buffer
        guard let latestMVE = mveBufferwidget.last else { return }
        print("Updating Live Activity with new %MVE data: \(latestMVE)")
        
        mveBufferwidget.append(latestMVE)
        if mveBufferwidget.count > maxBufferSizewidget {
            mveBufferwidget.removeFirst()
        }
        let recentValues = Array(mveBufferwidget.suffix(50))  // Keep 50 values
        
        // Schedule async task on main queue
        DispatchQueue.main.async { [weak self] in
            guard self != nil else { return }
            Task {
                if LiveActivityController.shared.shouldUpdateActivity(with: recentValues) {
                    await LiveActivityController.shared.update(with: recentValues)
                }
            }
        }
    }
    
    
    
    func append(values: [CGFloat], timestamp: CFTimeInterval, isInterpolated: Bool = false) {
        // print("🔄 append(values: \(values), timestamp: \(timestamp)) called") // Debug log
        
        // ✅ Ensure new data is received before proceeding
        guard !values.isEmpty else {
            print("⚠️ No new data received. Skipping UI update.")
            return
        }
        
        // ✅  Automatically update MVE if a new higher value is detected
        for value in values {
            if value > mveValue {
                mveValue = value
            }
            
            // ✅ Handle Calibration Mode
            if isCalibrating {
                calibrationBuffer.append(contentsOf: values)
                calibrationMVEHistory.append(values.max() ?? 0.0)
                
                if let start = calibrationStartTime, CACurrentMediaTime() - start >= 10 {
                    endMVECalibration()
                }
                return  // ❗ Skip normal processing during calibration
            }
            
            // ✅ Move %MVE Calculation to Background Thread
            // Process RMS and %MVE calculation in background
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                let rmsValue = self.calculateRMS(from: values.map { Float($0) })  // Compute RMS
                let percentMVE = self.mveValue > 0 ? (rmsValue / Float(self.mveValue)) * 100 : 0
                //      print("📊 %MVE Calculated: \(percentMVE) | MVE Value: \(self.mveValue)")
                
                // Update the UI on the main thread
                DispatchQueue.main.async {
                    if !self.isCalibrating {
                        self.percentMVEHistory.append(CGFloat(percentMVE))
                        self.recorded_rms.append(CGFloat(rmsValue))
                        
                        // Ensure buffer does not overflow
                        if self.percentMVEHistory.count > 500 {
                            self.percentMVEHistory.removeFirst(self.percentMVEHistory.count - 500)
                        }
                        
                        // Add the calculated %MVE to the mveBuffer for widget
                        self.mveBufferwidget.append(CGFloat(percentMVE))
                        
                        // Remove oldest data if buffer exceeds the maximum size
                        if self.mveBufferwidget.count > self.maxBufferSizewidget {
                            self.mveBufferwidget.removeFirst()
                            //   print("✅ mveBufferwidget size exceeded, removed the oldest value.")
                        }
                        
                        // Check if 5 seconds have passed since the last update
                        let currentTimestampwidget = CACurrentMediaTime()
                        if currentTimestampwidget - self.lastSentTimestampwidget >= self.updateIntervalwidget {
                            self.lastSentTimestampwidget = currentTimestampwidget
                            // Send the most recent %MVE data to the Live Activity
                            self.updateLiveActivity()
                            
                            
                        }
                    }
                }
            }
            
            
            
            // ✅ Auto-start recording only once (prevent looping)
            if !recording {
                print("⚠️ Recording was not active. Starting once...")
                self.record()
            }
            
            // ✅ Ensure recording is active before appending
            guard recording else {
                print("⚠️ Recording is not active. Data is not being appended.")
                return
            }
            
            // ✅ Ensure valid timestamp
            guard timestamp.isFinite else {
                print("❌ Invalid timestamp detected: \(timestamp). Skipping this entry.")
                return
            }
            
            // ✅ Ensure timestamps and values stay in sync
            if timestamps.count > recorded_values.count {
                print("⚠️ Timestamps count (\(timestamps.count)) exceeds values count (\(recorded_values.count))! Adjusting...")
                timestamps.removeFirst(timestamps.count - recorded_values.count)
            } else if recorded_values.count > timestamps.count {
                print("⚠️ Values count (\(recorded_values.count)) exceeds timestamps count (\(timestamps.count))! Adjusting...")
                recorded_values.removeFirst(recorded_values.count - timestamps.count)
            }
            
            // ✅ Prevent duplicate timestamps and ensure a monotonic sequence
            var normalizedTimestamp = normalizeTimestamp(timestamp)
            if let lastTimestamp = timestamps.last {
                if normalizedTimestamp - lastTimestamp < 0.002 {
                    print("⚠️ Adjusting timestamp to prevent duplicates.")
                    normalizedTimestamp = lastTimestamp + 0.002
                }
                
                // ✅ Prevent excessive jumps in timestamps
                if normalizedTimestamp - lastTimestamp > 10.0 {
                    print("⚠️ Huge timestamp jump detected (>10s). Skipping to prevent UI errors.")
                    return
                }
            }
            
            // ✅ Handle missing timestamps and packet loss (Restored original logic)
            if let lastTimestamp = timestamps.last, let lastValue = recorded_values.last {
                var normalizedLastTimestamp = normalizeTimestamp(lastTimestamp)
                let normalizedCurrentTimestamp = normalizeTimestamp(timestamp)
                let maxAllowedGap: CFTimeInterval = 0.2
                let maxGapThreshold: CFTimeInterval = 3.0 // Avoid excessive interpolation
                
                if normalizedCurrentTimestamp - normalizedLastTimestamp > maxGapThreshold {
                    print("⚠️ Large gap detected (>3s), skipping interpolation to prevent unrealistic values.")
                    normalizedLastTimestamp = normalizedCurrentTimestamp // Reset to avoid flooding
                } else {
                    while normalizedLastTimestamp + maxAllowedGap < normalizedCurrentTimestamp {
                        let missingTimestamp = normalizeTimestamp(normalizedLastTimestamp + 0.1)
                        recorded_values.append(lastValue)
                        timestamps.append(missingTimestamp)
                        interpolationFlags.append(1)
                        droppedPacketTimestamps.append(missingTimestamp)
                        print("⚠️ Small gap detected. Interpolating missing timestamp \(missingTimestamp) with value \(lastValue).")
                        normalizedLastTimestamp += 0.1
                    }
                }
            }
            
            // ✅ Append new values and timestamps
            for value in values {
                // ✅ Detect suspiciously constant EMG values
                if recorded_values.count > 10 {
                    let lastTenValues = recorded_values.suffix(10)
                    let maxDiff = lastTenValues.max()! - lastTenValues.min()!
                    if maxDiff < 0.0001 {
                        print("⚠️ Warning: Minimal signal variation detected at timestamp \(timestamp). Possible sensor issue?")
                    }
                }
                
                // ✅ Sanitize and store the value
                let sanitizedValue = value.isFinite ? value : 0.0
                recorded_values.append(sanitizedValue)
                timestamps.append(normalizedTimestamp)
                interpolationFlags.append(isInterpolated ? 1 : 0)  //Track if this is interpolated
                // print("✅ Appended value: \(sanitizedValue), timestamp: \(normalizedTimestamp)")
                
                if value.isNaN {
                    print("⚠️ NaN detected at timestamp \(normalizedTimestamp). Marked as dropped packet.")
                    droppedPacketTimestamps.append(normalizedTimestamp)
                }
                
                // ✅ Update RMS buffers
                shortTermRMSBuffer.append(sanitizedValue)
                shortTermSampleCounter += 1
                oneSecondRMSBuffer.append(sanitizedValue)
            }
            
            // ✅ Calculate short-term RMS (every 10 samples)
            if shortTermSampleCounter >= shortTermRMSWindowSize {
                DispatchQueue.global(qos: .background).async {
                    let shortTermRMS = self.calculateRMS(from: self.shortTermRMSBuffer.map { Float($0) })
                    self.shortTermRMSBuffer.removeAll()
                    DispatchQueue.main.async {
                        self.shortTermRMSValues.append(shortTermRMS)
                        self.shortTermRMSHistory.append(CGFloat(shortTermRMS))
                        //      print("📏 Short-Term RMS Count: \(self.shortTermRMSHistory.count)")
                    }
                }
                shortTermSampleCounter = 0
            }
            
            // ✅ Calculate one-second RMS (every 100 samples)
            if oneSecondRMSBuffer.count == oneSecondRMSWindowSize {
                let oneSecondRMS = calculateRMS(from: oneSecondRMSBuffer.map { Float($0) })
                let validOneSecondRMS = oneSecondRMS.isFinite ? oneSecondRMS : 0.0
                // ✅ Compute %MVE before using it
                let percentMVE: CGFloat = mveValue > 0 ? (CGFloat(validOneSecondRMS) / mveValue) * 100 : 0
                
                
                DispatchQueue.main.async {
                    self.oneSecondRMSHistory.append(CGFloat(validOneSecondRMS))
                    self.recorded_rms.append(CGFloat(validOneSecondRMS))
                    self.percentMVEHistory.append(percentMVE) // ✅ Update together
                    print("📏 One-Second RMS Count: \(self.oneSecondRMSHistory.count)")
                    print("🔹 Last One-Second RMS Value: \(validOneSecondRMS)")
                }
                
                updateMax10SecRMS(CGFloat(validOneSecondRMS))
                oneSecondRMSBuffer.removeAll()
            }
            
            // ✅ Debugging: Confirm latest timestamp and sample count
            // print("🕒 Latest Timestamp: \(timestamps.last ?? -1), Total Samples: \(timestamps.count)")
            
            // ✅ **Force UI Update only when values & timestamps are both valid**
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                //   let now = CACurrentMediaTime()
                
                
                // ✅ Prevent unnecessary UI updates if there’s no new data
                guard !values.isEmpty else {
                    print("⚠️ No new values added, skipping UI refresh.")
                    return
                }
                
                // ✅ Append values efficiently
                self.values.append(contentsOf: values.filter { $0.isFinite })
                
                // ✅ Debugging: Check values and timestamps count
                //         print("🔍 Debug: recorded_values count = \(self.recorded_values.count), values count = \(self.values.count), timestamps count = \(self.timestamps.count)")
                
                // ✅ Prevent buffer overflow
                let bufferLimit = min(self.maxBufferSize, 1000)
                if self.values.count > bufferLimit {
                    let dropCount = self.values.count - (bufferLimit * 90 / 100)
                    self.values.removeFirst(dropCount)
                    self.timestamps.removeFirst(dropCount)
                    self.recorded_values.removeFirst(dropCount)
                }
                
                // ✅ BUFFER WARNING / TRIM
                let warningLimit = 6000
                let trimTarget = 5000
                
                if recorded_values.count > warningLimit {
                    print("⚠️ WARNING: EMG buffer growing too large! Trimming to prevent crash.")
                    
                    let dropCount = recorded_values.count - trimTarget
                    
                    self.recorded_values.removeFirst(dropCount)
                    self.timestamps.removeFirst(min(dropCount, self.timestamps.count))
                    self.percentMVEHistory.removeFirst(min(dropCount, self.percentMVEHistory.count))
                    self.recorded_rms.removeFirst(min(dropCount, self.recorded_rms.count))
                    
                    // Optional: Trim UI graphs too
                    self.values.removeFirst(min(dropCount, self.values.count))
                    self.oneSecondRMSHistory.removeFirst(min(dropCount, self.oneSecondRMSHistory.count))
                    self.shortTermRMSHistory.removeFirst(min(dropCount, self.shortTermRMSHistory.count))
                    
                    print("✅ Trimmed \(dropCount) old samples from buffers.")
                }
                
                // ✅ Force UI update
                self.needsUIRefresh = true
                if self.updateThrottleTimer == nil {
                    self.updateThrottleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                        if self.needsUIRefresh {
                            self.objectWillChange.send()
                            self.needsUIRefresh = false
                        }
                        self.updateThrottleTimer = nil
                    }
                }
                
            }
            
        }
        
        func getLastSavedContent() -> String {
            print("📤 Exporting last recorded EMG data...")
            return stop_recording_and_save()
        }
    }
}
