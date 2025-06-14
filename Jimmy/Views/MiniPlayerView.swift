import SwiftUI

// Enhanced floating mini player with 3D design that floats above tab bar
struct FloatingMiniPlayerView: View {
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @State private var isMiniPlayerHidden = false
    let onTap: () -> Void
    let currentTab: Int // Add parameter to know current tab
    
    var body: some View {
        Group {
            if let currentEpisode = audioPlayer.currentEpisode,
               !isMiniPlayerHidden,
               currentTab != 2 { // Don't show mini player on "Now Playing" tab (tab 2)
                miniPlayer(for: currentEpisode)
            }
        }
        .onChange(of: currentTab) { _, newTab in
            // Reset mini player hidden state when visiting "Now Playing" tab
            // This allows it to reappear when navigating back to other tabs
            if newTab == 2 {
                isMiniPlayerHidden = false
            }
        }
    }

    @ViewBuilder
    private func miniPlayer(for currentEpisode: Episode) -> some View {
        VStack(spacing: 0) {
            // Floating card with enhanced 3D styling
            HStack(spacing: 16) {
                        // Episode artwork with less rounded corners
                        CachedAsyncImage(url: currentEpisode.artworkURL ?? getPodcast(for: currentEpisode)?.artworkURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
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
                        .transition(.opacity.combined(with: .scale))
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    Color.white.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                        
                        // Episode info with better text display
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentEpisode.title)
                                .font(.system(.subheadline, design: .default, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            if let podcast = getPodcast(for: currentEpisode) {
                                Text(podcast.title)
                                    .font(.system(.caption, design: .default, weight: .regular))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            // Simple progress indicator
                            HStack(spacing: 8) {
                                Text(formatTime(audioPlayer.playbackPosition))
                                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                                    .foregroundColor(.orange)
                                
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        // Background track
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color(.systemGray5))
                                            .frame(height: 3)
                                        
                                        // Progress fill
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.orange)
                                            .frame(
                                                width: geometry.size.width * (audioPlayer.playbackPosition / max(audioPlayer.duration, 1)),
                                                height: 3
                                            )
                                    }
                                }
                                .frame(height: 3)
                                
                                Text(formatTime(audioPlayer.duration))
                                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Only play/pause button
                        Button(action: {
                            audioPlayer.togglePlayPause()
                        }) {
                            ZStack {
                                // Shadow
                                Circle()
                                    .fill(Color.black.opacity(0.2))
                                    .frame(width: 46, height: 46)
                                    .blur(radius: 4)
                                    .offset(y: 2)
                                
                                // Main button
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 44, height: 44)
                                
                                // Play/pause icon
                                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(.body, weight: .bold))
                                    .foregroundColor(.white)
                                    .offset(x: audioPlayer.isPlaying ? 0 : 1)
                            }
                        }
                        .buttonStyle(SimpleButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .enhanced3DCard(cornerRadius: 16, elevation: 6)
                    .overlay(
                        // Small X button in top-right corner
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isMiniPlayerHidden = true
                                    }
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .padding(6)
                                        .background(
                                            Circle()
                                                .fill(.ultraThinMaterial)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                                )
                                        )
                                }
                                .buttonStyle(SimpleButtonStyle())
                                .offset(x: 8, y: -8)
                            }
                            Spacer()
                        }
                    )
                    .onTapGesture {
                        onTap()
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                    removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .bottom))
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
    
    
    // Simple button style for the play/pause button
    struct SimpleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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
                        .progressViewStyle(Enhanced3DProgressViewStyle())
                        .frame(height: 4)
                    
                    // Mini player content - Enhanced 3D design
                    HStack(spacing: 16) {
                        // Episode artwork - Enhanced with 3D effect
                        CachedAsyncImage(url: currentEpisode.artworkURL ?? getPodcast(for: currentEpisode)?.artworkURL) { image in
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
                        .transition(.opacity.combined(with: .scale))
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
                    .enhanced3DCard(cornerRadius: 0, elevation: 8)
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
    
    // Note: Enhanced3DButtonStyle is now defined in Enhanced3DStyles.swift
    
    // Enhanced 3D progress view style
    struct Enhanced3DProgressViewStyle: ProgressViewStyle {
        func makeBody(configuration: Configuration) -> some View {
            let progress = configuration.fractionCompleted ?? 0.0
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track with inset 3D effect
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.15),
                                    Color("DarkBackground").opacity(0.1),
                                    Color.black.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 4)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                        }
                    
                    // Progress fill with raised 3D effect
                    RoundedRectangle(cornerRadius: 2)
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
                        .frame(width: geometry.size.width * progress, height: 4)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.4),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: geometry.size.width * progress, height: 2)
                                .offset(y: -1)
                        }
                        .shadow(color: Color.orange.opacity(0.3), radius: 2, x: 0, y: 0)
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

