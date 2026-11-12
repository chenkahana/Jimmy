import CryptoKit
import Foundation

/// Spotify has no RSS, so everything from it arrives as names: shows by title and publisher,
/// episodes by title and show. `LibraryImport` looks the shows up in the podcast directory and
/// matches the episodes once their feeds are in.

// MARK: - Account data download (Settings > Account privacy > Download your data)

/// Reads the JSON files in Spotify's account data download: `YourLibrary.json` (saved shows and
/// episodes), `StreamingHistory_podcast_*.json` (the yearly history) and
/// `Streaming_History_Audio_*.json` (the extended history).
public nonisolated enum SpotifyDataExportParser {
    /// Whether `data` is one of the files above.
    public static func recognizes(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return false }
        if let library = json as? [String: Any] {
            return library["shows"] is [[String: Any]] || library["episodes"] is [[String: Any]]
        }
        if let entries = json as? [[String: Any]], let first = entries.first {
            return first["podcastName"] != nil || first["episode_show_name"] != nil
        }
        return false
    }

    /// - Throws: `ImportError.malformed` if `data` isn't one of the files above.
    public static func parse(data: Data) throws -> ImportResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { throw ImportError.malformed }
        if let library = json as? [String: Any] {
            return parseLibrary(library)
        }
        if let entries = json as? [[String: Any]] {
            return ImportResult(feeds: [], skipped: [], history: parseHistory(entries))
        }
        throw ImportError.malformed
    }

    private static func parseLibrary(_ library: [String: Any]) -> ImportResult {
        let shows = (library["shows"] as? [[String: Any]] ?? []).compactMap { show -> ImportedShowName? in
            guard let name = show["name"] as? String, !name.isEmpty else { return nil }
            return ImportedShowName(title: name, publisher: show["publisher"] as? String)
        }
        let saved = (library["episodes"] as? [[String: Any]] ?? []).compactMap { episode -> ImportedEpisodeState? in
            guard let name = episode["name"] as? String, let show = episode["show"] as? String else { return nil }
            return ImportedEpisodeState(podcastTitle: show, title: name, isQueued: true)
        }
        return ImportResult(feeds: [], skipped: [], showNames: shows, history: saved)
    }

    /// One entry per listening session, so time is summed per episode. Whether that adds up to
    /// played is decided once the episode's duration is known (see `ImportedEpisodeState.position`).
    private static func parseHistory(_ entries: [[String: Any]]) -> [ImportedEpisodeState] {
        var byEpisode: [String: ImportedEpisodeState] = [:]
        var order: [String] = []
        for entry in entries {
            let show = (entry["podcastName"] ?? entry["episode_show_name"]) as? String
            let title = (entry["episodeName"] ?? entry["episode_name"]) as? String
            guard let show, let title, !show.isEmpty, !title.isEmpty else { continue }
            let milliseconds = ((entry["msPlayed"] ?? entry["ms_played"]) as? NSNumber)?.doubleValue ?? 0
            let ended = ((entry["endTime"] ?? entry["ts"]) as? String).flatMap(ImportDates.parse)

            let key = TitleNormalizer.key(show) + "\u{1F}" + TitleNormalizer.key(title)
            var state = byEpisode[key] ?? ImportedEpisodeState(podcastTitle: show, title: title, position: 0)
            if byEpisode[key] == nil { order.append(key) }
            state.position = (state.position ?? 0) + milliseconds / 1000
            if let ended, ended > (state.updatedAt ?? .distantPast) { state.updatedAt = ended }
            byEpisode[key] = state
        }
        return order.compactMap { byEpisode[$0] }.filter { ($0.position ?? 0) >= 60 }
    }
}

// MARK: - Web API (sign in with Spotify)

/// Authorization Code with PKCE, which needs no client secret, and the two library endpoints:
/// `GET /v1/me/shows` and `GET /v1/me/episodes` (scopes `user-library-read` and
/// `user-read-playback-position`, the latter for `resume_point`).
public nonisolated struct SpotifyWebAPI: Sendable {
    public static let scopes = ["user-library-read", "user-read-playback-position"]

    public let clientID: String
    public let redirectURI: URL
    private let session: URLSession

    public init(clientID: String, redirectURI: URL, session: URLSession = .shared) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.session = session
    }

    /// A PKCE code verifier: 64 characters from the unreserved set.
    public static func makeCodeVerifier() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in alphabet.randomElement() ?? "a" })
    }

    /// `BASE64URL(SHA256(verifier))`, unpadded.
    public static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public func authorizationURL(codeChallenge: String, state: String) -> URL? {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
        ]
        return components?.url
    }

    /// The `code` from the redirect, if `state` matches.
    public func authorizationCode(from callback: URL, expectedState: String) -> String? {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == expectedState else { return nil }
        return items.first(where: { $0.name == "code" })?.value
    }

    /// Trades the authorization code for an access token.
    public func accessToken(code: String, codeVerifier: String) async throws -> String {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { throw ImportError.malformed }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, _) = try await session.data(for: request)
        struct Token: Decodable {
            let accessToken: String
            enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
        }
        guard let token = try? JSONDecoder().decode(Token.self, from: data) else { throw ImportError.malformed }
        return token.accessToken
    }

    /// Every saved show and saved episode, following `next` until the last page.
    public func library(accessToken: String) async throws -> ImportResult {
        var shows: [ImportedShowName] = []
        var episodes: [ImportedEpisodeState] = []
        var next = URL(string: "https://api.spotify.com/v1/me/shows?limit=50")
        while let url = next {
            let page = try SpotifyPages.shows(from: try await get(url, token: accessToken))
            shows += page.shows
            next = page.next
        }
        next = URL(string: "https://api.spotify.com/v1/me/episodes?limit=50")
        while let url = next {
            let page = try SpotifyPages.episodes(from: try await get(url, token: accessToken))
            episodes += page.episodes
            next = page.next
        }
        return ImportResult(feeds: [], skipped: [], showNames: shows, history: episodes)
    }

    private func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PodcastDirectoryError.http(statusCode: http.statusCode)
        }
        return data
    }
}

/// Decodes one page of `/v1/me/shows` or `/v1/me/episodes`.
public nonisolated enum SpotifyPages {
    private struct Page<Item: Decodable>: Decodable {
        let items: [Item]
        let next: String?
    }

    private struct Show: Decodable {
        let name: String
        let publisher: String?
    }

    private struct SavedShow: Decodable { let show: Show }

    private struct SavedEpisode: Decodable {
        struct Episode: Decodable {
            struct ResumePoint: Decodable {
                let fullyPlayed: Bool
                let resumePositionMS: Double

                enum CodingKeys: String, CodingKey {
                    case fullyPlayed = "fully_played"
                    case resumePositionMS = "resume_position_ms"
                }
            }

            let name: String
            let releaseDate: String?
            let resumePoint: ResumePoint?
            let show: Show?

            enum CodingKeys: String, CodingKey {
                case name, show
                case releaseDate = "release_date"
                case resumePoint = "resume_point"
            }
        }

        let episode: Episode?
    }

    public static func shows(from data: Data) throws -> (shows: [ImportedShowName], next: URL?) {
        guard let page = try? JSONDecoder().decode(Page<SavedShow>.self, from: data) else { throw ImportError.malformed }
        return (page.items.map { ImportedShowName(title: $0.show.name, publisher: $0.show.publisher) }, page.next.flatMap(URL.init(string:)))
    }

    public static func episodes(from data: Data) throws -> (episodes: [ImportedEpisodeState], next: URL?) {
        guard let page = try? JSONDecoder().decode(Page<SavedEpisode>.self, from: data) else { throw ImportError.malformed }
        let episodes = page.items.compactMap(\.episode).map { episode in
            ImportedEpisodeState(
                podcastTitle: episode.show?.name,
                title: episode.name,
                publishedDate: episode.releaseDate.flatMap(ImportDates.parse),
                position: episode.resumePoint.map { $0.resumePositionMS / 1000 },
                isPlayed: episode.resumePoint?.fullyPlayed ?? false,
                isQueued: !(episode.resumePoint?.fullyPlayed ?? false)
            )
        }
        return (episodes, page.next.flatMap(URL.init(string:)))
    }
}
