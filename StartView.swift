//
//  StartView.swift
//  HandWave
//

import SwiftUI

struct StartView: View {
    @StateObject var emgGraph: emgGraph
    @StateObject var bleManager: BLEManager
    let workoutManager: WorkoutManager  // <-- healthkit

    @State private var selectedTab = 0
    @State private var recordingTimeString: String = "00:00"
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            // App Header (Logo + Name)
            HStack {
                Image("HandWaveLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                Text("Hand Wave")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if let battery = bleManager.batteryLevel {
                    ZStack {
                        Image(systemName:
                            battery < 20 ? "battery.25" :
                            battery < 50 ? "battery.50" :
                            battery < 80 ? "battery.75" : "battery.100"
                        )
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 20)
                        .foregroundColor(battery < 20 ? .red : .green)

                        Text("\(battery)%")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.4), radius: 0.5, x: 0, y: 0)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)

            Divider()

            // TabView Section
            TabView(selection: $selectedTab) {
                // Home Tab
                ScrollView {
                    VStack(alignment: .center, spacing: 24) {
                        Text("Real-time Muscle Strain Monitoring")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("Use %MVE thresholds to detect overuse, validate posture, and document muscle workload efficiently.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        // Sensor & Recording Info
                        GroupBox(label: Label("Connection Status", systemImage: "bolt.horizontal.circle")) {
                            if bleManager.isConnected {
                                VStack(spacing: 12) {
                                    Label("Sensor Connected", systemImage: "antenna.radiowaves.left.and.right")
                                        .font(.headline)
                                        .foregroundColor(.green)

                                    HStack(spacing: 16) {
                                        if let battery = bleManager.batteryLevel {
                                            Label("Battery: \(battery)%", systemImage:
                                                battery < 20 ? "battery.25" :
                                                battery < 50 ? "battery.50" :
                                                battery < 80 ? "battery.75" :
                                                "battery.100"
                                            )
                                        }
                                        if emgGraph.isRecording {
                                            Label("Recording: Active", systemImage: "record.circle")
                                                .foregroundColor(.blue)

                                            Text("⏱ Duration: \(recordingTimeString)")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .font(.subheadline)
                                }
                                .onReceive(timer) { _ in
                                    if emgGraph.isRecording {
                                        let seconds = Int(CACurrentMediaTime() - emgGraph.start_time)
                                        let minutes = seconds / 60
                                        let remainingSeconds = seconds % 60
                                        recordingTimeString = String(format: "%02d:%02d", minutes, remainingSeconds)
                                    } else {
                                        recordingTimeString = "00:00"
                                    }
                                }
                            } else {
                                Label("No sensor connected", systemImage: "wifi.slash")
                                    .foregroundColor(.red)
                                    .font(.subheadline)
                            }
                        }
                        .padding()

                        // App Features
                        GroupBox(label: Label("Capabilities", systemImage: "staroflife.circle")) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("View EMG signals as %MVE in live plots", systemImage: "waveform.path.ecg")
                                Label("Review recorded sessions with MVE thresholds in-app", systemImage: "chart.bar.xaxis")
                                Label("Export CSV data for detailed offline analysis", systemImage: "square.and.arrow.up")
                            }
                            .font(.subheadline)
                            .padding(.vertical, 5)
                        }
                        .padding(.horizontal)

                        // CTA Button
                        Button(action: {
                            selectedTab = 2
                        }) {
                            Label("Start Monitoring", systemImage: "play.circle.fill")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .padding(.horizontal)
                        }

                        Spacer()
                    }
                    .padding(.top, 30)
                }
                .tabItem {
                    Image(systemName: "house")
                    Text("Home")
                }
                .tag(0)

                // Help Tab
                HelpView()
                    .tabItem {
                        Image(systemName: "questionmark.circle")
                        Text("Help")
                    }
                    .tag(1)

                // Graph Tab
                ContentView(emgGraph: emgGraph, bleManager: bleManager, workoutManager: workoutManager)
                    .tabItem {
                        Image(systemName: "waveform.path.ecg")
                        Text("Graph")
                    }
                    .tag(2)

                // Data Tab
                DataView()
                    .tabItem {
                        Image(systemName: "doc.text")
                        Text("Data")
                    }
                    .tag(3)
            }
            .background(Color.white)
        }
    }
}


