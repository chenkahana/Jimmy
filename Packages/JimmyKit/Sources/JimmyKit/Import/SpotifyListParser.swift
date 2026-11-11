import Foundation

/// Parses a Spotify-style plain-text list of feed URLs (one per line) into feeds JimmyKit
/// can import. Spotify exports carry no titles, so every feed's `title` is `nil`.
public nonisolated enum SpotifyListParser {
    public static func parse(data: Data) -> ImportResult {
        guard let text = String(data: data, encoding: .utf8) else {
            return ImportResult(feeds: [], skipped: [])
        }

        var candidates: [ImportedFeed] = []
        var skipped: [Skipped] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
                skipped.append(Skipped(reason: "invalid feed URL: \(trimmed)"))
                continue
            }
            candidates.append(ImportedFeed(feedURL: url, title: nil))
        }

        let (feeds, duplicateSkips) = FeedDeduplicator.deduplicate(candidates)
        return ImportResult(feeds: feeds, skipped: skipped + duplicateSkips)
    }
}
