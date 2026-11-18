# R5 Backlog

Every R2 finding scored, grouped into workstreams, and sliced into PRs that each make one visible change. Nothing
here is implemented. Chen approves (or reorders) before any PR starts.

Score = severity × reach ÷ effort (S1=4…S4=1; every session=4, daily=3, occasional=2, rare=1; S=1, M=2, L=4), same as
Boaz and Edison. **Needs Chen** = changes a product constraint, a written design rule, or needs his device.

## R5.1 Scored findings, highest first

| # | ID | Finding | Check | Sev | Reach | Eff | Score | Needs Chen |
|---|---|---|---|---|---|---|---|---|
| 1 | J-01 | Mini player Play/Skip hit targets 15–22 pt | 4 | S1 | every session | S | 16 | |
| 2 | J-22 | Now Playing chevron 18 × 10 pt; Speed/Sleep/Chapters 18 pt tall | 4 | S1 | every session | S | 16 | |
| 3 | J-06 | Queue row Play button 32.7 pt | 4 | S2 | every session | S | 12 | |
| 4 | J-23 | Flick doesn't close Now Playing; drag trails the finger | 1 | S2 | every session | S | 12 | |
| 5 | J-30 | Unlabeled duplicate "More" element in Now Playing | 12 | S2 | daily | S | 9 | |
| 6 | J-26 | No haptics or symbol motion on skips, speed, sleep | 2 | S3 | every session | S | 8 | |
| 7 | J-02 | Blank launch window, then "Queue Is Empty" flash | 1, 8, 11 | S2 | every session | M | 6 | N: keep store-then-playback order |
| 8 | J-07 | Gray swipe actions read as disabled | 4, 7 | S3 | daily | S | 6 | Yes: `design.md` one-accent rule |
| 9 | J-11 | Two VoiceOver stops per queue row | 12 | S3 | daily | S | 6 | |
| 10 | J-13 | Mark Played / Played / Mark as Played | 9 | S3 | daily | S | 6 | |
| 11 | J-20 | 42 min vs 41 min for the same episode | 9 | S3 | daily | S | 6 | |
| 12 | J-21 | Four date formats across screens | 9 | S3 | daily | S | 6 | |
| 13 | J-28 | Chapters button shown with no chapters | 8 | S3 | daily | S | 6 | |
| 14 | J-29 | Now Playing ••• menu has one item | 4, 10 | S3 | daily | S | 6 | |
| 15 | J-40 | 22 fixed font sizes (badges 10 pt) | 6 | S2 | occasional | S | 6 | |
| 16 | J-41 | No VoiceOver announcements for outcomes | 12 | S2 | occasional | S | 6 | |
| 17 | J-08 | Long-press drag doesn't reorder outside Edit | 4 | S2 | daily | M | 4.5 | Q; verify on device |
| 18 | J-12 | No Downloads view | 8 | S2 | daily | M | 4.5 | Yes: scope (design.md promises it) |
| 19 | J-16 | Discover charts uncached → error page | 8 | S2 | daily | M | 4.5 | P: cache on device only |
| 20 | J-17 | Show notes lose paragraphs and links | 6 | S2 | daily | M | 4.5 | |
| 21 | J-18 | Podcast hero and backdrop pop in after the zoom | 1, 5 | S2 | daily | M | 4.5 | |
| 22 | J-19 | Pinned "Episodes" header stacks over the title | 5 | S2 | daily | M | 4.5 | Verify on iPhone |
| 23 | J-25 | Speed is a five-segment control | 2 | S2 | daily | M | 4.5 | |
| 24 | J-10 | Suggestions: spinner-only sheet, no Done | 8 | S3 | occasional | S | 4 | |
| 25 | J-14 | Show context menu: only "Unsubscribe" | 9, 4 | S3 | occasional | S | 4 | |
| 26 | J-31 | "Cancel Timer" wraps | 5 | S3 | occasional | S | 4 | |
| 27 | J-32 | Naming drift in Settings and errors; "..." | 9 | S3 | occasional | S | 4 | |
| 28 | J-39 | Watch: fixed 15 s glyphs, tap gestures, no artwork | 3, 9, 12 | S3 | occasional | S | 4 | Device |
| 29 | J-42 | Skeleton shimmer ignores Reduce Motion | 1, 12 | S3 | occasional | S | 4 | |
| 30 | J-03 | Mini player blinks after closing the player | 1 | S3 | daily | M | 3 | |
| 31 | J-05 | Mini player title unreadable at AX5 | 6 | S2 | occasional | M | 3 | |
| 32 | J-09 | No Undo for queue removals; Clear All unconfirmed | 8 | S2 | occasional | M | 3 | Q |
| 33 | J-24 | Player slides in; no morph from the mini player | 1 | S2 | every session | L | 3 | N: transition only, audio untouched |
| 34 | J-27 | Plain slider scrubber | 2 | S3 | daily | M | 3 | |
| 35 | J-36 | Relaunch forgets tab and place | 10 | S3 | daily | M | 3 | |
| 36 | J-37 | Lock Screen: no chapters/rate, next-track disabled | 3 | S3 | daily | M | 3 | Q + device |
| 37 | J-38 | CarPlay text-only lists, no rate button | 3 | S3 | daily | M | 3 | Device |
| 38 | J-35 | No intents, widgets, controls, Spotlight, Handoff | 10 | S2 | daily | L | 2.25 | P; Handoff needs Chen |
| 39 | J-04 | First-run tip covers queue rows | 8 | S4 | rare | S | 1 | |
| 40 | J-15 | Library first load: spinner replaces page | 8 | S4 | rare | S | 1 | |
| 41 | J-33 | Feedback form closes on a timer | 11 | S4 | rare | S | 1 | |
| 42 | J-34 | Onboarding button floats over the last row | 5 | S4 | rare | S | 1 | |

**Top 10** (by score, ties broken by reach): J-01, J-22, J-06, J-23, J-30, J-26, J-02, J-07, J-11, J-13.

## R5.2 Workstreams

| Workstream | Findings | Systems (R4) | Why this order |
|---|---|---|---|
| **W1 Touch** | J-01, J-22, J-06, J-30, J-11, J-05 | R4.3 `.hitTarget()` | Highest scores, all effort S, no design debate. |
| **W2 Player feel** | J-23, J-26, J-28, J-29, J-31, J-25, J-27, J-03, J-24 | R4.1 gesture + emphasized, R4.2 | The surface people touch most; quick wins first, morph (L) last. |
| **W3 Launch and states** | J-02, J-16, J-10, J-15, J-09, J-04, J-41, J-42 | R4.6 state kit | Every session starts here; the empty flash is the first impression. |
| **W4 Words and type** | J-13, J-20, J-21, J-14, J-32, J-33, J-40, J-17 | R4.4, R4.5 String Catalog | Mostly small; the catalog PR makes the rest reviewable. |
| **W5 Artwork and geometry** | J-18, J-19, J-34, J-07 | R4.1 reveal, R4.3 radius | Needs one device check (J-19) and Chen's call on J-07. |
| **W6 Library and queue** | J-12, J-08, J-36 | R4.6 | Downloads view is a scope decision. |
| **W7 System citizen** | J-37, J-38, J-39, J-35 | — | Needs Chen's devices first; App Intents are the cheapest entry. |

## R5.3 PR slices (one visible change each)

Ordered for landing. Each PR: one change, before/after capture with the R0 driver, patch release per Jimmy's
process. "Done when" is what the reviewer checks in the simulator.

| PR | Change | Closes | Done when | Needs Chen |
|---|---|---|---|---|
| 1 | Add `.hitTarget()` (44 pt min frame + `contentShape`) and apply it to the mini player's Play and Skip | J-01 | AX tree shows both ≥ 44 × 44 | |
| 2 | Apply `.hitTarget()` to Now Playing's chevron, ••• and Speed/Sleep/Chapters; remove the unlabeled duplicate | J-22, J-30 | AX tree: all ≥ 44 pt, no nameless button | |
| 3 | Queue row Play button to 44 pt; fold it into the row for VoiceOver (custom action only) | J-06, J-11 | One VoiceOver stop per row; Play still tappable | |
| 4 | Drag-to-dismiss tracks 1:1 and uses predicted end translation | J-23 | 80 pt flick closes; slow 60 pt drag springs back | |
| 5 | Skip buttons: `symbolEffect(.bounce)` + light haptic; selection haptic on speed/sleep changes; success on sleep set | J-26 | Visible bounce in recording; haptics listed in code review | |
| 6 | Hide Chapters when an episode has none; fill the ••• menu (Go to Show, Go to Episode, Share, Mark Played) | J-28, J-29 | No "no chapters" panel; menu has 5 items | |
| 7 | Queue shows nothing (not the empty state) until the store's first answer; launch shows the shell immediately | J-02 | Launch strip has no "Queue Is Empty" frame | N: keep playback restore order |
| 8 | Show notes: render HTML structure (paragraphs, lists, link text with targets) | J-17 | `q-08` capture shows paragraphs and tappable links | |
| 9 | One duration formatter and one episode-date formatter everywhere | J-20, J-21 | Same episode shows the same minutes and date style on Queue, Library, podcast and detail | |
| 10 | String Catalog + naming pass (Mark Played, Follow, Send Feedback, backup names, "…") | J-13, J-14, J-32 | `Localizable.xcstrings` exists; grep finds no "Subscribe", "Mark as Played", "..." in UI strings | |
| 11 | Cache Discover charts on device; show cached charts with an inline retry on failure | J-16 | Airplane mode: Search tab still shows Top Shows | P: on-device cache |
| 12 | Podcast page uses the tile's cached artwork and color on the first frame | J-18 | `l-zoom` strip shows art and backdrop at frame 0 | |
| 13 | Speed as a dial: 0.5–3× in 0.05 steps with presets and a readout | J-25 | Panel capture; VoiceOver adjustable | |
| 14 | Undo toast for queue Remove / Clear Played; confirm Clear All | J-09 | Remove → Undo restores position | Q |
| 15 | Text styles for badges and the error banner; mini player at AX sizes drops Skip and gives the title room | J-40, J-05 | AX5 captures readable | |
| 16 | VoiceOver announcements for download done/failed, import done, sleep timer ended; Reduce Motion for the shimmer | J-41, J-42 | VoiceOver speaks each outcome | |
| 17 | Suggestions: placeholder rows and a Done button | J-10 | Capture shows rows, not a spinner | |
| 18 | Sleep panel layout ("Cancel Timer" on one line), onboarding button on a material bar, tip placement | J-31, J-34, J-04 | Captures | |
| 19 | Scrubber grows on touch, chapter ticks with selection haptic | J-27 | Recording shows growth; chapters ticked | |
| 20 | Mini player ↔ Now Playing morph (shared artwork geometry), no mini-player blink | J-24, J-03 | `p-open` strip shows artwork growing from the accessory | N: transition only |
| 21 | Fix pinned header stacking on the podcast page | J-19 | Verified on an iPhone first | Verify on iPhone |
| 22 | Long-press reorder in the queue without Edit (or drop the claim and keep Edit) | J-08 | Device recording | Q; verify on device |
| 23 | Restore tab and navigation path after relaunch (`SceneStorage`) | J-36 | `Restore` flow lands on the same podcast page | |
| 24 | Swipe action tints | J-07 | Captures | **Yes:** `design.md` "one accent" |
| 25 | Downloads segment in Library (in progress, failed, done, space used) | J-12 | Capture of all states | **Yes:** scope |
| 26 | App Intents: Play Queue, Skip Forward/Back, Set Sleep Timer (Siri and Shortcuts) | J-35 (part) | Shortcuts app lists the intents | P: intents run on device |
| 27 | Lock Screen: chapter info, playback-rate command; decide what "next" does | J-37 | Device steps R0.3 #1–4 | **Yes:** what "next" means in a queue |
| 28 | CarPlay artwork in lists, rate button in Now Playing | J-38 | Device steps R0.3 #7 | Device |
| 29 | Watch: skip glyphs from phone Settings, buttons not tap gestures, artwork | J-39 | Device steps R0.3 #8 | Device |
| 30 | Widgets / Control Center control / Live Activity | J-35 (rest) | — | **Yes:** scope |
| 31 | Feedback form closes on send completion, not a timer; Library first-load placeholders | J-33, J-15 | Code review | |

**Systems first?** No separate token PR: PR 1 introduces `.hitTarget()`, PR 4 introduces `Motion.gesture`, PR 9 the
formatters, PR 10 the catalog. Each system lands with its first visible use.

## Questions only Chen can answer

1. **Swipe tints (J-07):** keep `docs/design.md`'s one-accent rule (gray swipes) or allow system colors for swipe
   actions (Play Next blue, Remove red, Played green) as Apple Podcasts and Castro do? Default: allow system colors for swipe actions only, and note it in `design.md`.
2. **Downloads view (J-12):** build the Downloads segment `docs/design.md` promises, or remove it from the spec? Default: build it (offline listening is a private/on-device promise).
3. **"Next" in a queue (J-37):** should AirPods/Lock Screen/CarPlay "next track" skip to the next queued episode
   (marking the current one how: played, or left in place?), or stay disabled and map to skip forward? Default: next = start the next queued episode, leaving the current one in place with its progress.
4. **System reach (J-35):** which first: App Intents/Siri, Lock Screen widget, Control Center control or a Live
   Activity? Handoff to the Mac needs a Mac app or iCloud; is that in scope? Default: App Intents first (cheapest, unlocks Siri, Shortcuts and the Action button), then a Control Center control.
5. **Devices:** 20 minutes with the R0.3 steps (Lock Screen, AirPods, interruptions, CarPlay, Watch) and 10 with
   Instruments (R0.4) on a ProMotion iPhone; until then J-08, J-19, J-37–J-39 stay "verify".
