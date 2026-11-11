# CarPlay Crash Debugging Guide

## Fixes Applied

### 1. **Thread Safety Issues**
- Added dedicated CarPlay dispatch queue to prevent race conditions
- Made all shared resource access thread-safe with proper synchronization
- Added main thread checks for UI-related operations

### 2. **Nil Pointer Protection**  
- Added null safety checks for episode titles and podcast data
- Implemented graceful fallbacks for missing data (e.g., "Unknown Podcast")
- Added proper error handling for template operations

### 3. **Template Management**
- Added completion handlers with error handling for all template operations
- Implemented proper sequential template pushing/popping
- Added safety checks before template updates

### 4. **Resource Management**
- Added weak references to prevent retain cycles
- Implemented proper cleanup in disconnect scenarios
- Added application state checking to prevent background operations

## Debugging Steps

### Step 1: Check Console Logs
When the crash occurs, look for these specific log messages:
```
CarPlay: Scene connecting...
CarPlay: Failed to set root template: [error]
CarPlay: Failed to push queue template: [error]
CarPlay: Failed to reload data: [error]
```

### Step 2: Verify CarPlay Entitlements
Ensure your app has the proper entitlements:
- `com.apple.developer.carplay-audio` ✅ (Present)
- `com.apple.developer.playable-content` ✅ (Present)

### Step 3: Check Queue Data
The crash might occur if:
- QueueViewModel.shared.queue is empty or corrupted
- Episode objects have invalid/empty titles
- PodcastService.shared is not properly initialized

### Step 4: Test Scenarios
Test these specific scenarios:
1. **Empty Queue**: Launch CarPlay with no episodes in queue
2. **Missing Podcast Data**: Ensure episodes have valid podcastID references
3. **Background State**: Test when app is backgrounded during CarPlay connection
4. **Memory Pressure**: Test with low memory conditions

## Common Crash Causes

### 1. **Template Stack Issues**
CarPlay has strict limits on template navigation. The fixes now:
- Properly manage template stack depth
- Use completion handlers to ensure sequential operations
- Add error handling for failed template operations

### 2. **Data Synchronization**
Cross-thread access to shared data can cause crashes. The fixes now:
- Synchronize all shared data access
- Use proper dispatch queues for CarPlay operations
- Add safety checks for data validity

### 3. **Lifecycle Management**
Improper scene lifecycle handling can cause crashes. The fixes now:
- Add proper scene role validation
- Implement graceful connection/disconnection
- Add logging for debugging lifecycle issues

## Testing Checklist

Before deploying, test these scenarios:

- [ ] Connect CarPlay with empty queue
- [ ] Connect CarPlay with queue containing episodes
- [ ] Disconnect/reconnect CarPlay multiple times
- [ ] Background app while CarPlay is connected
- [ ] Play episode from CarPlay queue
- [ ] Add/remove episodes while CarPlay is connected

## If Crashes Continue

If crashes persist after these fixes, gather:

1. **Crash logs** from Settings > Privacy & Security > Analytics & Improvements
2. **Console logs** during CarPlay connection (look for "CarPlay:" prefix)
3. **Memory usage** during crash (use Xcode Memory Debugger)
4. **Specific reproduction steps** that consistently cause the crash

The logs will now provide much more detailed information about what's failing. 