//
//  ExpandedNowPlayingView.swift
//  Jimmy
//
//  The full-screen player: artwork on a flat backdrop sampled from it, the scrubber, transport in one glass
//  capsule, and speed, sleep and chapters in one bottom panel.
//

import SwiftUI
import AVKit
import JimmyKit

struct ExpandedNowPlayingView: View {
    @StateObject private var viewModel = CurrentPlayViewModel.shared
    @ObservedObject private var settings = SettingsViewModel.shared
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var skipGlyph: CGFloat = 28
    @ScaledMetric(relativeTo: .title) private var playGlyph: CGFloat = 30

    @State private var dragOffset: CGFloat = 0
    /// The artwork's color when it is legible; `nil` falls back to the system background.
    @State private var backdrop: ArtworkContrast?
    @State private var panel: Panel?
    /// The scrubber's position while it is being dragged.
    @State private var scrubPosition: TimeInterval?
    @State private var scrubsEnded = 0
    private let onClose: (() -> Void)?

    private enum Panel { case speed, sleep, chapters }
    private static let speeds: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            (backdrop?.color ?? Color(.systemBackground)).ignoresSafeArea()

            if let episode = viewModel.currentPlayingEpisode {
                player(for: episode)
                    .accessibilityHidden(panel != nil)
                    .offset(y: dragOffset)
                    .gesture(dismissGesture)
                    .task(id: artworkURL(for: episode)) {
                        guard let url = artworkURL(for: episode),
                              let color = await ArtworkColorExtractor.dominantColor(of: url) else {
                            backdrop = nil
                            return
                        }
                        backdrop = ArtworkContrast(color.resolve(in: EnvironmentValues())).usable
                    }
            } else {
                ContentUnavailableView {
                    Label("Nothing Is Playing", systemImage: "play.circle")
                } description: {
                    Text("Episodes you play appear here.")
                } actions: {
                    Button("Close", action: closePlayer)
                        .buttonStyle(.borderedProminent)
                }
            }

            if let panel {
                BottomPanel(tint: backdrop, maxHeight: 0.6, onDismiss: { show(nil) }, content: {
                    panelContent(panel)
                })
                .zIndex(1)
            }
        }
        .environment(\.colorScheme, backdrop?.colorScheme ?? colorScheme)
        .animation(.motion, value: dragOffset)
    }

    // MARK: - Player

    private func player(for episode: Episode) -> some View {
        VStack(spacing: JimmyDesign.Spacing.lg) {
            topBar(for: episode)
            artwork(for: episode)

            VStack(alignment: .leading, spacing: JimmyDesign.Spacing.xs) {
                Text(episode.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                if let show = viewModel.getPodcast(for: episode)?.title {
                    Text(show)
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            scrubber
            transport
            secondaryControls
            Spacer(minLength: 0)
        }
        .padding(.horizontal, JimmyDesign.Spacing.xl)
        .padding(.bottom, JimmyDesign.Spacing.sm)
        .foregroundStyle(.primary)
    }

    private func topBar(for episode: Episode) -> some View {
        HStack {
            Button(action: closePlayer) {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close Now Playing")

            Spacer()

            Menu {
                downloadButton(for: episode)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
        }
        .buttonStyle(.plain)
        .tint(.primary)
        .padding(.horizontal, -JimmyDesign.Spacing.md)
    }

    @ViewBuilder
    private func downloadButton(for episode: Episode) -> some View {
        switch viewModel.downloadState(for: episode) {
        case .queued, .downloading:
            Button("Cancel Download", systemImage: "xmark") { viewModel.cancelDownload(episode) }
        case .done:
            Button("Remove Download", systemImage: "trash", role: .destructive) { viewModel.deleteDownload(episode) }
        case .failed, nil:
            Button("Download", systemImage: "arrow.down.circle") { viewModel.downloadEpisode(episode) }
        }
    }

    private func artwork(for episode: Episode) -> some View {
        let podcastName = viewModel.getPodcast(for: episode)?.title ?? ""
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                BulletproofAsyncImage(url: artworkURL(for: episode)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color(.systemGray5)
                }
            }
            .clipShape(ArtworkShape())
            .shadow(color: JimmyDesign.Shadow.artworkColor, radius: JimmyDesign.Shadow.artworkRadius,
                    x: 0, y: JimmyDesign.Shadow.artworkY)
            .frame(maxWidth: 400)
            .layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(podcastName.isEmpty
                ? "Artwork for \(episode.title)"
                : "Artwork for \(episode.title) from \(podcastName)")
            .accessibilityAddTraits(.isImage)
    }

    private var scrubber: some View {
        let duration = appModel.playback?.duration ?? 0
        let position = scrubPosition ?? appModel.playback?.position ?? 0
        return VStack(spacing: JimmyDesign.Spacing.xs) {
            Slider(
                value: Binding(
                    get: { position },
                    set: { newValue in
                        if scrubPosition != nil {
                            scrubPosition = newValue
                        } else {
                            viewModel.seek(to: newValue)
                        }
                    }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        scrubPosition = position
                    } else if let target = scrubPosition {
                        viewModel.seek(to: target)
                        scrubPosition = nil
                        scrubsEnded += 1
                    }
                }
            )
            .tint(.accentColor)
            .sensoryFeedback(.selection, trigger: scrubsEnded)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(formatTime(position)) of \(formatTime(duration))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: viewModel.skipForward()
                case .decrement: viewModel.skipBackward()
                @unknown default: break
                }
            }

            HStack {
                Text(formatTime(position))
                Spacer()
                Text("\u{2212}\(formatTime(duration - position))")
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(secondaryText)
            .accessibilityHidden(true)
        }
    }

    private var transport: some View {
        let back = Int(settings.skipBackwardDuration)
        let forward = Int(settings.skipForwardDuration)
        let isPlaying = appModel.playback?.isPlaying ?? false
        return HStack(spacing: JimmyDesign.Spacing.xl) {
            Button(action: viewModel.skipBackward) {
                Image(systemName: "gobackward.\(back)")
                    .font(.system(size: min(skipGlyph, 40), weight: .semibold))
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Skip back \(back) seconds")

            Button(action: viewModel.playPauseCurrentEpisode) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: min(playGlyph, 44), weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 72, height: 72)
                    .background(Color.accentColor, in: .circle)
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button(action: viewModel.skipForward) {
                Image(systemName: "goforward.\(forward)")
                    .font(.system(size: min(skipGlyph, 40), weight: .semibold))
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Skip forward \(forward) seconds")
        }
        .buttonStyle(BounceButtonStyle())
        .padding(JimmyDesign.Spacing.sm)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var secondaryControls: some View {
        HStack {
            Button(speedText(settings.playbackSpeed)) { show(.speed) }
                .accessibilityLabel("Playback speed, \(speedText(settings.playbackSpeed))")
            Spacer()
            Button(sleepLabel) { show(.sleep) }
                .monospacedDigit()
                .accessibilityLabel(isSleepTimerActive ? "Sleep timer, \(sleepLabel)" : "Sleep timer")
            Spacer()
            Button("Chapters") { show(.chapters) }
            Spacer()
            RoutePickerViewRepresentable()
                .frame(width: 44, height: 44)
                .accessibilityLabel("AirPlay")
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    // MARK: - Panel

    @ViewBuilder
    private func panelContent(_ panel: Panel) -> some View {
        switch panel {
        case .speed:
            VStack(alignment: .leading, spacing: JimmyDesign.Spacing.lg) {
                Text("Playback Speed")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Picker("Playback Speed", selection: $settings.playbackSpeed) {
                    ForEach(Self.speeds, id: \.self) { speed in
                        Text(speedText(speed)).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(JimmyDesign.Spacing.xl)
        case .sleep:
            SleepTimerView()
                .padding(JimmyDesign.Spacing.xl)
        case .chapters:
            if let episode = viewModel.currentPlayingEpisode {
                NowPlayingChaptersPanel(episodeID: episode.id, duration: appModel.playback?.duration) { start in
                    viewModel.seek(to: start)
                }
                .id(episode.id)
            }
        }
    }

    private func show(_ newPanel: Panel?) {
        withAnimation(BottomPanelStyle.motion(reduceMotion: reduceMotion)) {
            panel = newPanel
        }
    }

    // MARK: - Gestures & Actions

    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = rubberBand(value.translation.height)
                }
            }
            .onEnded { value in
                if value.translation.height > 100 {
                    closePlayer()
                } else {
                    withAnimation(.motionGentle) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func closePlayer() {
        if let onClose {
            onClose()
        } else {
            DispatchQueue.main.async {
                dismiss()
            }
        }
    }

    // MARK: - Helpers

    /// Secondary text stays full strength on artwork color, where a translucent label could miss 4.5:1.
    private var secondaryText: HierarchicalShapeStyle {
        backdrop == nil ? .secondary : .primary
    }

    private func artworkURL(for episode: Episode) -> URL? {
        episode.artworkURL ?? viewModel.getPodcast(for: episode)?.artworkURL
    }

    private func speedText(_ speed: Double) -> String {
        "\(speed.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    private var isSleepTimerActive: Bool {
        appModel.playback?.sleepTimerMode != nil
    }

    private var sleepLabel: String {
        switch appModel.playback?.sleepTimerMode {
        case nil: return "Sleep"
        case .endOfEpisode: return SleepTimerPreset.endOfEpisode.label
        default:
            let total = Int(max(0, appModel.playback?.sleepTimerRemaining ?? 0))
            return String(format: "%d:%02d", total / 60, total % 60)
        }
    }

    private func rubberBand(_ translation: CGFloat) -> CGFloat {
        let constant: CGFloat = 0.55
        return (1.0 - (1.0 / ((translation * constant / 1000.0) + 1.0))) * 1000.0
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let time = max(0, time)
        let hours = Int(time) / 3600
        let minutes = Int(time) % 3600 / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

/// Artwork corners at 0.18 of the side, continuous.
private nonisolated struct ArtworkShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: min(rect.width, rect.height) * 0.18, style: .continuous).path(in: rect)
    }
}

struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.motion, value: configuration.isPressed)
    }
}

struct RoutePickerViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor.label
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

#Preview {
    ExpandedNowPlayingView()
}
