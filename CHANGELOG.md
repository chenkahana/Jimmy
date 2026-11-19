# Changelog

All notable changes to Jimmy are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Library's first load no longer replaces the page with a spinner.
- The feedback form closes when sending completes instead of on a 1.5-second timer.
- The mini player tip's title is in title case, like other titles.
- Onboarding's import button sits on a bar, so the source list no longer shows through behind it.
- The running sleep timer's Cancel button fits on one line.
- At the largest text sizes the mini player drops Skip Forward and stops its text at the first accessibility size, so the episode title is readable instead of "K…".
- An episode shows the same length and date everywhere: Library, podcast pages and episode detail use the queue's "42 min" and "Today", "3d" or "Oct 2".
- Search keeps the last Top Shows it loaded, on this device, and shows them with a Try Again row when a fetch fails, instead of an error page.
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

- Suggestions shows placeholder rows while it ranks, instead of a lone spinner, and has a Done button.
- Now Playing's More menu adds Go to Episode and Go to Show, and the Chapters button only appears when the episode has chapters.
- One name per action: Follow and Unfollow everywhere (Library, Search, Settings' Unfollow All Shows), Send Feedback in both places, and in-progress text ends with a real ellipsis.
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

- Removing an episode from the queue shows Undo for five seconds, which puts it back in its place; Clear All asks first.
- VoiceOver announces when a download finishes or fails and when the sleep timer ends.
- Single CI workflow for build validation.
- Community files: LICENSE, CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md, SUPPORT.md, THIRD_PARTY_NOTICES.md, documentation.
- A real Apple Watch app (Now Playing, Queue, Recent) that controls the phone's player over
  WatchConnectivity. Standalone playback with downloads to the watch is planned for later.
- Release guide in `docs/release.md`.
