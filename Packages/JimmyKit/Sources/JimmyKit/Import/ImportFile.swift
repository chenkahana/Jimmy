import Foundation

/// Any file a podcast app exports, read without asking which app it came from: OPML (Overcast,
/// Pocket Casts, Castro and most others), Spotify's account data download, a Google Takeout
/// subscriptions file, an Apple bulk JSON, or plain text with feed and show links in it.
public nonisolated enum ImportFile {
    public enum Kind: Sendable, Equatable {
        case opml
        case spotifyDataExport
        case googleTakeout
        case appleBulkJSON
        case links
    }

    public static func kind(of data: Data) -> Kind? {
        let head = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        if head.contains("<opml") { return .opml }
        if SpotifyDataExportParser.recognizes(data) { return .spotifyDataExport }
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let object = json as? [String: Any], object["subscriptions"] != nil { return .googleTakeout }
            if let array = json as? [[String: Any]], array.first?["feedUrl"] != nil { return .appleBulkJSON }
            return nil
        }
        return LinkTextParser.parse(String(decoding: data, as: UTF8.self)).feeds.isEmpty ? nil : .links
    }

    /// - Throws: `ImportError.malformed` if the file isn't any of the kinds above.
    public static func parse(data: Data) throws -> ImportResult {
        switch kind(of: data) {
        case .opml: return try OPMLParser.parse(data: data)
        case .spotifyDataExport: return try SpotifyDataExportParser.parse(data: data)
        case .googleTakeout: return try GoogleTakeoutParser.parse(data: data)
        case .appleBulkJSON: return try AppleBulkImportParser.parse(data: data)
        case .links: return LinkTextParser.parse(String(decoding: data, as: UTF8.self))
        case nil: throw ImportError.malformed
        }
    }
}

/// Every link in a block of text: RSS feeds, Apple Podcasts show pages and Spotify show pages,
/// one per line or mixed into prose (a Shortcuts result, a note, a message). A line that is only
/// an Apple Podcasts id (what Shortcuts' Store ID gives) counts as that show's page.
public nonisolated enum LinkTextParser {
    public static func parse(_ text: String) -> ImportResult {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return ImportResult(feeds: [], skipped: [])
        }
        let range = NSRange(text.startIndex..., in: text)
        var candidates = detector.matches(in: text, range: range).compactMap { match -> ImportedFeed? in
            guard let url = match.url, let scheme = url.scheme?.lowercased(),
                  ["http", "https", "feed", "itpc", "pcast"].contains(scheme), url.host != nil else { return nil }
            return ImportedFeed(feedURL: url, title: nil)
        }
        candidates += text.components(separatedBy: CharacterSet(charactersIn: "\n,;")).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard (6...12).contains(trimmed.count), trimmed.allSatisfy(\.isASCIIDigit),
                  let url = URL(string: "https://podcasts.apple.com/podcast/id\(trimmed)") else { return nil }
            return ImportedFeed(feedURL: url, title: nil)
        }
        let (feeds, skipped) = FeedDeduplicator.deduplicate(candidates)
        return ImportResult(feeds: feeds, skipped: skipped)
    }
}

/// What a show link points at, when it isn't a feed itself.
public nonisolated enum ShowLink: Sendable, Equatable {
    /// `podcasts.apple.com/…/id1234567890`
    case apple(id: Int)
    /// `open.spotify.com/show/<id>`
    case spotify(URL)
    case feed(URL)

    public init(_ url: URL) {
        let host = url.host?.lowercased() ?? ""
        if host.hasSuffix("podcasts.apple.com") || host.hasSuffix("itunes.apple.com"),
           let idComponent = url.pathComponents.last(where: { $0.hasPrefix("id") }),
           let id = Int(idComponent.dropFirst(2)) {
            self = .apple(id: id)
        } else if host == "open.spotify.com", url.pathComponents.contains("show") {
            self = .spotify(url)
        } else {
            self = .feed(url)
        }
    }
}

private nonisolated extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
