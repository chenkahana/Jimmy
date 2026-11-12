# Jimmy design

Calm, artwork-first, native. Jimmy is a sibling of Boaz: a neutral app where the shows supply the color.

## Principles

1. **Content or control.** Every element on screen is artwork, text the listener reads, or something they tap.
   No decorative icons, eyebrow labels, glows, intro cards or wordmarks.
2. **Artwork is the color.** The UI is system background and label colors. The only other color comes from show
   artwork: the Now Playing backdrop, the podcast header band, glass tinted at 0.35–0.45. Text on artwork color must
   pass WCAG 4.5:1.
3. **One accent, three jobs.** Signal marks the primary action, the unplayed dot and the progress fill. Nothing else
   is tinted.
4. **Native first.** `TabView`, `List`, `Form`, `.searchable`, `.swipeActions`, `contextMenu`,
   `ContentUnavailableView`, sheets with detents, `.glass` / `.glassProminent`, zoom transitions, SF Symbols. Custom
   code only for the Now Playing hero and the artwork-color pipeline.
5. **Lists, not cards.** Group with sections, whitespace and weight. Shadows only on floating artwork. Until a
   screen moves to `List` or `Form`, `JimmyCard` draws a flat grouped surface: no border, no shadow.
6. **Liquid Glass on controls only.** Never on content, never glass on glass. Inside glass, use flat fills.
7. **Precise copy.** "38 min left", "Played", "Couldn't refresh 3 shows. Try again." Title-case labels, never all
   caps. An empty state says what will appear and offers one action. No emoji.
8. **Motion answers a touch.** Nothing animates on appear. Haptics only when something is committed.
9. **Bold in one place: Now Playing.** Everything else is quiet.

## Tokens (`Jimmy/Views/Components/DesignSystem.swift`)

| | Value |
|---|---|
| Accent (Signal) | `#3139FB`, dark `#5563FF` (`AccentColor` asset). Boaz's light value; the dark value is lighter than `#3139FB` but keeps white text on filled buttons at 4.5:1 |
| Neutrals | `systemBackground`, `label`, `secondaryLabel`, `tertiaryLabel`, `separator`, grouped backgrounds in `Form` |
| Artwork color | `ArtworkColorExtractor`, made legible before use |
| Type | SF Pro text styles; New York (`.serif`) for show notes and transcripts, line spacing 6. `monospacedDigit()` for times. No `design: .rounded`, no fixed point sizes except capped transport glyphs |
| Spacing | 4, 8, 12, 16, 24, 32; system list margins |
| Radius | artwork 0.18 × side (continuous), nested shapes concentric, sheets and panels use the system radius |
| Motion | panels `.snappy(duration: 0.3)`, paging `.spring(response: 0.38, dampingFraction: 0.82)`, press scale 0.95; Reduce Motion `.easeOut(duration: 0.2)` |
| Haptics | queue add, remove, reorder drop |

## Screens

**Shell.** Tabs: Queue, Library, Search (`Tab(role: .search)`, trailing; its landing page is Discover). The mini
player is `.tabViewBottomAccessory` showing art, title, time left and play. Settings, Import, Stats and Feedback open
from Library's `ellipsis.circle` menu.

**Queue.** A plain `List`. Row: artwork (56–64 pt), title in two lines, then "Show · 42 min left · 3d" in footnote
secondary, a thin accent progress line. The playing episode is first, marked by an animated `waveform`. Native
reorder and swipe actions (Play Next, Remove, Played), `contextMenu`. Footer: "4 episodes · 2 h 10 min". Empty:
"Queue Is Empty" / "Episodes you add appear here." / Browse Shows.

**Now Playing.** Large artwork with a soft shadow on a flat backdrop sampled from it. Title (title3 semibold, two
lines), show (secondary), scrubber with elapsed and remaining time. Transport (15 back, play, 30 forward) in one glass
capsule. Speed, Sleep and Chapters open one shared bottom panel; chapters show their lengths.

**Library.** Artwork grid, adaptive columns, title under each, small accent unplayed count. Segmented Shows / Episodes
/ Downloads. `.searchable`.

**Podcast.** Artwork on a band of its color, title, author, Follow (`.glassProminent`), description in three lines
with More. Episodes use the Queue row. Episode show notes in New York, tint only on links.

**Search / Discover.** Recent searches, Top Shows as a numbered list (it's a ranking), categories as a list. Loading
uses `redacted(.placeholder)` on real rows.

**Settings.** `Form` with sections Playback, Appearance, Sync & Backup, Import & Export, Assistant, About, and the
destructive actions last. Explanations go in section footers. The version appears once, in About.

## Checks for every UI change

- Screenshots in light and dark, at AX5 text size, with Increase Contrast, Reduce Motion and Reduce Transparency.
- `rg -n 'tracking\(|uppercased\(\)|LinearGradient|\.shadow\(|design: \.rounded|font\(\.system\(size|sparkles|ultraThinMaterial'`
  over the touched views returns nothing, except the Now Playing artwork shadow and the capped transport glyphs.
