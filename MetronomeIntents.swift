import AppIntents
import Foundation

/// What a Live Activity button asks the metronome to do.
enum MetronomeCommand: Sendable {
    case togglePlay
    case tempoUp
    case tempoDown
}

/// The app plugs itself in here at launch (see StepClickApp.swift).
/// The widget extension only needs this file to compile; the buttons' actions
/// actually run inside the app, where the handler is set.
@MainActor
enum MetronomeCommandCenter {
    static var handler: (@MainActor (MetronomeCommand) -> Void)?
}

// This file belongs to BOTH the app and the widget extension.

struct TogglePlayIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or pause"

    @MainActor
    func perform() async throws -> some IntentResult {
        MetronomeCommandCenter.handler?(.togglePlay)
        return .result()
    }
}

struct TempoUpIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Faster"

    @MainActor
    func perform() async throws -> some IntentResult {
        MetronomeCommandCenter.handler?(.tempoUp)
        return .result()
    }
}

struct TempoDownIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Slower"

    @MainActor
    func perform() async throws -> some IntentResult {
        MetronomeCommandCenter.handler?(.tempoDown)
        return .result()
    }
}
