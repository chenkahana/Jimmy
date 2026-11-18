# R3 References

The same flows in Apple Podcasts, Overcast, Pocket Casts, Castro and (for the player) Apple Music, written as
mechanics: what moves, how it's driven, what it does when interrupted, what the haptics mark.

**How this was gathered.** None of these apps run in the iOS simulator (no App Store; Podcasts and Music aren't in the
simulator image), so this is desk research: the apps' own help pages and release notes where they exist, plus
long-standing, widely documented behavior. Each line carries a confidence mark: **(doc)** a vendor page says so,
**(known)** stable public behavior over several releases, **(verify)** plausible but needs a 2-minute look on
Chen's phone before a backlog item depends on it. The "verify" list at the end is the device checklist.

## R3.1 Apple Podcasts (iOS 26/27)

| Flow | Mechanics |
|---|---|
| Mini → full player | The mini player lives in the tab bar's bottom accessory (same API Jimmy uses). Tapping it expands the player from the accessory: the artwork grows from the mini player's thumbnail into the hero position while the rest of the player fades in; dismissing runs the same path back. **(known)** |
| Dismiss | Drag down anywhere on the player; the sheet tracks the finger 1:1, keeps release velocity, and a quick flick of a few dozen points dismisses. Upward drag rubber-bands. **(known)** |
| Scrubber | The progress bar thickens while touched and the thumb grows; elapsed/remaining labels follow. Drag is relative (touch anywhere on the bar, the position doesn't jump to the finger). **(known)** Fine-scrub by moving the finger away from the bar was the classic iOS behavior; current builds rely on the long bar. **(verify)** |
| Transport | Back 15 / forward 30 by default (Settings), glyphs show the interval; buttons have a pressed scale and the play/pause glyph morphs with a symbol transition. **(known)** |
| Speed | A button showing the current speed opens a compact menu: 0.5×, 0.75×, 1×, 1.25×, 1.5×, 1.75×, 2×. **(known)** |
| Sleep timer | Menu: 5, 10, 15, 30, 45 min, 1 h, End of Episode; the button shows the remaining time once set. **(known)** |
| Chapters | Chapter title under the episode title; chapter list from the player's menu; Lock Screen shows chapter artwork. **(known)** |
| Queue (Up Next) | Lives in the player (scroll below or "Up Next" button); reorder by drag handles with lift; swipe to remove. **(known)** |
| Episode rows | Swipe actions (Play Next, Save, Remove download) and long-press context menu with a preview card. **(known)** |
| States | Empty Library: "Shows you follow appear here" + Browse. Offline: downloaded episodes still listed and playable; others greyed. **(known)** |
| System | Lock Screen with chapter info and artwork, CarPlay with artwork grids, Watch app with Up Next, Siri/App Intents ("Play the latest episode of …"), Spotlight for shows, Live Activity-style Now Playing in the Dynamic Island, Handoff to Mac. **(known)** |
| Haptics | Light tick when a swipe action passes its full-swipe threshold (system), selection haptic on menu choices. Transport taps have no haptic. **(known)** |

## R3.2 Overcast

| Flow | Mechanics |
|---|---|
| Player layout | Full player is pageable: swipe right for the Effects pane (Smart Speed, Voice Boost, speed slider, per-show save), left for show notes, further left for chapters. **(doc: MacStories, The Sweet Setup)** |
| Speed | A continuous slider (not a segmented picker) with fine steps; the value reads out as you drag. **(doc)** |
| Smart Speed | Trims silences; the app reports time saved overall. Not a UI motion, but a "feels physical" detail: speed is a dial with feedback. **(doc)** |
| Chapters | Each chapter has its own progress bar, link and art. **(doc)** |
| Scrubbing | The seek bar is long and thin; Overcast also exposes skip buttons with per-podcast skip-intro/outro durations (2025). **(doc: iClarified)** |
| Queue | Playlists with drag handles; long-press to reorder. **(known)** |
| Watch | Full standalone Watch app with playback controls and downloaded episodes. **(doc: MacStories)** |
