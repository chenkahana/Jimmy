import SwiftUI
import AVKit

struct CurrentPlayView: View {
    @ObservedObject private var queueViewModel = QueueViewModel.shared
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @State private var selectedEpisode: Episode?
    @State private var showingOutputPicker = false
    @State private var isDownloading = false
    
    var currentPlayingEpisode: Episode? {
        return audioPlayer.currentEpisode ?? queueViewModel.queue.first { $0.playbackPosition > 0 && !$0.played }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if let currentEpisode = currentPlayingEpisode {
                    ModernNowPlayingView(
                        episode: currentEpisode,
                        podcast: getPodcast(for: currentEpisode),
                        isPlaying: audioPlayer.isPlaying,
                        currentTime: audioPlayer.playbackPosition,
                        duration: audioPlayer.duration,
                        isDownloading: $isDownloading,
                        showingOutputPicker: $showingOutputPicker,
                        onPlayPause: {
                            if audioPlayer.currentEpisode?.id == currentEpisode.id {
                                audioPlayer.togglePlayPause()
                            } else {
                                audioPlayer.loadEpisode(currentEpisode)
                                audioPlayer.play()
                            }
                        },
                        onBackward: {
                            audioPlayer.seekBackward()
                        },
                        onForward: {
                            audioPlayer.seekForward()
                        },
                        onDownload: {
                            downloadEpisode(currentEpisode)
                        },
                        onOutputTap: {
                            showingOutputPicker = true
                        },
                        onSeek: { time in
                            audioPlayer.seek(to: time)
                        }
                    )
                } else {
                    EmptyPlayStateView()
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .sheet(item: $selectedEpisode) { episode in
                EpisodePlayerView(episode: episode)
            }
            .actionSheet(isPresented: $showingOutputPicker) {
                ActionSheet(
                    title: Text("Audio Output"),
                    buttons: [
                        .default(Text("iPhone Speaker")) { },
                        .default(Text("AirPods")) { },
                        .default(Text("Bluetooth Device")) { },
                        .cancel()
                    ]
                )
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        return PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }
    
    private func downloadEpisode(_ episode: Episode) {
        isDownloading = true
        PodcastService.shared.downloadEpisode(episode) { url in
            DispatchQueue.main.async {
                isDownloading = false
            }
        }
    }
}

struct ModernNowPlayingView: View {
    let episode: Episode
    let podcast: Podcast?
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    @Binding var isDownloading: Bool
    @Binding var showingOutputPicker: Bool
    let onPlayPause: () -> Void
    let onBackward: () -> Void
    let onForward: () -> Void
    let onDownload: () -> Void
    let onOutputTap: () -> Void
    let onSeek: (TimeInterval) -> Void
    
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    
    var progressValue: Double {
        isDragging ? dragValue : (duration > 0 ? currentTime / duration : 0)
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top spacing
                Spacer()
                    .frame(height: 60)
                
                // Episode Artwork
                VStack(spacing: 32) {
                    AsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 28)
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
                                    .font(.system(size: 64, weight: .thin))
                                    .foregroundStyle(Color(.systemGray2))
                            )
                    }
                    .frame(width: min(geometry.size.width - 80, 340), height: min(geometry.size.width - 80, 340))
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                    
                    // Episode Information
                    VStack(spacing: 12) {
                        Text(episode.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .foregroundColor(.primary)
                        
                        if let podcast = podcast {
                            Text(podcast.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // Progress and Controls Section
                VStack(spacing: 40) {
                    // Progress Slider with Time Labels
                    VStack(spacing: 12) {
                        Slider(
                            value: Binding(
                                get: { progressValue },
                                set: { newValue in
                                    dragValue = newValue
                                    if !isDragging {
                                        onSeek(newValue * duration)
                                    }
                                }
                            ),
                            in: 0...1,
                            onEditingChanged: { editing in
                                isDragging = editing
                                if !editing {
                                    onSeek(dragValue * duration)
                                }
                            }
                        )
                        .accentColor(.primary)
                        .frame(height: 6)
                        
                        HStack {
                            Text(formatTime(isDragging ? dragValue * duration : currentTime))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            
                            Spacer()
                            
                            Text("-\(formatTime(duration - (isDragging ? dragValue * duration : currentTime)))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Control Buttons
                    HStack(spacing: 44) {
                        // Download Button
                        ControlButton(
                            systemImage: isDownloading ? "arrow.down.circle.fill" : 
                                        PodcastService.shared.isEpisodeDownloaded(episode) ? "checkmark.circle.fill" : "arrow.down.circle",
                            size: .medium,
                            color: PodcastService.shared.isEpisodeDownloaded(episode) ? .green : .primary,
                            action: onDownload,
                            isDisabled: isDownloading || PodcastService.shared.isEpisodeDownloaded(episode)
                        )
                        
                        // Backward Button
                        ControlButton(
                            systemImage: "gobackward.15",
                            size: .medium,
                            action: onBackward
                        )
                        
                        // Play/Pause Button (Large)
                        ControlButton(
                            systemImage: isPlaying ? "pause.fill" : "play.fill",
                            size: .large,
                            color: .white,
                            backgroundColor: .primary,
                            action: onPlayPause
                        )
                        
                        // Forward Button
                        ControlButton(
                            systemImage: "goforward.15",
                            size: .medium,
                            action: onForward
                        )
                        
                        // Output Button
                        ControlButton(
                            systemImage: "airpods",
                            size: .medium,
                            action: onOutputTap
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 120) // Account for tab bar and mini player
            }
        }
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

struct ControlButton: View {
    let systemImage: String
    let size: ButtonSize
    var color: Color = .primary
    var backgroundColor: Color = Color(.systemGray5)
    let action: () -> Void
    var isDisabled: Bool = false
    
    enum ButtonSize {
        case medium, large
        
        var dimension: CGFloat {
            switch self {
            case .medium: return 56
            case .large: return 72
            }
        }
        
        var iconSize: Font {
            switch self {
            case .medium: return .title2
            case .large: return .title
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(backgroundColor)
                .frame(width: size.dimension, height: size.dimension)
                .overlay(
                    Image(systemName: systemImage)
                        .font(size.iconSize)
                        .fontWeight(.medium)
                        .foregroundColor(color)
                )
                .shadow(
                    color: backgroundColor == .primary ? Color.black.opacity(0.25) : Color.black.opacity(0.08),
                    radius: backgroundColor == .primary ? 8 : 4,
                    x: 0,
                    y: backgroundColor == .primary ? 4 : 2
                )
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct EmptyPlayStateView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(Color(.systemGray3))
                
                VStack(spacing: 12) {
                    Text("No Episode Playing")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Choose an episode from your queue or library to start listening")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 48)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    CurrentPlayView()
} 