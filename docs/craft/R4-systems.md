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
