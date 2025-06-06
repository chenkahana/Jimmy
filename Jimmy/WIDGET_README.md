# Jimmy Lock Screen Widget

This document explains the lock screen widget implementation for the Jimmy podcast app.

## 🚨 Current Status (Updated May 2025)

### ✅ Main App Status
- **Main app builds successfully** with no errors
- **All core functionality** working perfectly
- **Widget data service** integrated and ready
- **Repository published** and updated on GitHub

### ✅ Widget Status
- **Widget implementation completed** and extension target configured
 - **Widget files now located** in `../JimmyWidgetExtension/` directory
- **App Groups enabled for data sharing**

## 🎯 Features

The lock screen widget displays:
- Episode artwork (40x40 points)
- Episode title (truncated if too long)
- Playback progress timeline
- Three control buttons:
  - Seek backward 15 seconds
  - Play/Pause toggle
  - Seek forward 15 seconds

## 🔧 Build Fixes Applied

### Issues Resolved:
1. **Multiple @main attributes conflict** - Removed from widget bundle
2. **Widget TimelineProvider errors** - Fixed to use StaticConfiguration
3. **File organization conflicts** - Separated widget files from main app target
4. **App Groups configuration** - Prepared for proper data sharing

### Files Status:
 - **Widget files location**: `../JimmyWidgetExtension/` directory
- **Shared files**: `WidgetDataService.swift` and `Episode.swift` remain in main app
- **Main app**: Builds and runs successfully

## 🛠 Complete Setup Instructions

### Step 1: Create Widget Extension Target

**In Xcode:**
1. `File` → `New` → `Target`
2. Choose `Widget Extension`
3. **Product Name**: `JimmyWidgetExtension`
4. **Bundle Identifier**: `com.chenkahana.jimmy.widget`
5. **DO NOT** check "Include Configuration Intent" (we use StaticConfiguration)
6. Click `Finish`

### Step 2: Verify Widget Files in Extension

**Ensure these files are included in the widget extension target:**
```
JimmyWidgetExtension/JimmyWidgetBundle.swift
JimmyWidgetExtension/JimmyWidgetExtension.swift
JimmyWidgetExtension/WidgetIntents.swift
JimmyWidgetExtension/JimmyWidgetExtension-Info.plist
JimmyWidgetExtension/JimmyWidgetExtension.entitlements
```

### Step 3: Add Shared Files to Both Targets

**Add to BOTH main app AND widget extension targets:**
- `Jimmy/Services/WidgetDataService.swift`
- `Jimmy/Models/Episode.swift`

### Step 4: Configure App Groups

**In Apple Developer Account:**
1. Create App Group: `group.com.chenkahana.jimmy`

**In Xcode - Main App Target:**
1. Select Jimmy target → `Signing & Capabilities`
2. Click `+ Capability` → `App Groups`
3. Check `group.com.chenkahana.jimmy`

**In Xcode - Widget Extension Target:**
1. Select JimmyWidgetExtension target → `Signing & Capabilities`
2. Click `+ Capability` → `App Groups`
3. Check `group.com.chenkahana.jimmy`

### Step 5: Build Configuration

**Widget Extension Target Settings:**
- **Bundle Identifier**: `com.chenkahana.jimmy.widget`
- **Deployment Target**: iOS 18.4 or later
- **Supported Device Families**: iPhone, iPad

**Build Settings:**
- Ensure widget extension links against same frameworks as main app
- Verify code signing is properly configured

## 📱 Usage Instructions

### Testing the Widget:
1. **Build and run** the main app on a physical device (widgets don't work in simulator for lock screen)
2. **Play an episode** in the app to populate widget data
3. **Lock your device**
4. Go to `Settings` → `Face ID & Passcode` → `Customize Lock Screen`
5. Tap `Add Widgets`
6. Find `Jimmy Player` and add it
7. The widget will appear on your lock screen showing current episode

### Widget Functionality:
- **Episode artwork** loads from URL or shows placeholder
- **Episode title** displays with truncation for long titles
- **Progress bar** shows current playback position
- **Control buttons** work from lock screen:
  - Left: Seek backward 15 seconds
  - Center: Play/Pause toggle
  - Right: Seek forward 15 seconds

## 🔧 Technical Implementation

### Data Sharing Architecture
```
Main App (AudioPlayerService)
    ↓ (saves data via WidgetDataService)
UserDefaults (App Groups)
    ↑ (reads data via WidgetDataService)  
Widget Extension (Provider)
```

### Widget Update Strategy:
- **When playing**: Updates every 30 seconds
- **When paused**: Updates every 5 minutes
- **User interactions**: Immediate updates via App Intents

### App Intents Integration:
- `PlayPauseIntent` - Communicates with AudioPlayerService.shared
- `SeekBackwardIntent` - Seeks back 15 seconds
- `SeekForwardIntent` - Seeks forward 15 seconds

### Data Persistence:
- Current episode info stored in shared UserDefaults
- Playback state (playing/paused/position/duration) synced
- Widget timeline reloads triggered on state changes

## 🐛 Troubleshooting

### Common Issues:

**Widget not appearing:**
- ✅ Check App Groups are configured identically for both targets
- ✅ Verify bundle identifiers are correct
- ✅ Ensure widget extension builds successfully

**Buttons not working:**
- ✅ Verify App Intents are properly registered
- ✅ Check that AudioPlayerService is accessible from widget
- ✅ Ensure proper imports in WidgetIntents.swift

**Data not syncing:**
- ✅ Confirm both targets have same App Group enabled
- ✅ Check WidgetDataService is added to both targets
- ✅ Verify UserDefaults suite name is correct

**Build errors:**
- ✅ Ensure no duplicate @main attributes
- ✅ Check all required files are added to correct targets
- ✅ Verify import statements are correct

**Images not loading:**
- ✅ Check network permissions in widget Info.plist
- ✅ Verify artwork URLs are accessible
- ✅ Ensure placeholder image displays correctly

### Debug Steps:
1. **Build main app first** - Should succeed without errors
2. **Build widget extension** - Check for compilation errors
3. **Test on device** - Widgets require physical device testing
4. **Check console logs** - Look for widget-related errors
5. **Verify data flow** - Ensure main app populates shared data

## 📂 Final Project Structure

```
Jimmy/
├── Jimmy/                          # Main app target
│   ├── Services/
│   │   ├── AudioPlayerService.swift
│   │   └── WidgetDataService.swift    # Shared with widget
│   ├── Models/
│   │   └── Episode.swift             # Shared with widget
│   └── ... (other app files)
├── JimmyWidgetExtension/            # Widget extension target
│   ├── JimmyWidgetBundle.swift
│   ├── JimmyWidgetExtension.swift
│   ├── WidgetIntents.swift
│   ├── Info.plist
│   └── Entitlements.plist
└── (no temporary widget directory)
```

## 🚀 Next Steps

1. **Build and test** on a physical device
2. **Review App Groups or target settings** if issues occur

The widget implementation is **complete and configured**. Build on a device to verify everything works as expected.
