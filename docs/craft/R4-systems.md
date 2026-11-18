# R4 Systems

Six small systems that turn the R2 findings from one-off fixes into rules. Each is written so it can land as one PR
of tokens plus call-site moves, and each names the R2 findings it closes. Names line up with Boaz's plan
(`quick`, `standard`, `emphasized`, `gesture`) so the three apps share vocabulary.

## R4.1 Motion tokens

**Today:** 31 animation sites use 16 distinct curves (`PLAN.md` starting evidence). `MotionCompatibility.swift:32-37`
already names four (`motion`, `motionGentle`, `motionMicro`, `motionTransition`), but two of them are the same
`.snappy(0.3)`, and the artwork color fade (`easeInOut(0.6)`), image fades (`proMotionEaseInOut(0.2)`), skeleton
shimmer (`linear(1.5)` / `easeInOut(2.0)` forever) and banner springs live outside them.

**Proposal** (`Jimmy/Utilities/Motion.swift`, replacing `MotionCompatibility.swift` and `ProMotionManager`'s
helpers):

| Token | Value | Use | Reduce Motion |
|---|---|---|---|
| `Motion.quick` | `.snappy(duration: 0.2)` | press states, toggles, symbol swaps, selection | `.easeOut(0.15)` |
| `Motion.standard` | `.snappy(duration: 0.3)` | panels (BottomPanel), menus, rows inserting/removing | `.easeOut(0.2)` (today's panel rule) |
| `Motion.emphasized` | `.spring(duration: 0.45, bounce: 0.15)` | Now Playing open/close morph, artwork → detail | cross-fade `.easeOut(0.25)` |
| `Motion.gesture` | `.interactiveSpring(duration: 0.3, extraBounce: 0)` while tracking; on release `.spring(duration: 0.4, bounce: 0.2)` seeded with the gesture's velocity | drag-to-dismiss, panel drag, scrubber | no rubber band, fade |
| `Motion.reveal` | `.easeOut(duration: 0.2)` and only when the content wasn't there at the first frame | artwork/images loading in, backdrop color | none (appear instantly) |

**Rules:**
1. Never animate a value that the finger is driving (`ExpandedNowPlayingView.swift:75` does): track 1:1, animate
   only the release. (J-23)
2. Dismissal is decided by `predictedEndTranslation`, not distance alone; `BottomPanel.swift:67` already does it
   right, copy that into Now Playing. (J-23)
3. Content present at the first frame never animates in: images already in the cache appear without a fade, and the
   artwork backdrop uses the cached color synchronously (`ArtworkColorExtractor` with a memory cache keyed by URL).
   (J-02, J-18)
4. The mini player and the full player share one geometry: the artwork uses
   `matchedTransitionSource`/`navigationTransition(.zoom)` or a matched geometry pair, so open and close run the same
   path. The unused `NowPlayingNamespace` is the hook. (J-24)
5. Every `repeatForever` checks Reduce Motion. (J-42)

## R4.2 Haptic map

**Today:** queue remove (light), queue reorder drop (medium), scrubber release (selection), error banner taps; a
`FeedbackManager` with impact/notification/selection exists but is barely used (`sweeps/haptics.txt`). Nothing on
play/pause, skips, speed, sleep, follow, or downloads.

| Moment | Feedback | Why |
|---|---|---|
| Swipe passes full-swipe threshold | system (comes with `.swipeActions`) | already free |
| Queue reorder lift / drop | `.sensoryFeedback(.selection)` on lift, `.impact(weight: .medium)` on drop | physical object |
| Remove from queue, Clear Played | `.impact(weight: .light)` plus Undo | committed and reversible |
| Skip back / forward | `.impact(weight: .light, intensity: 0.5)` | a detent you feel with eyes off the screen |
| Scrubber crosses a chapter start | `.selection` | detent (J-27) |
| Speed or sleep value changes | `.selection` per step | dial (J-25) |
| Sleep timer set / cancelled | `.success` / none | commit |
| Follow a show | `.success` | commit |
| Download finished (app in foreground) / failed | `.success` / `.error` with a VoiceOver announcement | outcome (J-41) |
| Play / pause | none | the audio is the feedback; Apple does the same |

All through `.sensoryFeedback(_:trigger:)`; retire `Motion.lightHaptic()` etc. and `FeedbackManager` once moved.

## R4.3 Layout tokens

**Today:** `JimmyDesign.Spacing` (4, 8, 12, 16, 24, 32) is used 83 times; 40 paddings are still literals.
`JimmyDesign.Radius` (8, 12, 16, 24) is used rarely; 45 literal radii span 2–24 pt (most common: 12 ×12, 3 ×7,
4 ×6, 16 ×6). Artwork corners are 0.18 × side in three places by hand.

**Proposal:**
- Keep the spacing scale; add `JimmyDesign.Spacing.hairline = 2` for the progress-line gap and replace literal
  paddings in touched files as each PR lands (no sweep PR).
- Radius: one function, `JimmyDesign.Radius.artwork(side:)` = `side * 0.18` continuous, used by the queue row,
  mini player, episode header, Now Playing and show tiles; nested shapes use `ConcentricRectangle` /
  `.containerShape` instead of fixed radii; sheets, panels and glass keep the system radius
  (`BottomPanelStyle.cornerRadius` 28 matches the system sheet). Progress bars and small badges use `Capsule`.
- Hit targets: `JimmyDesign.minHit = 44`, applied with a `.hitTarget()` modifier that sets
  `frame(minWidth: 44, minHeight: 44)` and `contentShape(.rect)` on icon-only and text-only controls. (J-01, J-06,
  J-22)
- The old `liquid-glass-design-tokens.md` tab-bar metrics are retired with the custom tab bar (R2.11); nothing
  carries over.

## R4.4 Type ramp

**Today:** text styles dominate (`.subheadline` 18, `.caption` 16, `.footnote` 13, `.headline` 11, …) but 30
`.system(size:)` calls remain, 22 of them fixed; `JimmyDesign.Typography` defines five aliases that few views use.

| Role | Style | Notes |
|---|---|---|
| Screen title | system large title | nav bar |
| Detail title (episode, Now Playing) | `.title2.bold()` / `.title3.semibold()` | 2–4 lines, tail truncation |
| Row title | `.headline` | 2 lines, 4 at AX sizes (already in `QueueEpisodeRow`) |
| Row metadata | `.footnote` secondary, `monospacedDigit()` | one formatter for times and dates (R4.5) |
| Show notes, transcripts | `.body` in New York (`.serif`), line spacing 6 | per `docs/design.md` |
| Badges | `.caption2.weight(.semibold)` | replaces 10 pt fixed (`StatusBadge.swift`) (J-40) |
| Transport glyphs | `@ScaledMetric` with caps (already) | keep |
| Mini player | `.subheadline.semibold` title; at AX sizes hide skip and keep play, let the title take two lines | (J-05) |

Rule: no `.system(size:)` outside glyphs that have a `@ScaledMetric` and a cap.

## R4.5 Copy rules and the English String Catalog

English only (Chen, 2026-11-18). The catalog exists for review, plurals and consistency, not for translation.

1. **One name per concept.** Follow / Following / Unfollow (not Subscribe); Queue (not Up Next); Mark Played /
   Mark Unplayed everywhere (not "Played", "Mark as Played"); Send Feedback; Back Up Library / Restore Library /
   Export Shows (OPML) / Import Shows to replace the four backup items; Listening Stats out of "Developer".
   (J-13, J-14, J-32)
2. **Title case** for buttons, menu items, section titles and navigation titles; **sentence case** for
   descriptions, footers and alert messages (already the habit; the tip "Jump back into now playing" is a title and
   should be title case).
3. **Real ellipsis** "…" for in-progress text and for items that open a further step ("Choose File…"); never "...".
   (J-32)
4. **One formatter per kind**, through `FormatStyle`: durations via `Duration.formatted(.units(allowed: [.hours,
   .minutes], width: .abbreviated))` with a single rounding rule (round up while listening: "1 min left", never
   "0 min"); dates via one `EpisodeDate.format` with relative ("Today", "Yesterday", "3d") for the last week and
   "Nov 17" otherwise, everywhere. (J-20, J-21)
5. **Plurals and agreement** through the catalog (`^[\(count) episode](inflect: true)` already appears once in
   `LibraryView.swift`; the queue footer builds "1 episode/episodes" by hand in `QueueView.swift:299`).
6. **Errors** say what happened and the next step in plain words, and don't blame the connection unless it's down:
   "Couldn't load Top Shows. Try Again." (J-16)
7. **Adoption:** add `Localizable.xcstrings` with "Use Compiler to Extract Strings" on; SwiftUI `Text("…")` and
   `Button("…")` literals flow in automatically; convert string building in view models to `String(localized:)`.
   No translation targets.
