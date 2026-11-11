import Foundation
import JimmyKit
import os

/// Which subscription-export format a file is.
enum SubscriptionImportFormat {
    case opml
    case appleBulkJSON
    case googleTakeout
    case spotifyList
}

/// Parses a subscription export with JimmyKit's `Import/` parsers and subscribes to every feed
/// found through `AppModel.subscribe(feedURL:)`. Replaces `SubscriptionImportService`, which hand-
/// rolled its own JSON decoding and screen-scraped Apple Podcasts/Spotify/Google Podcasts pages
/// (`PodcastURLResolver`) to resolve a show by name.
///
/// Note: a title-only export row (no feed URL at all) isn't resolvable by the JimmyKit parsers,
/// which require one per entry, so it's silently skipped. A *link* to a show (an
/// `podcasts.apple.com`/`open.spotify.com` page rather than a feed) still resolves, by title,
/// through `iTunesSearchService` below. Revisit if a title-only export turns out to matter.
enum SubscriptionImporter {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "SubscriptionImporter")

    struct Outcome {
        var importedCount = 0
        var skippedCount = 0
    }

    static func importSubscriptions(from data: Data, format: SubscriptionImportFormat) async throws -> Outcome {
        let parsed: JimmyKit.ImportResult
        switch format {
        case .opml:
            parsed = try JimmyKit.OPMLParser.parse(data: data)
        case .appleBulkJSON:
            parsed = try JimmyKit.AppleBulkImportParser.parse(data: data)
        case .googleTakeout:
            parsed = try JimmyKit.GoogleTakeoutParser.parse(data: data)
        case .spotifyList:
            parsed = JimmyKit.SpotifyListParser.parse(data: data)
        }

        let existingURLs = Set((await AppModel.current?.podcasts ?? []).map(\.feedURL))
        var outcome = Outcome(importedCount: 0, skippedCount: parsed.skipped.count)

        for feed in parsed.feeds {
            guard let resolvedURL = await resolveFeedURL(feed) else {
                outcome.skippedCount += 1
                continue
            }
            guard !existingURLs.contains(resolvedURL) else { continue }
            if (try? await AppModel.current?.subscribe(feedURL: resolvedURL)) != nil {
                outcome.importedCount += 1
            } else {
                outcome.skippedCount += 1
            }
        }

        logger.info("Imported \(outcome.importedCount) feed(s), skipped \(outcome.skippedCount)")
        return outcome
    }

    /// `feed.feedURL` is sometimes a share link (Apple Podcasts/Spotify), not an actual RSS feed —
    /// resolve those by title through iTunes search; everything else is used as-is.
    private static func resolveFeedURL(_ feed: ImportedFeed) async -> URL? {
        let host = feed.feedURL.host ?? ""
        guard host.contains("podcasts.apple.com") || host.contains("open.spotify.com") else {
            return feed.feedURL
        }
        guard let title = feed.title else { return nil }
        let results = await iTunesSearchService.shared.searchPodcasts(query: title)
        return results.first?.feedURL
    }
}
