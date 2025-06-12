import SwiftUI

struct PodcastDetailView: View {
    let podcast: Podcast
    
    @State private var selectedTab: EpisodeTab = .episodes
    @State private var isSubscribed = false
    @State private var subscriptionMessage = ""
    @State private var showingSubscriptionAlert = false
    
    @Environment(\.dismiss) private var dismiss
    
    private enum EpisodeTab: String, CaseIterable, Identifiable {
        case episodes = "Episodes"
        case about = "About"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            tabPicker
            contentView
        }
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.large)
        .alert("Subscription", isPresented: $showingSubscriptionAlert) {
            Button("OK") { }
        } message: {
            Text(subscriptionMessage)
        }
    }
    
    private var headerView: some View {
        PodcastHeaderView(podcast: podcast)
    }
    
    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(EpisodeTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding()
    }
    
    private var contentView: some View {
        TabView(selection: $selectedTab) {
            episodesTabView
                .tag(EpisodeTab.episodes)
            
            aboutTabView
                .tag(EpisodeTab.about)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }
    
    private var episodesTabView: some View {
        PaginatedEpisodeListView(podcast: podcast)
    }
    
    private var aboutTabView: some View {
        PodcastAboutView(podcast: podcast)
    }
    
    private func toggleSubscription() {
        // Implementation for subscription toggle
        isSubscribed.toggle()
        subscriptionMessage = isSubscribed ? "Subscribed to \(podcast.title)" : "Unsubscribed from \(podcast.title)"
        showingSubscriptionAlert = true
    }
}

// MARK: - Supporting Views

struct PodcastHeaderView: View {
    let podcast: Podcast
    
    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: podcast.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(1, contentMode: .fit)
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(spacing: 8) {
                Text(podcast.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                Text(podcast.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

struct PodcastAboutView: View {
    let podcast: Podcast
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.headline)
            
            Text(podcast.description)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            
            // Remove website section since it doesn't exist in Podcast model
        }
        .padding()
    }
}

#Preview {
    NavigationView {
        PodcastDetailView(podcast: Podcast(
            id: UUID(),
            title: "Sample Podcast",
            author: "Sample Author",
            description: "This is a sample podcast description that explains what the show is about.",
            feedURL: URL(string: "https://example.com")!,
            artworkURL: nil
        ))
    }
} 