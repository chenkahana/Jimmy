# Signal 9 Crash Fixes for Jimmy Podcast App

## Problem Analysis
Your app was experiencing Signal 9 (SIGKILL) crashes after a few minutes in the background. Signal 9 crashes are typically caused by:

1. **Excessive memory usage** - App consuming too much RAM
2. **Unauthorized background processing** - Running too many background tasks
3. **System resource exhaustion** - Overwhelming the system with concurrent operations

## Root Causes Identified

### 1. Aggressive Background Processing
- **EpisodeUpdateService** was running every 15 minutes with unlimited concurrent operations
- **BackgroundTaskManager** was scheduling background refresh every 30 minutes
- Multiple TaskGroups running simultaneously without proper resource management
- Blocking network operations using semaphores

### 2. Memory Management Issues
- **AudioPlayerService** had unlimited `playerItemCache` that grew indefinitely
- **EpisodeCacheService** had no size limits, potentially caching hundreds of episodes
- No cache cleanup when app went to background

### 3. Timer and Resource Leaks
- Update timers weren't being stopped when app went to background
- Background tasks were being scheduled aggressively on app startup

## Fixes Applied

### 1. EpisodeUpdateService.swift
```swift
// BEFORE: Aggressive 15-minute updates with unlimited concurrency
private let updateInterval: TimeInterval = 900 // 15 minutes

// AFTER: Reduced to 30 minutes with batched processing
private let updateInterval: TimeInterval = 1800 // 30 minutes

// BEFORE: Unlimited concurrent operations
for podcast in podcasts {
    group.addTask { await self.fetchEpisodesForPodcast(podcast) }
}

// AFTER: Limited to 3 concurrent operations with batching
let maxConcurrentOperations = min(podcasts.count, 3)
let batches = podcasts.chunked(into: maxConcurrentOperations)
```

**Key Changes:**
- ✅ Added app state observers to stop updates when app goes to background
- ✅ Increased update interval from 15 to 30 minutes
- ✅ Limited concurrent operations to max 3 at a time
- ✅ Added batching with delays between batches
- ✅ Converted blocking network calls to proper async/await
- ✅ Added proper cleanup in deinit

### 2. AudioPlayerService.swift
```swift
// BEFORE: Unlimited cache
private var playerItemCache: [String: AVPlayerItem] = [:]

// AFTER: Limited cache with cleanup
private var playerItemCache: [String: AVPlayerItem] = [:]
private let maxCacheSize = 5 // Limit cache to prevent memory issues
```

**Key Changes:**
- ✅ Added cache size limit (5 items max)
- ✅ Clear cache when app goes to background
- ✅ Added cache management methods
- ✅ Proper memory cleanup

### 3. BackgroundTaskManager.swift
```swift
// BEFORE: Aggressive 30-minute background refresh
static let refreshInterval: TimeInterval = 30 * 60 // 30 minutes
static let maxBackgroundTime: TimeInterval = 25 // 25 seconds

// AFTER: Reduced background processing
static let refreshInterval: TimeInterval = 60 * 60 // 60 minutes  
static let maxBackgroundTime: TimeInterval = 15 // 15 seconds
```

**Key Changes:**
- ✅ Increased refresh interval from 30 to 60 minutes
- ✅ Reduced max background time from 25 to 15 seconds
- ✅ Simplified background operations (only podcast data, not episodes)
- ✅ Cancel background tasks when app goes to background
- ✅ Disabled automatic background task scheduling on startup

### 4. EpisodeCacheService.swift
```swift
// BEFORE: Unlimited cache
private var episodeCache: [UUID: CacheEntry] = [:]

// AFTER: Limited cache with size management
private var episodeCache: [UUID: CacheEntry] = [:]
private let maxCacheEntries = 20 // Limit cache size
```

**Key Changes:**
- ✅ Added cache size limit (20 entries max)
- ✅ Added cache size management with LRU eviction
- ✅ Proper cleanup of old entries

### 5. JimmyApp.swift
```swift
// BEFORE: Aggressive background task scheduling on startup
backgroundTaskManager.scheduleBackgroundRefresh()

// AFTER: Disabled automatic background scheduling
// DISABLED: Don't schedule background refresh on startup to prevent Signal 9 crashes
// backgroundTaskManager.scheduleBackgroundRefresh()
```

**Key Changes:**
- ✅ Disabled automatic background task scheduling on app startup
- ✅ Reduced startup load

## Additional Improvements

### Memory Management
- Added proper cache size limits across all services
- Implemented cache cleanup when app goes to background
- Added LRU (Least Recently Used) eviction policies

### Background Processing
- Reduced frequency of background operations
- Limited concurrent operations to prevent resource exhaustion
- Added proper timeouts and cancellation

### Resource Cleanup
- Added proper observer cleanup in deinit methods
- Implemented app state observers to manage resources
- Added cache clearing when app backgrounds

## Expected Results

After these changes, your app should:

1. **Use significantly less memory** - Cache limits prevent unbounded growth
2. **Perform less background processing** - Reduced frequency and scope
3. **Be more respectful of system resources** - Limited concurrency and proper cleanup
4. **Avoid Signal 9 crashes** - No more aggressive background processing

## Monitoring

To verify the fixes are working:

1. **Check memory usage** in Xcode's Memory Debugger
2. **Monitor background task execution** in Console.app
3. **Test leaving app in background** for extended periods
4. **Watch for crash logs** in Settings > Privacy & Security > Analytics & Improvements

The app should now run stably in the background without being terminated by the system. 