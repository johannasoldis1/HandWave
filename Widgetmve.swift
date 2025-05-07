//
//  Widgetmve.swift
//  Widgetmve
//
//  Created by Alfonso Herrera Rodriguez on 12/03/25.
//
import WidgetKit
import SwiftUI

struct EMGWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> EMGEntry {
        EMGEntry(date: Date(), emgValues: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (EMGEntry) -> Void) {
        let entry = EMGEntry(date: Date(), emgValues: fetchLatestEMGValues())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EMGEntry>) -> Void) {
        let emgValues = fetchLatestEMGValues()
        let entry = EMGEntry(date: Date(), emgValues: emgValues)
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }

    func fetchLatestEMGValues() -> [CGFloat] {
        if let data = UserDefaults.standard.data(forKey: "latestEMGValues"),
           let values = try? JSONDecoder().decode([CGFloat].self, from: data) {
            return values
        }
        return [0.0]
    }
}

struct EMGEntry: TimelineEntry {
    let date: Date
    let emgValues: [CGFloat]
}

struct WidgetmveEntryView: View {
    var entry: EMGEntry

    var body: some View {
        VStack {
            if entry.emgValues.first == -1 {
                // 🔴 Disconnected alert view
                VStack(spacing: 4) {
                    Text("❌ Sensor Disconnected")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text("Please reconnect.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(height: 100)
            } else {
                // ✅ Normal EMG graph
                GeometryReader { geometry in
                    Path { path in
                        let width = geometry.size.width
                        let height = geometry.size.height
                        let values = entry.emgValues
                        guard !values.isEmpty else { return }
                        
                        let clamped = values.map { min(max($0, 0), 100) }
                        let normalized = clamped.map { $0 / 100 }
                        
                        for (index, value) in normalized.enumerated() {
                            let x = CGFloat(index) / CGFloat(max(values.count - 1, 1)) * width
                            let y = height - (value * height)
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)
                }
                .frame(height: 30)
            }
            Text("% MVE Activity")
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(10)
    }
}

struct Widgetmve: Widget {
    let kind: String = "Widgetmve"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EMGWidgetProvider()) { entry in
            WidgetmveEntryView(entry: entry)
        }
        .configurationDisplayName("EMG Graph")
        .description("Displays recent EMG readings.")
        .supportedFamilies([.accessoryRectangular]) // ✅ Lock Screen Widget
        .supportedFamilies([.systemMedium, .systemLarge])  // Allows larger widget sizes
    }
}
