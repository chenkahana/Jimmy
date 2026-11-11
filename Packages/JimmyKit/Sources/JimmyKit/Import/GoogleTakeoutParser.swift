import Foundation

/// Parses a Google Takeout subscriptions export into feeds JimmyKit can import.
public nonisolated enum GoogleTakeoutParser {
    struct GoogleFeed: Codable {
        let title: String
        let feedUrl: String
    }

    struct GoogleSubscriptions: Codable {
        let subscriptions: [GoogleFeed]
    }

    /// - Throws: `ImportError.malformed` if the JSON cannot be decoded at all.
    public static func parse(data: Data) throws -> ImportResult {
        let subs: GoogleSubscriptions
        do {
            subs = try JSONDecoder().decode(GoogleSubscriptions.self, from: data)
        } catch {
            throw ImportError.malformed
        }

        var candidates: [ImportedFeed] = []
        var skipped: [Skipped] = []
        for feed in subs.subscriptions {
            guard let url = URL(string: feed.feedUrl), url.scheme != nil, url.host != nil else {
                skipped.append(Skipped(reason: "invalid feed URL: \(feed.feedUrl)"))
                continue
            }
            candidates.append(ImportedFeed(feedURL: url, title: feed.title))
        }

        let (feeds, duplicateSkips) = FeedDeduplicator.deduplicate(candidates)
        return ImportResult(feeds: feeds, skipped: skipped + duplicateSkips)
    }
}
