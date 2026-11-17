import Foundation

// MARK: - Box states

/// What a box does when the beat reaches it.
nonisolated enum StepState: Int, Codable, Sendable {
    case off = 0
    case regular = 1
    case accent = 2

    /// Tapping a box goes off -> click -> accent -> off.
    var next: StepState {
        switch self {
        case .off: return .regular
        case .regular: return .accent
        case .accent: return .off
        }
    }

    /// Older versions saved true/false. `true` becomes a regular click, except box 1,
    /// which always used to sound accented, so it stays accented.
    static func fromLegacy(_ bools: [Bool]) -> [StepState] {
        var result: [StepState] = []
        for (index, isOn) in bools.enumerated() {
            if !isOn {
                result.append(.off)
            } else if index == 0 {
                result.append(.accent)
            } else {
                result.append(.regular)
            }
        }
        return result
    }

    /// Reads a steps list saved either as numbers (0/1/2) or as old true/false values.
    static func decodeList<K: CodingKey>(from container: KeyedDecodingContainer<K>,
                                         forKey key: K) throws -> [StepState] {
        if let states = try? container.decode([StepState].self, forKey: key) {
            return states
        }
        return fromLegacy(try container.decode([Bool].self, forKey: key))
    }
}

// MARK: - Sounds

nonisolated struct VoiceParams {
    static let sine = 0
    static let square = 1
    static let twoSine = 2
    static let twoSquare = 3
    static let noise = 4

    var kind: Int
    var freq1: Double
    var freq2: Double = 0
    var sweepTo: Double = 0      // if > 0, pitch glides from freq1 down to this
    var duration: Double         // seconds
    var decayRate: Double        // bigger = shorter, snappier
    var gain: Float
}

nonisolated enum ClickSound: Int, CaseIterable, Identifiable, Sendable {
    case highClick = 0
    case click
    case highBeep
    case beep
    case woodblock
    case clave
    case cowbell
    case hihat
    case kick

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .highClick: return "High click"
        case .click: return "Click"
        case .highBeep: return "High beep"
        case .beep: return "Beep"
        case .woodblock: return "Woodblock"
        case .clave: return "Clave"
        case .cowbell: return "Cowbell"
        case .hihat: return "Hi-hat"
        case .kick: return "Kick"
        }
    }

    var params: VoiceParams {
        switch self {
        case .highClick:
            return VoiceParams(kind: VoiceParams.square, freq1: 1300, duration: 0.05, decayRate: 7, gain: 1.0)
        case .click:
            return VoiceParams(kind: VoiceParams.square, freq1: 950, duration: 0.05, decayRate: 7, gain: 1.0)
        case .highBeep:
            return VoiceParams(kind: VoiceParams.sine, freq1: 1320, duration: 0.09, decayRate: 5, gain: 1.2)
        case .beep:
            return VoiceParams(kind: VoiceParams.sine, freq1: 880, duration: 0.09, decayRate: 5, gain: 1.2)
        case .woodblock:
            return VoiceParams(kind: VoiceParams.twoSine, freq1: 800, freq2: 1190, duration: 0.07, decayRate: 8, gain: 1.2)
        case .clave:
            return VoiceParams(kind: VoiceParams.sine, freq1: 2500, duration: 0.08, decayRate: 10, gain: 1.2)
        case .cowbell:
            return VoiceParams(kind: VoiceParams.twoSquare, freq1: 540, freq2: 800, duration: 0.14, decayRate: 6, gain: 0.7)
        case .hihat:
            return VoiceParams(kind: VoiceParams.noise, freq1: 0, duration: 0.045, decayRate: 8, gain: 1.0)
        case .kick:
            return VoiceParams(kind: VoiceParams.sine, freq1: 150, sweepTo: 45, duration: 0.16, decayRate: 5, gain: 1.2)
        }
    }
}

// MARK: - Synth

/// Generates the sound on the real-time audio thread.
///
/// Timing is sample-accurate: the next step is counted in audio samples, so the beat
/// never drifts no matter what the UI is doing. Nothing inside `fill` allocates memory
/// or takes a lock.
nonisolated final class ClickSynth: @unchecked Sendable {
    static let maxSteps = 100
    static let minBPM = 20
    static let maxBPM = 700

    // MARK: Written by the UI, read by the audio thread
    var bpm: Double = 120
    var numSteps: Int = 8
    var running = false
    var sampleRate: Double = 48000
    var accentSound: Int = ClickSound.highClick.rawValue
    var regularSound: Int = ClickSound.click.rawValue
    /// 0 = nothing, 1 = play the regular sound once, 2 = play the accent sound once.
    var previewRequest = 0

    // MARK: Written by the audio thread, read by the UI
    private(set) var playheadStep = 0
    private(set) var triggerCount = 0
    /// 0 = off, 1 = regular, 2 = accent (the state of the box that was just reached).
    private(set) var lastState = 0

    // MARK: Audio-thread state
    private let stepsPtr: UnsafeMutablePointer<UInt8>
    private var samplesUntilNext: Double = 0
    private var step = -1

    private var vKind = 1
    private var vLeft = 0
    private var vPhase: Double = 0
    private var vPhase2: Double = 0
    private var vFreq: Double = 0
    private var vFreq2: Double = 0
    private var vSweepTo: Double = 0
    private var vSweepFactor: Double = 1
    private var vEnv: Float = 0
    private var vDecay: Float = 0.999
    private var vAmp: Float = 0.5
    private var noiseState: UInt32 = 12345
    private var prevNoise: Float = 0

    init() {
        stepsPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: ClickSynth.maxSteps)
        stepsPtr.initialize(repeating: 1, count: ClickSynth.maxSteps)
    }

    deinit {
        stepsPtr.deallocate()
    }

    /// Copies the pattern into the buffer the audio thread reads.
    func setSteps(_ values: [StepState]) {
        for i in 0..<ClickSynth.maxSteps {
            stepsPtr[i] = i < values.count ? UInt8(values[i].rawValue) : 1
        }
    }

    /// Call while `running` is false, right before starting.
    func reset() {
        samplesUntilNext = 0
        step = -1
        vLeft = 0
        vEnv = 0
    }

    /// Starts one hit of the given sound.
    private func trigger(soundID: Int, accent: Bool) {
        let sound = ClickSound(rawValue: soundID) ?? .click
        let p = sound.params
        let sr = sampleRate
        let total = max(1, Int(p.duration * sr))

        vKind = p.kind
        vFreq = p.freq1
        vFreq2 = p.freq2
        vSweepTo = p.sweepTo
        vSweepFactor = p.sweepTo > 0 ? exp(log(p.sweepTo / p.freq1) / (0.08 * sr)) : 1
        vPhase = 0
        vPhase2 = 0
        vEnv = 1
        vDecay = Float(exp(-p.decayRate / Double(total)))
        vAmp = (accent ? 0.8 : 0.5) * p.gain
        vLeft = total
    }

    private func square(_ phase: Double) -> Float {
        phase < 0.5 ? 1 : -1
    }

    /// Fills one buffer of audio. Called by the system on the audio thread.
    func fill(frames: Int,
              left: UnsafeMutablePointer<Float>,
              right: UnsafeMutablePointer<Float>?) {
        let sr = sampleRate
        let stepCount = max(1, min(numSteps, ClickSynth.maxSteps))
        let twoPi = 2.0 * Double.pi

        let preview = previewRequest
        if preview != 0 {
            previewRequest = 0
            let isAccent = (preview == 2)
            trigger(soundID: isAccent ? accentSound : regularSound, accent: isAccent)
        }

        for i in 0..<frames {
            if running {
                if samplesUntilNext <= 0 {
                    step = (step + 1) % stepCount
                    let state = Int(stepsPtr[step])

                    if state > 0 {
                        let isAccent = (state == 2)
                        trigger(soundID: isAccent ? accentSound : regularSound, accent: isAccent)
                    }

                    playheadStep = step
                    lastState = state
                    triggerCount &+= 1

                    samplesUntilNext += 60.0 / max(1.0, bpm) * sr
                }
                samplesUntilNext -= 1
            }

            var sample: Float = 0
            if vLeft > 0 {
                var s: Float
                switch vKind {
                case VoiceParams.sine:
                    s = Float(sin(vPhase * twoPi))
                case VoiceParams.square:
                    s = square(vPhase)
                case VoiceParams.twoSine:
                    s = 0.6 * Float(sin(vPhase * twoPi)) + 0.4 * Float(sin(vPhase2 * twoPi))
                case VoiceParams.twoSquare:
                    s = 0.5 * (square(vPhase) + square(vPhase2))
                default:
                    noiseState = noiseState &* 1664525 &+ 1013904223
                    let n = Float(Int32(bitPattern: noiseState)) / 2147483648
                    s = (n - prevNoise) * 0.5     // differencing the noise gives a bright, hissy tone
                    prevNoise = n
                }

                sample = s * vEnv * vAmp
                vEnv *= vDecay

                vPhase += vFreq / sr
                if vPhase >= 1 { vPhase -= 1 }
                vPhase2 += vFreq2 / sr
                if vPhase2 >= 1 { vPhase2 -= 1 }
                if vSweepTo > 0 { vFreq = max(vSweepTo, vFreq * vSweepFactor) }

                vLeft -= 1
            }

            left[i] = sample
            right?[i] = sample
        }
    }
}
