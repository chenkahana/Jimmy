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
