//
//  HelpView.swift
//  Project
//
//  Created by Jóhanna Sóldís Hyström on 1.5.2025.
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Using HandWave for Ergonomic Assessment")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom, 5)

                Group {
                    Text("Step 1: Sensor Placement")
                        .font(.headline)

                    Text("""
                    • Place the EMG sensor over the target muscle.
                    • Follow standard ergonomic protocols for placement consistency.
                    • Minimize motion artifacts through secure attachment.
                    """)
                }

                Group {
                    Text("Step 2: Connect to Device")
                        .font(.headline)

                    Text("""
                    • Turn on Bluetooth and power the EMG sensor.
                    • In the Graph tab, select your sensor to connect.
                    • Battery and connection status appear on the Home screen.
                    """)
                }

                Group {
                    Text("Step 3: Record Activity")
                        .font(.headline)

                    Text("""
                    • Use the Graph tab to start and stop the recording.
                    • Perform the relevant task or posture during recording.
                    • Sessions are saved automatically for review.
                    """)
                }

                Group {
                    Text("Step 4: Review Results")
                        .font(.headline)

                    Text("""
                    • Go to the Data tab to view saved sessions.
                    • Graphs display %MVE over time with thresholds shown.
                    • Use this view to support quick ergonomic analysis.
                    """)
                }
            }
            .padding()
        }
        .navigationTitle("Help & Instructions")
    }
}
