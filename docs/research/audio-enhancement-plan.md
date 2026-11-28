# Audio enhancement plan: loudness, pitch quality, skip silence

Status: proposal. Nothing here is implemented. Written against `main` as of 2026-11-27.

## Why

Side by side with Apple Podcasts on stock settings, on every show and at normal speed, Jimmy sounds worse.
Jimmy already uses the same engine (`AVPlayer`, session `.playback` / `.spokenAudio`), so decode quality is
not the gap. The gap is processing: Jimmy plays the raw file.

What the code does today (`Packages/JimmyKit/Sources/JimmyKit/Playback/AVPlayerEngine.swift`):

- `AVPlayer(playerItem: AVPlayerItem(url:))`, with `rate` and `defaultRate` kept in sync.
- `volume` is `AVPlayer.volume` only. It is 0...1 and cannot amplify. It exists for the sleep-timer fade.
- `audioTimePitchAlgorithm` is never set.
- There is no audio processing at all: no gain, no loudness normalization, no limiter.
- The README advertises "skip silence" and "volume boost". A search of the Swift sources finds no
  implementation of either (only the README line).

Quiet or uneven shows stay quiet and uneven. Apple Podcasts levels them. That is the most likely reason
Jimmy "sounds worse" on every show. This is an inference from the code and the symptom, not a measurement.
Step 0 below confirms it.

## Step 0: measure first (half a day)

Pick 5 to 8 episodes across shows (loud, quiet, music-heavy, two-host, solo). For each, play in Jimmy and in
Apple Podcasts at the same device volume and record the output (or analyze the files offline).

- Measure integrated loudness (LUFS) and true peak per episode, for example with `ffmpeg -af ebur128=peak=true`.
- Write the numbers into `docs/research/audio-loudness-baseline.md`.
- Pass criterion for the project: Jimmy episodes land within about 1 LU of the target on all samples.

If the episodes are already around -16 LUFS, loudness is not the gap and Phase 2 reorders (see Risks).

## Phase 1: pitch quality (trivial, ship first)

Set `audioTimePitchAlgorithm` on the `AVPlayerItem` in `AVPlayerEngine.load(url:startPosition:)`.

- `.spectral` when rate != 1.0 (higher quality for sped-up speech, more CPU).
- `.timeDomain` is the current default on iOS 15+ and is cheaper. Keep it as the fallback for Apple Watch
  and low-power mode.
- Make it a single `PlaybackQuality` choice read by the engine, not a scattered conditional.
- Test: unit test that the engine sets the algorithm for a rate change (the engine already has a fake
  `PlayerEngine` seam in tests).

Expected effect: cleaner speech at 1.25x and above. No effect at 1.0x.

## Phase 2: real volume boost and loudness normalization (the main win)

`AVPlayer.volume` cannot go above 1.0, so gain must be applied in the audio path.

### Approach: `MTAudioProcessingTap` on the AVPlayerItem

Attach a tap through `AVMutableAudioMix` on the item's audio track. It keeps `AVPlayer`, so the existing
queue, now-playing, remote commands, rate handling, seeking and background behavior are untouched. Do not
move to `AVAudioEngine` for this: `AVAudioPlayerNode` wants files or buffers, which would mean rebuilding
streaming, buffering and seek, and the risk is much larger than the gain.

Tap processing chain (mono or stereo float, in the tap's process callback):

1. Per-episode gain (dB), from the loudness estimate below.
2. A soft-knee compressor, light (about 2:1 above -24 dBFS, slow release) so quiet voices come up without pumping.
3. A true-peak limiter at about -1 dBFS so the gain can never clip.

All DSP lives in a small, allocation-free C or Swift-with-unsafe-pointers type (`LoudnessProcessor`) with no
locks in the callback. Parameters are passed through an atomic struct so the UI can change them live.

### Where the gain comes from

- Downloaded episodes: analyze once after download with `AVAssetReader` (K-weighted loudness per ITU-R BS.1770
  / EBU R128 on a background queue), store `integratedLUFS` and `truePeak` with the episode in the store. Gain =
  target minus measured, clamped.
- Streamed episodes: no whole-file measurement is available. Start with a neutral gain plus the compressor and
  limiter, run a short-window running loudness estimate over the first 30 to 60 seconds, and ease the gain
  toward target (slow, over several seconds, never jumpy). Persist the estimate when the episode finishes or
  downloads.

Target: -16 LUFS integrated (the common podcast target; Apple's own guidance is -16 LUFS for stereo, with a peak
under -1 dBTP). Clamp gain to +12 dB and -12 dB.

### User-facing setting

"Volume boost" in Player settings (already advertised in the README), three levels:

- Off: today's behavior, no tap attached.
- Normal: normalize to -16 LUFS.
- High: normalize to about -14 LUFS plus the compressor, for noisy environments.

Default: Normal, because the goal is to match or beat Apple Podcasts out of the box. It is a global setting
first. A per-show override can follow, as Apple does for Enhance Dialogue.

### Constraints and known limits

- `MTAudioProcessingTap` works on progressive files (mp3, m4a) and local files. It has historically not
  worked on HLS streams. If a feed serves HLS audio, fall back to the Phase 1 setup with `volume` unchanged
  and show nothing broken. Verify against Jimmy's real feeds before committing.
- Tap on watchOS and CarPlay: CarPlay shares the iPhone engine and is covered. The Watch target
  (`JimmyWatch`) needs its own check and may ship Off only.
- Bypass the tap entirely when Off so there is no cost.
- The sleep-timer fade keeps using `AVPlayer.volume`. It runs after the processing, so it is unaffected.

### Files

- New: `Playback/LoudnessProcessor.swift`, `Playback/LoudnessTap.swift`, `Playback/LoudnessAnalyzer.swift`.
- Change: `AVPlayerEngine.swift` (attach tap in `load`), `PlayerEngine.swift` (add `audioEnhancement`),
  the episode store model (loudness fields), Player settings UI.
- Schema: additive fields only, so existing stores migrate without changes.

### Tests

- Unit: gain math, limiter never exceeds -1 dBTP on a synthetic +6 dB sine and a full-scale square wave,
  compressor ratio on a known ramp, clamp behavior.
- Golden files: 3 short fixtures (quiet voice, loud voice, music bed). Process offline through
  `LoudnessProcessor` and assert output LUFS is within 1 LU of target.
- Manual: A/B against Apple Podcasts on the Step 0 episodes, same device, same volume.
- Real-time safety: run the tap under Instruments (Audio System Trace). No allocations or locks in the callback.

## Phase 3: skip silence that actually works

README advertises it; nothing implements it. Do not gate audio in the tap, because that does not make the
episode shorter.

- Downloaded episodes: during the Phase 2 analysis pass, also record silence ranges (below about -45 dBFS for
  at least 0.4 s). Store them with the episode.
- Playback: when the playhead enters a stored range, either seek past it, or (smoother) ramp `rate` up to
  about 4x until the range ends, then ramp back. Keep a 100 to 150 ms pad at each end so words are not clipped.
- Streamed episodes: no skipping until analyzed. Do not guess in real time.
- Setting: "Skip silence" on/off, plus a running "time saved" counter, which is a good thing to show.
- Test: fixtures with known pauses, assert ranges within 50 ms, and that skipping never cuts into speech.

## Phase 4: dialogue enhancement (only if still needed)

Apple's Enhance Dialogue in Apple Podcasts is its own on-device ML feature and has no public API that a
third-party app can call, as far as public sources show. If Phases 1 to 3 do not close the gap, add a cheap
speech EQ in the same tap (high-pass at about 80 Hz, gentle 2 to 4 kHz presence boost, light noise gate) as a
"Voice clarity" toggle. A model-based approach is a separate, larger project and should not be started now.

## Order and size

| Phase | Work | Size | Risk |
| --- | --- | --- | --- |
| 0 | Measure baseline | 0.5 day | none |
| 1 | `.spectral` pitch | under 0.5 day | low |
| 2 | Tap, gain, limiter, analysis, setting | 4 to 6 days | medium (real-time audio, HLS) |
| 3 | Skip silence from analysis | 2 to 3 days | low to medium |
| 4 | Voice clarity EQ | 1 to 2 days | low |

Ship Phase 1 alone as a small PR. Phase 2 in two PRs: processor plus tests first, wiring and setting second.

## Risks

- Phase 0 shows episodes already near -16 LUFS. Then the gap is something else (for example Enhance Dialogue,
  or Apple using a different source file or bitrate). Re-measure with Enhance Dialogue off in Apple Podcasts
  and compare the files, then revisit the order.
- HLS feeds bypass the tap. Mitigation: measure how many of Jimmy's feeds are HLS.
- Aggressive compression sounds worse than none. Keep the default light, and expose only the three levels.

## Sources

- Apple, AVPlayerItem `audioTimePitchAlgorithm` documentation (timeDomain default on iOS 15+, spectral for higher quality).
- Apple, `MTAudioProcessingTap` and `AVMutableAudioMix` documentation.
- Apple, iOS 26 Apple Podcasts notes (Enhance Dialogue): https://podcasters.apple.com/support/5549-iOS-26-whats-new-for-apple-podcasts
- ITU-R BS.1770 / EBU R128 for loudness measurement.

The tap-versus-engine choice, the targets and the effort sizes above are recommendations to confirm, not
verified facts.
