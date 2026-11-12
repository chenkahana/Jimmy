# Onboarding Import Research

Researched 2026-11-12. Sources are linked in each section, with their dates where the page gives one. Anything marked "unverified" came from a secondary source or could not be checked against a primary one.

## Sources at a Glance

| App | Subscriptions | History / Played | Progress | Queue | Effort | Automatic? |
|---|---|---|---|---|---|---|
| Apple Podcasts | No export. Partial on-device path through MediaPlayer, downloaded shows only (unverified on iOS 27). Shortcuts gives Store IDs, not feed URLs. | Only in the privacy.apple.com download | Only in the privacy.apple.com download | No | A Shortcut run, or a data request that takes days | Half-automatic at best |
| Spotify | Yes: `GET /me/shows` | Saved episodes only (`GET /me/episodes`). Recently played excludes episodes. | Yes: `resume_point` on episode objects | No | Sign in (OAuth PKCE) | Automatic after sign-in, but capped at 5 users in Development Mode |
| Spotify data download | Yes (`YourLibrary.json`) | Yes (streaming history) | Only ms played per stream, not a resume point | No | Web request, wait about 5 days (account data) or up to 30 days (extended history) | Manual file |
| Overcast | Yes (OPML) | Yes: `played`, `userDeleted`, `userUpdatedDate` (in the "All data" export) | Yes: `progress`, in seconds | No (playlists are definitions, not an ordered queue) | Web sign-in, download a file, share it to Jimmy | Half-automatic (file) |
| Pocket Casts | Yes (OPML) | No (in-app list only; GDPR request by email) | No | No | Settings, export a file, share it | Half-automatic (file) |
| Castro | Yes (OPML) | No in the OPML. The iCloud backup has it but the format is private. | No | No (in the private backup only) | Settings, export a file, share it | Half-automatic (file) |
| Google Podcasts | Was OPML. Service shut down in 2024. Takeout data scheduled for deletion one year later. | No | No | No | Not possible now | No |
| YouTube Music | No podcast export found | Watch history JSON (YouTube-wide, not podcast-specific) | No | No | Google Takeout | Manual file, poor fit |
| Castbox / Podcast Addict / Snipd | OPML (Castbox, Podcast Addict). Snipd export path unverified. | No | No | No | Settings, export a file | Half-automatic (file) |

## Per App

### Apple Podcasts

**On-device access for third-party apps**
- `MPMediaQuery.podcasts()` (MediaPlayer) reads the Music media library, not the Podcasts app's library. Since iOS 8.4, `MPMediaPickerController` stops returning podcasts ([Apple Developer Forums 9613, 2015](https://developer.apple.com/forums/thread/9613)). One competitor (The Podcast App) still imports from Apple Podcasts through the Media Library permission ("Media & Apple Music"), but documents that "the import process only works for shows with downloaded episodes in Apple Podcasts" ([help.podcast.app](https://help.podcast.app/en/articles/2204608), undated). Treat this as partial and unverified on iOS 27; it needs a device test. Fields that are likely available are podcast title and per-item play count, last played date and bookmark time; there is no feed URL. All of this is unverified.
- MusicKit and the Apple Music API have no podcast endpoints. `MusicLibraryRequest` has no podcast equivalent; the question on the forums has no answer ([Developer Forums 736824, Sep 2023](https://developer.apple.com/forums/thread/736824)).
- Apple Podcasts syncs "the play position of the podcast episodes you are listening to, and the contents of your library" through iCloud, but exposes no API for it ([Apple Podcasts & Privacy](https://www.apple.com/legal/privacy/data/en/apple-podcasts/)).

**Export from the app**
- iOS: there is no export.
- macOS Podcasts app: there is no OPML export. Apple's Podcasts for Mac guide doesn't mention import, export or OPML ([guide](https://support.apple.com/guide/podcasts/pod5c5fe4d06/mac)). "File > Library > Export Playlist" (cited by [Pocket Casts](https://support.pocketcasts.com/article/opml-import/)) is the old iTunes path and was removed with Catalina ([kaspars.net, 2019](https://kaspars.net/blog/apple-podcasts-subscriptions)).
- Mac database workaround (developer use only, not reachable from an iOS app): `~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Documents/MTLibrary.sqlite`, with tables `ZMTPODCAST` (`ZFEEDURL`, `ZTITLE`) and `ZMTEPISODE`. This comes from community reports (unverified).

**Shortcuts**
- Podcasts actions: Get Podcasts from Library, Get Details of Podcast, Get Episodes for Podcast, Get Details of Podcast Episode, Play Podcast, Subscribe to Podcast, Search Podcasts ([Cassinelli action index](https://matthewcassinelli.com/action_groups/media/podcasts)).
- Get Details of Podcast offers: Store ID, Store URL, Title, Author, Description, Genres, Duration, Artwork, Artwork URL, Name. There is **no Feed URL** ([Cassinelli](https://matthewcassinelli.com/actions/get-details-of-podcast/)). A Shortcut can therefore produce Apple IDs, which Jimmy resolves to feeds through the iTunes Lookup API.
- Competitor precedent: Pocket Casts ships an "Apple Podcasts to Pocket Casts" shortcut. The user taps Install Shortcut, adds it, runs it, and Pocket Casts reopens and finishes the import ([Pocket Casts](https://support.pocketcasts.com/article/opml-import/)).
- User steps for a Jimmy shortcut:
  1. Tap the Jimmy link that installs the shortcut.
  2. Tap **Add Shortcut**.
  3. Run it. It calls Get Podcasts from Library, then Get Details of Podcast (Store ID), and opens `jimmy://import?ids=...` or hands the list over with an App Intent.
- Result: subscriptions only. Feeds that aren't in the Apple directory (private or premium RSS) have no Store ID and are lost. Whether those return an empty Store ID is unverified.

**privacy.apple.com data download**
- Request it at [privacy.apple.com](https://privacy.apple.com) under **Request a copy of your data**, category **Apple Media Services information**. Apple posts it to the page when ready, and it stays downloadable for 14 days ([Apple Support 102208](https://support.apple.com/en-us/102208)).
- Contents: a Podcasts folder with "Your Podcasts" (subscribed shows, by RSS URL) and "Podcasts Playstate" (episodes played and how long), per [James Cridland, 2022](https://james.cridland.net/blog/2022/what-does-apple-know-about-me/). The format is CSV or JSON; the exact file names are unverified.
- Turnaround was about 5 days in that report. Apple doesn't publish a turnaround time.

### Spotify

**Web API** (docs fetched 2026-11-12)
- `GET /me/shows`: saved shows. Scope `user-library-read`. Up to 50 per page, each with `added_at` ([ref](https://developer.spotify.com/documentation/web-api/reference/get-users-saved-shows)).
- `GET /me/episodes`: saved episodes. Scopes `user-library-read` and `user-read-playback-position` ([ref](https://developer.spotify.com/documentation/web-api/reference/get-users-saved-episodes)).
- `GET /shows/{id}/episodes`: each episode carries `resume_point { fully_played, resume_position_ms }` when the user token has `user-read-playback-position` ([ref](https://developer.spotify.com/documentation/web-api/reference/get-a-shows-episodes)). This is how to get per-episode progress for unsaved episodes of followed shows.
- `GET /me/player/recently-played` (`user-read-recently-played`): the docs say it "Currently doesn't support podcast episodes" ([ref](https://developer.spotify.com/documentation/web-api/reference/get-recently-played)). It is useless for podcast history.
- There is no endpoint for the queue or Up Next ("Your Episodes" is the saved-episodes list).
- The Show object has **no RSS field**. Its fields are id, name, description, images, `is_externally_hosted`, total_episodes and others ([ref](https://developer.spotify.com/documentation/web-api/reference/get-a-show)). Feeds have to be matched by name through iTunes Search or Podcast Index. Spotify-exclusive and Spotify-hosted-only shows have no public RSS, so they can't be followed in Jimmy.

**Authentication**
- Authorization Code with PKCE is "the recommended authorization flow if you're implementing authorization in a mobile app". It needs no client secret ([PKCE tutorial](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow)).
- Refresh also works without a secret: send `grant_type=refresh_token`, `refresh_token` and `client_id`, with no Authorization header ([refresh tutorial](https://developer.spotify.com/documentation/web-api/tutorials/refreshing-tokens)).

**Quota and policy changes**
- 2024-11-27: new and development-mode apps lost Related Artists, Recommendations, Audio Features/Analysis, Featured and Category Playlists, and previews. No podcast endpoints were affected ([blog](https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api)).
- 2025-05-15: Extended Quota only for organizations, with **at least 250k MAU**, an established business entity, and a review of up to 6 weeks ([quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)).
- 2026-02-11 for new apps, 2026-03-09 for existing apps: Development Mode requires the owner to have **Premium**, allows **1 Client ID**, and caps it at **5 authorized users** (down from 25) ([blog 2026-02-06](https://developer.spotify.com/blog/2026-02-06-update-on-developer-access-and-platform-security), [migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide)). The same guide removes `PUT/DELETE /me/shows|episodes`, `/contains` and batch `GET /shows|episodes?ids=`, and drops the Show fields `publisher` and `available_markets`. `GET /me/shows`, `GET /me/episodes` and `GET /shows/{id}/episodes` remain. The blog says enforcement of the endpoint changes for existing apps was postponed.
- What this means for Jimmy: a public Spotify import needs Extended Quota (250k MAU, organization). Under that bar, the button works for at most 5 allow-listed users.
- [Developer Policy](https://developer.spotify.com/policy) (effective 2025-05-15): III.9 bans transferring data to another service "except for the purpose of enabling a user to transfer their personal data, or the metadata of the user's playlists". III.5 bans products "integrated with streams or content from another service". How these apply to a podcast player is a judgment call, not verified.

**Data download** ([Spotify Privacy page](https://www.spotify.com/account/privacy/), [Understanding my data](https://support.spotify.com/us/article/understanding-my-data/))
- Account data covers the past year. It includes Streaming History, with podcasts (show and episode names, ms played), and Your Library (shows and episodes). Spotify's page doesn't state a turnaround; secondary sources say about 5 days. File names `StreamingHistory_podcast_*.json` and `YourLibrary.json` are unverified.
- Extended streaming history covers the account's lifetime and includes episode name, show name, `spotify_episode_uri` and ms played. Secondary sources say up to 30 days.
- The download is a JSON ZIP sent by email. There are no RSS URLs, so the same name matching is needed.

### Overcast

**Export steps** (iOS app 2024+ rewrite)
1. Sign in at overcast.fm. Most accounts have no password, so the web sign-in uses a QR code or a link from the app ([overcast.fm/login](https://overcast.fm/login)). The exact in-app label is unverified.
2. Go to [overcast.fm/account](https://overcast.fm/account), then **Export Your Data**.
3. Tap **OPML** for subscriptions only, or **All data** for extended OPML with playlists and episode data ([IndieWeb](https://indieweb.org/Overcast)). The direct URL is `https://overcast.fm/account/export_opml/extended`.
4. Share or open the file in Jimmy.

The in-app **Settings > Export OPML** existed in the pre-2024 app (Snipd still documents it, [2025-01-06](https://intercom.help/snipd-8a3377583e36/en/articles/10225394-import-from-overcast)). The July 2024 rewrite shipped without it, and it was back in beta by September 2024 ([Michael Tsai](https://mjtsai.com/blog/2024/07/18/overcasts-new-foundation/)). Whether the current in-app export includes extended data is unverified.

The "All data" download is limited to about 10 a day (Marco Arment via [IndieWeb](https://indieweb.org/Overcast); [Music Assistant](https://www.music-assistant.io/music-providers/overcast/)).

**Extended OPML format** (a composite: the 2019 sample lacks `overcastAddedDate` and `includePodcastIds`, which come from the parser. Sources are a real export sample in a [2019 gist comment](https://gist.github.com/manuzhang/cc1a0cc49638f0f2a30af2e2d06dc6d3), and from the maintained parser [overcast-to-sqlite](https://github.com/hbmartin/overcast-to-sqlite), active 2026)
```xml
<opml version="1.0"><head><title>Overcast Podcast Subscriptions</title></head><body>
  <outline text="playlists">
    <outline type="podcast-playlist" title="All Episodes" smart="1" sorting="chronological-by-podcast" includePodcastIds="..."/>
  </outline>
  <outline text="feeds">
    <outline type="rss" overcastId="565005" text="..." title="..." xmlUrl="https://..." htmlUrl="https://..."
             subscribed="1" notifications="1" overcastAddedDate="...">
      <outline type="podcast-episode" overcastId="606669652347564" pubDate="2019-05-29T03:05:49-04:00"
               title="..." url="https://..." overcastUrl="https://overcast.fm/+Inw0kfyqw"
               enclosureUrl="https://....mp3" userUpdatedDate="2019-06-15T20:25:56-04:00"
               userDeleted="1" played="1" progress="1049" userRecommendedDate="..."/>
    </outline>
  </outline>
</body></opml>
```
- Feed attributes: `type="rss"`, `overcastId`, `text`, `title`, `xmlUrl`, `htmlUrl`, `subscribed` (1 = followed; feeds with episode history but no subscription can appear), `notifications`, `overcastAddedDate`.
- Episode attributes: `type="podcast-episode"`, `overcastId`, `pubDate`, `title`, `url` (episode web page), `overcastUrl`, `enclosureUrl`, `userUpdatedDate` (last user interaction), `played="1"`, `progress` (integer seconds; the attribute is absent when there is no progress), `userDeleted="1"`, `userRecommendedDate` (starred).
- Playlist attributes: `title`, `smart`, `sorting`, `includePodcastIds`. These are rules, not an ordered queue.
- Match episodes to Jimmy's by `enclosureUrl` (strip the query string, as overcast-to-sqlite does), falling back to title plus `pubDate`.

### Pocket Casts

**Export steps** for iOS ([Pocket Casts: OPML export](https://support.pocketcasts.com/article/opml-export), undated)
1. Tap the **Profile** tab.
2. Tap **Settings**.
3. Tap **Import & Export OPML**.
4. Tap **Send email** or **Save file**.

- Contents: followed podcasts only.
- No self-serve full export. Staff say users can "contact us to request your GDPR data, however that may not include the details you're looking for" ([forum, 2026-01-02](https://forums.pocketcasts.com/forums/topic/listening-data-export)).
- **Help & Feedback > ... > Export database** produces a ZIP with podcasts, folders, playlists, bookmarks and history. It is meant for support troubleshooting, and the format is private ([KB](https://support.pocketcasts.com/knowledge-base/exporting-the-app-database/)).
- Unofficial API, for reference only. Jimmy will not use it because it needs the user's Pocket Casts password. The base is `https://api.pocketcasts.com` with `POST /user/login` (email and password, returns a bearer token), `/user/podcast/list`, `/up_next/list`, `/user/history`, `/user/in_progress`, `/user/starred`, `/user/new_releases`, `/user/episode` and `/sync/update_episode` ([music-assistant client](https://github.com/music-assistant/server/blob/dev/music_assistant/providers/pocketcasts/api_client.py)). It doesn't work for Sign in with Apple or Google accounts without a password (unverified).

### Castro

**Export steps** ([Pocket Casts forum, 2023-12-01](https://forums.pocketcasts.com/forums/topic/switching-from-castro/))
1. Tap **Settings** (the gear icon, top left).
2. Scroll down and tap **User Data**.
3. Tap **Export Subscriptions**.
4. Save `subscriptions.opml` to Files, or share it.

- Contents: subscriptions only.
- Castro also writes an automatic iCloud Drive backup every 24 hours, holding "user subscriptions, history, starred episodes, inbox and queue state" ([Castro 2.6 blog, 2017-12-18](https://castro.fm/blog/castro-2-6)). It is restored through **Settings > Backup / Restore Castro**. The format is undocumented and private, and it's unknown whether Jimmy can read it (unverified).

### Google Podcasts and YouTube Music

- Google Podcasts stopped in the US on 2024-04-02 and globally in June 2024. The export tool ran until 2024-08-29, and Takeout kept the data for one year, after which Google began deleting it ([9to5Google](https://9to5google.com/2024/03/06/how-to-export-subscriptions-google-podcasts/), [Android Central](https://androidcentral.com/apps-software/google-podcasts-migration-tool-available)). At 2026-11 the data is gone for practically everyone. The Takeout format was an OPML of subscriptions.
- YouTube Music lets users add podcasts by RSS ([Google Help](https://support.google.com/youtubemusic/answer/13946190)), but there is no podcast export. Takeout "YouTube and YouTube Music" gives `subscriptions.csv` (channels), `watch-history.json` or `.html`, and playlists, which are YouTube-wide and not podcast-aware (secondary sources, unverified). A followed YouTube podcast is a playlist, and many have no RSS.

### Others (Brief)

- Castbox (iOS): the **Personal** tab has **OPML Export** and **OPML Import**, plus a direct "import from Apple Podcasts" ([Castbox Help](https://helpcenter.castbox.fm/portal/kb/articles/settings-on-the-personal-tab-ios)). Exports subscriptions only.
- Podcast Addict (Android only): **Settings > Backup, Restore & Sync** has backups to Google Drive in its own format, plus OPML export (exact label unverified; [FAQ 20](https://podcastaddict.com/faq/20) blocked fetch). Not relevant to iOS users except people switching from Android.
- Snipd: imports OPML and Apple Podcasts. Its own OPML export path is unverified (its help center has an "Export & Sync" collection, [help](https://intercom.help/snipd-8a3377583e36/en/)).

## What's Impossible, and Why

- **Reading Apple Podcasts' full library, queue or progress on iOS.** It is sandboxed, and no public framework (MediaPlayer, MusicKit, Apple Music API) exposes it. MediaPlayer covers at most downloaded shows (unverified on iOS 27).
- **Feed URLs from Apple Podcasts through Shortcuts.** Get Details of Podcast has no Feed URL, so private or premium feeds can't be carried over.
- **Instant Apple Podcasts history.** History exists only in the privacy.apple.com download, which takes days and arrives by email.
- **Spotify podcast listening history through the API.** `recently-played` excludes episodes. Only saved episodes and `resume_point` on fetched episodes are available.
- **Spotify for the general public.** Development Mode caps an app at 5 users, and Extended Quota requires an organization with 250k or more MAU.
- **Spotify-exclusive shows.** They have no RSS, so Jimmy can't play them.
- **RSS URLs from Spotify.** The Show object has no feed field, and `publisher` was removed in Dev Mode in 2026, which makes name matching harder.
- **Queue or Up Next from any app without a password.** No app exports it. Pocket Casts has it only through the unofficial password API. Overcast playlists are rules, not a queue. Castro keeps it only in its private iCloud backup.
- **Played state from Pocket Casts, Castro or Castbox.** Their OPML contains subscriptions only.
- **Google Podcasts.** The service and its Takeout data are gone.
- **Zero-tap import from any app.** Every source needs at least a share sheet, a file, a shortcut run or a sign-in.

## Onboarding Patterns

**Apple HIG**
- [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) (change log 2024-06-10):
  - Ideally there is no onboarding. If there is, make it "fast, fun, and optional", and run it after launch completes.
  - Teach through interaction. Prefer contextual tips over one long flow.
  - Make any tutorial skippable, never show it again once skipped, and keep it findable in settings.
  - Postpone nonessential setup and provide sensible defaults.
  - Don't let large downloads block the start.
  - Ask for permissions in onboarding only if the app can't work without them. Otherwise ask when the feature is first used.
  - Ask for ratings or purchases only after people are engaged.
- [Launching](https://developer.apple.com/design/human-interface-guidelines/launching) (2024-06-10):
  - Launch instantly.
  - The launch screen should be nearly identical to the first screen, with no text and no branding or ads.
  - A splash screen, if any, belongs at the start of onboarding.
  - Restore previous state on relaunch.
- [Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts): require an account only when core features need it, and "people often abandon apps when they're forced to sign in before they can do anything useful". Delay sign-in.
- [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy): request permission only when clearly needed, and "avoid requesting permission at launch" unless the app can't work without it. This rules out an upfront Media Library prompt for the MediaPlayer path.

**Competitors**
- Pocket Casts: import lives under **Profile > Settings > Import & Export OPML** ("Import from other apps") and opens OPML from the share sheet. It names ten source apps, and for Apple Podcasts it offers a one-tap "Apple Podcasts to Pocket Casts" Shortcut ([support](https://support.pocketcasts.com/article/opml-import/)). Its first-launch screens are not documented on its help pages (unverified).
- Overcast: after the 2024 rewrite, first launch goes from creating a sync account straight to the main screen, with no tutorial (secondary source, unverified). Import is OPML through the share sheet.
- Castro: OPML import from Settings. Its automatic iCloud backup makes reinstalling seamless, but the backup is not cross-app.
- Snipd: help-center "Getting Started" puts "Import podcasts from Apple Podcasts" first, and has per-app import guides such as the Overcast one, which uses the share sheet to Snipd ([help](https://intercom.help/snipd-8a3377583e36/en/)).
- Castbox and The Podcast App: they offer a direct "import from Apple Podcasts". The Podcast App's version uses the Media Library permission and only finds shows with downloaded episodes ([help.podcast.app](https://help.podcast.app/en/articles/2204608)).
- Apple Music: the first-run flow was not researched; no primary source was found (unverified).

## Recommended Flow

This is what `Jimmy/Onboarding/` builds. Screenshots in light and dark are in `docs/screenshots/onboarding/`.

**Principles taken from the research**
- No sign-up wall and no permission prompt at launch. The first screen is the import itself, and **Skip** is always in the toolbar.
- One primary action per screen. If a source app is installed, it is "Import from Overcast". If none is, it is "Choose an Export File", and Jimmy works out the format itself (`ImportFile.kind(of:)`: OPML, Spotify data download, Google Takeout, Apple bulk JSON, or plain text with links).
- Each source gets the shortest path it allows: a sign-in where an API exists (Spotify, when a client ID is configured), a file with exact steps where it doesn't, and the clipboard for Apple Podcasts.
- The import is visible while it runs. Rows appear at once, and each show's artwork fills in as its feed arrives. Six shows are added at a time.
- At the end, Jimmy says what came over and opens the Queue if anything was in progress, otherwise the Library.

**Wireframes**

```
1 Start                       2 Source (Overcast)           3 Importing                   4 Done
+-------------------------+   +-------------------------+   +-------------------------+   +-------------------------+
| Welcome to Jimmy   Skip |   | < Overcast              |   | Found 42 shows          |   | 41 shows added          |
| Bring your shows, played|   | Overcast's website      |   | Adding 12 of 42...      |   | 318 episodes marked     |
| episodes and progress...|   | exports your shows with |   | [=======-------------]  |   |   played.               |
|                         |   | every played episode... |   |                         |   | 3 episodes to pick up,  |
| ON THIS IPHONE          |   | STEPS                   |   | [art] Planet Money    v |   |   now in your Queue.    |
|  Overcast             > |   | 1 In Safari, go to      |   | [art] Hard Fork       v |   | 1 show couldn't be      |
| OTHER APPS              |   |   overcast.fm/account   |   | [   ] Radiolab        o |   |   found.                |
|  Apple Podcasts       > |   | 2 Under Export Your     |   | [   ] Search Engine     |   | [art] Planet Money    v |
|  Spotify              > |   |   Data, tap All Data    |   |  ...                    |   | [   ] Gone Show Not Found|
|  Pocket Casts         > |   | 3 Tap Download          |   |                         |   |                         |
|  Castro / Another App > |   | 4 Come back, Choose File|   |                         |   |                         |
| START FRESH             |   | [Open overcast.fm]      |   |                         |   |                         |
|  Browse Top Shows       |   |                         |   |                         |   |                         |
|  ( Import from Overcast)|   |     ( Choose File )     |   | (Continue in Background)|   |     ( Open Queue )      |
+-------------------------+   +-------------------------+   +-------------------------+   +-------------------------+
```

**Per source in Jimmy**

| Source | Path in Jimmy | What comes over |
|---|---|---|
| Overcast | Steps to overcast.fm/account, All Data, then Choose File (or share the file to Jimmy) | Shows, played episodes, progress. In-progress episodes go to the Queue. |
| Spotify | Sign In with Spotify (PKCE) when `SPOTIFY_CLIENT_ID` is set; otherwise the data-download steps and Choose Files (several files at once) | Saved shows, matched by name. Saved episodes go to the Queue with their resume point. Streaming history adds progress; under a minute is ignored. |
| Apple Podcasts | Steps for a four-action shortcut that copies each show's Store URL, then the system Paste button (no clipboard prompt) | Shows, resolved through the iTunes Lookup API by Apple ID. |
| Pocket Casts, Castro, others | Steps to export OPML, then Choose File (or share the file to Jimmy) | Shows. |
| Start fresh | Browse Top Shows opens Discover | Nothing to import. |

**Matching**
- Shows: a feed URL is used as is. An Apple Podcasts link goes through iTunes Lookup by id. A Spotify show link gets its title from Spotify's public oEmbed. A name is searched in the directory, and only an exact title (preferring the same publisher), or a near title from the same publisher, counts (`DirectoryMatcher`).
- Episodes: the enclosure URL with tracking prefixes (Podtrac, Chartable, pdst.fm and similar) and the query stripped. If that fails, the title within three days of the publish date. If that fails, the title alone when exactly one episode has it (`EpisodeMatcher`). An episode at 95% or more counts as played, the same rule as playback.
- The Queue gets at most 10 episodes, most recently touched first.

**Re-entry and testing**
- Shown once, on a launch with an empty library. Anyone updating with shows already in their library never sees it.
- **Settings > Import & Export > Import from Another App** opens the same flow.
- Sharing an `.opml` file to Jimmy (from Overcast, Files or Mail) opens the flow and starts the import.
- `-resetOnboarding` shows it again. `-skipOnboarding` hides it. `-demoLibrary` hides it unless `-resetOnboarding` is also passed.

**Next steps, not built**
- A hosted iCloud shortcut link for Apple Podcasts, which would make it two taps: Add Shortcut, then Run. This needs Chen to publish the shortcut.
- A `jimmy://import` App Intent, so the shortcut can hand Jimmy the list without the clipboard.
- Spotify Extended Quota, needed before sign-in can work for the public.
- Reading the privacy.apple.com Podcasts files, once their exact file names are confirmed from a real download.
