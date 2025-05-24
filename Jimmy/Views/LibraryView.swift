import SwiftUI

struct LibraryView: View {
    @State private var searchText: String = ""
    @State private var subscribedPodcasts: [Podcast] = []
    @State private var isEditMode: Bool = false
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var filteredPodcasts: [Podcast] {
        if searchText.isEmpty {
            return subscribedPodcasts
        } else {
            return subscribedPodcasts.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) || 
                $0.author.localizedCaseInsensitiveContains(searchText) 
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                SearchBarView(searchText: $searchText)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                // Main Content Area
                ScrollView {
                    VStack(spacing: 24) {
                        // Subscribed Shows Section
                        SubscribedShowsGridView(
                            podcasts: filteredPodcasts,
                            searchText: searchText,
                            isEditMode: isEditMode,
                            onDelete: { podcast in
                                deletePodcast(podcast)
                            }
                        )
                        
                        // Spacer to push content up properly  
                        Spacer(minLength: 50)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditMode ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditMode.toggle()
                        }
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                }
            }
        }
        .onAppear {
            loadSubscribedPodcasts()
        }
        .refreshable {
            loadSubscribedPodcasts()
        }
    }
    
    private func loadSubscribedPodcasts() {
        subscribedPodcasts = PodcastService.shared.loadPodcasts()
        
        // For testing purposes - add sample data if no podcasts exist
        if subscribedPodcasts.isEmpty {
            addSampleDataForTesting()
        }
    }
    
    private func addSampleDataForTesting() {
        let samplePodcasts = [
            Podcast(
                title: "Tech Talk Daily",
                author: "Tech Network",
                description: "Daily discussions about the latest technology trends and innovations.",
                feedURL: URL(string: "https://example.com/tech-talk.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/tech/400/400")
            ),
            Podcast(
                title: "Design Matters",
                author: "Design Studio",
                description: "Exploring the world of design through interviews with leading designers.",
                feedURL: URL(string: "https://example.com/design-matters.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/design/400/400")
            ),
            Podcast(
                title: "History Uncovered",
                author: "History Channel",
                description: "Discovering untold stories from our past.",
                feedURL: URL(string: "https://example.com/history.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/history/400/400")
            ),
            Podcast(
                title: "Startup Stories",
                author: "Business Weekly",
                description: "Inspiring stories from successful entrepreneurs.",
                feedURL: URL(string: "https://example.com/startup.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/startup/400/400")
            ),
            Podcast(
                title: "Science Explorer",
                author: "Science Network",
                description: "Making complex scientific concepts accessible to everyone.",
                feedURL: URL(string: "https://example.com/science.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/science/400/400")
            ),
            Podcast(
                title: "Music & Culture",
                author: "Cultural Media",
                description: "The intersection of music and culture around the world.",
                feedURL: URL(string: "https://example.com/music.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/music/400/400")
            ),
            Podcast(
                title: "Mindful Living",
                author: "Wellness Group",
                description: "Tips and techniques for living a more mindful life.",
                feedURL: URL(string: "https://example.com/mindful.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/mindful/400/400")
            ),
            Podcast(
                title: "Sports Central",
                author: "Sports Network",
                description: "Your daily dose of sports news and analysis.",
                feedURL: URL(string: "https://example.com/sports.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/sports/400/400")
            ),
            Podcast(
                title: "Comedy Hour",
                author: "Laugh Factory",
                description: "The best comedy content to brighten your day.",
                feedURL: URL(string: "https://example.com/comedy.xml")!,
                artworkURL: URL(string: "https://picsum.photos/seed/comedy/400/400")
            )
        ]
        
        subscribedPodcasts = samplePodcasts
        PodcastService.shared.savePodcasts(samplePodcasts)
        
        // Also add a sample current episode for testing the mini player
        addSampleCurrentEpisode()
    }
    
    private func addSampleCurrentEpisode() {
        let sampleEpisode = Episode(
            id: UUID(),
            title: "Tech Talk Daily | The Future of AI in Technology",
            artworkURL: URL(string: "https://picsum.photos/seed/episode/400/400"),
            audioURL: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"),
            description: "An in-depth discussion about how artificial intelligence is shaping the future of technology and our daily lives.",
            played: false,
            podcastID: UUID(),
            publishedDate: Date(),
            localFileURL: nil,
            playbackPosition: 120 // 2 minutes in
        )
        
        // Load the sample episode into the audio player for testing the mini player
        AudioPlayerService.shared.loadEpisode(sampleEpisode)
    }
    
    private func deletePodcast(_ podcast: Podcast) {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            subscribedPodcasts.removeAll { $0.id == podcast.id }
        }
        
        // Save the updated list
        PodcastService.shared.savePodcasts(subscribedPodcasts)
        
        // Also remove from queue if any episodes from this podcast are queued
        let queueViewModel = QueueViewModel.shared
        let episodesToRemove = queueViewModel.queue.filter { $0.podcastID == podcast.id }
        if !episodesToRemove.isEmpty {
            let idsToRemove = Set(episodesToRemove.map { $0.id })
            queueViewModel.removeEpisodes(withIDs: idsToRemove)
        }
    }
}

// MARK: - Search Bar Component
struct SearchBarView: View {
    @Binding var searchText: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16, weight: .medium))
            
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Subscribed Shows Grid
struct SubscribedShowsGridView: View {
    let podcasts: [Podcast]
    let searchText: String
    let isEditMode: Bool
    let onDelete: (Podcast) -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Text("Subscribed Shows")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // Grid Content
            if podcasts.isEmpty {
                EmptySubscriptionsView(hasSearchText: !searchText.isEmpty)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(podcasts) { podcast in
                        ZStack(alignment: .topTrailing) {
                            // Main podcast item
                            NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                                PodcastGridItemView(podcast: podcast, isEditMode: isEditMode)
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditMode) // Disable navigation when in edit mode
                            
                            // Delete button overlay (only shown in edit mode)
                            if isEditMode {
                                Button(action: {
                                    onDelete(podcast)
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 24, height: 24)
                                        
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .offset(x: 8, y: -8)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isEditMode)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Podcast Grid Item
struct PodcastGridItemView: View {
    let podcast: Podcast
    let isEditMode: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: podcast.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color.orange.opacity(0.3), Color.red.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(
                        Image(systemName: "waveform.circle")
                            .font(.title2)
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
            .scaleEffect(isEditMode ? 0.9 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isEditMode)
            
            Text(podcast.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32)
                .opacity(isEditMode ? 0.7 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isEditMode)
        }
    }
}

// MARK: - Empty State
struct EmptySubscriptionsView: View {
    let hasSearchText: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasSearchText ? "magnifyingglass" : "waveform.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(hasSearchText ? "No Results" : "No Subscriptions")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text(hasSearchText ? "Try a different search term" : "Your subscribed podcasts will appear here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    LibraryView()
} 