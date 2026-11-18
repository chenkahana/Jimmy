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

## R3.3 Pocket Casts

| Flow | Mechanics |
|---|---|
| Speed | 0.5× to 3× (5× in newer builds) in 0.1× steps with − / + buttons and presets; can be saved per show. **(doc: App Store page, support)** |
| Sleep timer | 15 min, 30 min, 1 h, End of Episode, custom; **shake the phone to restart** the timer before it ends; a fading volume ramp at the end. **(doc: support.pocketcasts.com)** |
| Player | Sheet-style full player with tabs for Now Playing, Show Notes, Chapters; chapters can be skipped (deselected). Artwork-tinted background. **(known)** |
| Up Next | Drag to reorder with lift and haptic; swipe actions configurable (full swipe = primary). **(known)** |
| Episode rows | Multi-select mode for bulk actions; swipe actions with colors (Up Next top/bottom, archive). **(known)** |

## R3.4 Castro

| Flow | Mechanics |
|---|---|
| Model | Inbox → Queue triage: new episodes land in an Inbox; a swipe sends them to the top or bottom of the Queue or archives them. Closest product to Jimmy's queue-centric model. **(known)** |
| Swipes | Colored, labeled swipe actions with full-swipe; distinct haptic when the full-swipe threshold is crossed. **(known)** |
| Queue | Reorder by long-press anywhere on the row (no Edit mode), lift with shadow, auto-scroll near edges. **(known)** |
| Player | Pull-up player card; chapter list inline; speed per show. **(verify)** |

## R3.5 Apple Music (player only)

| Flow | Mechanics |
|---|---|
| Mini → full player | Artwork morph from the accessory thumbnail to the hero art; the background blooms from the artwork's colors; reverse path on dismiss. Interruptible: grab the player mid-animation and it follows the finger. **(known)** |
| Dismiss | Tracks the finger, velocity-aware, small flick dismisses; background content scales slightly behind. **(known)** |
| Scrubber / volume | Both bars grow on touch and rubber-band past the ends; a haptic tick when the volume bar hits min or max. **(known)** |
| Play/pause | Symbol morph; artwork shrinks a little when paused and springs back when playing. **(known)** |
| Up Next | Below the player; drag handles; history above. **(known)** |

## Takeaways for Jimmy (feed R4 and R5)

1. **Morph, don't slide.** Both Apple players grow the full player out of the mini player's artwork and shrink back
   along the same path, and the gesture is interruptible. Jimmy slides a full-screen cover.
2. **Velocity decides dismissal.** A short flick closes the player everywhere; a fixed 100 pt threshold doesn't.
3. **Speed and sleep are dials.** Fine steps (0.1×) with a visible readout (Overcast, Pocket Casts), or Apple's
   compact menu; never a five-segment control that hides 1.75× and 0.5×.
4. **Scrubber grows on touch** and doesn't jump to the finger. Chapter marks on the bar are common in third-party
   players; Apple doesn't draw them.
5. **Swipe actions are colored and full-swipeable** with a threshold haptic; long-press anywhere reorders the
   queue (Castro) or handles do (Apple). Jimmy's gray actions and context-menu-first long-press read as less direct.
6. **Remaining sleep time lives on the button** (Apple) and shake-to-extend (Pocket Casts) is the one delight
   worth considering.
7. **System reach is table stakes**: Lock Screen chapter info, CarPlay artwork, Watch queue, Siri intents. Jimmy has
   the first-level hooks but none of the extensions.

## Verify on Chen's phone (5 minutes, before R5 items that cite "(verify)")

1. Apple Podcasts: does a short flick (< 50 pt) dismiss the player? Does the scrubber jump to the finger or move
   relatively?
2. Castro: is reorder a long-press anywhere on the row?
3. Apple Music: is there a haptic when the volume bar hits its end?

Sources: [Pocket Casts sleep timer](https://support.pocketcasts.com/article/sleep-timer/),
[Pocket Casts on the App Store](https://apps.apple.com/app/414834813),
[The Sweet Setup on Overcast](https://thesweetsetup.com/like-overcast/),
[MacStories: Overcast Watch and Shortcuts](https://www.macstories.net/reviews/overcast-revamps-apple-watch-app-and-shortcuts-actions/),
[iClarified: Overcast Voice Boost 2 and per-podcast skips](https://www.iclarified.com/74295/overcast-podcast-player-gets-voice-boost-2-perpodcast-skip-durations-for-introsoutros-more).
