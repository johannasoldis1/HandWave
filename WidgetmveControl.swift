//
//  WidgetmveControl.swift
//  Widgetmve
//
//  Created by Alfonso Herrera Rodriguez on 12/03/25.
//
import SwiftUI
import WidgetKit

struct WidgetmveControl: Widget {
    let kind: String = "WidgetmveControl"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EMGWidgetProvider()) { entry in
            VStack {
                Button("Start Recording") {
                    // ✅ Call EMG recording start function here
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .configurationDisplayName("EMG Control")
        .description("Start or stop EMG recording.")
    }
}
