import Foundation
import JimmyKit

/// Library: the one place every screen subscribes, unsubscribes, and refreshes podcasts through.
/// `podcasts` (declared on `AppModel` itself) is kept current by `store.observePodcasts()`.
extension AppModel {
    /// Fetches, parses, and stores `feedURL` as a new subscription. Idempotent on feed URL: if
    /// already subscribed, returns the existing podcast rather than adding a duplicate.
    func subscribe(feedURL: URL) async throws -> JimmyKit.Podcast {
        guard let readyStore else { throw AppModelError.storeNotReady }

        let fetchableURL = FeedURLNormalizer.fetchableURL(for: feedURL)
        let fetchResult = try await feedFetcher.fetch(from: fetchableURL, etag: nil, lastModified: nil)

        let data: Data
        let etag: String?
        switch fetchResult {
        case .notModified:
            // Can't happen on a first fetch (no validators were sent), but a podcast with no
            // episodes yet is a better outcome than crashing on it.
            data = Data()
            etag = nil
        case .fetched(let fetchedData, let fetchedETag, _):
            data = fetchedData
            etag = fetchedETag
        }

        let podcastID = FeedIDs.generatePodcastID(from: fetchableURL)
        let parsed = try FeedParser.parse(data: data, podcastID: podcastID, feedURL: fetchableURL)
        return try await readyStore.subscribe(feedURL: fetchableURL, parsed: parsed, etag: etag)
    }

    /// Unsubscribes from `podcastID`: dequeues its episodes first (so the queue's `1...n`
    /// positions stay contiguous around the gap this leaves), then deletes the podcast — which
    /// cascades to its episodes and everything that references them.
    func unsubscribe(_ podcastID: UUID) async {
        guard let readyStore else { return }
        await removeEpisodesFromPodcast(podcastID)
        try? await readyStore.unsubscribe(podcastID)
    }

    /// Refreshes every subscribed podcast's feed, applies each outcome to the store, and
    /// auto-adds newly-fetched episodes to the queue for podcasts with `autoAddToQueue` set —
    /// capped at 5 episodes per refresh, matching today's background refresh.
    func refreshAll() async {
        guard let readyStore else { return }
        let subscribedPodcasts = podcasts
        guard !subscribedPodcasts.isEmpty else {
            lastRefreshErrors = [:]
            return
        }

        let requests = subscribedPodcasts.map {
            FeedRefreshRequest(podcastID: $0.id, feedURL: $0.feedURL, etag: $0.etag)
        }
        let outcomes = await FeedRefresher.refresh(requests, fetcher: feedFetcher)
        let autoAddPodcastIDs = Set(subscribedPodcasts.filter(\.autoAddToQueue).map(\.id))

        var errors: [UUID: String] = [:]
        var autoAddedCount = 0
        for outcome in outcomes {
            await apply(outcome, readyStore: readyStore, autoAddPodcastIDs: autoAddPodcastIDs, autoAddedCount: &autoAddedCount, errors: &errors)
        }
        lastRefreshErrors = errors
    }

    /// Refreshes one podcast's feed and applies the outcome, same as one feed out of
    /// `refreshAll()`.
    func refresh(_ podcastID: UUID) async {
        guard let readyStore else { return }
        guard let podcast = podcasts.first(where: { $0.id == podcastID }) else { return }

        let request = FeedRefreshRequest(podcastID: podcast.id, feedURL: podcast.feedURL, etag: podcast.etag)
        guard let outcome = await FeedRefresher.refresh([request], fetcher: feedFetcher).first else { return }

        let autoAddPodcastIDs: Set<UUID> = podcast.autoAddToQueue ? [podcastID] : []
        var errors = lastRefreshErrors
        var autoAddedCount = 0
        await apply(outcome, readyStore: readyStore, autoAddPodcastIDs: autoAddPodcastIDs, autoAddedCount: &autoAddedCount, errors: &errors)
        lastRefreshErrors = errors
    }

    private func apply(
        _ outcome: FeedRefreshOutcome,
        readyStore: Store,
        autoAddPodcastIDs: Set<UUID>,
        autoAddedCount: inout Int,
        errors: inout [UUID: String]
    ) async {
        switch outcome.result {
        case .failure(let error):
            errors[outcome.podcastID] = String(describing: error)
        case .success:
            errors[outcome.podcastID] = nil
            let newEpisodeIDs = (try? await readyStore.apply(outcome)) ?? []
            guard autoAddPodcastIDs.contains(outcome.podcastID) else { return }
            let maxAutoAddPerRefresh = 5
            for episodeID in newEpisodeIDs {
                guard autoAddedCount < maxAutoAddPerRefresh else { return }
                guard !isQueued(episodeID) else { continue }
                await enqueue(episodeID)
                autoAddedCount += 1
            }
        }
    }
}

enum AppModelError: Error {
    case storeNotReady
}
