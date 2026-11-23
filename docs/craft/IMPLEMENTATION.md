RESUME HERE (2026-11-23): PR #54 (J-07, J-12, J-37, J-35), PR #55 (J-24/J-03 zoom morph), PR #56 (J-30/J-11 VoiceOver) all open on chenkahana/Jimmy. Next: merge all three when CI is green, then the remaining non-device backlog batch.

# Implementation tracker

Chen approved implementation 2026-11-18 for backlog items that don't need his decision. One PR per slice of
`R5-backlog.md` R5.3, branch `craft/<id>-<slug>`, worktree `~/.worktrees/Jimmy/<branch-tail>`, squash-merged when CI
is green. Simulator checks on a dedicated iPhone Duo (iOS 27.1) "Jimmy Impl", driver and captures under
`~/tmp/codex/jimmy-impl/`.

## Top items (lead's order)

- [x] J-01 Mini player Play/Skip 44 pt targets — PR https://github.com/chenkahana/Jimmy/pull/41
- [x] J-22 Now Playing chevron, •••, Speed/Sleep/Chapters targets — PR https://github.com/chenkahana/Jimmy/pull/42
- [x] J-30 No nameless "More" duplicate — PR #56: a throwaway XCUITest dumped the real tree (`Accessibility Inspector` isn't scriptable headlessly here) and found the actual bug — the `Menu`'s bridged `UIButton` stayed in the tree unlabeled alongside the labeled one. Fixed with `.accessibilityRepresentation`, which replaces the whole reported subtree instead of trying to suppress pieces of it; the same test confirms the real menu still opens on tap.
- [x] J-06 Queue row Play 44 pt — PR https://github.com/chenkahana/Jimmy/pull/43
- [x] J-11 One VoiceOver stop per queue row — PR #56, same technique and same test rig: `QueueEpisodeRow`'s nested Play button was a real second stop (confirmed: 5 "Play"/"Pause" buttons tree-wide before the fix, across 4 rows + the mini player; 0 after). `.accessibilityRepresentation` collapses the row to one stop with Play/Pause as a custom action; the row still opens episode detail on tap.
- [x] J-23 Player drag follows the finger; flick dismisses with velocity — PR https://github.com/chenkahana/Jimmy/pull/44
- [x] J-26 Haptics and symbol bounce on skip, speed, sleep — PR https://github.com/chenkahana/Jimmy/pull/45
- [x] J-02 No "Queue Is Empty" flash at launch — PR https://github.com/chenkahana/Jimmy/pull/46 (blank pre-first-frame window not changed: needs a Release App Launch trace on an iPhone)
- [x] J-13 One name for Mark Played — PR https://github.com/chenkahana/Jimmy/pull/47
- [x] J-17 Show notes keep paragraphs and links — PR https://github.com/chenkahana/Jimmy/pull/48
- [x] J-16 Cache Top Shows on device; no error page when a cache exists — PR https://github.com/chenkahana/Jimmy/pull/49

## Remaining non-gated

- [x] J-28 + J-29 Hide Chapters with none; fill the ••• menu (Go to Episode, Go to Show) — batch PR https://github.com/chenkahana/Jimmy/pull/53
- [x] J-20 + J-21 One duration and one date format — PR https://github.com/chenkahana/Jimmy/pull/50
- [x] J-14 (naming) + J-32 Naming pass (Follow, Send Feedback, "…") — PR https://github.com/chenkahana/Jimmy/pull/51
- [x] J-18 Podcast hero art on the first frame — PR https://github.com/chenkahana/Jimmy/pull/52
- [x] J-25 Speed slider with presets — batch PR https://github.com/chenkahana/Jimmy/pull/53 (rates above 2× need a device check)
- [x] J-09 Undo for queue Remove; confirm Clear All — batch PR https://github.com/chenkahana/Jimmy/pull/53
- [ ] J-40 Fixed font sizes — skipped: the 10 pt badges and 12–16 pt banner are in dead code (`StatusBadge` only via unused `EpisodeRowView`, `ErrorBannerView` only via unused `PodcastSearchViewModel`); live fixed sizes are capped glyphs
- [x] J-05 Mini player at AX sizes — batch PR https://github.com/chenkahana/Jimmy/pull/53
- [x] J-41 + J-42 VoiceOver announcements — batch PR https://github.com/chenkahana/Jimmy/pull/53 (announcements need device VoiceOver). J-42: nothing to do (skeleton unused; waveform already honors Reduce Motion)
- [x] J-10 Suggestions placeholder rows and Done — batch PR https://github.com/chenkahana/Jimmy/pull/53
- [x] J-31 + J-34 + J-04 Sleep panel, onboarding button, tip copy — batch PR https://github.com/chenkahana/Jimmy/pull/53 (J-04 partial: copy only, placement unchanged)
- [x] J-27 (part) Scrub times emphasized while scrubbing — batch PR https://github.com/chenkahana/Jimmy/pull/53; chapter ticks not done (nothing fills chapters)
- [x] J-24 + J-03 Mini player ↔ Now Playing morph — PR #55: `.navigationTransition(.zoom)` + `matchedTransitionSource`, with J-23's custom drag gesture removed (it fought the zoom transition's own interactive dismiss — the actual cause of the earlier "breaks flick-to-close" failure). The system sheet's built-in interactive dismiss now provides the flick; exact feel still wants a device pass.
- [x] J-36 (part) Restore tab after relaunch — batch PR https://github.com/chenkahana/Jimmy/pull/53; in-tab navigation path not restored
- [x] J-33 + J-15 Feedback form closes on completion; no Library first-load spinner — batch PR https://github.com/chenkahana/Jimmy/pull/53
- [ ] J-19 Pinned header stacking (needs an iPhone check)
- [ ] J-08 Long-press reorder (needs a device check)
- [ ] J-38 CarPlay artwork and rate button (needs CarPlay)
- [x] J-39 (part) Watch rows as buttons, named skip buttons, wording — batch PR https://github.com/chenkahana/Jimmy/pull/53; skip intervals from phone settings and artwork need a Watch

## Waiting: Chen

All product decisions for this section were delegated to the implementer; defaults from `R5-backlog.md`
("Questions only Chen can answer") were applied and are shipped in PR #54:

- [x] J-07 Swipe action tints — system colors for swipe actions only; `design.md`'s one-accent rule now lists swipe actions as its exception — PR #54
- [x] J-12 Downloads view — built (`docs/design.md`'s promised Downloads segment: in progress, failed, done, space used) — PR #54
- [x] J-37 Lock Screen chapters, rate, "next track" — "next" = start the next queued episode, current one keeps its position; also speed and chapter info — PR #54
- [x] J-35 App Intents, widgets, controls — App Intents (Siri/Shortcuts) first, then Home Screen/Lock Screen widgets and a Control Center control; no Live Activity, no Handoff — PR #54

## Device checks owed

- J-30, J-11: fixed in PR #56, verified by an XCUITest tree dump; still wants a real VoiceOver pass on a device (announcement timing, rotor behavior) as a lower-priority confirmation, not a reopen risk.
- J-26: haptics on an iPhone.
- J-02: Release App Launch trace on an iPhone (blank window before the first frame).
- J-23: drag and flick feel on a ProMotion iPhone.
