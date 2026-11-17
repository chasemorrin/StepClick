import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Lock Screen banner and Dynamic Island layouts. Widget extension target only.

private enum LAColor {
    static let background = Color(red: 0.09, green: 0.078, blue: 0.059)
    static let amber = Color(red: 1.0, green: 0.616, blue: 0.11)
    static let amberSoft = Color(red: 1.0, green: 0.81, blue: 0.478)
    static let button = Color.white.opacity(0.12)
}

struct MetronomeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MetronomeActivityAttributes.self) { context in
            // Lock Screen / banner
            LockScreenView(state: context.state)
                .activityBackgroundTint(LAColor.background)
                .activitySystemActionForegroundColor(LAColor.amber)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(context.state.bpm)")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(LAColor.amberSoft)
                        Text(context.state.isPlaying ? "BPM · playing" : "BPM · paused")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PlayPauseButton(isPlaying: context.state.isPlaying)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        TempoButton(intent: TempoDownIntent(), title: "−5")
                        TempoButton(intent: TempoUpIntent(), title: "+5")
                    }
                }
            } compactLeading: {
                Image(systemName: "metronome.fill")
                    .foregroundStyle(LAColor.amber)
            } compactTrailing: {
                Text("\(context.state.bpm)")
                    .monospacedDigit()
                    .foregroundStyle(LAColor.amberSoft)
            } minimal: {
                Image(systemName: "metronome.fill")
                    .foregroundStyle(LAColor.amber)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: MetronomeActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "metronome.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(LAColor.amber)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(state.bpm)")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(LAColor.amberSoft)
                        Text("BPM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(state.isPlaying ? "StepClick · playing" : "StepClick · paused")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                PlayPauseButton(isPlaying: state.isPlaying)
            }
            HStack(spacing: 10) {
                TempoButton(intent: TempoDownIntent(), title: "−5")
                TempoButton(intent: TempoUpIntent(), title: "+5")
            }
        }
        .padding(16)
    }
}

private struct PlayPauseButton: View {
    let isPlaying: Bool

    var body: some View {
        Button(intent: TogglePlayIntent()) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(width: 46, height: 46)
                .background(Circle().fill(LAColor.amber))
        }
        .buttonStyle(.plain)
    }
}

private struct TempoButton<I: AppIntent>: View {
    let intent: I
    let title: String

    var body: some View {
        Button(intent: intent) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LAColor.amberSoft)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(LAColor.button))
        }
        .buttonStyle(.plain)
    }
}
