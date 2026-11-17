import SwiftUI

@main
struct StepClickApp: App {
    @StateObject private var engine = MetronomeEngine.shared
    @StateObject private var store = PresetStore()

    init() {
        // Lets the Live Activity buttons control the metronome,
        // even when the app is in the background.
        MetronomeCommandCenter.handler = { command in
            MetronomeEngine.shared.handle(command)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .environmentObject(store)
        }
    }
}
