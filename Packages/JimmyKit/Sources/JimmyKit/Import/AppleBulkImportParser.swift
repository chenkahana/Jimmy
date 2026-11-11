import Foundation

/// Parses an Apple-style bulk subscription export (a JSON array of shows) into feeds
/// JimmyKit can import.
public nonisolated enum AppleBulkImportParser {
    struct ExportedPodcast: Codable {
        let title: String
        let feedURL: String
        let author: String?

        enum CodingKeys: String, CodingKey {
            case title
            case feedURL = "feedUrl"
            case author
        }
    }

    /// - Throws: `ImportError.malformed` if the JSON cannot be decoded at all.
    public static func parse(data: Data) throws -> ImportResult {
        let exports: [ExportedPodcast]
        do {
            exports = try JSONDecoder().decode([ExportedPodcast].self, from: data)
        } catch {
            throw ImportError.malformed
        }

        var candidates: [ImportedFeed] = []
        var skipped: [Skipped] = []
        for item in exports {
            guard let url = URL(string: item.feedURL), url.scheme != nil, url.host != nil else {
                skipped.append(Skipped(reason: "invalid feed URL: \(item.feedURL)"))
                continue
            }
            candidates.append(ImportedFeed(feedURL: url, title: item.title))
        }

        let (feeds, duplicateSkips) = FeedDeduplicator.deduplicate(candidates)
        return ImportResult(feeds: feeds, skipped: skipped + duplicateSkips)
    }
}
