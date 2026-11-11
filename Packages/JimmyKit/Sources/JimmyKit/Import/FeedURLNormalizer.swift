import Foundation

/// Comparison keys and de-duplication for feed URLs discovered during import.
///
/// Two URLs are considered the same feed when they agree after: lowercasing the scheme
/// and host, dropping a trailing slash from the path, and treating `feed://`, `itpc://`,
/// and `pcast://` as `https://`.
public nonisolated enum FeedURLNormalizer {
    /// `url` with a `feed://`, `itpc://` or `pcast://` scheme replaced by `https://`, so it can be fetched.
    public static func fetchableURL(for url: URL) -> URL {
        guard let scheme = url.scheme?.lowercased(), ["feed", "itpc", "pcast"].contains(scheme),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        return components.url ?? url
    }

    static func key(for url: URL) -> String {
        var scheme = (url.scheme ?? "").lowercased()
        switch scheme {
        case "feed", "itpc", "pcast":
            scheme = "https"
        default:
            break
        }

        let host = (url.host ?? "").lowercased()

        var path = url.path
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }

        var key = "\(scheme)://\(host)"
        if let port = url.port {
            key += ":\(port)"
        }
        key += path
        if let query = url.query, !query.isEmpty {
            key += "?\(query)"
        }
        return key
    }
}

/// De-duplicates candidate feeds by their normalized URL, recording every duplicate past
/// the first as a `Skipped` entry rather than silently dropping it.
nonisolated enum FeedDeduplicator {
    static func deduplicate(_ candidates: [ImportedFeed]) -> (feeds: [ImportedFeed], skipped: [Skipped]) {
        var seenKeys = Set<String>()
        var feeds: [ImportedFeed] = []
        var skipped: [Skipped] = []
        for feed in candidates {
            let key = FeedURLNormalizer.key(for: feed.feedURL)
            if seenKeys.insert(key).inserted {
                feeds.append(ImportedFeed(feedURL: FeedURLNormalizer.fetchableURL(for: feed.feedURL), title: feed.title))
            } else {
                skipped.append(Skipped(reason: "duplicate feed: \(feed.feedURL.absoluteString)"))
            }
        }
        return (feeds, skipped)
    }
}
