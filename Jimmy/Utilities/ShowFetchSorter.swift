import Foundation

/// Fetches latest episode dates for podcasts and returns them sorted by newest first.
/// Designed for high performance and resiliency with bounded concurrency and
/// cache-aware fallbacks. The generic fetcher allows callers to plug in whatever
/// networking stack they prefer while this utility focuses purely on orchestration
/// and ordering.
public enum ShowFetchSorter {
    /// Type alias for a closure that fetches the most recent episode date for a
    /// podcast. Returning `nil` indicates that the date could not be determined.
    public typealias EpisodeDateFetcher = (Podcast) async throws -> Date?

    /// Concurrently fetch latest episode dates for the supplied podcasts, apply
    /// the results to the provided cache and return podcasts sorted by newest
    /// episode first. A reasonable upper bound for concurrent tasks keeps memory
    /// and CPU usage predictable even when handling hundreds of subscriptions.
    ///
    /// - Parameters:
    ///   - podcasts: Podcasts that need fresh metadata.
    ///   - cache: A cache of previously seen episode dates. Updated in-place.
    ///   - maxConcurrent: Maximum number of concurrent fetch tasks. Defaults to 6.
    ///   - fetcher: Closure used to retrieve the latest episode date for a podcast.
    /// - Returns: Podcasts sorted so the newest show (by episode date) appears first.
    public static func fetchAndSort(
        podcasts: [Podcast],
        cache: inout [UUID: Date],
        maxConcurrent: Int = 6,
        fetcher: @escaping EpisodeDateFetcher
    ) async -> [Podcast] {
        guard !podcasts.isEmpty else { return [] }

        var results: [(podcast: Podcast, date: Date)] = []
        results.reserveCapacity(podcasts.count)

        await withTaskGroup(of: (Podcast, Date?).self) { group in
            var iterator = podcasts.makeIterator()

            // Seed initial tasks respecting max concurrency
            for _ in 0..<maxConcurrent {
                guard let podcast = iterator.next() else { break }
                group.addTask {
                    let date = try? await fetcher(podcast)
                    return (podcast, date)
                }
            }

            // For each completed task, append result and kick off the next one
            while let result = await group.next() {
                let podcast = result.0
                let fetchedDate = result.1
                let finalDate = fetchedDate ?? cache[podcast.id] ?? Date.distantPast

                cache[podcast.id] = finalDate
                results.append((podcast, finalDate))

                if let next = iterator.next() {
                    group.addTask {
                        let date = try? await fetcher(next)
                        return (next, date)
                    }
                }
            }
        }

        // Sort by newest date first
        results.sort { $0.date > $1.date }
        return results.map { $0.podcast }
    }
}
