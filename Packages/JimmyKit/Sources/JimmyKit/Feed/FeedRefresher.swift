import Foundation

/// One feed to refresh: its podcast id (for stamping parsed episodes) and feed URL,
/// plus the conditional-GET validators from the last successful fetch, if any.
nonisolated public struct FeedRefreshRequest: Sendable {
    public var podcastID: UUID
    public var feedURL: URL
    public var etag: String?
    public var lastModified: String?

    public init(podcastID: UUID, feedURL: URL, etag: String? = nil, lastModified: String? = nil) {
        self.podcastID = podcastID
        self.feedURL = feedURL
        self.etag = etag
        self.lastModified = lastModified
    }
}

/// What happened for one feed that *did* get a response (as opposed to a network/parse failure).
nonisolated public enum FeedRefreshSuccess: Sendable {
    case notModified
    case updated(ParsedFeed, etag: String?, lastModified: String?)
}

/// Why one feed's refresh failed. Wraps the underlying error's description rather than
/// the error itself so this stays `Sendable` regardless of what `URLSession` throws.
nonisolated public enum FeedRefreshError: Error, Sendable {
    case fetch(underlying: String)
    case parse(FeedError)
}

/// The result for a single feed out of a batch refresh.
nonisolated public struct FeedRefreshOutcome: Sendable {
    public var podcastID: UUID
    public var result: Result<FeedRefreshSuccess, FeedRefreshError>

    public init(podcastID: UUID, result: Result<FeedRefreshSuccess, FeedRefreshError>) {
        self.podcastID = podcastID
        self.result = result
    }
}

/// Refreshes many feeds concurrently, capped at a fixed number of fetches in flight,
/// so one slow or huge feed can't starve the rest and a user with hundreds of
/// subscriptions doesn't open hundreds of sockets at once. One feed failing (network
/// error or malformed XML) never fails or blocks any other feed in the batch.
nonisolated public enum FeedRefresher {
    public static let maxConcurrentFetches = 6

    public static func refresh(
        _ requests: [FeedRefreshRequest],
        fetcher: FeedFetcher = FeedFetcher()
    ) async -> [FeedRefreshOutcome] {
        guard !requests.isEmpty else { return [] }

        return await withTaskGroup(of: FeedRefreshOutcome.self) { group in
            var remaining = requests[...]
            var outcomes: [FeedRefreshOutcome] = []
            outcomes.reserveCapacity(requests.count)

            func startNext() {
                guard let next = remaining.first else { return }
                remaining = remaining.dropFirst()
                group.addTask {
                    await refreshOne(next, fetcher: fetcher)
                }
            }

            for _ in 0..<min(maxConcurrentFetches, requests.count) {
                startNext()
            }

            while let outcome = await group.next() {
                outcomes.append(outcome)
                startNext()
            }

            return outcomes
        }
    }

    private static func refreshOne(_ request: FeedRefreshRequest, fetcher: FeedFetcher) async -> FeedRefreshOutcome {
        let fetchResult: FeedFetchResult
        do {
            fetchResult = try await fetcher.fetch(from: request.feedURL, etag: request.etag, lastModified: request.lastModified)
        } catch {
            return FeedRefreshOutcome(podcastID: request.podcastID, result: .failure(.fetch(underlying: String(describing: error))))
        }

        switch fetchResult {
        case .notModified:
            return FeedRefreshOutcome(podcastID: request.podcastID, result: .success(.notModified))

        case .fetched(let data, let etag, let lastModified):
            do {
                let parsed = try FeedParser.parse(data: data, podcastID: request.podcastID, feedURL: request.feedURL)
                return FeedRefreshOutcome(
                    podcastID: request.podcastID,
                    result: .success(.updated(parsed, etag: etag, lastModified: lastModified))
                )
            } catch let feedError as FeedError {
                return FeedRefreshOutcome(podcastID: request.podcastID, result: .failure(.parse(feedError)))
            } catch {
                return FeedRefreshOutcome(
                    podcastID: request.podcastID,
                    result: .failure(.parse(.malformed(reason: String(describing: error))))
                )
            }
        }
    }
}
