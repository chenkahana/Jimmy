# Legacy Data Fixtures

This directory contains fixtures of the OLD storage formats the app must migrate from. These files represent data structures as they were stored by the app in previous versions.

## Files and Their Mappings

### 1. `saved_podcasts.json`

**What it represents:**  
The legacy UserDefaults storage of followed podcasts.

**App source:**
- **Write location:** `Jimmy/Data/Repositories/GRDBRepositories.swift` (reading legacy data, no longer written by current app)
- **Storage key:** `UserDefaults.standard` key `"saved_podcasts"`
- **Storage method:** Encoded via `JSONEncoder().encode([Podcast])` and stored as binary data

**Structure:**  
JSON array of Podcast objects with the following properties:
- `id`: UUID
- `title`: String
- `cleanTitle`: String (processed version of title with duplicates removed)
- `author`: String
- `description`: String
- `feedURL`: URL
- `artworkURL`: URL? (nullable)
- `autoAddToQueue`: Boolean
- `notificationsEnabled`: Boolean
- `lastEpisodeDate`: Date? (seconds since 2001-01-01; omitted when nil)
- `etag`: String? (HTTP ETag for caching, nullable)
- `lastFetched`: Date? (seconds since 2001-01-01; omitted when nil)

**Date encoding:**  
Plain `JSONEncoder()` with the default `.deferredToDate` strategy: a number of seconds since 2001-01-01 00:00 UTC (e.g. `728215200.0` is 2024-01-29T10:00:00Z). Nil optionals are omitted, not written as `null`.

**Test contents:**  
3 example podcasts:
- Show One: fully populated with all fields
- Show Two: with autoAddToQueue and notificationsEnabled enabled
- Show Three: minimal (nulls for optional fields)

---

### 2. `podcasts.json`

**What it represents:**  
The alternate storage location for podcasts in the Documents/AppData directory (pre-database).

**App source:**
- **Legacy storage:** `Documents/AppData/podcasts.json` (FileStorage utility)
- **Write location:** Previously written by `FileStorage.save()` method
- **Storage method:** `JSONEncoder().encode([Podcast])` written to file

**Structure:**  
Identical to `saved_podcasts.json` — same Podcast object format.

**Relationship to saved_podcasts:**  
In the fixture, one podcast (Show One with ID `550e8400-e29b-41d4-a716-446655440001`) appears in both files to simulate overlap during migration.

**Test contents:**  
2 example podcasts:
- Show One (overlaps with saved_podcasts.json for deduplication testing)
- Show Four (unique to this file)

---

### 3. `episode_queue.json`

**What it represents:**  
The legacy UserDefaults storage of the episode queue.

**App source:**
- **Write location:** `Jimmy/Presentation/ViewModels/QueueViewModel.swift` (legacy fallback)
- **Storage key:** `UserDefaults.standard` key `"episode_queue"`
- **Storage method:** Encoded via `JSONEncoder().encode([Episode])` and stored as binary data

**Structure:**  
JSON array of Episode objects with the following properties:
- `id`: UUID
- `title`: String
- `audioURL`: URL? (nullable)
- `podcastID`: UUID? (nullable)
- `publishedDate`: Date? (seconds since 2001-01-01; omitted when nil)
- `duration`: TimeInterval? (seconds as Double, nullable)
- `artworkURL`: URL? (nullable)
- `description`: String? (nullable)
- `played`: Boolean (legacy, now replaced by `status` flags)
- `isNew`: Boolean
- `localFileURL`: URL? (nullable, for offline episodes)
- `playbackPosition`: TimeInterval (seconds as Double, 0.0 default)
- `lastFetched`: Date? (seconds since 2001-01-01; omitted when nil)
- `status`: Integer (OptionSet: 1=played, 2=queued, 4=playing)
- `starred`: Boolean

**Date encoding:**  
Plain `JSONEncoder()` with the default `.deferredToDate` strategy: a number of seconds since 2001-01-01 00:00 UTC (e.g. `728215200.0` is 2024-01-29T10:00:00Z). Nil optionals are omitted, not written as `null`.

**Test contents:**  
4 example episodes:
- Episode 1: Queued, not yet played
- Episode 2: Partially played (playbackPosition = 1200s)
- Episode 3: Queued, starred
- Episode 4: Fully played (playbackPosition = 3600s = duration)

---

### 4. `listening_stats.json`

**What it represents:**  
The legacy listening statistics and streaks data stored in the app's Documents directory.

**App source:**
- **Write location:** `Jimmy/Services/ListeningStatsService.swift` (line ~init)
- **File path:** `Documents/listening_stats.json`
- **Storage method:** `ListeningStatsService` with its own `JSONEncoder` set to `.iso8601` (`Jimmy/Services/ListeningStatsService.swift:66`)

**Structure:**  
JSON object with the following properties:
- `totalListeningTime`: Number (total seconds as Double)
- `dailyLogs`: Array of DailyLog objects:
  - `dateString`: String in format "yyyy-MM-dd"
  - `seconds`: Number (listening time in seconds for that day)
- `perPodcast`: Object/Dictionary (podcastID string → listening seconds)
- `currentStreakDays`: Integer (consecutive days with listening)
- `longestStreakDays`: Integer (longest streak recorded)
- `lastListenedDate`: ISO8601 DateTime? (nullable, when listening last occurred)
- `episodesCompleted`: Integer (count of episodes marked as fully played)

**Date encoding:**  
- `dailyLogs.dateString`: "yyyy-MM-dd" format (simple string, not ISO8601)
- `lastListenedDate`: ISO8601 format when present: `"2024-01-31T20:30:00Z"`

**Deterministic aspects:**  
- Daily logs are sorted chronologically (oldest first)
- Streak days represent consecutive calendar days with listening activity
- Per-podcast totals sum to totalListeningTime (approximately, allowing for rounding)

**Test contents:**  
- 7 days of listening logs (Jan 25–31, 2024)
- 3 podcasts tracked separately
- 7-day current streak, 12-day longest streak
- 8 episodes completed

---

## Migration Path

During app startup, the following migration sequence occurs:
1. Check UserDefaults for `"saved_podcasts"` → migrate to database if present
2. Check Documents/AppData for `"podcasts.json"` → merge into database if present
3. Check UserDefaults for `"episode_queue"` → migrate to queue table if present
4. Check Documents for `"listening_stats.json"` → use for statistics if present

**Deduplication:**  
When both `saved_podcasts.json` and `podcasts.json` contain the same podcast (by ID), the database insert should handle the duplicate gracefully (INSERT OR IGNORE or similar logic).

---

## Verification Checklist

- [ ] `saved_podcasts.json` parses as `[Podcast]`
- [ ] `podcasts.json` parses as `[Podcast]`
- [ ] `episode_queue.json` parses as `[Episode]`
- [ ] `listening_stats.json` parses as `ListeningStats`
- [ ] All UUID values are valid UUID strings
- [ ] All dates are valid ISO8601 format (or "yyyy-MM-dd" for dailyLogs)
- [ ] Total listening time ≈ sum of dailyLogs + podcasts
- [ ] Episode playbackPosition ≤ episode duration
- [ ] Podcast count in saved_podcasts + unique podcasts in podcasts.json ≈ expected
