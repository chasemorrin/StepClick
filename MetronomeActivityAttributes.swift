import ActivityKit
import Foundation

/// The data shown on the Lock Screen / Dynamic Island.
/// This file belongs to BOTH the app and the widget extension.
nonisolated struct MetronomeActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var bpm: Int
        var isPlaying: Bool
    }

    init() {}
}
