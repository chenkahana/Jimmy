# QA Checklist

## What is a QA Round?

A QA round is one person, one device, testing the entire app against a comprehensive checklist. Results are recorded at the end: the date, build identifier, device and iOS version, tester name, and counts of P1, P2, P3 issues found. Each round takes 1–2 hours on a device and simulator combined.

### Installing a Build

**For the simulator** (fast, no provisioning):
```bash
make run  # Build, install, launch, and screenshot
```

**For a device** (requires provisioning):
1. Open Xcode and select the device in Product → Destination.
2. Run Product → Run or `make archive` for a signed release build.
3. Manually install via Xcode Organizer if using TestFlight.

---

## QA Checklist

### First Launch and Upgrade

- [ ] First launch on a clean device: Onboarding screen appears; tapping Get Started shows the empty Queue screen
- [ ] Upgrading from a previous version with a library: Existing podcasts, queue, progress, and downloads are all present and unchanged
- [ ] Database error on launch: If the database cannot open, Reset is offered; after reset, app launches successfully with an empty library

### Library Screen

- [ ] Browse subscriptions list: Podcasts appear in alphabetical order with artwork, title, and unplay count
- [ ] Pull to refresh: New episodes appear for all podcasts; no duplicates
- [ ] Add podcast by URL: Entering a valid podcast URL subscribes and adds episodes within 30 seconds
- [ ] Add podcast by search: Search for a popular podcast (e.g., "NPR"), tap to subscribe, episodes load
- [ ] Unsubscribe from podcast: Podcast is removed from the library, and its episodes leave the queue
- [ ] Sort podcasts: Each option in the sort menu reorders the list, and the choice survives a relaunch
- [ ] Empty library on first launch: Empty state message appears; Add Podcast button is prominent

### Podcast Detail and Episode

- [ ] Podcast detail screen: Artwork, title, description, unplay count, and episode list are visible
- [ ] Episode list: Episodes appear in descending publish date; titles, dates, and play state badges are shown
- [ ] Mark episode as played: Tap on an episode, play state updates; episode count in the library decrements
- [ ] Mark episode as unplayed: Tap a played episode's badge, state reverts; count increments
- [ ] Download an episode: Tap the download icon; download begins (indicator shows progress, then Complete)
- [ ] Episode metadata: Tap an episode to see its description, publish date, podcast title, and any chapters or transcript

### Queue Screen

- [ ] View current queue: All queued episodes are listed in play order with now-playing indicators
- [ ] Add episode to queue: Tap Add to Queue on any episode (from Library, Discover, or Podcast detail); episode appears at the end of the queue
- [ ] Add episode as next: Using Play Next (long-press or context menu), episode appears after the now-playing episode
- [ ] Reorder queue: Long-press and drag a queue entry to a new position; order persists after relaunching
- [ ] Remove from queue: Swipe left on a queue entry, confirm delete; entry is removed but episode is not deleted
- [ ] Clear entire queue: Tap Clear (if available), confirm; all entries removed in one action
- [ ] Queue survives relaunch: Quit the app entirely, relaunch; same queue in same order appears

### Player

- [ ] Play: Tap Play on any episode or queue entry; playback begins with audio output
- [ ] Pause: Tap Pause during playback; audio stops; tap Play to resume from the same position
- [ ] Seek forward/backward: Swipe or tap the scrubber in the player; position updates without dropouts
- [ ] Skip forward/backward: Tap skip buttons; position advances/retracts by the configured skip interval (default 15s)
- [ ] Speed control: Tap speed selector (1.0×, 1.25×, 1.5×, 2.0×); playback speed changes and persists
- [ ] Sleep timer: Open the Now Playing screen, tap Sleep Timer, set a duration, start playback; after the duration, playback stops
- [ ] Sleep timer end-of-episode: Queue a 2-minute episode, set sleep timer for 3 minutes; after the episode ends, timer continues and stops at 3 minutes total
- [ ] Resume after relaunch: Stop playback at 30 seconds into an episode, quit and relaunch the app; playback resumes at the same position
- [ ] Plays downloaded file offline: Download an episode, disable WiFi/cellular, tap play; episode plays without buffering
- [ ] Auto-advance to next queue entry: Enable auto-advance in settings, reach the end of an episode; next episode in queue begins automatically

### Lock Screen and System Controls

- [ ] Lock screen playback controls: Start playback, lock the device; Play/Pause buttons appear on the lock screen and control playback
- [ ] Control Center: During playback, open Control Center; Now Playing shows the episode with Play/Pause and skip buttons that work
- [ ] AirPods controls: During playback via AirPods, double-tap to pause/play; press and hold to skip (if enabled)
- [ ] Remote command integration: Using Siri or lock screen commands, play/pause and skip controls affect the queue and now-playing state

### Downloads

- [ ] Start download: Tap the download icon on an episode; download begins and a progress indicator appears
- [ ] Cancel download: While downloading, tap the cancel icon; download stops and the file is removed
- [ ] Delete downloaded file: After a download completes, tap delete; file is removed but the episode remains in the library
- [ ] Resume interrupted download: Start downloading an episode, force-quit the app, relaunch; download resumes from where it paused
- [ ] Download persists across relaunch: Download an episode, quit and relaunch; downloaded file is still present and plays offline

### Discover and Search

- [ ] Discover screen loads: Browse button shows trending episodes, recommended podcasts, or genre categories (depending on the implementation)
- [ ] Tap trending episode or recommended podcast: Detail screen opens with full metadata and an immediate option to add to queue or subscribe
- [ ] Search for episodes: Type a keyword into the search bar; matching episodes from the library appear with podcast and publish date
- [ ] Search across all feeds: If search includes non-subscribed podcasts, results show with a Subscribe option

### Import and Export

- [ ] Import OPML file: Tap Import, select an OPML file (from Files or Mail); podcasts from the file are added to the library
- [ ] Import Apple Podcast export: Import an Apple Podcasts OPML export; subscriptions import without errors
- [ ] Import Spotify show list: Import a Spotify export (if supported); shows are looked up and subscribed
- [ ] Import Google Takeout podcast data: Import Google Podcast export; subscriptions restore correctly
- [ ] Export OPML: Tap Export in Settings; OPML file is generated and saved to Files or shared via Mail
- [ ] Import with malformed OPML: Upload a broken OPML file; app shows an error and allows retry without crashing

### Settings

- [ ] Settings screen opens: All preference sections are visible (Playback, Notifications, About)
- [ ] Playback speed default: Change the default speed in Settings; new episodes play at that speed
- [ ] Skip interval: Change skip forward/backward interval; skip buttons use the new value
- [ ] Dark mode toggle (if present): Switching between light and dark modes updates the entire app without relaunch
- [ ] App version and build number: About section displays the correct version and build
- [ ] Legal links: Privacy Policy and License links open and display correctly

### CarPlay

- [ ] CarPlay simulator: Launch CarPlay through the iOS Simulator's Window menu (if available)
- [ ] Queue on CarPlay: CarPlay shows the current queue as a scrollable list
- [ ] Play/Pause on CarPlay: Tap play/pause in CarPlay; audio output changes and the main app updates
- [ ] Skip on CarPlay: Skip forward/backward controls work in CarPlay and sync with the main player
- [ ] Search and browse on CarPlay: CarPlay allows browsing the library and searching for podcasts (if implemented)

### Apple Watch

- [ ] Now Playing on watch: Start playback on the phone; the watch app shows the current episode with play/pause controls
- [ ] Queue on watch: View the queue list on the watch; tap an entry to jump to it
- [ ] Recent episodes on watch: Recent episodes are listed and tappable
- [ ] Watch controls phone player: Pause on the watch; audio stops on the phone and vice versa
- [ ] Phone unreachable: Put the phone into Airplane Mode; watch shows appropriate error or offline state

### Accessibility

- [ ] VoiceOver labels: Enable VoiceOver; all main controls (play, pause, add to queue, subscribe) have descriptive labels
- [ ] Dynamic Type at largest size: Set font size to the largest in Settings > Display & Text Size; text remains readable and layout adapts
- [ ] Increase Contrast: Enable Increase Contrast in Accessibility; UI elements have sufficient contrast
- [ ] Dark mode: Switch to Dark Mode; app is readable and colors are not glitchy

### Localization (Hebrew and Right-to-Left)

- [ ] Hebrew locale: Change device language to Hebrew in Settings > General > Language & Region
- [ ] RTL layout: All screens (Library, Queue, Settings) display correctly with right-to-left flow; text and icons are mirrored appropriately
- [ ] RTL playback controls: Player buttons and progress bar are positioned correctly for RTL
- [ ] RTL keyboard: Typing in search with Hebrew keyboard works correctly

---

## Performance Benchmarks

Record these metrics per round. Use Xcode's built-in gauges or Instruments.

### Cold Launch Time
**Measurement:** Tap the app icon from the home screen until the first screen (Queue or onboarding) is fully interactive.  
**Tool:** Xcode > Window > Devices and Simulators > select device > open Xcode Metrics or use Instruments (Time Profiler).  
**Target:** < 2.0 seconds from tap to fully drawn queue.

### Memory After Browsing
**Measurement:** Launch the app, subscribe to 3–5 podcasts, browse Library and Podcast details for 5 minutes, then record the resident memory.  
**Tool:** Xcode Metrics or Instruments > Memory > Allocations.  
**Target:** < 150 MB resident memory on an iPhone 15 Pro.

### Scrolling a Large Podcast
**Test:** Open Podcast detail for a podcast with 2,000+ episodes.  
**Measurement:** Scroll smoothly from top to bottom; record any frame drops or stutters.  
**Tool:** Xcode > debug gauge (show frame rate during scroll).  
**Target:** 60 FPS (or 120 FPS on Pro models), no frame drops.

### CPU While Playing in Background
**Measurement:** Start playback of an episode, send the app to the background (press Home), and let it play for 2 minutes. Record CPU usage.  
**Tool:** Xcode Metrics > CPU % or Activity Monitor (process name `Jimmy`).  
**Target:** < 5% CPU usage during background playback.

---

## Issue Severity

Issues are classified by impact on the user:

- **P1 (Must fix before release):** Data loss, app crash, inability to play audio, or inability to add/manage podcasts. Zero P1 issues allowed.
- **P2 (Should fix before release):** A feature broken with a clear workaround (e.g., reboot, reimport), or a significant visual glitch affecting usability. Zero P2 issues allowed.
- **P3 (Nice to fix):** Cosmetic issues, minor text misalignments, or edge cases that do not prevent core functionality. P3s may be deferred.

---

## QA Rounds Log

| Date | Build / Commit | Device | iOS | Tester | P1 | P2 | P3 | Notes |
|------|---|---|---|---|---|---|---|---|
| YYYY-MM-DD | (commit SHA or build #) | iPhone 17 Pro | 18.x | Name | 0 | 0 | 0 | Initial round; all core features verified. |
| | | | | | | | | |
