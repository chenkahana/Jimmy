import SwiftUI
import JimmyKit

/// A preset duration (or end-of-episode) the sleep timer can be started with — purely a UI
/// label; `startSleepTimer` is called with the `SleepTimerMode` it maps to.
enum SleepTimerPreset: String, CaseIterable, Identifiable {
    case minutes5, minutes15, minutes30, minutes45, minutes60, endOfEpisode

    var id: String { label }

    var label: String {
        switch self {
        case .minutes5: return "5 min"
        case .minutes15: return "15 min"
        case .minutes30: return "30 min"
        case .minutes45: return "45 min"
        case .minutes60: return "60 min"
        case .endOfEpisode: return "End of Episode"
        }
    }

    var mode: SleepTimerMode {
        switch self {
        case .minutes5: return .duration(5 * 60)
        case .minutes15: return .duration(15 * 60)
        case .minutes30: return .duration(30 * 60)
        case .minutes45: return .duration(45 * 60)
        case .minutes60: return .duration(60 * 60)
        case .endOfEpisode: return .endOfEpisode
        }
    }
}

/// Now Playing's sleep timer panel: presets, or the running timer with extend and cancel.
struct SleepTimerView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: JimmyDesign.Spacing.lg) {
            Text("Sleep Timer")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if let mode = appModel.playback?.sleepTimerMode {
                // An end-of-episode timer has no end date to count down to, so it shows its own label.
                Text(mode == .endOfEpisode ? SleepTimerPreset.endOfEpisode.label : formattedRemaining)
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()

                HStack(spacing: JimmyDesign.Spacing.md) {
                    Button("+5 min") { appModel.playback?.extendSleepTimer(by: 5 * 60) }
                        .accessibilityLabel("Add 5 minutes")
                    Button("+15 min") { appModel.playback?.extendSleepTimer(by: 15 * 60) }
                        .accessibilityLabel("Add 15 minutes")
                    Spacer()
                    Button("Cancel Timer", role: .destructive) { appModel.playback?.cancelSleepTimer() }
                }
                .buttonStyle(.bordered)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: JimmyDesign.Spacing.md) {
                    ForEach(SleepTimerPreset.allCases) { preset in
                        Button {
                            appModel.playback?.startSleepTimer(preset.mode)
                        } label: {
                            Text(preset.label)
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .accessibilityLabel("Set sleep timer to \(preset.label)")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .tint(.primary)
    }

    private var formattedRemaining: String {
        guard let remaining = appModel.playback?.sleepTimerRemaining else { return "--:--" }
        let total = Int(max(0, remaining))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
