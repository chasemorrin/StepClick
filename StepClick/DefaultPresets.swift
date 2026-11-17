import Foundation

/// Presets that ship inside the app and appear on first launch.
///
/// TO ADD YOURS: open your bin on jsonbin.io, copy the JSON, and paste it between the
/// triple quotes below (replace the `{}`). It's the same format the web version used:
///
///     {
///       "My pattern": { "bpm": 120, "numSteps": 8, "steps": [true, false, true, ...] },
///       "Another one": { ... }
///     }
///
/// Steps can be true/false, or numbers: 0 = off, 1 = click, 2 = accent. (With true/false,
/// box 1 becomes an accent and the other true boxes become regular clicks.)
///
/// If you change this list later, add 1 to `version` so existing installs pick up the
/// new entries (names that already exist are left alone).
enum DefaultPresets {
    static let version = 1

    static let json = """
    {
      "2-3 Clave": {
        "bpm": 320,
        "numSteps": 16,
        "steps": [
          false,
          false,
          true,
          false,
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          true,
          false,
          false,
          true,
          false
        ]
      },
      "5 Clave": {
        "bpm": 350,
        "numSteps": 20,
        "steps": [
          false,
          false,
          true,
          false,
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          true,
          false
        ]
      },
      "13 Clave": {
        "bpm": 350,
        "numSteps": 26,
        "steps": [
          false,
          false,
          true,
          false,
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          true,
          false,
          false,
          true,
          false,
          false,
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          true,
          false
        ]
      },
      "Abakua": {
        "bpm": 253,
        "numSteps": 12,
        "steps": [
          true,
          false,
          true,
          false,
          true,
          true,
          false,
          true,
          false,
          true,
          false,
          true
        ]
      },
      "7 Clave": {
        "bpm": 344,
        "numSteps": 28,
        "steps": [
          false,
          false,
          true,
          false,
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          true,
          false,
          false,
          true,
          false,
          false,
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          true,
          false,
          true,
          false
        ]
      }
    }
    """

    // MARK: Loading (no need to edit below)

    private struct Body: Decodable {
        let bpm: Int
        let numSteps: Int
        let steps: [StepState]

        enum CodingKeys: String, CodingKey {
            case bpm, numSteps, steps
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bpm = try container.decode(Int.self, forKey: .bpm)
            numSteps = try container.decode(Int.self, forKey: .numSteps)
            steps = try StepState.decodeList(from: container, forKey: .steps)
        }
    }

    static func load() -> [Preset] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Body].self, from: data) else {
            return []
        }
        return dict.map { name, body in
            let count = min(max(body.numSteps, 1), ClickSynth.maxSteps)
            var steps = Array(body.steps.prefix(count))
            while steps.count < count { steps.append(.regular) }
            return Preset(name: name,
                          bpm: min(max(body.bpm, ClickSynth.minBPM), ClickSynth.maxBPM),
                          numSteps: count,
                          steps: steps)
        }
    }
}
