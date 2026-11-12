import Foundation
import Testing
@testable import JimmyKit

/// The first-run import: Overcast's extended OPML, Spotify's data download and Web API pages,
/// file sniffing, and matching history back onto feed episodes.
struct OvercastExtendedOPMLTests {
    let opml = """
    <?xml version="1.0" encoding="utf-8"?>
    <opml version="1.0">
      <head><title>Overcast Podcast Subscriptions</title></head>
      <body>
        <outline text="feeds">
          <outline type="rss" overcastId="1" text="Planet Money" title="Planet Money" xmlUrl="https://feeds.npr.org/510289/podcast.xml" subscribed="1">
            <outline type="podcast-episode" overcastId="11" pubDate="2026-10-01T05:00:00-04:00" title="The Fed, Explained" url="https://www.npr.org/1" overcastUrl="https://overcast.fm/+abc" enclosureUrl="https://dts.podtrac.com/redirect.mp3/traffic.megaphone.fm/NPR111.mp3" userUpdatedDate="2026-10-02T08:00:00-04:00" played="1"/>
            <outline type="podcast-episode" overcastId="12" pubDate="2026-10-08T05:00:00-04:00" title="Tariffs, Again" url="https://www.npr.org/2" enclosureUrl="https://traffic.megaphone.fm/NPR222.mp3" userUpdatedDate="2026-10-09T08:00:00-04:00" progress="754"/>
            <outline type="podcast-episode" overcastId="13" pubDate="2026-10-15T05:00:00-04:00" title="Untouched" url="https://www.npr.org/3" enclosureUrl="https://traffic.megaphone.fm/NPR333.mp3"/>
          </outline>
          <outline type="rss" text="Left Show" xmlUrl="https://example.com/left.xml" subscribed="0">
            <outline type="podcast-episode" title="Old" url="https://example.com/old" played="1"/>
          </outline>
        </outline>
      </body>
    </opml>
    """

    @Test func subscribedFeedsOnly() throws {
        let result = try OPMLParser.parse(data: Data(opml.utf8))
        #expect(result.feeds.map(\.title) == ["Planet Money"])
    }

    @Test func episodeOutlinesAreHistoryNotFeeds() throws {
        let result = try OPMLParser.parse(data: Data(opml.utf8))
        #expect(!result.feeds.contains { $0.feedURL.host == "www.npr.org" })
        #expect(result.history.count == 2)

        let played = try #require(result.history.first)
        #expect(played.title == "The Fed, Explained")
        #expect(played.isPlayed)
        #expect(played.feedURL?.absoluteString == "https://feeds.npr.org/510289/podcast.xml")
        #expect(played.publishedDate != nil)
        #expect(played.updatedAt != nil)

        let started = result.history[1]
        #expect(!started.isPlayed)
        #expect(started.position == 754)
        #expect(started.isInProgress)
    }

    @Test func plainOPMLHasNoHistory() throws {
        let plain = """
        <opml version="2.0"><body><outline text="A" type="rss" xmlUrl="https://example.com/a.xml"/></body></opml>
        """
        let result = try OPMLParser.parse(data: Data(plain.utf8))
        #expect(result.feeds.count == 1)
        #expect(result.history.isEmpty)
    }
}

struct EpisodeMatcherTests {
    let published = Date(timeIntervalSince1970: 1_790_000_000)

    func episode(_ title: String, audio: String?, published: Date? = nil) -> Episode {
        Episode(title: title, audioURL: audio.flatMap(URL.init(string:)), publishedDate: published, duration: 1800)
    }

    @Test func matchesThroughTrackingPrefixes() {
        let target = episode("Something Else", audio: "https://chtbl.com/track/X1/pdst.fm/e/traffic.megaphone.fm/NPR111.mp3?updated=1")
        let state = ImportedEpisodeState(title: "The Fed", enclosureURL: URL(string: "https://dts.podtrac.com/redirect.mp3/traffic.megaphone.fm/NPR111.mp3"))
        #expect(EpisodeMatcher.match(state, in: [episode("Other", audio: "https://traffic.megaphone.fm/NPR999.mp3"), target]) == target)
    }

    @Test func enclosureKeyIgnoresWWWAndQuery() {
        let a = EpisodeMatcher.enclosureKey(URL(string: "https://www.example.com/ep/1.mp3?x=1")!)
        let b = EpisodeMatcher.enclosureKey(URL(string: "http://example.com/ep/1.mp3")!)
        #expect(a == b)
    }

    @Test func fallsBackToTitleNearTheDate() {
        let rerun = episode("Best Of: The Fed", audio: nil, published: published.addingTimeInterval(-400 * 86400))
        let target = episode("The Fed, Explained!", audio: nil, published: published.addingTimeInterval(3600))
        let state = ImportedEpisodeState(title: "the fed explained", publishedDate: published)
        #expect(EpisodeMatcher.match(state, in: [rerun, target]) == target)
    }

    @Test func ambiguousTitleWithoutDateIsNoMatch() {
        let first = episode("Trailer", audio: nil)
        let second = episode("Trailer", audio: nil)
        #expect(EpisodeMatcher.match(ImportedEpisodeState(title: "Trailer"), in: [first, second]) == nil)
        #expect(EpisodeMatcher.match(ImportedEpisodeState(title: "Trailer"), in: [first]) == first)
    }
}

extension EpisodeMatcherTests {
    @Test func sharedEnclosureKeyFallsBackToTitle() {
        let first = episode("One", audio: "https://example.com/download.php?id=1")
        let second = episode("Two", audio: "https://example.com/download.php?id=2")
        let state = ImportedEpisodeState(title: "Two", enclosureURL: URL(string: "https://example.com/download.php?id=2"))
        #expect(EpisodeMatcher.match(state, in: [first, second]) == second)
    }
}

struct DirectoryMatcherTests {
    func result(_ id: Int, _ title: String, _ author: String) -> PodcastDirectoryResult {
        PodcastDirectoryResult(
            id: id, title: title, author: author,
            feedURL: URL(string: "https://example.com/\(id).xml")!,
            artworkURL: nil, description: nil, genre: "News", trackCount: 10
        )
    }

    @Test func prefersExactTitleFromSamePublisher() {
        let results = [result(1, "The Daily Show", "Comedy Central"), result(2, "The Daily", "Someone Else"), result(3, "The Daily", "The New York Times")]
        let match = DirectoryMatcher.bestMatch(for: ImportedShowName(title: "The Daily", publisher: "The New York Times"), in: results)
        #expect(match?.id == 3)
    }

    @Test func looseTitleNeedsPublisher() {
        let results = [result(1, "Hard Fork: Tech News", "The New York Times")]
        #expect(DirectoryMatcher.bestMatch(for: ImportedShowName(title: "Hard Fork", publisher: "The New York Times"), in: results)?.id == 1)
        #expect(DirectoryMatcher.bestMatch(for: ImportedShowName(title: "Hard Fork", publisher: nil), in: results) == nil)
    }
}

struct SpotifyImportTests {
    @Test func dataDownloadLibrary() throws {
        let json = """
        {"tracks": [], "shows": [{"name": "Hard Fork", "publisher": "The New York Times", "uri": "spotify:show:1"}],
         "episodes": [{"name": "A.I. Week", "show": "Hard Fork", "uri": "spotify:episode:2"}]}
        """
        let data = Data(json.utf8)
        #expect(ImportFile.kind(of: data) == .spotifyDataExport)
        let result = try ImportFile.parse(data: data)
        #expect(result.showNames == [ImportedShowName(title: "Hard Fork", publisher: "The New York Times")])
        #expect(result.history.first?.isQueued == true)
        #expect(result.history.first?.podcastTitle == "Hard Fork")
    }

    @Test func streamingHistorySumsSessionsAndDropsSamples() throws {
        let json = """
        [{"endTime": "2026-09-01 08:00", "podcastName": "Hard Fork", "episodeName": "A.I. Week", "msPlayed": 600000},
         {"endTime": "2026-09-02 08:00", "podcastName": "Hard Fork", "episodeName": "A.I. Week", "msPlayed": 900000},
         {"endTime": "2026-09-03 08:00", "podcastName": "Hard Fork", "episodeName": "Skipped", "msPlayed": 5000}]
        """
        let result = try SpotifyDataExportParser.parse(data: Data(json.utf8))
        #expect(result.history.count == 1)
        #expect(result.history[0].position == 1500)
    }

    @Test func extendedStreamingHistory() throws {
        let json = """
        [{"ts": "2026-09-01T08:00:00Z", "ms_played": 120000, "episode_name": "Ep", "episode_show_name": "Show", "master_metadata_track_name": null}]
        """
        let data = Data(json.utf8)
        #expect(SpotifyDataExportParser.recognizes(data))
        #expect(try SpotifyDataExportParser.parse(data: data).history.first?.updatedAt != nil)
    }

    @Test func webAPIPages() throws {
        let shows = """
        {"items": [{"added_at": "2026-01-01T00:00:00Z", "show": {"name": "Search Engine", "publisher": "PJ Vogt"}}],
         "next": "https://api.spotify.com/v1/me/shows?offset=50&limit=50"}
        """
        let showPage = try SpotifyPages.shows(from: Data(shows.utf8))
        #expect(showPage.shows == [ImportedShowName(title: "Search Engine", publisher: "PJ Vogt")])
        #expect(showPage.next != nil)

        let episodes = """
        {"items": [
          {"episode": {"name": "Halfway", "release_date": "2026-09-01", "duration_ms": 3600000,
                       "resume_point": {"fully_played": false, "resume_position_ms": 1800000},
                       "show": {"name": "Search Engine", "publisher": "PJ Vogt"}}},
          {"episode": {"name": "Done", "release_date": "2026-08-01",
                       "resume_point": {"fully_played": true, "resume_position_ms": 0},
                       "show": {"name": "Search Engine", "publisher": "PJ Vogt"}}}
        ], "next": null}
        """
        let episodePage = try SpotifyPages.episodes(from: Data(episodes.utf8))
        #expect(episodePage.next == nil)
        #expect(episodePage.episodes[0].position == 1800)
        #expect(episodePage.episodes[0].isQueued)
        #expect(episodePage.episodes[1].isPlayed)
        #expect(!episodePage.episodes[1].isQueued)
    }

    @Test func pkceChallengeMatchesRFC7636() {
        #expect(SpotifyWebAPI.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let verifier = SpotifyWebAPI.makeCodeVerifier()
        #expect(verifier.count == 64)
    }

    @Test func authorizationRoundTrip() throws {
        let api = SpotifyWebAPI(clientID: "abc", redirectURI: URL(string: "jimmy://spotify-callback")!)
        let url = try #require(api.authorizationURL(codeChallenge: "xyz", state: "s1"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "code_challenge_method" }?.value == "S256")
        #expect(items.first { $0.name == "scope" }?.value == "user-library-read user-read-playback-position")

        #expect(api.authorizationCode(from: URL(string: "jimmy://spotify-callback?code=C&state=s1")!, expectedState: "s1") == "C")
        #expect(api.authorizationCode(from: URL(string: "jimmy://spotify-callback?code=C&state=evil")!, expectedState: "s1") == nil)
    }
}

struct ImportFileTests {
    @Test func sniffsEachKind() {
        #expect(ImportFile.kind(of: Data("<?xml version=\"1.0\"?><opml><body/></opml>".utf8)) == .opml)
        #expect(ImportFile.kind(of: Data(#"{"subscriptions": []}"#.utf8)) == .googleTakeout)
        #expect(ImportFile.kind(of: Data(#"[{"title": "A", "feedUrl": "https://e.com/a.xml"}]"#.utf8)) == .appleBulkJSON)
        #expect(ImportFile.kind(of: Data("https://example.com/feed.xml\n".utf8)) == .links)
        #expect(ImportFile.kind(of: Data("hello".utf8)) == nil)
        #expect(throws: ImportError.malformed) { try ImportFile.parse(data: Data("hello".utf8)) }
    }

    @Test func linksInProse() {
        let text = """
        My shows: https://podcasts.apple.com/us/podcast/the-daily/id1200361736 and
        https://open.spotify.com/show/2mTUnDkuKUkhiueKcVWoP0?si=1, plus feed://example.com/rss
        and again https://podcasts.apple.com/us/podcast/the-daily/id1200361736
        """
        let feeds = LinkTextParser.parse(text).feeds
        #expect(feeds.count == 3)
        #expect(ShowLink(feeds[0].feedURL) == .apple(id: 1_200_361_736))
        if case .spotify = ShowLink(feeds[1].feedURL) {} else { Issue.record("expected a Spotify show link") }
        #expect(ShowLink(feeds[2].feedURL) == .feed(URL(string: "https://example.com/rss")!))
    }

    @Test func mergeDeduplicates() throws {
        let a = ImportResult(feeds: [ImportedFeed(feedURL: URL(string: "https://e.com/a.xml")!, title: "A")], skipped: [], showNames: [ImportedShowName(title: "S", publisher: nil)])
        let b = ImportResult(feeds: [ImportedFeed(feedURL: URL(string: "https://E.com/a.xml/")!, title: "A")], skipped: [], showNames: [ImportedShowName(title: "s", publisher: "P")])
        let merged = a.merged(with: b)
        #expect(merged.feeds.count == 1)
        #expect(merged.showNames.count == 1)
        #expect(merged.skipped.count == 1)
    }
}

struct HistoryPlanTests {
    @Test func playedProgressAndQueue() {
        let done = Episode(title: "Done", duration: 1000)
        let half = Episode(title: "Half", duration: 1000)
        let almost = Episode(title: "Almost", duration: 1000)
        let saved = Episode(title: "Saved", duration: 1000)
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        let plan = HistoryPlan.make(states: [
            ImportedEpisodeState(title: "Done", isPlayed: true),
            ImportedEpisodeState(title: "Half", position: 500, updatedAt: older),
            ImportedEpisodeState(title: "Almost", position: 990),
            ImportedEpisodeState(title: "Saved", updatedAt: newer, isQueued: true),
            ImportedEpisodeState(title: "Missing", isPlayed: true),
            ImportedEpisodeState(title: "Done", isPlayed: true),
        ], episodes: [done, half, almost, saved])

        #expect(plan.playedCount == 2)
        #expect(plan.inProgressCount == 1)
        #expect(plan.unmatchedCount == 1)
        #expect(plan.queue.map(\.episodeID) == [saved.id, half.id])
        #expect(plan.actions.contains(.markPlayed(almost.id)))
        #expect(plan.actions.contains { if case .saveProgress(let p) = $0 { p.episodeID == half.id && p.position == 500 } else { false } })
    }
}

extension HistoryPlanTests {
    @Test func savedEpisodePlusStreamingHistoryCombine() {
        let episode = Episode(title: "A.I. Week", duration: 3480)
        let plan = HistoryPlan.make(states: [
            ImportedEpisodeState(podcastTitle: "Hard Fork", title: "A.I. Week", isQueued: true),
            ImportedEpisodeState(podcastTitle: "Hard Fork", title: "A.I. Week", position: 3400),
        ], episodes: [episode])
        #expect(plan.actions == [.markPlayed(episode.id)])
        #expect(plan.queue.isEmpty)
    }

    @Test func newerOrFinishedJimmyProgressWins() {
        let finished = Episode(title: "Finished", duration: 1000)
        let newer = Episode(title: "Newer", duration: 1000)
        let older = Episode(title: "Older", duration: 1000)
        let imported = Date(timeIntervalSince1970: 1_000)
        let existing: [UUID: JimmyKit.Progress] = [
            finished.id: JimmyKit.Progress(episodeID: finished.id, position: 0, isFinished: true, updatedAt: .distantPast),
            newer.id: JimmyKit.Progress(episodeID: newer.id, position: 700, updatedAt: Date(timeIntervalSince1970: 2_000)),
            older.id: JimmyKit.Progress(episodeID: older.id, position: 100, updatedAt: Date(timeIntervalSince1970: 500)),
        ]
        let plan = HistoryPlan.make(states: [
            ImportedEpisodeState(title: "Finished", position: 200, updatedAt: imported),
            ImportedEpisodeState(title: "Newer", position: 200, updatedAt: imported),
            ImportedEpisodeState(title: "Older", position: 200, updatedAt: imported),
        ], episodes: [finished, newer, older], existing: existing)
        #expect(plan.inProgressCount == 1)
        #expect(plan.queue.map(\.episodeID) == [older.id])
    }
}
