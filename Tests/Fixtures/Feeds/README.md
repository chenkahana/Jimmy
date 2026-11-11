# RSS Feed Fixtures

This directory contains 25 synthetic RSS feed XML files, each designed to test specific parsing scenarios. All fixtures use realistic structure and placeholder content (example.com URLs, synthetic titles/descriptions).

## Feed Index

| # | Filename | What it Tests | Item Count | Playable Enclosures |
|---|----------|---------------|------------|---------------------|
| 1 | `01_apple_style_itunes_duration_hh_mm_ss.xml` | Apple Podcasts format with `itunes:duration` in HH:MM:SS | 3 | 3 |
| 2 | `02_apple_style_itunes_duration_seconds.xml` | Apple format with duration in seconds | 2 | 2 |
| 3 | `03_apple_style_itunes_duration_mm_ss.xml` | Apple format with duration in MM:SS | 2 | 2 |
| 4 | `04_libsyn_style_basic.xml` | Libsyn hosting with content:encoded | 2 | 2 |
| 5 | `05_libsyn_style_with_analytics.xml` | Libsyn with tracking codes in descriptions | 2 | 2 |
| 6 | `06_megaphone_style_uuid_guids.xml` | Megaphone format with UUID-style GUIDs | 2 | 2 |
| 7 | `07_megaphone_with_ad_markers.xml` | Megaphone with ad markers in descriptions | 2 | 2 |
| 8 | `08_anchor_spotify_style.xml` | Anchor/Spotify Podcasts format | 2 | 2 |
| 9 | `09_buzzsprout_style.xml` | Buzzsprout hosting with m4a enclosures | 2 | 2 |
| 10 | `10_simplecast_style.xml` | Simplecast hosting format | 2 | 2 |
| 11 | `11_transistor_with_transcript_chapters.xml` | Transistor with `podcast:transcript` and `podcast:chapters` | 2 | 2 |
| 12 | `12_hebrew_titles_descriptions.xml` | Hebrew titles and descriptions (RTL text) | 2 | 2 |
| 13 | `13_emoji_html_entities.xml` | Emoji and HTML entities in titles | 2 | 2 |
| 14 | `14_cdata_descriptions_with_html.xml` | CDATA descriptions containing HTML | 2 | 2 |
| 15 | `15_missing_enclosure_on_some_items.xml` | Some items without enclosure tags | 3 | 2 |
| 16 | `16_enclosure_without_length_type.xml` | Enclosures missing length and type attributes | 3 | 3 |
| 17 | `17_duplicate_guids.xml` | Duplicate GUIDs across items | 3 | 3 |
| 18 | `18_no_guids_link_only.xml` | No GUID elements, link-based identification | 3 | 3 |
| 19 | `19_rfc822_dates_odd_timezones.xml` | RFC 822 dates with unusual timezone formats | 3 | 3 |
| 20 | `20_non_rfc_date_formats.xml` | Non-RFC date formats (ISO, long form, abbreviated) | 3 | 3 |
| 21 | `21_missing_pubdate.xml` | Some items missing pubDate element | 3 | 3 |
| 22 | `22_malformed_xml_unclosed_tag.xml` | Intentional XML malformation (unclosed tag) | 2 | 2 |
| 23 | `23_atom_style_feed.xml` | Atom feed format instead of RSS 2.0 | 2 | 2 |
| 24 | `24_itunes_new_feed_url_redirect.xml` | Feed with `itunes:new-feed-url` migration indicator | 2 | 2 |
| 25 | `25_large_feed_2000_items.xml` | Large feed for performance testing | 2000 | 2000 |

## Notes

- **Enclosure Type**: "Playable enclosures" counts items with a valid `<enclosure>` tag containing a `url` attribute with a `.mp3` or `.m4a` file.
- **Date Encoding**: Dates use RFC 822 format where valid, or intentional non-RFC formats as noted.
- **Hebrew Content**: Feed #12 uses real Hebrew words ("פרק" = chapter, "דיון" = discussion) as realistic placeholders.
- **Large Feed**: Feed #25 is generated programmatically with 2000 items of 9-10 KB each; total file size ~18 MB.
- **Malformed Feed**: Feed #22 contains an intentionally unclosed tag to test error recovery.
