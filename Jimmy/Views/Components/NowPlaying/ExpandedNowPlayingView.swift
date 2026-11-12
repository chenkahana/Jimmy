//
//  ExpandedNowPlayingView.swift
//  Jimmy
//
//  Full-screen now playing experience with matched geometry morphing
//

import SwiftUI
import AVKit
import JimmyKit

struct ExpandedNowPlayingView: View {
    @StateObject private var viewModel = CurrentPlayViewModel.shared
    @Environment(AppModel.self) private var appModel
    @Environment(\.nowPlayingNamespace) private var namespace
    @Environment(\.dismiss) private var dismiss

    @State private var dragOffset: CGFloat = 0
    @State private var showingSleepTimer = false
    @State private var playPulse = false
    @StateObject private var colorExtractor = ArtworkColorExtractor.shared
    private let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            let topInset = max(geometry.safeAreaInsets.top, 52)
            let bottomInset = max(geometry.safeAreaInsets.bottom, 20)
            let horizontalPadding = min(max(screenWidth * 0.06, JimmyDesign.Spacing.lg), JimmyDesign.Spacing.xl)

            ZStack {
                Color.black.ignoresSafeArea()
                backgroundView

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.22),
                        Color.black.opacity(backdropOpacity + 0.56)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if let currentEpisode = viewModel.currentPlayingEpisode {
                    VStack(spacing: 0) {
                        topBar(topInset: topInset)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: JimmyDesign.Spacing.lg) {
                                artworkView(
                                    for: currentEpisode,
                                    availableWidth: screenWidth - (horizontalPadding * 2)
                                )
                                metadataView(for: currentEpisode)
                                progressCard
                                transportControlsCard
                                secondaryControlsCard
                                episodeDetailsCard(for: currentEpisode)
                            }
                            .frame(width: max(screenWidth - (horizontalPadding * 2), 0), alignment: .center)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, JimmyDesign.Spacing.md)
                            .padding(.bottom, max(bottomInset, JimmyDesign.Spacing.lg) + JimmyDesign.Spacing.xl)
                        }
                    }
                    .frame(width: screenWidth, height: screenHeight, alignment: .top)
                    .offset(y: dragOffset)
                    .gesture(dismissGesture)
                    .onAppear {
                        colorExtractor.extractColors(from: currentEpisode.artworkURL ?? viewModel.getPodcast(for: currentEpisode)?.artworkURL)
                        playPulse = appModel.playback?.isPlaying ?? false
                    }
                } else {
                    VStack(spacing: JimmyDesign.Spacing.lg) {
                        topBar(topInset: topInset)

                        Spacer()

                        JimmyCard {
                            VStack(spacing: JimmyDesign.Spacing.md) {
                                Image(systemName: "waveform.circle")
                                    .font(.system(size: 46, weight: .light))
                                    .foregroundStyle(.secondary)

                                Text("Nothing Is Playing")
                                    .font(.title3.weight(.semibold))

                                Text("Start an episode from Queue, Library, or Discover and the full player will appear here.")
                                    .font(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)

                                Button("Close") {
                                    closePlayer()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, horizontalPadding)

                        Spacer()
                    }
                    .frame(width: screenWidth, height: screenHeight, alignment: .top)
                }
            }
            .frame(width: screenWidth, height: screenHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.motion, value: dragOffset)
    }

    // MARK: - Subviews

    private var backgroundView: some View {
        Group {
            if let currentEpisode = viewModel.currentPlayingEpisode {
                BulletproofAsyncImage(url: currentEpisode.artworkURL ?? viewModel.getPodcast(for: currentEpisode)?.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 72)
                        .overlay(Color.black.opacity(0.52))
                } placeholder: {
                    Color.black
                }
                .ignoresSafeArea()
                .overlay(colorExtractor.dominantColor.opacity(0.12).ignoresSafeArea())
            } else {
                Color.black.ignoresSafeArea()
            }
        }
    }

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.28))
            .frame(width: 36, height: 5)
            .padding(.bottom, 8)
            .accessibilityLabel("Drag to dismiss")
            .accessibilityHint("Swipe down to close the player")
            .accessibilityAddTraits(.isButton)
    }

    private func topBar(topInset: CGFloat) -> some View {
        VStack(spacing: JimmyDesign.Spacing.sm) {
            dragIndicator
                .padding(.top, max(topInset, JimmyDesign.Spacing.sm))

            HStack {
                Button(action: dismissWithAnimation) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close now playing")

                Spacer()

                Text("NOW PLAYING")
                    .font(JimmyDesign.Typography.caption)
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.72))

                Spacer()

                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, JimmyDesign.Spacing.lg)
        }
    }

    private func artworkView(for episode: Episode, availableWidth: CGFloat) -> some View {
        let podcastName = viewModel.getPodcast(for: episode)?.title ?? ""
        let artworkLabel = podcastName.isEmpty
            ? "Artwork for \(episode.title)"
            : "Artwork for \(episode.title) from \(podcastName)"
        let artworkSize = min(max(availableWidth, 0), 320.0)

        return BulletproofAsyncImage(url: episode.artworkURL ?? viewModel.getPodcast(for: episode)?.artworkURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            artworkPlaceholder
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: JimmyDesign.Radius.xl))
        .shadow(color: JimmyDesign.Shadow.elevatedColor, radius: JimmyDesign.Shadow.elevatedRadius, x: 0, y: JimmyDesign.Shadow.elevatedY)
        .accessibilityLabel(artworkLabel)
        .accessibilityAddTraits(.isImage)
        .if(namespace != nil) { view in
            view.matchedGeometryEffect(id: NowPlayingGeometryID.artwork, in: namespace!)
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: JimmyDesign.Radius.xl)
            .fill(
                LinearGradient(
                    colors: [
                        Color(.systemGray5),
                        Color(.systemGray4)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80, weight: .thin))
                    .foregroundStyle(Color(.systemGray2))
            )
    }

    private func metadataView(for episode: Episode) -> some View {
        VStack(spacing: JimmyDesign.Spacing.sm) {
            Text(episode.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .if(namespace != nil) { view in
                    view.matchedGeometryEffect(id: NowPlayingGeometryID.title, in: namespace!)
                }

            if let podcast = viewModel.getPodcast(for: episode) {
                Text(podcast.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .if(namespace != nil) { view in
                        view.matchedGeometryEffect(id: NowPlayingGeometryID.subtitle, in: namespace!)
                    }
            }

            Label(viewModel.currentOutputDevice.displayName, systemImage: viewModel.currentOutputDevice.icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.horizontal, JimmyDesign.Spacing.md)
                .padding(.vertical, JimmyDesign.Spacing.xs + 2)
                .background(.thinMaterial, in: Capsule())
        }
        .frame(maxWidth: .infinity)
    }

    private var progressCard: some View {
        JimmyCard {
            progressSliderView
        }
        .frame(maxWidth: .infinity)
    }

    private var transportControlsCard: some View {
        JimmyCard {
            HStack(spacing: 48) {
                Button(action: {
                    viewModel.skipBackward()
                    Motion.lightHaptic()
                }) {
                    Image(systemName: "gobackward.\(Int(SettingsViewModel.shared.skipBackwardDuration))")
                        .font(.title2.weight(.semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip back \(Int(SettingsViewModel.shared.skipBackwardDuration)) seconds")
                .accessibilityHint("Double tap to rewind")

                Button(action: {
                    viewModel.playPauseCurrentEpisode()
                    Motion.mediumHaptic()
                }) {
                    ZStack {
                        if appModel.playback?.isPlaying ?? false {
                            Circle()
                                .stroke(Color.accentColor.opacity(playPulse ? 0 : 0.6), lineWidth: 3)
                                .frame(width: playPulse ? 94 : 70, height: playPulse ? 94 : 70)
                                .animation(
                                    .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                                    value: playPulse
                                )
                        }

                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Image(systemName: (appModel.playback?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                                    .font(.title2.weight(.bold))
                                    .foregroundColor(.white)
                                    .contentTransition(.symbolEffect(.replace.downUp))
                            )
                            .shadow(color: .accentColor.opacity(0.4), radius: 12, x: 0, y: 6)
                    }
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityLabel((appModel.playback?.isPlaying ?? false) ? "Pause" : "Play")
                .accessibilityHint("Double tap to \((appModel.playback?.isPlaying ?? false) ? "pause" : "play") the episode")
                .onChange(of: appModel.playback?.isPlaying) { _, playing in
                    playPulse = playing ?? false
                }

                Button(action: {
                    viewModel.skipForward()
                    Motion.lightHaptic()
                }) {
                    Image(systemName: "goforward.\(Int(SettingsViewModel.shared.skipForwardDuration))")
                        .font(.title2.weight(.semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip forward \(Int(SettingsViewModel.shared.skipForwardDuration)) seconds")
                .accessibilityHint("Double tap to skip ahead")
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    private var currentEpisodeDownloadState: JimmyKit.DownloadState? {
        guard let episode = viewModel.currentPlayingEpisode else { return nil }
        return viewModel.downloadState(for: episode)
    }

    private var secondaryControlsCard: some View {
        JimmyCard {
            HStack(spacing: JimmyDesign.Spacing.xl) {
                Button(action: {
                    guard let episode = viewModel.currentPlayingEpisode else { return }
                    switch currentEpisodeDownloadState {
                    case .queued, .downloading:
                        viewModel.cancelDownload(episode)
                    case .done:
                        viewModel.deleteDownload(episode)
                    case .failed, nil:
                        viewModel.downloadEpisode(episode)
                    }
                }) {
                    Image(systemName: {
                        switch currentEpisodeDownloadState {
                        case .queued, .downloading: return "arrow.down.circle.fill"
                        case .done: return "checkmark.circle.fill"
                        case .failed, nil: return "arrow.down.circle"
                        }
                    }())
                    .font(.title3)
                    .foregroundColor(currentEpisodeDownloadState == .done ? .green : .primary)
                    .contentTransition(.symbolEffect(.replace.downUp))
                }
                .buttonStyle(.plain)
                .accessibilityLabel({
                    switch currentEpisodeDownloadState {
                    case .queued, .downloading: return "Cancel download"
                    case .done: return "Remove download"
                    case .failed, nil: return "Download episode"
                    }
                }())

                Button(action: { showingSleepTimer = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: isSleepTimerActive ? "moon.zzz.fill" : "moon.zzz")
                            .font(.title3)
                        if isSleepTimerActive {
                            Text(formattedSleepTimerRemaining)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary)
                .accessibilityLabel(isSleepTimerActive ? "Sleep timer active, \(formattedSleepTimerRemaining) remaining" : "Sleep timer")
                .accessibilityHint("Double tap to configure sleep timer")

                RoutePickerViewRepresentable()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("AirPlay")
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingSleepTimer) {
            SleepTimerView()
                .presentationDetents([.medium])
        }
    }

    private var progressSliderView: some View {
        let position = appModel.playback?.position ?? 0
        let duration = appModel.playback?.duration ?? 0
        return VStack(spacing: JimmyDesign.Spacing.sm) {
            Slider(
                value: Binding(
                    get: { position },
                    set: { newValue in
                        viewModel.seek(to: newValue)
                    }
                ),
                in: 0...max(duration, 1)
            )
            .frame(height: 44)
            .tint(.accentColor)
            .accessibilityLabel("Playback progress")
            .accessibilityValue("\(formatTime(position)) of \(formatTime(duration))")
            .accessibilityHint("Drag to seek")

            HStack {
                Text(formatTime(position))
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Spacer()

                Text("-\(formatTime(duration - position))")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .if(namespace != nil) { view in
            view.matchedGeometryEffect(id: NowPlayingGeometryID.progress, in: namespace!)
        }
    }

    private var isSleepTimerActive: Bool {
        appModel.playback?.sleepTimerMode != nil
    }

    private var formattedSleepTimerRemaining: String {
        guard let remaining = appModel.playback?.sleepTimerRemaining else { return "" }
        let total = Int(max(0, remaining))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func episodeDetailsCard(for episode: Episode) -> some View {
        JimmyCard {
            VStack(alignment: .leading, spacing: JimmyDesign.Spacing.sm) {
                Text("Episode Details")
                    .font(.headline.weight(.semibold))

                if let description = episode.description, !description.cleanedDescription.isEmpty {
                    Text(description.cleanedDescription)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No description available for this episode yet.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
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
                    dismissWithAnimation()
                } else {
                    withAnimation(.motionGentle) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func dismissWithAnimation() {
        Motion.mediumHaptic()
        closePlayer()
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

    private var backdropOpacity: Double {
        let maxOpacity = 0.3
        let dragProgress = min(1.0, dragOffset / 200.0)
        return maxOpacity * (1.0 - dragProgress)
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

struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.45), value: configuration.isPressed)
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
