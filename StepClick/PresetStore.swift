import Combine
import Foundation
import SwiftUI

struct Preset: Codable, Identifiable, Equatable {
    var name: String
    var bpm: Int
    var numSteps: Int
    var steps: [StepState]

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, bpm, numSteps, steps
    }

    init(name: String, bpm: Int, numSteps: Int, steps: [StepState]) {
        self.name = name
        self.bpm = bpm
        self.numSteps = numSteps
        self.steps = steps
    }

    /// Also reads presets saved by the first version, which stored steps as true/false.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        bpm = try container.decode(Int.self, forKey: .bpm)
        numSteps = try container.decode(Int.self, forKey: .numSteps)
        steps = try StepState.decodeList(from: container, forKey: .steps)
    }
}

/// Saves presets on the device itself (UserDefaults), so every person who installs
/// the app has their own list. Nothing is sent over the network.
@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [Preset] = []

    private let presetsKey = "stepclick.presets.v1"
    private let defaultsVersionKey = "stepclick.defaultsVersion"

    init() {
        load()
        mergeNewDefaults()
    }

    func save(name: String, bpm: Int, numSteps: Int, steps: [StepState]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = Preset(name: trimmed, bpm: bpm, numSteps: numSteps, steps: steps)
        if let index = presets.firstIndex(where: { $0.name == trimmed }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        sortAndPersist()
    }

    func delete(at offsets: IndexSet) {
        presets.remove(atOffsets: offsets)
        persist()
    }

    // MARK: Storage

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let decoded = try? JSONDecoder().decode([Preset].self, from: data) else { return }
        presets = decoded
        sortPresets()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: presetsKey)
    }

    private func sortPresets() {
        presets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func sortAndPersist() {
        sortPresets()
        persist()
    }

    /// Adds the built-in presets from DefaultPresets.swift.
    /// Runs again only when `DefaultPresets.version` is increased, and only adds names
    /// that aren't already in the list, so presets you deleted stay deleted.
    private func mergeNewDefaults() {
        let seenVersion = UserDefaults.standard.integer(forKey: defaultsVersionKey)
        guard seenVersion < DefaultPresets.version else { return }

        for preset in DefaultPresets.load() where !presets.contains(where: { $0.name == preset.name }) {
            presets.append(preset)
        }
        sortAndPersist()
        UserDefaults.standard.set(DefaultPresets.version, forKey: defaultsVersionKey)
    }
}
