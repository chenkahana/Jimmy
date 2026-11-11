# GRDB Setup Instructions

## Manual GRDB Installation Required

The CHAT_HELP.md implementation requires GRDB to be added as a Swift Package dependency.

### Steps to Add GRDB:

1. **Open Xcode Project**
   ```bash
   open Jimmy.xcodeproj
   ```

2. **Add Package Dependency**
   - Select the project in the navigator
   - Go to the "Package Dependencies" tab
   - Click the "+" button
   - Enter URL: `https://github.com/groue/GRDB.swift`
   - Select "Up to Next Major Version" with version 6.0.0

3. **Add to Target**
   - Select the "Jimmy" target
   - Add GRDB to the target

### Alternative: Command Line (if available)
```bash
# This would be the ideal approach but requires Xcode 15+
xcodebuild -resolvePackageDependencies -project Jimmy.xcodeproj
```

### Verification
After adding GRDB, the following files should compile without errors:
- `Jimmy/Services/PodcastRepository.swift`
- `Jimmy/Services/FetchWorker.swift`
- `Jimmy/Services/PodcastStore.swift`
- `Jimmy/ViewModels/PodcastViewModel.swift`

### Current Status
✅ All CHAT_HELP.md architecture implemented
❌ GRDB dependency needs manual addition via Xcode
✅ Build will pass once GRDB is added

### Files Implementing CHAT_HELP.md Specification:
- **Repository Pattern**: `PodcastRepository.swift` with GRDB + WAL mode
- **FetchWorker**: `FetchWorker.swift` with Task.detached + GCD barriers
- **Swift Actor**: `PodcastStore.swift` for thread-safe storage
- **ViewModel**: `PodcastViewModel.swift` with AsyncPublisher
- **Background Tasks**: `BackgroundRefreshService.swift` with BGAppRefreshTask
- **Performance Monitoring**: `PerformanceMonitor.swift` with os_signpost 