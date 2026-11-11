import Foundation

/// FetchWorker handles background episode fetching operations
class FetchWorker {
    static let shared = FetchWorker()

    private init() {}

    func batchFetchEpisodes(for podcasts: [Podcast]) async -> [UUID: [Episode]] {
        guard !podcasts.isEmpty else {
            return [:]
        }

        var results: [UUID: [Episode]] = [:]

        // Use TaskGroup for concurrent fetching
        await withTaskGroup(of: (UUID, [Episode]).self) { group in
            for podcast in podcasts {
                group.addTask {
                    do {
                        let parser = ConcreteRSSParser()
                        // Use conditional GET — returns nil data if 304 Not Modified
                        let (data, newEtag, _) = try await UnifiedNetworkService.shared.fetchRSSFeedConditional(
                            from: podcast.feedURL,
                            etag: podcast.etag,
                            lastModified: nil
                        )

                        // If data is nil, feed hasn't changed — skip parsing
                        guard let feedData = data else {
                            return (podcast.id, [])
                        }

                        let (episodes, _) = try await parser.parse(data: feedData, podcastID: podcast.id, feedURL: podcast.feedURL)

                        // Update podcast's etag and lastFetched in database
                        await Self.updatePodcastFetchMetadata(
                            podcastID: podcast.id,
                            etag: newEtag,
                            lastFetched: Date()
                        )

                        return (podcast.id, episodes)
                    } catch {
                        return (podcast.id, [])
                    }
                }
            }

            for await (podcastID, episodes) in group {
                results[podcastID] = episodes
            }
        }

        return results
    }

    /// Sort podcasts by staleness — those not fetched recently come first
    static func prioritizedByStale(_ podcasts: [Podcast]) -> [Podcast] {
        podcasts.sorted { a, b in
            let aDate = a.lastFetched ?? .distantPast
            let bDate = b.lastFetched ?? .distantPast
            return aDate < bDate  // Older (more stale) first
        }
    }

    /// Update podcast etag and lastFetched after a successful fetch
    private static func updatePodcastFetchMetadata(podcastID: UUID, etag: String?, lastFetched: Date) async {
        do {
            try await DatabaseManager.shared.writeAsync { db in
                let idString = podcastID.uuidString
                try db.execute(
                    sql: "UPDATE podcasts SET etag = ?, lastFetched = ? WHERE id = ?",
                    arguments: [etag, lastFetched, idString]
                )
            }
        } catch {
            // Non-critical — metadata update failure shouldn't block refresh
        }
    }
}
