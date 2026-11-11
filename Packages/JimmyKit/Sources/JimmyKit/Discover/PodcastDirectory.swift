import Foundation

/// A podcast returned by Apple's iTunes Search or Lookup API.
nonisolated public struct PodcastDirectoryResult: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let author: String
    public let feedURL: URL
    public let artworkURL: URL?
    public let description: String?
    public let genre: String
    public let trackCount: Int

    public init(
        id: Int,
        title: String,
        author: String,
        feedURL: URL,
        artworkURL: URL?,
        description: String?,
        genre: String,
        trackCount: Int
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.description = description
        self.genre = genre
        self.trackCount = trackCount
    }
}

/// One entry from Apple's "top podcasts" chart feed — id, name, artist and artwork only, ahead
/// of the fuller `lookup(ids:)` metadata (feed URL, description, genre, ...).
nonisolated public struct PodcastDirectoryChartEntry: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let artistName: String
    public let artworkURL: URL?

    public init(id: Int, name: String, artistName: String, artworkURL: URL?) {
        self.id = id
        self.name = name
        self.artistName = artistName
        self.artworkURL = artworkURL
    }
}

nonisolated public enum PodcastDirectoryError: Error, Sendable, Equatable {
    case invalidResponse
    case http(statusCode: Int)
}

/// Apple Podcasts search and top charts — the iTunes Search/Lookup API plus the marketing-tools
/// charts feed — for the Discover and Search screens and the Assistant's podcast search.
/// URLSession is injectable so tests can stub responses instead of hitting the network.
nonisolated public struct PodcastDirectory: Sendable {
    public static let timeout: TimeInterval = 15
    private static let chartsBaseURL = "https://rss.applemarketingtools.com/api/v2/us/podcasts"

    private let session: URLSession

    /// - Parameter session: Inject a session (e.g. one configured with a stub `URLProtocol`)
    ///   for testing. Defaults to a dedicated ephemeral session with `timeout` applied, not
    ///   `URLSession.shared`.
    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = Self.timeout
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Searches Apple's podcast directory for `query`. A Hebrew query tries the Israeli store
    /// first (podcasts there are indexed more reliably there than in the global store), falling
    /// back to the global store if that comes back empty.
    public func search(query: String) async throws -> [PodcastDirectoryResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let containsHebrew = trimmed.unicodeScalars.contains { (0x0590...0x05FF).contains($0.value) }

        var urlStrings = ["https://itunes.apple.com/search?term=\(encoded)&media=podcast&entity=podcast&limit=50"]
        if containsHebrew {
            urlStrings.insert(
                "https://itunes.apple.com/search?term=\(encoded)&media=podcast&entity=podcast&limit=50&country=IL",
                at: 0
            )
        }

        for urlString in urlStrings {
            guard let url = URL(string: urlString) else { continue }
            let results = try await fetchSearchResults(from: url)
            if !results.isEmpty {
                return results
            }
        }
        return []
    }

    /// Fetches the first `limit` entries of Apple's "top podcasts" chart (US store), in rank
    /// order, ahead of the richer `lookup(ids:)` metadata.
    public func topChartEntries(limit: Int = 50) async throws -> [PodcastDirectoryChartEntry] {
        guard let url = URL(string: "\(Self.chartsBaseURL)/top/\(limit)/podcasts.json") else {
            throw PodcastDirectoryError.invalidResponse
        }
        let (data, response) = try await session.data(from: url)
        try Self.validate(response)
        let decoded = try JSONDecoder().decode(AppleTopChartResponse.self, from: data)
        return decoded.feed.results.compactMap { result in
            guard let id = Int(result.id) else { return nil }
            return PodcastDirectoryChartEntry(
                id: id,
                name: result.name,
                artistName: result.artistName,
                artworkURL: Self.highResArtworkURL(from: result.artworkUrl100)
            )
        }
    }

    /// Looks up full metadata (feed URL, description, artwork, genre, ...) for podcasts by
    /// iTunes collection id.
    public func lookup(ids: [Int]) async throws -> [PodcastDirectoryResult] {
        guard !ids.isEmpty else { return [] }
        let idList = ids.map(String.init).joined(separator: ",")
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(idList)&entity=podcast") else {
            throw PodcastDirectoryError.invalidResponse
        }
        return try await fetchSearchResults(from: url)
    }

    // MARK: - Private

    private func fetchSearchResults(from url: URL) async throws -> [PodcastDirectoryResult] {
        let (data, response) = try await session.data(from: url)
        try Self.validate(response)
        let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        return decoded.results.compactMap { result in
            guard let feedURL = result.feedUrl.flatMap(URL.init(string:)) else { return nil }
            return PodcastDirectoryResult(
                id: result.collectionId,
                title: result.collectionName,
                author: result.artistName,
                feedURL: feedURL,
                artworkURL: Self.bestArtworkURL(result),
                description: result.description,
                genre: result.primaryGenreName,
                trackCount: result.trackCount
            )
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw PodcastDirectoryError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw PodcastDirectoryError.http(statusCode: http.statusCode) }
    }

    /// Upgrades a `100x100` artwork URL to `600x600` where possible.
    private static func highResArtworkURL(from artworkString: String?) -> URL? {
        guard let artworkString, !artworkString.isEmpty else { return nil }
        let highRes = artworkString
            .replacingOccurrences(of: "100x100", with: "600x600")
            .replacingOccurrences(of: "/100/", with: "/600/")
        return URL(string: highRes) ?? URL(string: artworkString)
    }

    private static func bestArtworkURL(_ result: ITunesPodcastResult) -> URL? {
        let candidates = [result.artworkUrl600, result.artworkUrl100, result.artworkUrl60, result.artworkUrl30, result.artworkUrl]
        for candidate in candidates {
            if let candidate, !candidate.isEmpty, let url = URL(string: candidate) {
                return url
            }
        }
        return nil
    }
}

// MARK: - Wire format (iTunes Search/Lookup API and the marketing-tools charts feed)

private nonisolated struct ITunesSearchResponse: Codable {
    let results: [ITunesPodcastResult]
}

private nonisolated struct ITunesPodcastResult: Codable {
    let collectionId: Int
    let artistName: String
    let collectionName: String
    let feedUrl: String?
    let artworkUrl30: String?
    let artworkUrl60: String?
    let artworkUrl100: String?
    let artworkUrl600: String?
    let artworkUrl: String?
    let trackCount: Int
    let primaryGenreName: String
    let description: String?
}

private nonisolated struct AppleTopChartResponse: Codable {
    let feed: AppleTopChartFeed
}

private nonisolated struct AppleTopChartFeed: Codable {
    let results: [AppleTopChartResultEntry]
}

private nonisolated struct AppleTopChartResultEntry: Codable {
    let id: String
    let name: String
    let artistName: String
    let artworkUrl100: String?
}
