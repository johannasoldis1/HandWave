import ActivityKit
import Foundation
import SwiftUI

@available(iOS 16.1, *)
public struct EMGAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var graphValues: [CGFloat]
    }

    public var name: String
}
