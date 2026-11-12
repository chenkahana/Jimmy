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

/// Sheet for configuring the sleep timer with preset durations
struct SleepTimerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    private var isActive: Bool { appModel.playback?.sleepTimerMode != nil }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if isActive {
                    activeTimerView
                } else {
                    presetSelectionView
                }
            }
            .padding()
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Active Timer View

    private var activeTimerView: some View {
        VStack(spacing: 24) {
            Spacer()

            // An end-of-episode timer has no end date to count down to, so it shows its own label
            // instead of "--:--".
            if appModel.playback?.sleepTimerMode == .endOfEpisode {
                Text(SleepTimerPreset.endOfEpisode.label)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.primary)
            } else {
                Text(formattedRemaining)
                    .font(.system(size: 64, weight: .thin))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button(action: { appModel.playback?.extendSleepTimer(by: 5 * 60) }) {
                    Label("+5 min", systemImage: "plus.circle")
                        .font(.system(.subheadline, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add 5 minutes")
                .accessibilityHint("Extends the sleep timer by 5 minutes")

                Button(action: { appModel.playback?.extendSleepTimer(by: 15 * 60) }) {
                    Label("+15 min", systemImage: "plus.circle")
                        .font(.system(.subheadline, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add 15 minutes")
                .accessibilityHint("Extends the sleep timer by 15 minutes")
            }

            Button(role: .destructive, action: {
                appModel.playback?.cancelSleepTimer()
                dismiss()
            }) {
                Text("Cancel Timer")
                    .font(.system(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Preset Selection

    private var presetSelectionView: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SleepTimerPreset.allCases) { preset in
                    Button(action: {
                        appModel.playback?.startSleepTimer(preset.mode)
                    }) {
                        Text(preset.label)
                            .font(.system(.body, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set sleep timer to \(preset.label)")
                    .accessibilityHint("Double tap to start a \(preset.label) sleep timer")
                }
            }
        }
    }

    private var formattedRemaining: String {
        guard let remaining = appModel.playback?.sleepTimerRemaining else { return "--:--" }
        let total = Int(max(0, remaining))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
