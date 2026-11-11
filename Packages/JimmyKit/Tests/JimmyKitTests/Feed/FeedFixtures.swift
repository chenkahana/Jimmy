import Foundation

/// Shared helpers for locating the RSS fixture files under `Tests/Fixtures/Feeds` at
/// the repo root. We read them straight off disk via a `#filePath`-relative URL rather
/// than through SPM resources, per the PR's testing approach.
enum FeedFixtures {
    /// `Tests/Fixtures/Feeds` at the repo root, resolved relative to this source file's
    /// own location so it works regardless of the current working directory.
    static let directory: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FeedFixtures.swift -> Feed/
            .deletingLastPathComponent() // Feed/ -> JimmyKitTests/
            .deletingLastPathComponent() // JimmyKitTests/ -> Tests/
            .deletingLastPathComponent() // Tests/ -> JimmyKit/
            .deletingLastPathComponent() // JimmyKit/ -> Packages/
            .deletingLastPathComponent() // Packages/ -> repo root
            .appendingPathComponent("Tests/Fixtures/Feeds", isDirectory: true)
    }()

    static func url(_ filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    static func data(_ filename: String) throws -> Data {
        try Data(contentsOf: url(filename))
    }

    /// One row of the `Tests/Fixtures/Feeds/README.md` index table.
    struct Expectation {
        let filename: String
        let itemCount: Int
        let playableCount: Int
    }

    /// Every non-malformed fixture's expected item count / playable-enclosure count,
    /// transcribed from the README table. Fixture 22 (intentionally malformed) and
    /// fixture 25 (performance — asserted separately) are not in this table.
    static let expectations: [Expectation] = [
        .init(filename: "01_apple_style_itunes_duration_hh_mm_ss.xml", itemCount: 3, playableCount: 3),
        .init(filename: "02_apple_style_itunes_duration_seconds.xml", itemCount: 2, playableCount: 2),
        .init(filename: "03_apple_style_itunes_duration_mm_ss.xml", itemCount: 2, playableCount: 2),
        .init(filename: "04_libsyn_style_basic.xml", itemCount: 2, playableCount: 2),
        .init(filename: "05_libsyn_style_with_analytics.xml", itemCount: 2, playableCount: 2),
        .init(filename: "06_megaphone_style_uuid_guids.xml", itemCount: 2, playableCount: 2),
        .init(filename: "07_megaphone_with_ad_markers.xml", itemCount: 2, playableCount: 2),
        .init(filename: "08_anchor_spotify_style.xml", itemCount: 2, playableCount: 2),
        .init(filename: "09_buzzsprout_style.xml", itemCount: 2, playableCount: 2),
        .init(filename: "10_simplecast_style.xml", itemCount: 2, playableCount: 2),
        .init(filename: "11_transistor_with_transcript_chapters.xml", itemCount: 2, playableCount: 2),
        .init(filename: "12_hebrew_titles_descriptions.xml", itemCount: 2, playableCount: 2),
        .init(filename: "13_emoji_html_entities.xml", itemCount: 2, playableCount: 2),
        .init(filename: "14_cdata_descriptions_with_html.xml", itemCount: 2, playableCount: 2),
        .init(filename: "15_missing_enclosure_on_some_items.xml", itemCount: 3, playableCount: 2),
        .init(filename: "16_enclosure_without_length_type.xml", itemCount: 3, playableCount: 3),
        .init(filename: "17_duplicate_guids.xml", itemCount: 3, playableCount: 3),
        .init(filename: "18_no_guids_link_only.xml", itemCount: 3, playableCount: 3),
        .init(filename: "19_rfc822_dates_odd_timezones.xml", itemCount: 3, playableCount: 3),
        .init(filename: "20_non_rfc_date_formats.xml", itemCount: 3, playableCount: 3),
        .init(filename: "21_missing_pubdate.xml", itemCount: 3, playableCount: 3),
        .init(filename: "23_atom_style_feed.xml", itemCount: 2, playableCount: 2),
        .init(filename: "24_itunes_new_feed_url_redirect.xml", itemCount: 2, playableCount: 2),
    ]

    static let sampleFeedURL = URL(string: "https://example.com/feed.xml")!
    static let samplePodcastID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
}
