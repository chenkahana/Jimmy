# Changelog

All notable changes to Jimmy are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Show notes keep their paragraphs, line breaks and list items, and linked text links to its page instead of running together as plain text.
- Launch no longer flashes "Queue Is Empty" before the queue appears.
- Now Playing follows your finger as you drag it down, and a quick flick down closes it.
- A queue row's Play button takes taps across a 44-point target; it was 33 points.
- Now Playing's Close, More, Speed, Sleep and Chapters controls take taps across a 44-point target; Close was 18 × 10 points.
- Artwork that's already loaded shows at once when a screen opens, so a podcast page no longer starts with a blank hero that fades in.
- The mini player's Play and Skip Forward buttons take taps across a full 44-point target instead of just the glyph.
- Download buttons on Now Playing, episode detail, and episode rows now download the episode.

### Removed

- Firebase analytics and crash reporting SDK.
- Four legacy CI workflows and their supporting scripts; replaced with one minimal workflow.

### Changed

- Now Playing's skip buttons bounce and tick when tapped, a speed change ticks, and setting a sleep timer gives a success tap.
- Marking an episode played is called Mark Played (and Mark Unplayed) in every swipe and menu, and Add to Queue uses one icon everywhere.
- Now Playing sits on a flat color sampled from the artwork, with transport in one glass capsule. Speed, Sleep and
  Chapters open one bottom panel, and chapters show their lengths. Download moves to the More menu.
- Tabs are Queue, Library and Search. The mini player sits above the tab bar, which shrinks as you scroll, and
  Settings, Add by URL, Listening Stats and Feedback open from Library's More menu.
- Library: shows are an artwork grid with no cards, search is the system search field, the Shows/Episodes switch
  sits under the title, and unsubscribing moves to each show's context menu. A show counts its new episodes.
- A calmer look: system backgrounds instead of the gradient backdrop, no card shadows, plain section headers,
  standard empty states, and a new accent color.
- Settings is a native grouped form: Playback, Appearance, Sync & Backup, Import & Export, About, with
  destructive actions last and the app version shown once.
- Discover is a plain list: your recent searches, then Top Shows as a numbered ranking. Search results are rows,
  and loading shows placeholder rows instead of shimmering cards. The Featured and Trending Episodes rows, which
  repeated the same chart, are gone.
- The queue is a plain list with artwork rows, drag to reorder, and swipe or long-press for Play Next, Played, Download and Remove.
- Podcast pages open on the show's artwork as a large hero that fades into the page; episodes are plain rows and
  show notes are set in New York.
- Simplified architecture with a new core package, JimmyKit.
- Xcode project now generated from `project.yml` via XcodeGen; build with `make build`.

### Added

- Single CI workflow for build validation.
- Community files: LICENSE, CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md, SUPPORT.md, THIRD_PARTY_NOTICES.md, documentation.
- A real Apple Watch app (Now Playing, Queue, Recent) that controls the phone's player over
  WatchConnectivity. Standalone playback with downloads to the watch is planned for later.
- Release guide in `docs/release.md`.
