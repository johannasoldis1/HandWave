//
//  ContentView.swift
//  HandWave
//

import SwiftUI
import UniformTypeIdentifiers
import ActivityKit
import Foundation

struct ContentView: View {
    @StateObject var emgGraph: emgGraph
    @StateObject var bleManager: BLEManager
    @State private var showingExporter = false
    @State private var isExporting = false
    @State var file_content: TextFile = TextFile(initialText: "")
    @State private var showingDeviceSelection = false
    @State private var isCalibrating = false
    @State private var calibrationTimeRemaining = 10
    @State private var isRecordingActive = false

    let workoutManager: WorkoutManager

    struct HighlightButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(6)
                .frame(width: 110, height: 40)
                .background(configuration.isPressed ? Color.gray.opacity(0.5) : Color.blue.opacity(0.8))
                .cornerRadius(10)
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(configuration.isPressed ? Color.gray : Color.blue, lineWidth: 2)
                )
                .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    struct TextFile: FileDocument {
        static var readableContentTypes = [UTType.commaSeparatedText]
        var text: String
        init(initialText: String = "") { self.text = initialText }
        init(configuration: ReadConfiguration) throws {
            text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
        }
        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: text.data(using: .utf8) ?? Data())
        }
    }

    func startCalibration() {
        isCalibrating = true
        calibrationTimeRemaining = 10
        emgGraph.startMVECalibration()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if calibrationTimeRemaining > 0 {
                calibrationTimeRemaining -= 1
            } else {
                timer.invalidate()
                isCalibrating = false
                emgGraph.endMVECalibration()
            }
        }
    }

    init(emgGraph: emgGraph, bleManager: BLEManager, workoutManager: WorkoutManager) {
        _emgGraph = StateObject(wrappedValue: emgGraph)
        _bleManager = StateObject(wrappedValue: bleManager)
        self.workoutManager = workoutManager
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with custom logo from Assets
                    
                    VStack(alignment: .center) {
                        Text("iOS 17+Mode Active").font(.subheadline).foregroundColor(.gray).frame(maxWidth: .infinity, alignment: .center)
                    }
                    Spacer()

                // EMG Graph Grid (2x2)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    EMGGraphView(title: "Raw EMG Data", values: emgGraph.values, color: .blue)
                        .environmentObject(emgGraph) // <--- ADD THIS
                    EMGGraphView(title: "1 Second RMS", values: emgGraph.oneSecondRMSHistory, color: .green)
                        .environmentObject(emgGraph) // <--- ADD THIS
                    EMGGraphView(title: "MVE", values: emgGraph.percentMVEHistory, color: .red)
                        .environmentObject(emgGraph) // <--- ADD THIS
                    VStack(alignment: .center, spacing: 6) {
                        Text("MVE Values")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("Current: \(String(format: "%.2f", emgGraph.percentMVEHistory.last ?? 0.0))%")
                            .font(.subheadline)
                        Text("Max: \(String(format: "%.2f", emgGraph.mveValue))%")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                Spacer()
            

                // Connection Status
                VStack(spacing: 8) {
                    if !bleManager.isConnected {
                        Button("Connect to Sensor") {
                            showingDeviceSelection = true
                        }
                        .buttonStyle(HighlightButtonStyle())
                    } else {
                        Text("Connected to EMGBLE2!")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    HStack(spacing: 4) {
                        Text("STATUS:")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(bleManager.BLEisOn ? "Bluetooth is ON" : "Bluetooth is OFF")
                            .font(.headline)
                            .foregroundColor(bleManager.BLEisOn ? .green : .red)
                    }
                    Spacer()

                    // Moved Calibration button here
                    Button(action: startCalibration) {
                        Text(isCalibrating ? "Calibrating... \(calibrationTimeRemaining)s" : "Calibrate MVE")
                    }
                    .disabled(isCalibrating)
                    
                    .buttonStyle(HighlightButtonStyle())
                }
                .frame(maxWidth: .infinity)
                Spacer()

                // Control Buttons Grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    Button(bleManager.isScanning ? "Stop Scan" : "Scan") {
                        if bleManager.isScanning {
                            bleManager.stopScanning()
                        } else {
                            bleManager.startScanning()
                        }
                    }

                    Button(isRecordingActive ? "Stop Record" : "Record") {
                        if isRecordingActive {
                            let text = emgGraph.stop_recording_and_save()
                            file_content.text = text
                            showingExporter = true
                            isRecordingActive = false
                        } else {
                            emgGraph.record()
                            isRecordingActive = true
                        }
                    }

                    Button("Reset") {
                        emgGraph.resetGraph()
                    }

                    Button("Refresh") {
                        emgGraph.objectWillChange.send()
                    }

                    Button("Reconnect") {
                        if let first = bleManager.BLEPeripherals.first {
                            bleManager.connectSensor(p: first)
                        }
                    }

                    Button("Export last") {
                        showingExporter = true
                    }
                }
                .buttonStyle(HighlightButtonStyle())
                .padding(.horizontal)
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: file_content,
            contentType: .commaSeparatedText,
            defaultFilename: "emg-data"
        ) { result in
            switch result {
            case .success(let url):
                print("Saved to \(url)")
            case .failure(let error):
                print("Export error: \(error.localizedDescription)")
            }
        }
        .actionSheet(isPresented: $showingDeviceSelection) {
            ActionSheet(
                title: Text("Available Sensors"),
                message: Text("Tap a device to connect"),
                buttons: bleManager.BLEPeripherals.map { peripheral in
                    .default(Text(peripheral.name)) {
                        bleManager.connectSensor(p: peripheral)
                    }
                } + [.cancel()]
            )
        }
    }
}

struct EMGGraphView: View {
    @EnvironmentObject var emgGraph: emgGraph
    var title: String
    var values: [CGFloat]
    var color: Color

    var body: some View {
        VStack {
            Text(title).font(.caption).foregroundColor(.gray)
            Canvas { context, size in
                guard !emgGraph.isUIUpdatesPaused else { return } // <--- ADD THIS GUARD
                let height = size.height
                let width = size.width
                let midY = height / 2
                let displayValues = values.suffix(300)

                guard displayValues.count > 1 else { return }

                var path = Path()

                               // 🛠 Here: Use fixed max for MVE
                               let fixedMaxValue: CGFloat = (title.contains("MVE")) ? 120.0 : (displayValues.map { abs($0) }.max() ?? 1.0)

                               for (index, value) in displayValues.enumerated() {
                                   let x = CGFloat(index) / CGFloat(displayValues.count - 1) * width
                                   let normalizedValue = value / fixedMaxValue // Normalize based on fixed scale if MVE
                                   let y = midY - (midY * normalizedValue)

                                   if index == 0 {
                                       path.move(to: CGPoint(x: x, y: y))
                                   } else {
                                       path.addLine(to: CGPoint(x: x, y: y))
                                   }
                               }
                
                context.stroke(path, with: .color(color), lineWidth: 1.5)
            }
            .frame(height: 80)
        }
    }
}

