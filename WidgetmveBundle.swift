//
//  WidgetmveBundle.swift
//  Widgetmve
//
//  Created by Alfonso Herrera Rodriguez on 12/03/25.
//

import WidgetKit
import SwiftUI

@main
struct WidgetmveBundle: WidgetBundle {
    var body: some Widget {
        Widgetmve()
        WidgetmveControl()
        WidgetmveLiveActivity()
    }
}
