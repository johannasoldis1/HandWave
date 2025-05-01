//
//  WidgetmveLiveActivity.swift
//  Widgetmve
//

import WidgetKit
import SwiftUI


// MARK: - Live Activity Widget
struct WidgetmveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EMGAttributes.self) { context in
            VStack(alignment: .leading) {
                Text("📡 Live MVE% Active")
                    .font(.caption)
                    .foregroundColor(.green)

                EMGGraphView(values: context.state.graphValues)  // Pass the updated values
                                 .frame(height: 100)

                Text("Data points: \(context.state.graphValues.count)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text("%MVE")
                            .font(.caption)
                            .foregroundColor(.white)

                        EMGGraphView(values: context.state.graphValues)
                            .frame(height: 24)
                    }
                }
            } compactLeading: {
                Text("💪")
            } compactTrailing: {
                Text("\(Int(context.state.graphValues.last ?? 0))%")
            } minimal: {
                Text("MVE")
            }
        }
    }
}


// MARK: - Graph View
struct EMGGraphView: View {
    let values: [CGFloat]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !values.isEmpty else { return }

                let width = geometry.size.width
                let height = geometry.size.height

                let normalized = values.map { min(max($0 / 100.0, 0.0), 1.0) }

                for (i, val) in normalized.enumerated() {
                    let x = CGFloat(i) / CGFloat(values.count - 1) * width
                    let y = height - (val * height)
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.green, lineWidth: 2)
        }
    }
}

