# UserDefaults Storage Limit Fix

## Problem
The app encountered a critical error when trying to store large amounts of data in UserDefaults:

```
CFPrefsPlistSource<0x101181100> (...): Attempting to store >= 4194304 bytes of data in CFPreferences/NSUserDefaults on this platform is invalid.
```

**Root Cause:**
- UserDefaults has a 4MB (4,194,304 bytes) limit on iOS
- The `episodesKey` data had grown to 12.9MB
- The `episodeCacheData` was also using UserDefaults
- Total UserDefaults usage exceeded the platform limit

## Solution
Implemented a comprehensive file-based storage system to replace UserDefaults for large data:

### 1. File Storage Utility (`FileStorage.swift`)
- **Purpose**: Handle large data storage in Documents directory instead of UserDefaults
- **Features**:
  - Automatic migration from UserDefaults
  - Codable object serialization
  - Storage statistics and monitoring
  - Automatic cleanup capabilities

### 2. Episode Storage Migration (`EpisodeViewModel.swift`)
- **Before**: Episodes stored in UserDefaults (`episodesKey`)
- **After**: Episodes stored in `episodes.json` file
- **Migration**: Automatic detection and migration of existing data

### 3. Cache Storage Migration (`EpisodeCacheService.swift`)
- **Before**: Cache stored in UserDefaults (`episodeCacheData`)
- **After**: Cache stored in `episodeCache.json` file with proper Codable structures
- **Migration**: Automatic conversion from old dictionary format to new Codable format

### 4. UserDefaults Cleanup (`UserDefaultsCleanup.swift`)
- **Purpose**: Remove large data from UserDefaults after migration
- **Features**:
  - Usage statistics and monitoring
  - Automatic cleanup of migrated data
  - Warning system for approaching limits

## Technical Implementation

### Data Storage Locations
```
Old: UserDefaults (limited to 4MB total)
├── episodesKey: 12.9MB ❌
├── episodeCacheData: Variable ❌
└── Other settings: ~100KB ✅

New: Hybrid approach
├── UserDefaults (small settings only)
│   ├── podcastsKey: ~31KB ✅
│   ├── queueKey: ~4KB ✅
│   └── App preferences: ~100KB ✅
└── File Storage (unlimited)
    ├── episodes.json: Episode data ✅
    └── episodeCache.json: Cache data ✅
```

### Migration Process
1. **Automatic Detection**: Check if UserDefaults contains large data
2. **Data Migration**: Convert and save to file storage
3. **Cleanup**: Remove migrated data from UserDefaults
4. **Verification**: Ensure data integrity during migration

### Benefits
- **No Storage Limits**: File storage has no 4MB restriction
- **Better Performance**: Large data operations don't impact UserDefaults
- **Data Integrity**: Proper Codable serialization ensures type safety
- **Backward Compatibility**: Automatic migration preserves existing data
- **Monitoring**: Built-in statistics and cleanup utilities

## File Structure
```
Documents/AppData/
├── episodes.json       # All episode data (previously in UserDefaults)
└── episodeCache.json   # Episode cache data (previously in UserDefaults)
```

## Automatic Cleanup
The app now automatically:
1. Detects large UserDefaults data on startup
2. Migrates data to appropriate file storage
3. Removes migrated data from UserDefaults
4. Monitors UserDefaults usage to prevent future issues

## Result
- ✅ UserDefaults usage reduced from >12MB to <100KB
- ✅ No more 4MB limit errors
- ✅ Improved app stability and performance
- ✅ Maintained all existing functionality
- ✅ Seamless migration for existing users 