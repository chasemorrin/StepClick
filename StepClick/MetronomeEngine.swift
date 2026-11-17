import Combine
import AVFoundation
import SwiftUI
import UIKit

struct FlashState: Equatable {
    let index: Int
    let accent: Bool
}

enum EngineError: Error {
    case noFormat
}

/// Builds the audio node that pulls samples from the synth.
/// Declared `nonisolated` so the render closure is never tied to the main actor
/// (it runs on the real-time audio thread).
nonisolated func makeSourceNode(synth: ClickSynth, format: AVAudioFormat) -> AVAudioSourceNode {
    AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard let first = buffers.first, let leftRaw = first.mData else { return noErr }
        let left = leftRaw.assumingMemoryBound(to: Float.self)

        var right: UnsafeMutablePointer<Float>? = nil
        if buffers.count > 1, let rightRaw = buffers[1].mData {
            right = rightRaw.assumingMemoryBound(to: Float.self)
        }

        synth.fill(frames: Int(frameCount), left: left, right: right)
        return noErr
    }
}

@MainActor
final class MetronomeEngine: ObservableObject {
    /// One shared metronome, so the Live Activity buttons and the screen control the same thing.
    static let shared = MetronomeEngine()

    static let minBPM = ClickSynth.minBPM
    static let maxBPM = ClickSynth.maxBPM
    static let maxSteps = ClickSynth.maxSteps

    private static let accentSoundKey = "stepclick.accentSound"
    private static let regularSoundKey = "stepclick.regularSound"

    /// How long the audio stays ready after you pause from the Live Activity,
    /// so the play button on the Lock Screen still works.
    private static let keepAliveSeconds = 120.0

    // MARK: Pattern state

    @Published var bpm: Int = 120 {
        didSet {
            let clamped = min(max(bpm, Self.minBPM), Self.maxBPM)
            if clamped != bpm { bpm = clamped }
            synth.bpm = Double(clamped)
            scheduleActivityUpdate()
        }
    }

    @Published var numSteps: Int = 8 {
        didSet {
            let clamped = min(max(numSteps, 1), Self.maxSteps)
            if clamped != numSteps { numSteps = clamped }
            if steps.count < clamped {
                steps.append(contentsOf: Array(repeating: StepState.regular, count: clamped - steps.count))
            } else if steps.count > clamped {
                steps.removeLast(steps.count - clamped)
            }
            synth.numSteps = clamped
        }
    }

    /// Box 1 starts accented, the rest are regular clicks.
    @Published var steps: [StepState] = [.accent] + Array(repeating: StepState.regular, count: 7) {
        didSet { synth.setSteps(steps) }
    }

    // MARK: Sound choices (remembered on the device)

    @Published var accentSound: ClickSound = .highClick {
        didSet {
            synth.accentSound = accentSound.rawValue
            UserDefaults.standard.set(accentSound.rawValue, forKey: Self.accentSoundKey)
        }
    }

    @Published var regularSound: ClickSound = .click {
        didSet {
            synth.regularSound = regularSound.rawValue
            UserDefaults.standard.set(regularSound.rawValue, forKey: Self.regularSoundKey)
        }
    }

    // MARK: Playback state (what the UI shows)

    @Published private(set) var isPlaying = false
    @Published private(set) var playhead: Int? = nil
    @Published private(set) var flash: FlashState? = nil

    // MARK: Private

    private let synth = ClickSynth()
    private let engine = AVAudioEngine()
    private let liveActivity = LiveActivityController()
    private var sourceNode: AVAudioSourceNode?
    private var pollTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var activityUpdateTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var lastTrigger = 0
    private var flashUntil = Date.distantPast

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.object(forKey: Self.accentSoundKey) as? Int,
           let sound = ClickSound(rawValue: raw) {
            accentSound = sound
        }
        if let raw = defaults.object(forKey: Self.regularSoundKey) as? Int,
           let sound = ClickSound(rawValue: raw) {
            regularSound = sound
        }

        synth.bpm = Double(bpm)
        synth.numSteps = numSteps
        synth.setSteps(steps)
        synth.accentSound = accentSound.rawValue
        synth.regularSound = regularSound.rawValue
        observeAudioSession()
    }

    // MARK: Editing the pattern

    /// off -> click -> accent -> off
    func cycle(_ index: Int) {
        guard steps.indices.contains(index) else { return }
        steps[index] = steps[index].next
    }

    func setAll(_ value: StepState) {
        steps = Array(repeating: value, count: numSteps)
    }

    func load(_ preset: Preset) {
        let count = min(max(preset.numSteps, 1), Self.maxSteps)
        var newSteps = Array(preset.steps.prefix(count))
        while newSteps.count < count { newSteps.append(.regular) }
        bpm = preset.bpm
        numSteps = count
        steps = newSteps
    }

    // MARK: Commands from the Live Activity buttons

    func handle(_ command: MetronomeCommand) {
        switch command {
        case .togglePlay:
            if isPlaying { stop() } else { start() }
        case .tempoUp:
            bpm += 5
        case .tempoDown:
            bpm -= 5
        }
    }

    // MARK: Transport

    func start() {
        guard !isPlaying else { return }
        previewTask?.cancel()
        previewTask = nil
        keepAliveTask?.cancel()
        keepAliveTask = nil
        do {
            try configureAudio()
            if !engine.isRunning { try engine.start() }
        } catch {
            print("StepClick: could not start audio: \(error)")
            return
        }

        synth.reset()
        synth.running = true
        lastTrigger = synth.triggerCount
        isPlaying = true
        UIApplication.shared.isIdleTimerDisabled = true   // keep the screen on while playing
        liveActivity.start(state: activityState)

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    func stop() {
        guard isPlaying else { return }
        synth.running = false
        pollTask?.cancel()
        pollTask = nil
        UIApplication.shared.isIdleTimerDisabled = false

        isPlaying = false
        playhead = nil
        flash = nil

        if liveActivity.isActive {
            // Show "paused" with a play button, and keep the audio ready for a couple
            // of minutes so that button still works from the Lock Screen.
            liveActivity.update(state: activityState)
            keepAliveTask?.cancel()
            keepAliveTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.keepAliveSeconds))
                guard !Task.isCancelled, let self, !self.isPlaying else { return }
                self.shutdownAudio(endActivity: true)
            }
        } else {
            shutdownAudio(endActivity: false)
        }
    }

    private func shutdownAudio(endActivity: Bool) {
        engine.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if endActivity { liveActivity.end() }
    }

    /// Plays one hit of the accent or regular sound so you can hear your choice.
    func preview(accent: Bool) {
        do {
            try configureAudio()
            if !engine.isRunning { try engine.start() }
        } catch {
            print("StepClick: could not preview: \(error)")
            return
        }
        synth.previewRequest = accent ? 2 : 1

        previewTask?.cancel()
        guard !isPlaying, !liveActivity.isActive else { return }
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled, let self, !self.isPlaying, !self.liveActivity.isActive else { return }
            self.shutdownAudio(endActivity: false)
        }
    }

    // MARK: Live Activity

    private var activityState: MetronomeActivityAttributes.ContentState {
        MetronomeActivityAttributes.ContentState(bpm: bpm, isPlaying: isPlaying)
    }

    /// Tempo changes can come in fast (dragging the slider), so send them in batches.
    private func scheduleActivityUpdate() {
        guard liveActivity.isActive else { return }
        activityUpdateTask?.cancel()
        activityUpdateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.liveActivity.update(state: self.activityState)
        }
    }

    // MARK: Audio setup

    private func configureAudio() throws {
        let session = AVAudioSession.sharedInstance()
        // .playback keeps playing when the phone locks; .mixWithOthers lets you play along
        // with music from another app instead of stopping it.
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        guard sourceNode == nil else { return }

        var sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if sampleRate <= 0 { sampleRate = 48000 }
        synth.sampleRate = sampleRate

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw EngineError.noFormat
        }
        let node = makeSourceNode(synth: synth, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default

        // A phone call, Siri, an alarm, etc. grabs the audio: stop cleanly.
        center.addObserver(forName: AVAudioSession.interruptionNotification,
                           object: nil, queue: .main) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                if typeRaw == AVAudioSession.InterruptionType.began.rawValue {
                    self?.stop()
                }
            }
        }

        // Headphones plugged in or out, Bluetooth connected, etc.
        center.addObserver(forName: .AVAudioEngineConfigurationChange,
                           object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, !self.engine.isRunning else { return }
                try? self.engine.start()
            }
        }
    }

    // MARK: Visual playhead

    /// Runs ~120 times a second while playing and mirrors what the audio thread is doing.
    private func poll() {
        let count = synth.triggerCount
        if count != lastTrigger {
            lastTrigger = count
            playhead = synth.playheadStep
            let state = synth.lastState
            if state > 0 {
                flash = FlashState(index: synth.playheadStep, accent: state == 2)
                // At very fast tempos keep the flash shorter than the gap between beats.
                let beat = 60.0 / Double(max(1, bpm))
                flashUntil = Date().addingTimeInterval(min(0.09, beat * 0.6))
            }
        }
        if flash != nil && Date() > flashUntil {
            flash = nil
        }
    }
}
