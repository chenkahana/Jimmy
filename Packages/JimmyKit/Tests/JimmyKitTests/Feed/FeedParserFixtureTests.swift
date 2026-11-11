import Foundation
import Testing
@testable import JimmyKit

/// Parses every non-malformed fixture and checks it against the item-count /
/// playable-enclosure-count row in `Tests/Fixtures/Feeds/README.md`.
///
/// Policy this assumes (see `FeedParser`'s doc comment): items without a playable
/// enclosure are KEPT with `audioURL == nil`, so "item count" is `episodes.count` and
/// "playable enclosures" is `episodes.filter { $0.audioURL != nil }.count`.
struct FeedParserFixtureTests {
    @Test(arguments: FeedFixtures.expectations)
    func fixtureMatchesExpectedCounts(_ expectation: FeedFixtures.Expectation) throws {
        let data = try FeedFixtures.data(expectation.filename)
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)

        #expect(parsed.episodes.count == expectation.itemCount, "item count for \(expectation.filename)")
        #expect(
            parsed.episodes.filter { $0.audioURL != nil }.count == expectation.playableCount,
            "playable-enclosure count for \(expectation.filename)"
        )
    }

    @Test func allEpisodesStampedWithPodcastID() throws {
        let data = try FeedFixtures.data("01_apple_style_itunes_duration_hh_mm_ss.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes.allSatisfy { $0.podcastID == FeedFixtures.samplePodcastID })
    }

    // MARK: - Durations

    @Test func durationsHHMMSS() throws {
        let data = try FeedFixtures.data("01_apple_style_itunes_duration_hh_mm_ss.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        let durations = parsed.episodes.map { $0.duration }
        #expect(durations == [5445, 8130, 2720]) // 01:30:45, 02:15:30, 00:45:20
    }

    @Test func durationsSeconds() throws {
        let data = try FeedFixtures.data("02_apple_style_itunes_duration_seconds.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes.map { $0.duration } == [3600, 2400])
    }

    @Test func durationsMMSS() throws {
        let data = try FeedFixtures.data("03_apple_style_itunes_duration_mm_ss.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes.map { $0.duration } == [2520, 4320]) // 42:00, 72:00
    }

    // MARK: - Dates

    @Test func rfc822OddTimezones() throws {
        let data = try FeedFixtures.data("19_rfc822_dates_odd_timezones.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        let dates = parsed.episodes.map { $0.publishedDate }

        #expect(dates[0] == utcDate(2024, 1, 24, 7, 0, 0))  // +0300 -> 07:00 UTC
        #expect(dates[1] == utcDate(2024, 1, 31, 21, 0, 0)) // PDT (UTC-7) -> 21:00 UTC
        #expect(dates[2] == utcDate(2024, 2, 2, 12, 0, 0))  // GMT
    }

    @Test func nonRFC822DateFormats() throws {
        let data = try FeedFixtures.data("20_non_rfc_date_formats.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        let dates = parsed.episodes.map { $0.publishedDate }

        #expect(dates[0] == utcDate(2024, 1, 25, 0, 0, 0))  // "2024-01-25"
        #expect(dates[1] == utcDate(2024, 1, 25, 0, 0, 0))  // "January 25, 2024"
        #expect(dates[2] == utcDate(2024, 2, 2, 10, 0, 0))  // "Fri, 2 Feb 2024 10:00"
    }

    @Test func missingPubDateIsNilNotCrash() throws {
        let data = try FeedFixtures.data("21_missing_pubdate.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes[0].publishedDate != nil)
        #expect(parsed.episodes[1].publishedDate == nil)
        #expect(parsed.episodes[2].publishedDate != nil)
    }

    // MARK: - Text handling

    @Test func hebrewTitlesAndDescriptionsPreservedExactly() throws {
        let data = try FeedFixtures.data("12_hebrew_titles_descriptions.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes[0].title == "פרק 1: התחלה")
        #expect(parsed.episodes[0].description == "ברוכים הבאים לפודקאסט שלנו")
        #expect(parsed.episodes[1].title == "פרק 2: דיון עמוק")
        #expect(parsed.podcast.title == "פודקאסט ישראלי")
    }

    @Test func emojiAndHTMLEntitiesDecoded() throws {
        let data = try FeedFixtures.data("13_emoji_html_entities.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes[0].title == "🚀 Episode 1: Launch & Learn ✨")
        #expect(parsed.episodes[1].title == "🎯 Episode 2: Target & Achieve 💪")
        #expect(parsed.podcast.title == "🎙️ Podcast & Friends")
    }

    @Test func cdataDescriptionsCaptureEmbeddedHTMLVerbatim() throws {
        let data = try FeedFixtures.data("14_cdata_descriptions_with_html.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        let description = try #require(parsed.episodes[0].description)
        #expect(description.contains("<strong>rich HTML content</strong>"))
        #expect(description.contains("<li>Point one</li>"))
    }

    @Test func contentEncodedPreferredOverPlainDescription() throws {
        let data = try FeedFixtures.data("04_libsyn_style_basic.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes[0].description == "<p>Welcome to our first episode.</p>")
        #expect(parsed.episodes[1].description == "<p>In this episode we learn about podcasting.</p>")
    }

    // MARK: - GUIDs

    @Test func duplicateGUIDsStillProduceDistinctEpisodes() throws {
        let data = try FeedFixtures.data("17_duplicate_guids.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes.count == 3)
        #expect(Set(parsed.episodes.map(\.id)).count == 3)
    }

    @Test func missingGUIDsStillParseViaLink() throws {
        let data = try FeedFixtures.data("18_no_guids_link_only.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes.count == 3)
        #expect(parsed.episodes.allSatisfy { $0.audioURL != nil })
    }

    // MARK: - Missing enclosures

    @Test func itemsWithoutEnclosureAreKeptWithNilAudioURL() throws {
        let data = try FeedFixtures.data("15_missing_enclosure_on_some_items.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes.count == 3)
        #expect(parsed.episodes[0].audioURL != nil)
        #expect(parsed.episodes[1].audioURL == nil)
        #expect(parsed.episodes[2].audioURL != nil)
    }

    @Test func enclosuresWithoutLengthOrTypeStillPlayable() throws {
        let data = try FeedFixtures.data("16_enclosure_without_length_type.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes.allSatisfy { $0.audioURL != nil })
    }

    // MARK: - Atom

    @Test func atomFeedParsesEntriesAsEpisodes() throws {
        let data = try FeedFixtures.data("23_atom_style_feed.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes.count == 2)
        #expect(parsed.episodes[0].title == "Episode 1: Atom Introduction")
        #expect(parsed.episodes[0].audioURL == URL(string: "https://example.com/episodes/001.mp3"))
        #expect(parsed.episodes[0].description == "Welcome to our Atom-formatted show")
        #expect(parsed.episodes[0].publishedDate == utcDate(2024, 1, 27, 10, 0, 0))
        #expect(parsed.podcast.title == "Atom Example Show")
    }

    // MARK: - itunes:new-feed-url

    @Test func newFeedURLCaptured() throws {
        let data = try FeedFixtures.data("24_itunes_new_feed_url_redirect.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.podcast.newFeedURL == URL(string: "https://example.com/new-feed-url"))
        #expect(parsed.episodes.count == 2)
    }

    // MARK: - Transcript / chapters

    @Test func transcriptAndChaptersURLsCaptured() throws {
        let data = try FeedFixtures.data("11_transistor_with_transcript_chapters.xml")
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        #expect(parsed.episodes.count == 2)

        for episode in parsed.episodes {
            let transcript = try #require(parsed.transcripts[episode.id])
            #expect(transcript.format == .vtt)
            #expect(transcript.url.absoluteString.hasSuffix("-transcript.vtt"))

            let chaptersURL = try #require(parsed.chaptersURLs[episode.id])
            #expect(chaptersURL.absoluteString.hasSuffix("-chapters.json"))
        }
    }

    // MARK: - Malformed XML

    @Test func malformedXMLThrowsAndDiscardsEverything() throws {
        let data = try FeedFixtures.data("22_malformed_xml_unclosed_tag.xml")
        #expect(throws: FeedError.self) {
            _ = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        }
    }

    // MARK: - Performance

    @Test func largeFeedParsesWellUnderTwoSeconds() throws {
        let data = try FeedFixtures.data("25_large_feed_2000_items.xml")

        let start = ContinuousClock.now
        let parsed = try FeedParser.parse(data: data, podcastID: FeedFixtures.samplePodcastID, feedURL: FeedFixtures.sampleFeedURL)
        let elapsed = ContinuousClock.now - start

        #expect(parsed.episodes.count == 2000)
        #expect(elapsed < .seconds(2))
    }
}

private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: components)!
}
