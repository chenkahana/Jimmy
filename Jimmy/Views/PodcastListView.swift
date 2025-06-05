import SwiftUI

struct PodcastListView: View {
    @State private var searchText: String = ""
    @State private var subscribedPodcasts: [Podcast] = []
    @State private var isEditMode = false
    @State private var showingDeleteAlert = false
    @State private var podcastToDelete: Podcast?
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
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
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("Search podcasts...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.top)
            
            // Subscribed Shows Grid
            ScrollView {
                if filteredPodcasts.isEmpty {
                    VStack(spacing: 16) {
                        // RSS-style icon
                        ZStack {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 60, height: 60)
                            
                            VStack(spacing: 2) {
                                HStack(spacing: 2) {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 4, height: 4)
                                    
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: 12, height: 2)
                                    
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: 8, height: 2)
                                }
                                
                                HStack(spacing: 2) {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 4, height: 4)
                                    
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: 16, height: 2)
                                    
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: 4, height: 2)
                                }
                                
                                HStack(spacing: 2) {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 4, height: 4)
                                    
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: 14, height: 2)
                                    
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: 6, height: 2)
                                }
                            }
                        }
                        
                        Text("No Subscriptions")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("Your subscribed podcasts will appear here")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredPodcasts) { podcast in
                            ZStack(alignment: .topTrailing) {
                                if isEditMode {
                                    PodcastGridItem(podcast: podcast) {
                                        // No action in edit mode
                                    }
                                } else {
                                    NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                                        PodcastGridItem(podcast: podcast) {
                                            // Navigation handled by NavigationLink
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                // Delete button in edit mode
                                if isEditMode {
                                    Button(action: {
                                        podcastToDelete = podcast
                                        showingDeleteAlert = true
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.red)
                                            .background(Color.white)
                                            .clipShape(Circle())
                                    }
                                    .offset(x: 8, y: -8)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !filteredPodcasts.isEmpty {
                    Button(isEditMode ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditMode.toggle()
                        }
                    }
                }
            }
        }
        .onAppear {
            loadSubscribedPodcasts()
        }
        .refreshable {
            loadSubscribedPodcasts()
        }
        .alert("Remove Subscription", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                podcastToDelete = nil
            }
            Button("Remove", role: .destructive) {
                if let podcast = podcastToDelete {
                    removePodcast(podcast)
                }
                podcastToDelete = nil
            }
        } message: {
            Text("Are you sure you want to remove \"\(podcastToDelete?.title ?? "this podcast")\" from your subscriptions?")
        }
        .keyboardDismissToolbar()
    }
    
    private func loadSubscribedPodcasts() {
        subscribedPodcasts = PodcastService.shared.loadPodcasts()
    }
    
    private func removePodcast(_ podcast: Podcast) {
        subscribedPodcasts.removeAll { $0.id == podcast.id }
        PodcastService.shared.savePodcasts(subscribedPodcasts)
        
        // Exit edit mode if no podcasts left
        if subscribedPodcasts.isEmpty {
            isEditMode = false
        }
    }
}

// MARK: - Supporting Views

struct PodcastGridItem: View {
    let podcast: Podcast
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                PodcastArtworkView(
                    artworkURL: podcast.artworkURL,
                    size: 100,
                    cornerRadius: 12
                )
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                
                Text(podcast.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 32)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PodcastListView()
} 