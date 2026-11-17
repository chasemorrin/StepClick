import SwiftUI

// MARK: - Theme

enum Theme {
    static let bg = Color(hex: 0x17140F)
    static let panel = Color(hex: 0x1A160F)
    static let edge = Color(hex: 0x2C261C)
    static let amber = Color(hex: 0xFF9D1C)
    static let amberSoft = Color(hex: 0xFFCF7A)
    static let off = Color(hex: 0x2B271F)
    static let offBorder = Color(hex: 0x3C362A)
    static let onIdle = Color(hex: 0x4A3C22)
    static let onBorder = Color(hex: 0x7A5C26)
    static let accentIdle = Color(hex: 0xF7D117)      // bright yellow for accented boxes
    static let accentBorder = Color(hex: 0xFFE766)
    static let accentFlash = Color(hex: 0xFFFBE0)
    static let text = Color(hex: 0xF2EAD9)
    static let dim = Color(hex: 0x9C9284)
    static let stop = Color(hex: 0xEF7A6A)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Main screen

struct ContentView: View {
    @EnvironmentObject var engine: MetronomeEngine
    @EnvironmentObject var store: PresetStore
    @State private var showPresets = false

    private var bpmBinding: Binding<Double> {
        Binding(get: { Double(engine.bpm) },
                set: { engine.bpm = Int($0.rounded()) })
    }

    /// Choosing a sound also plays it once so you can hear it.
    private var accentSoundBinding: Binding<ClickSound> {
        Binding(get: { engine.accentSound },
                set: { engine.accentSound = $0; engine.preview(accent: true) })
    }

    private var regularSoundBinding: Binding<ClickSound> {
        Binding(get: { engine.regularSound },
                set: { engine.regularSound = $0; engine.preview(accent: false) })
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Stays put at the top.
                VStack(spacing: 14) {
                    header
                    tempoCard
                    HStack(spacing: 14) {
                        boxesCard
                        playButton
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Rectangle()
                    .fill(Theme.edge)
                    .frame(height: 1)

                // Only this part scrolls.
                ScrollView {
                    VStack(spacing: 14) {
                        gridCard
                        footer
                        soundsCard
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showPresets) {
            PresetsView()
                .environmentObject(engine)
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("STEP").foregroundStyle(Theme.text)
                    Text("CLICK").foregroundStyle(Theme.amber)
                }
                .font(.system(size: 22, weight: .semibold))
                .tracking(2.5)
                Text("pattern-based metronome")
                    .font(.caption2)
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Button { showPresets = true } label: {
                HStack(spacing: 6) {
                    Text("PRESETS")
                    Text("\(store.presets.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.onIdle))
                        .foregroundStyle(Theme.amberSoft)
                }
                .font(.system(size: 11, weight: .medium))
                .tracking(1)
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x262019)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.edge))
            }
        }
    }

    private var tempoCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                label("TEMPO")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(engine.bpm)")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.amberSoft)
                    Text("BPM")
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                    Spacer()
                    nudgeButton("minus", label: "Slower") { engine.bpm -= 1 }
                    nudgeButton("plus", label: "Faster") { engine.bpm += 1 }
                }
                Slider(value: bpmBinding,
                       in: Double(MetronomeEngine.minBPM)...Double(MetronomeEngine.maxBPM),
                       step: 1)
                    .tint(Theme.amber)
            }
        }
    }

    private var boxesCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                label("BOXES")
                Text("\(engine.numSteps)")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.amberSoft)
                HStack(spacing: 8) {
                    nudgeButton("minus", label: "Fewer boxes") { engine.numSteps -= 1 }
                    nudgeButton("plus", label: "More boxes") { engine.numSteps += 1 }
                }
            }
        }
    }

    private var playButton: some View {
        Button {
            if engine.isPlaying { engine.stop() } else { engine.start() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: engine.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 22))
                Text(engine.isPlaying ? "STOP" : "PLAY")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(2)
            }
            .foregroundStyle(engine.isPlaying ? Theme.stop : Theme.amberSoft)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(engine.isPlaying ? Color(hex: 0x3A1818) : Color(hex: 0x33291A))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(engine.isPlaying ? Color(hex: 0x7A3030) : Theme.onBorder)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var gridCard: some View {
        VStack {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 8), spacing: 7) {
                ForEach(engine.steps.indices, id: \.self) { i in
                    StepBox(index: i,
                            state: engine.steps[i],
                            isPlayhead: engine.playhead == i,
                            flash: engine.flash)
                        .onTapGesture { engine.cycle(i) }
                        .accessibilityElement()
                        .accessibilityLabel("Box \(i + 1), \(StepBox.spokenName(engine.steps[i]))")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x141009)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.edge))
    }

    private var footer: some View {
        HStack {
            Text("Tap a box: off, click, accent.")
                .font(.caption2)
                .foregroundStyle(Theme.dim)
            Spacer()
            smallButton("ALL CLICKS") { engine.setAll(.regular) }
            smallButton("ALL OFF") { engine.setAll(.off) }
        }
    }

    private var soundsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                label("SOUNDS")
                soundRow(title: "Accent",
                         dot: Theme.accentIdle,
                         selection: accentSoundBinding,
                         accent: true)
                Divider().overlay(Theme.edge)
                soundRow(title: "Click",
                         dot: Theme.onBorder,
                         selection: regularSoundBinding,
                         accent: false)
            }
        }
    }

    // MARK: Helpers

    private func soundRow(title: String,
                          dot: Color,
                          selection: Binding<ClickSound>,
                          accent: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 10, height: 10)
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Picker(title, selection: selection) {
                    ForEach(ClickSound.allCases) { sound in
                        Text(sound.title).tag(sound)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(selection.wrappedValue.title)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.amberSoft)
            }
            Button {
                engine.preview(accent: accent)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 38, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x262019)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.edge))
            }
            .accessibilityLabel("Play \(title) sound")
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.edge))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .tracking(1.5)
            .foregroundStyle(Theme.dim)
    }

    private func nudgeButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x262019)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.edge))
        }
        .accessibilityLabel(label)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.edge))
        }
    }
}

// MARK: - One box in the grid

struct StepBox: View {
    let index: Int
    let state: StepState
    let isPlayhead: Bool
    let flash: FlashState?

    private var isFlashing: Bool { flash?.index == index }
    private var isAccentFlash: Bool { isFlashing && (flash?.accent ?? false) }

    static func spokenName(_ state: StepState) -> String {
        switch state {
        case .off: return "off"
        case .regular: return "click"
        case .accent: return "accent"
        }
    }

    private var fillColor: Color {
        if isFlashing {
            return isAccentFlash ? Theme.accentFlash : Theme.amber
        }
        switch state {
        case .off: return Theme.off
        case .regular: return Theme.onIdle
        case .accent: return Theme.accentIdle
        }
    }

    private var borderColor: Color {
        switch state {
        case .off: return isFlashing ? Theme.onBorder : Theme.offBorder
        case .regular: return Theme.onBorder
        case .accent: return Theme.accentBorder
        }
    }

    private var numberColor: Color {
        switch state {
        case .off: return Color.white.opacity(0.2)
        case .regular: return Color.black.opacity(0.35)
        case .accent: return Color.black.opacity(0.45)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.amberSoft, lineWidth: isPlayhead ? 2 : 0)
            )
            .overlay(alignment: .bottomTrailing) {
                Text("\(index + 1)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(numberColor)
                    .padding(.trailing, 3)
                    .padding(.bottom, 1)
            }
            .shadow(color: isFlashing ? (isAccentFlash ? Theme.accentIdle : Theme.amber).opacity(0.8) : .clear,
                    radius: isFlashing ? 8 : 0)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
    }
}

// MARK: - Presets sheet

struct PresetsView: View {
    @EnvironmentObject var engine: MetronomeEngine
    @EnvironmentObject var store: PresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Save current pattern") {
                    HStack {
                        TextField("Name this pattern…", text: $name)
                            .submitLabel(.done)
                            .onSubmit(save)
                        Button("Save", action: save)
                            .disabled(trimmedName.isEmpty)
                    }
                }

                Section("Saved patterns") {
                    if store.presets.isEmpty {
                        Text("No saved patterns yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.presets) { preset in
                        Button {
                            engine.load(preset)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .foregroundStyle(Theme.text)
                                Text("\(preset.bpm) BPM · \(preset.numSteps) boxes")
                                    .font(.caption)
                                    .foregroundStyle(Theme.dim)
                            }
                        }
                    }
                    .onDelete { store.delete(at: $0) }
                }
            }
            .navigationTitle("Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        store.save(name: trimmedName,
                   bpm: engine.bpm,
                   numSteps: engine.numSteps,
                   steps: engine.steps)
        name = ""
    }
}
