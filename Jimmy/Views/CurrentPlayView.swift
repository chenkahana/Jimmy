import SwiftUI
import AVKit

struct CurrentPlayView: View {
    @ObservedObject private var queueViewModel = QueueViewModel.shared
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
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
                    .frame(height: 40)
                
                // Episode Artwork - Made larger and more prominent
                AsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 24)
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
                                .font(.system(size: 72, weight: .thin))
                                .foregroundStyle(Color(.systemGray2))
                        )
                }
                .frame(width: min(geometry.size.width - 60, 280), height: min(geometry.size.width - 60, 280))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.2), radius: 25, x: 0, y: 12)
                
                Spacer()
                    .frame(height: 40)
                
                // Control Buttons Section - Matches your mockup layout
                VStack(spacing: 32) {
                    // Main control row with 5 buttons as shown in mockup
                    HStack(spacing: 0) {
                        // Download episode button (left)
                        Spacer()
                        ControlButton(
                            systemImage: isDownloading ? "arrow.down.circle.fill" : 
                                        PodcastService.shared.isEpisodeDownloaded(episode) ? "checkmark.circle.fill" : "arrow.down.circle",
                            size: .small,
                            color: PodcastService.shared.isEpisodeDownloaded(episode) ? .green : .primary,
                            action: onDownload,
                            isDisabled: isDownloading || PodcastService.shared.isEpisodeDownloaded(episode)
                        )
                        
                        Spacer()
                        
                        // Move backward button
                        ControlButton(
                            systemImage: "gobackward.15",
                            size: .small,
                            action: onBackward
                        )
                        
                        Spacer()
                        
                        // Play/Pause Button (Large center button)
                        ControlButton(
                            systemImage: isPlaying ? "pause.fill" : "play.fill",
                            size: .large,
                            color: .white,
                            backgroundColor: .primary,
                            action: onPlayPause
                        )
                        
                        Spacer()
                        
                        // Move forward button
                        ControlButton(
                            systemImage: "goforward.15",
                            size: .small,
                            action: onForward
                        )
                        
                        Spacer()
                        
                        // Choose output (airpods/speaker) button (right)
                        ControlButton(
                            systemImage: "airpods",
                            size: .small,
                            action: onOutputTap
                        )
                        
                        Spacer()
                    }
                    
                    // Progress Slider (below controls as in your design)
                    VStack(spacing: 8) {
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
                    .padding(.horizontal, 40)
                }
                .padding(.horizontal, 20)
                
                Spacer()
                    .frame(height: 30)
                
                // Episode Details Section - As shown in your mockup
                EpisodeDetailsSection(episode: episode, podcast: podcast)
                
                Spacer()
                    .frame(height: 20)
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

struct EpisodeDetailsSection: View {
    let episode: Episode
    let podcast: Podcast?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Episode Details")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            
            // Details container
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
                .frame(height: 120)
                .overlay(
                    VStack(spacing: 12) {
                        // Episode title
                        HStack {
                            Text(episode.title.cleanedEpisodeTitle)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        
                        // Podcast name
                        if let podcast = podcast {
                            HStack {
                                Text("From: \(podcast.title)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        
                        // Episode description preview
                        if let description = episode.description {
                            HStack {
                                Text(description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                )
                .padding(.horizontal, 24)
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
        case small, large
        
        var dimension: CGFloat {
            switch self {
            case .small: return 48
            case .large: return 72
            }
        }
        
        var iconSize: Font {
            switch self {
            case .small: return .title3
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