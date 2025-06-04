import SwiftUI

struct DiscoverView: View {
    @State private var recommended: [PodcastSearchResult] = []
    @State private var isLoading = true
    @State private var subscribed: [Podcast] = []
    @State private var showingSubscriptionAlert = false
    @State private var subscriptionMessage = ""

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading recommendations...")
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                }
            } else if recommended.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No recommendations yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(recommended) { result in
                    NavigationLink(destination: SearchResultDetailView(result: result)) {
                        SearchResultRow(
                            result: result,
                            isSubscribed: isSubscribed(result)
                        ) {
                            // navigation handled by NavigationLink
                        } onSubscribe: {
                            subscribe(to: result)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Discover")
        .onAppear {
            loadData()
        }
        .alert("Subscription", isPresented: $showingSubscriptionAlert) {
            Button("OK") { }
        } message: {
            Text(subscriptionMessage)
        }
    }

    private func loadData() {
        subscribed = PodcastService.shared.loadPodcasts()
        isLoading = true
        RecommendationService.shared.getRecommendations(basedOn: subscribed) { results in
            recommended = results
            isLoading = false
        }
    }

    private func isSubscribed(_ result: PodcastSearchResult) -> Bool {
        subscribed.contains { $0.feedURL == result.feedURL }
    }

    private func subscribe(to result: PodcastSearchResult) {
        if isSubscribed(result) {
            subscriptionMessage = "You're already subscribed to \(result.title)"
            showingSubscriptionAlert = true
            return
        }

        subscribed.append(result.toPodcast())
        PodcastService.shared.savePodcasts(subscribed)
        subscriptionMessage = "Successfully subscribed to \(result.title)"
        showingSubscriptionAlert = true
    }
}

#Preview {
    NavigationView {
        DiscoverView()
    }
}
