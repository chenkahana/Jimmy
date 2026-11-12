import SwiftUI
import JimmyKit
import os

// MARK: - Async Podcast Detail View Wrapper
/// A show opened from Discover or search: loads the feed for display without subscribing to it.
struct AsyncPodcastDetailView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "AsyncPodcastDetailView")
    let searchResult: PodcastSearchResult
    @State private var podcast: Podcast?
    @State private var episodes: [Episode] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        PreviewPodcastDetailView(
            podcast: podcast ?? Podcast(
                title: searchResult.title,
                author: searchResult.author,
                description: searchResult.description ?? "",
                feedURL: searchResult.feedURL,
                artworkURL: searchResult.artworkURL
            ),
            episodes: episodes,
            isLoading: isLoading,
            loadFailed: loadFailed,
            onRetry: { Task { await loadPodcast() } }
        )
        .task {
            guard podcast == nil else { return }
            await loadPodcast()
        }
    }

    private func loadPodcast() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            // Preview only: loads the feed without saving it to the database.
            guard let appModel = AppModel.current else { throw AppModelError.storeNotReady }
            let (podcastData, episodesData) = try await appModel.previewPodcast(feedURL: searchResult.feedURL)
            podcast = podcastData.asLegacyPodcast()
            episodes = episodesData.map { $0.asLegacyEpisode() }
            logger.info("Podcast preview loaded: \(podcastData.title) with \(episodesData.count) episodes (not saved)")
        } catch {
            logger.error("Failed to load podcast: \(error)")
            loadFailed = true
        }
    }
}

// MARK: - Preview-specific PodcastDetailView

struct PreviewPodcastDetailView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "PreviewPodcastDetailView")
    let podcast: Podcast
    let episodes: [Episode]
    var isLoading = false
    var loadFailed = false
    var onRetry: () -> Void = {}
    @Environment(AppModel.self) private var appModel
    @State private var selectedEpisode: EpisodeWithPlaybackState?
    @State private var subscriptionError: SubscriptionError?
    @State private var isSubscribing = false
    @State private var filterOption: PodcastDetailViewModel.EpisodeFilter = .all
    @State private var sortOrder: PodcastDetailViewModel.EpisodeSortOrder = .newestFirst

    var body: some View {
        PodcastPage(
            podcast: podcast,
            isFollowing: appModel.podcasts.contains { $0.feedURL == podcast.feedURL },
            isUpdatingFollow: isSubscribing,
            onFollow: { Task { await subscribeToPodcast() } },
            onUnfollow: nil,
            filterOption: $filterOption,
            sortOrder: $sortOrder,
            selectedEpisode: $selectedEpisode,
            rows: { episodeRows }
        )
        .subscriptionErrorAlert(
            error: $subscriptionError,
            podcastTitle: podcast.title,
            onRetry: { Task { await subscribeToPodcast() } }
        )
    }

    @ViewBuilder
    private var episodeRows: some View {
        if isLoading {
            EpisodePlaceholderRows()
        } else if loadFailed {
            ContentUnavailableView {
                Label("Couldn't Load Episodes", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again", action: onRetry)
            }
            .listRowSeparator(.hidden)
        } else if filteredAndSortedEpisodes.isEmpty {
            ContentUnavailableView(
                episodes.isEmpty ? "No Episodes" : "No \(filterOption.rawValue) Episodes",
                systemImage: "list.bullet",
                description: episodes.isEmpty ? Text("Episodes appear here when the show publishes them.") : nil
            )
            .listRowSeparator(.hidden)
        } else {
            ForEach(filteredAndSortedEpisodes, id: \.id) { episode in
                EpisodeCard(
                    episode: episodeWithStatus(episode),
                    onTap: {
                        selectedEpisode = EpisodeWithPlaybackState(
                            episode: episode,
                            playbackState: PlaybackState(
                                episodeID: episode.id,
                                position: episode.playbackPosition,
                                finished: episode.played || episode.status.contains(.played),
                                updatedAt: Date()
                            )
                        )
                    },
                    onPlay: { Task { await appModel.play(episode.asPlaybackEpisode()) } },
                    onAddToQueue: { Task { await appModel.enqueue(episode.id) } },
                    showsArtwork: false
                )
            }
        }
    }

    private var filteredAndSortedEpisodes: [Episode] {
        var filtered = episodes

        switch filterOption {
        case .all:
            break
        case .unplayed:
            filtered = filtered.filter { !$0.played && !$0.status.contains(.played) }
        case .played:
            filtered = filtered.filter { $0.played || $0.status.contains(.played) }
        case .downloaded:
            filtered = filtered.filter { $0.localFileURL != nil }
        }

        switch sortOrder {
        case .newestFirst:
            filtered.sort { ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) }
        case .oldestFirst:
            filtered.sort { ($0.publishedDate ?? Date.distantPast) < ($1.publishedDate ?? Date.distantPast) }
        case .titleAZ:
            filtered.sort { $0.title < $1.title }
        case .titleZA:
            filtered.sort { $0.title > $1.title }
        }

        return filtered
    }

    private func episodeWithStatus(_ episode: Episode) -> EpisodeWithStatus {
        // Preview episodes aren't persisted, so the only progress is the freshly parsed (zero) position.
        let playProgress: Double = episode.duration.map { $0 > 0 ? episode.playbackPosition / $0 : 0.0 } ?? 0.0
        let isCurrentlyPlaying = (appModel.playback?.isPlaying ?? false)
            && appModel.playback?.currentEpisode?.id == episode.id

        return EpisodeWithStatus(
            episode: episode,
            podcastTitle: podcast.title,
            playProgress: playProgress,
            status: EpisodeWithStatus.deriveStatus(
                episode: episode,
                playProgress: playProgress,
                isQueued: appModel.isQueued(episode.id),
                isCurrentlyPlaying: isCurrentlyPlaying
            ),
            podcastArtworkURL: podcast.artworkURL
        )
    }

    private func subscribeToPodcast() async {
        isSubscribing = true
        defer { isSubscribing = false }
        do {
            _ = try await appModel.subscribe(feedURL: podcast.feedURL)
            logger.info("Subscribed to podcast: \(podcast.title)")
        } catch {
            subscriptionError = .unknownError(error.localizedDescription)
            logger.error("Unexpected error subscribing to podcast: \(error)")
        }
    }
}

// MARK: - Podcast Detail View

struct PodcastDetailView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "PodcastDetailView")
    let podcast: Podcast
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [EpisodeListItem]?
    @State private var selectedEpisode: EpisodeWithPlaybackState?
    @State private var showingUnsubscribeAlert = false
    @State private var subscriptionError: SubscriptionError?
    @State private var isSubscribing = false
    @State private var filterOption: PodcastDetailViewModel.EpisodeFilter = .all
    @State private var sortOrder: PodcastDetailViewModel.EpisodeSortOrder = .newestFirst

    var body: some View {
        PodcastPage(
            podcast: podcast,
            isFollowing: appModel.podcasts.contains { $0.feedURL == podcast.feedURL },
            isUpdatingFollow: isSubscribing,
            onFollow: { Task { await subscribeToPodcast() } },
            onUnfollow: { showingUnsubscribeAlert = true },
            filterOption: $filterOption,
            sortOrder: $sortOrder,
            selectedEpisode: $selectedEpisode,
            rows: {
                PodcastEpisodeListView(
                    items: items,
                    podcastTitle: podcast.title,
                    podcastArtworkURL: podcast.artworkURL,
                    filterOption: filterOption,
                    sortOrder: sortOrder,
                    onEpisodeTap: { selectedEpisode = $0 }
                )
            }
        )
        .task(id: podcast.id) {
            guard let stream = appModel.observeEpisodes(podcastID: podcast.id) else { return }
            do {
                for try await newItems in stream {
                    items = newItems
                }
            } catch {
                logger.error("observeEpisodes stopped: \(error)")
            }
        }
        .alert("Unfollow \(podcast.title)?", isPresented: $showingUnsubscribeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Unfollow", role: .destructive) {
                Task { await unsubscribeFromPodcast() }
            }
        } message: {
            Text("It's removed from your library.")
        }
        .subscriptionErrorAlert(
            error: $subscriptionError,
            podcastTitle: podcast.title,
            onRetry: { Task { await subscribeToPodcast() } }
        )
    }

    private func subscribeToPodcast() async {
        isSubscribing = true
        defer { isSubscribing = false }
        do {
            _ = try await appModel.subscribe(feedURL: podcast.feedURL)
            logger.info("Successfully subscribed to \(podcast.title)")
        } catch {
            subscriptionError = .unknownError(error.localizedDescription)
            logger.error("Unexpected error subscribing to \(podcast.title): \(error)")
        }
    }

    private func unsubscribeFromPodcast() async {
        await appModel.unsubscribe(podcast.id)
        logger.info("Successfully unsubscribed from \(podcast.title)")
        dismiss()
    }
}

// MARK: - Page

/// The podcast page: the artwork hero and header, then the episode rows, in a plain `List` that runs
/// up under the system navigation bar.
private struct PodcastPage<Rows: View>: View {
    let podcast: Podcast
    let isFollowing: Bool
    let isUpdatingFollow: Bool
    let onFollow: () -> Void
    /// `nil` where following can't be undone from this page.
    let onUnfollow: (() -> Void)?
    @Binding var filterOption: PodcastDetailViewModel.EpisodeFilter
    @Binding var sortOrder: PodcastDetailViewModel.EpisodeSortOrder
    @Binding var selectedEpisode: EpisodeWithPlaybackState?
    @ViewBuilder let rows: Rows

    @State private var isTitleVisible = true

    private var title: String { podcast.cleanTitle.isEmpty ? podcast.title : podcast.cleanTitle }

    var body: some View {
        List {
            PodcastHeader(
                podcast: podcast,
                title: title,
                isFollowing: isFollowing,
                isUpdatingFollow: isUpdatingFollow,
                onFollow: onFollow,
                onUnfollow: onUnfollow,
                isTitleVisible: $isTitleVisible
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                rows
            } header: {
                Text("Episodes")
            }
            .headerProminence(.increased)
        }
        .listStyle(.plain)
        // The hero starts at the top of the screen, behind the status bar and the navigation bar.
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle(isTitleVisible ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        // No bar background over the hero; once the title scrolls away the bar takes over.
        .toolbarBackgroundVisibility(isTitleVisible ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Filter and Sort", systemImage: "line.3.horizontal.decrease") {
                    Picker("Filter", selection: $filterOption) {
                        ForEach([PodcastDetailViewModel.EpisodeFilter.all, .unplayed, .played]) { option in
                            Text(option == .all ? "All Episodes" : option.rawValue).tag(option)
                        }
                    }
                    Picker("Sort", selection: $sortOrder) {
                        ForEach([PodcastDetailViewModel.EpisodeSortOrder.newestFirst, .oldestFirst]) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedEpisode != nil },
            set: { if !$0 { selectedEpisode = nil } }
        )) {
            if let selectedEpisode {
                EpisodeDetailView(episodeWithState: selectedEpisode)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        PodcastDetailView(podcast: Podcast(
            id: UUID(),
            title: "Sample Podcast",
            author: "Sample Author",
            description: "A sample description, long enough to show how the header lays out its text.",
            feedURL: URL(filePath: "/feed.rss"),
            artworkURL: nil
        ))
    }
}
