import SwiftUI

// Enhanced floating mini player with 3D design that floats above tab bar
struct FloatingMiniPlayerView: View {
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    let onTap: () -> Void
    
    var body: some View {
        if let currentEpisode = audioPlayer.currentEpisode {
            VStack(spacing: 0) {
                // Floating card with enhanced 3D styling
                HStack(spacing: 16) {
                    // Episode artwork with enhanced 3D effects
                    AsyncImage(url: currentEpisode.artworkURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.orange.opacity(0.6), 
                                        Color.orange.opacity(0.4),
                                        Color.orange.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Image(systemName: "waveform.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.title2)
                                    .shadow(color: .orange.opacity(0.5), radius: 4, x: 0, y: 2)
                            )
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    // Multiple shadow layers for depth
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.1),
                                        Color.clear,
                                        Color.black.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    
                    // Episode info with enhanced styling
                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentEpisode.title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0.5)
                        
                        if let podcast = getPodcast(for: currentEpisode) {
                            Text(podcast.title)
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        // Animated progress bar with glow
                        HStack(spacing: 8) {
                            Text(formatTime(audioPlayer.playbackPosition))
                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                                .foregroundColor(.orange)
                                .shadow(color: .orange.opacity(0.4), radius: 2, x: 0, y: 1)
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background track
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(.systemGray5))
                                        .frame(height: 4)
                                    
                                    // Progress fill with enhanced glow
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.orange.opacity(0.9),
                                                    Color.orange,
                                                    Color.orange.opacity(0.8)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(
                                            width: geometry.size.width * (audioPlayer.playbackPosition / max(audioPlayer.duration, 1)), 
                                            height: 4
                                        )
                                        .shadow(color: .orange.opacity(0.6), radius: 4, x: 0, y: 0)
                                        .shadow(color: .orange.opacity(0.3), radius: 2, x: 0, y: 0)
                                }
                            }
                            .frame(height: 4)
                            
                            Text(formatTime(audioPlayer.duration))
                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Enhanced 3D control buttons
                    HStack(spacing: 14) {
                        // Backward button with enhanced 3D styling
                        Button(action: {
                            audioPlayer.seekBackward()
                        }) {
                            ZStack {
                                // Shadow layer
                                Circle()
                                    .fill(Color.black.opacity(0.2))
                                    .frame(width: 42, height: 42)
                                    .blur(radius: 6)
                                    .offset(y: 3)
                                
                                // Main button
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(.systemGray6),
                                                Color(.systemGray5),
                                                Color(.systemGray4),
                                                Color(.systemGray5)
                                            ],
                                            startPoint: UnitPoint(x: 0.3, y: 0.3),
                                            endPoint: UnitPoint(x: 0.7, y: 0.7)
                                        )
                                    )
                                    .frame(width: 38, height: 38)
                                
                                // Inner highlight
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.white.opacity(0.1),
                                                Color.clear,
                                                Color.black.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                                    .frame(width: 38, height: 38)
                                
                                Image(systemName: "gobackward.15")
                                    .font(.system(.caption, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 0.5)
                            }
                        }
                        .buttonStyle(FloatingButton3DStyle())
                        
                        // Play/pause button with premium 3D styling
                        Button(action: {
                            audioPlayer.togglePlayPause()
                        }) {
                            ZStack {
                                // Multiple shadow layers for depth
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                                    .frame(width: 52, height: 52)
                                    .blur(radius: 8)
                                    .offset(y: 4)
                                
                                // Main button with gradient
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.orange.opacity(0.95),
                                                Color.orange,
                                                Color.orange.opacity(0.85),
                                                Color.orange.opacity(0.9)
                                            ],
                                            startPoint: UnitPoint(x: 0.3, y: 0.3),
                                            endPoint: UnitPoint(x: 0.7, y: 0.7)
                                        )
                                    )
                                    .frame(width: 48, height: 48)
                                
                                // Inner highlight for 3D effect
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.5),
                                                Color.white.opacity(0.2),
                                                Color.clear,
                                                Color.black.opacity(0.2)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                                    .frame(width: 48, height: 48)
                                
                                // Play/pause icon with enhanced styling
                                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(.title3, weight: .bold))
                                    .foregroundColor(.white)
                                    .offset(x: audioPlayer.isPlaying ? 0 : 2)
                                    .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1.5)
                            }
                        }
                        .buttonStyle(FloatingButton3DStyle())
                        
                        // Forward button with enhanced 3D styling
                        Button(action: {
                            audioPlayer.seekForward()
                        }) {
                            ZStack {
                                // Shadow layer
                                Circle()
                                    .fill(Color.black.opacity(0.2))
                                    .frame(width: 42, height: 42)
                                    .blur(radius: 6)
                                    .offset(y: 3)
                                
                                // Main button
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(.systemGray6),
                                                Color(.systemGray5),
                                                Color(.systemGray4),
                                                Color(.systemGray5)
                                            ],
                                            startPoint: UnitPoint(x: 0.3, y: 0.3),
                                            endPoint: UnitPoint(x: 0.7, y: 0.7)
                                        )
                                    )
                                    .frame(width: 38, height: 38)
                                
                                // Inner highlight
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.white.opacity(0.1),
                                                Color.clear,
                                                Color.black.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                                    .frame(width: 38, height: 38)
                                
                                Image(systemName: "goforward.15")
                                    .font(.system(.caption, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 0.5)
                            }
                        }
                        .buttonStyle(FloatingButton3DStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    // Premium floating card background
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(.systemBackground),
                                    Color(.systemGray6).opacity(0.3),
                                    Color(.systemBackground),
                                    Color(.systemGray6).opacity(0.2)
                                ],
                                startPoint: UnitPoint(x: 0.2, y: 0.2),
                                endPoint: UnitPoint(x: 0.8, y: 0.8)
                            )
                        )
                        .overlay(
                            // Glassmorphism effect
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                                .opacity(0.3)
                        )
                        .overlay(
                            // Enhanced border with multiple highlights
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.5),
                                            Color.white.opacity(0.2),
                                            Color.clear,
                                            Color.black.opacity(0.1),
                                            Color.clear,
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        // Multiple shadow layers for enhanced depth
                        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                )
                .onTapGesture {
                    onTap()
                }
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                removal: .scale(scale: 0.8).combined(with: .opacity).combined(with: .move(edge: .bottom))
            ))
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: audioPlayer.currentEpisode?.id)
            .animation(.easeInOut(duration: 0.25), value: audioPlayer.isPlaying)
        }
    }
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        return PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let time = max(0, time)
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Enhanced 3D button style for floating mini player
struct FloatingButton3DStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// Original MiniPlayerView for backward compatibility
struct MiniPlayerView: View {
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    let onTap: () -> Void
    
    var body: some View {
        if let currentEpisode = audioPlayer.currentEpisode {
            VStack(spacing: 0) {
                // Thin progress bar with glow effect
                ProgressView(value: audioPlayer.playbackPosition, total: audioPlayer.duration)
                    .progressViewStyle(GlowingProgressViewStyle())
                    .frame(height: 4)
                
                // Mini player content - Enhanced 3D design
                HStack(spacing: 16) {
                    // Episode artwork - Enhanced with 3D effect
                    AsyncImage(url: currentEpisode.artworkURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.orange.opacity(0.4), 
                                        Color.orange.opacity(0.2),
                                        Color.orange.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Image(systemName: "waveform.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.title2)
                                    .shadow(color: .orange.opacity(0.3), radius: 2, x: 0, y: 1)
                            )
                    }
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.clear,
                                        Color.black.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    
                    // Episode info - Enhanced typography
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentEpisode.title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0.5)
                        
                        if let podcast = getPodcast(for: currentEpisode) {
                            Text(podcast.title)
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        // Playback progress text with glow
                        Text(formatTime(audioPlayer.playbackPosition))
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .foregroundColor(.orange)
                            .shadow(color: .orange.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    
                    Spacer()
                    
                    // Control buttons with enhanced 3D styling
                    HStack(spacing: 12) {
                        // Backward button - Enhanced 3D effect
                        Button(action: {
                            audioPlayer.seekBackward()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(.systemGray5),
                                                Color(.systemGray4),
                                                Color(.systemGray5)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 38, height: 38)
                                
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.3),
                                                Color.clear,
                                                Color.black.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                                    .frame(width: 38, height: 38)
                                
                                Image(systemName: "gobackward.15")
                                    .font(.system(.caption, weight: .medium))
                                    .foregroundColor(.primary)
                                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0.5)
                            }
                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(Enhanced3DButtonStyle())
                        
                        // Play/pause button - Enhanced 3D effect
                        Button(action: {
                            audioPlayer.togglePlayPause()
                        }) {
                            ZStack {
                                // Background circle with gradient
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.orange.opacity(0.9),
                                                Color.orange,
                                                Color.orange.opacity(0.8)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 46, height: 46)
                                
                                // Inner shadow effect
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.clear,
                                                Color.black.opacity(0.2)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                                    .frame(width: 46, height: 46)
                                
                                // Play/pause icon
                                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(.title3, weight: .semibold))
                                    .foregroundColor(.white)
                                    .offset(x: audioPlayer.isPlaying ? 0 : 2) // Slight offset for play icon
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }
                            .shadow(color: .orange.opacity(0.4), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(Enhanced3DButtonStyle())
                        
                        // Forward button - Enhanced 3D effect
                        Button(action: {
                            audioPlayer.seekForward()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(.systemGray5),
                                                Color(.systemGray4),
                                                Color(.systemGray5)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 38, height: 38)
                                
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.3),
                                                Color.clear,
                                                Color.black.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                                    .frame(width: 38, height: 38)
                                
                                Image(systemName: "goforward.15")
                                    .font(.system(.caption, weight: .medium))
                                    .foregroundColor(.primary)
                                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0.5)
                            }
                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(Enhanced3DButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    // Enhanced 3D background
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(.systemBackground),
                                    Color(.systemGray6).opacity(0.4),
                                    Color(.systemBackground)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    // Top highlight line for 3D effect
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.2),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                        .offset(y: -7),
                    alignment: .top
                )
                .onTapGesture {
                    onTap()
                }
            }
            .background(
                // Enhanced drop shadow and background with depth
                Rectangle()
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: -6)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: -2)
            )
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: audioPlayer.currentEpisode?.id)
            .animation(.easeInOut(duration: 0.2), value: audioPlayer.isPlaying)
        }
    }
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        return PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let time = max(0, time)
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Enhanced 3D button style for mini player controls
struct Enhanced3DButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Custom glowing progress view style
struct GlowingProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let progress = configuration.fractionCompleted ?? 0.0
        
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 4)
                
                // Progress fill with glow
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.orange.opacity(0.8),
                                Color.orange,
                                Color.orange.opacity(0.9)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress, height: 4)
                    .shadow(color: .orange.opacity(0.4), radius: 3, x: 0, y: 0)
                
                // Highlight line for 3D effect
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: geometry.size.width * progress, height: 1)
                    .offset(y: -1.5)
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        Text("Main Content")
            .font(.title)
        Spacer()
        MiniPlayerView(onTap: {})
    }
} 