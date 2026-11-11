import SwiftUI

struct EpisodeDetailView: View {
    let episodeWithState: EpisodeWithPlaybackState
    @StateObject private var viewModel: EpisodeDetailViewModel
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @State private var showingShareSheet = false
    @State private var scrollOffset: CGFloat = 0
    @State private var gradientOpacity: Double = 1.0
    @State private var showingCopiedMessage = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private let headerHeight: CGFloat = 400
    
    init(episodeWithState: EpisodeWithPlaybackState) {
        self.episodeWithState = episodeWithState
        _viewModel = StateObject(wrappedValue: EpisodeDetailViewModel(
            episode: episodeWithState.episode
        ))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Main scrollable content
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // 50pt spacer to align all content with artwork offset
                        Spacer()
                            .frame(height: 50)
                        
                        // Collapsible episode artwork header with title/metadata overlay
                        EpisodeCollapsibleHeaderView(
                            episodeWithState: episodeWithState,
                            podcast: viewModel.podcast,
                            headerHeight: headerHeight,
                            minHeight: 80,
                            scrollOffset: scrollOffset
                        )
                        .overlay(alignment: .top) {
                            // Top gradient overlay for header
                            GradientOverlay(edge: .top)
                                .frame(height: 70)
                                .opacity(gradientOpacity)
                                .animation(.easeInOut(duration: 0.4), value: gradientOpacity)
                        }
                        .overlay(alignment: .bottom) {
                            // Episode title and metadata overlaid on artwork
                            VStack(spacing: 8) {
                                Text(episodeWithState.episode.title.cleanedTitle)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.9), radius: 6, x: 0, y: 3)
                                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                    .padding(.horizontal, 16)

                                if let podcast = viewModel.podcast {
                                    Text(podcast.title)
                                        .font(.title2)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.9), radius: 6, x: 0, y: 3)
                                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                        .padding(.horizontal, 16)
                                }
                                
                                // Episode metadata
                                episodeMetadataOverlay
                            }
                            .padding(.bottom, 20)
                        }
                        
                        // Action buttons section
                        actionButtonsSection
                            .padding(.top, 24)
                        
                        // Episode description content
                        descriptionContent
                            .padding(.top, 8)
                            .background(
                                // Bottom gradient overlay positioned behind description content
                                VStack {
                                    Spacer()
                                    GradientOverlay(edge: .bottom)
                                        .frame(height: 50)
                                        .opacity(gradientOpacity * 0.6)
                                        .animation(.easeInOut(duration: 0.4), value: gradientOpacity)
                                }
                            )
                    }
                    .tabBarSpacing() // Add proper bottom spacing for tab bar
                }
                .coordinateSpace(name: "scroll")
                .background(Color(.systemBackground))
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("scroll")).minY
                        )
                    }
                )
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
                
                // Sticky compact header (appears when scrolled past collapse point)
                if scrollOffset < -250 {
                    VStack {
                        EpisodeStickyCompactHeader(
                            episodeWithState: episodeWithState,
                            podcast: viewModel.podcast,
                            onDismiss: { dismiss() },
                            onShare: { copyApplePodcastsURL() },
                            onPlay: { playEpisode() },
                            onAddToQueue: { toggleQueueStatus() },
                            isPlaying: viewModel.isPlaying,
                            isInQueue: viewModel.isInQueue
                        )
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: scrollOffset < -250)
                }
                
                // Floating navigation bar
                floatingNavigationBar(geometry: geometry)
            }
        }
        .navigationBarHidden(true)
        .ignoresSafeArea(.all, edges: .top)
        .alert("Link Copied", isPresented: $showingCopiedMessage) {
            Button("OK") { }
        } message: {
            Text("Apple Podcasts link has been copied to your clipboard.")
        }
        .sheet(isPresented: $showingShareSheet) {
            if let audioURL = episodeWithState.episode.audioURL {
                ShareSheet(items: [audioURL])
            }
        }
    }
    
    // MARK: - View Components
    
    private var episodeMetadataOverlay: some View {
        HStack(spacing: 16) {
            if let date = episodeWithState.episode.publishedDate {
                Text(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)
            }
            
            if let duration = episodeWithState.episode.duration {
                Text(formatTime(duration))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)
            }
            
            // Playback status badge
            playbackStatusBadge
        }
    }
    
    private var playbackStatusBadge: some View {
        VStack {
            if episodeWithState.playbackState.finished {
                Label("Played", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.green.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
            } else if episodeWithState.playbackState.position > 0 {
                Label("In Progress", systemImage: "play.circle.fill")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
            }
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 20) {
            // Progress section (if episode has progress)
            if episodeWithState.playbackState.position > 0 {
                progressSection
            }
            
            // Main action buttons
            HStack(spacing: 16) {
                // Play/Pause button (primary)
                Button(action: playEpisode) {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(viewModel.isPlaying ? "Pause" : "Play")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 8, x: 0, y: 4)
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                // Add to Queue button
                Button(action: toggleQueueStatus) {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isInQueue ? "minus.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(viewModel.isInQueue ? "Remove" : "Queue")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    )
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                
                // Share button
                Button(action: { copyApplePodcastsURL() }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.regularMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
    }
    
    private var progressSection: some View {
        VStack(spacing: 12) {
            Text("Progress")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if let duration = episodeWithState.episode.duration {
                VStack(spacing: 8) {
                    ProgressView(value: episodeWithState.playbackState.position, total: duration)
                        .progressViewStyle(LinearProgressViewStyle(tint: Color.accentColor))
                        .scaleEffect(y: 1.5)
                    
                    HStack {
                        Text(formatTime(episodeWithState.playbackState.position))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatTime(duration))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var descriptionContent: some View {
        VStack(spacing: 0) {
            // Description header
            HStack {
                Text("Description")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // Description text
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let description = episodeWithState.episode.description, !description.isEmpty {
                        Text(description.cleanedDescription)
                            .font(.callout)
                            .lineSpacing(4)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            
                            Text("No description available")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
    }
    
    private func floatingNavigationBar(geometry: GeometryProxy) -> some View {
        VStack {
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
                }
                .offset(y: 30)
                
                Spacer()
                
                // Share button in nav bar
                Button(action: { copyApplePodcastsURL() }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
                }
                .offset(y: 30)
            }
            .padding(.horizontal, 20)
            .padding(.top, geometry.safeAreaInsets.top + 30)
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func playEpisode() {
        // Check if this episode is already the current episode
        if audioPlayer.currentEpisode?.id == episodeWithState.episode.id {
            // If it's the same episode, toggle play/pause
            audioPlayer.togglePlayPause()
        } else {
            // If it's a different episode, load and play it
            audioPlayer.loadEpisode(episodeWithState.episode, startPlaying: true)
        }
    }
    
    private func toggleQueueStatus() {
        Task {
            if viewModel.isInQueue {
                await AppModel.current?.dequeue(episodeWithState.episode.id)
            } else {
                await AppModel.current?.enqueue(episodeWithState.episode.id)
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func copyApplePodcastsURL() {
        // Generate Apple Podcasts URL for the episode
        
        // Try to get the iTunes ID from the podcast or episode
        var applePodcastsURL = ""
        
        if let podcast = viewModel.podcast {
            // Try to extract iTunes ID from the podcast's feed URL or other metadata
            // For now, we'll create a search-based URL using the podcast and episode titles
            let podcastTitle = podcast.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let episodeTitle = episodeWithState.episode.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            
            applePodcastsURL = "https://podcasts.apple.com/search?term=\(podcastTitle)+\(episodeTitle)"
        } else {
            // Fallback to episode title only
            let episodeTitle = episodeWithState.episode.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            applePodcastsURL = "https://podcasts.apple.com/search?term=\(episodeTitle)"
        }
        
        // Copy to clipboard
        UIPasteboard.general.string = applePodcastsURL
        
        // Show confirmation
        showingCopiedMessage = true
    }
}

// MARK: - Episode Collapsible Header View

struct EpisodeCollapsibleHeaderView: View {
    let episodeWithState: EpisodeWithPlaybackState
    let podcast: Podcast?
    let headerHeight: CGFloat
    let minHeight: CGFloat
    let scrollOffset: CGFloat
    
    private let artworkVerticalOffset: CGFloat = 10
    
    private var collapseProgress: CGFloat {
        let totalCollapse = headerHeight - minHeight
        guard totalCollapse > 0 else { return 1 }
        let progress = (-scrollOffset) / totalCollapse
        return progress.clamped(to: 0...1)
    }
    
    private var pullOffset: CGFloat {
        max(scrollOffset + artworkVerticalOffset, 0)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Full-screen background artwork
                BulletproofAsyncImagePhase(url: episodeWithState.episode.artworkURL ?? podcast?.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(
                    width: geometry.size.width * 1.05,
                    height: headerHeight + pullOffset + geometry.safeAreaInsets.top
                )
                .offset(x: geometry.size.width * -0.025, y: -pullOffset - geometry.safeAreaInsets.top + artworkVerticalOffset)
                
                // Blurred overlay for bottom section
                .overlay(
                    BulletproofAsyncImagePhase(url: episodeWithState.episode.artworkURL ?? podcast?.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            LinearGradient(
                                colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                    .blur(radius: 20)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .clear, location: 0.55),
                                .init(color: .black, location: 0.75),
                                .init(color: .black, location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(1.0)
                    .frame(
                        width: geometry.size.width * 1.05,
                        height: headerHeight + pullOffset + geometry.safeAreaInsets.top
                    )
                    .offset(x: geometry.size.width * -0.025, y: -pullOffset - geometry.safeAreaInsets.top - 25 + artworkVerticalOffset)
                )
                
                // Gradient overlay to dissolve into background
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.clear,
                        Color(.systemBackground).opacity(0.3),
                        Color(.systemBackground).opacity(0.7),
                        Color(.systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: headerHeight)
            }
        }
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .ignoresSafeArea(.all, edges: .top)
    }
}

// MARK: - Episode Sticky Compact Header

struct EpisodeStickyCompactHeader: View {
    let episodeWithState: EpisodeWithPlaybackState
    let podcast: Podcast?
    let onDismiss: () -> Void
    let onShare: () -> Void
    let onPlay: () -> Void
    let onAddToQueue: () -> Void
    let isPlaying: Bool
    let isInQueue: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            // Episode artwork (small)
            BulletproofAsyncImage(url: episodeWithState.episode.artworkURL ?? podcast?.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Episode title
            VStack(alignment: .leading, spacing: 2) {
                Text(episodeWithState.episode.title.cleanedTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                if let podcast = podcast {
                    Text(podcast.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Compact action buttons
            HStack(spacing: 8) {
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                Button(action: onAddToQueue) {
                    Image(systemName: isInQueue ? "minus.circle" : "plus.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 0)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
}

// MARK: - Utility Extension

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

#Preview {
    let sampleEpisode = Episode(
        id: UUID(),
        title: "Sample Episode",
        podcastID: UUID(),
        publishedDate: Date(),
        duration: 3600,
        artworkURL: nil,
        description: "This is a sample episode description.",
        audioURL: URL(string: "https://example.com/episode.mp3")
    )
    
    EpisodeDetailView(episodeWithState: EpisodeWithPlaybackState(episode: sampleEpisode, playbackState: PlaybackState(episodeID: sampleEpisode.id, position: 1245, finished: false)))
} 