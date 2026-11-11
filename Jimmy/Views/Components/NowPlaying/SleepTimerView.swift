import SwiftUI

/// Sheet for configuring the sleep timer with preset durations
struct SleepTimerView: View {
    @ObservedObject private var sleepTimer = SleepTimerService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if sleepTimer.isActive {
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

            // Countdown display
            Text(sleepTimer.formattedRemaining)
                .font(.system(size: 64, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)

            if let preset = sleepTimer.selectedPreset {
                Text(preset.label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button(action: { sleepTimer.extend(by: 5 * 60) }) {
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

                Button(action: { sleepTimer.extend(by: 15 * 60) }) {
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
                sleepTimer.cancel()
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
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)

            Text("Fall asleep to your podcasts")
                .font(.subheadline)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SleepTimerService.SleepTimerPreset.allCases) { preset in
                    Button(action: {
                        sleepTimer.start(preset: preset)
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
}
