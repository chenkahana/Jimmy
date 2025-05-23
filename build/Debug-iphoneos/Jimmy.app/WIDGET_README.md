# Jimmy Lock Screen Widget

This document explains the lock screen widget implementation for the Jimmy podcast app.

## Features

The lock screen widget displays:
- Episode artwork (40x40 points)
- Episode title (truncated if too long)
- Playback progress timeline
- Three control buttons:
  - Seek backward 15 seconds
  - Play/Pause toggle
  - Seek forward 15 seconds

## Setup Instructions

### 1. Widget Extension Target

You need to create a Widget Extension target in Xcode:

1. File → New → Target
2. Choose "Widget Extension"
3. Name it "JimmyWidgetExtension"
4. Ensure "Include Configuration Intent" is checked

### 2. App Groups Configuration

Both the main app and widget extension need to be configured with App Groups:

1. In your Apple Developer Account:
   - Create an App Group with identifier: `group.com.chenkahana.jimmy`

2. In Xcode:
   - Select the main app target → Signing & Capabilities → Add App Groups
   - Select the widget extension target → Signing & Capabilities → Add App Groups
   - Enable the same App Group for both targets

### 3. Files Structure

The implementation includes these files:

- `JimmyWidgetBundle.swift` - Widget bundle configuration
- `JimmyWidgetExtension.swift` - Main widget implementation
- `WidgetIntents.swift` - App Intents for button actions
- `WidgetDataService.swift` - Shared data management
- `Jimmy.entitlements` - Main app entitlements
- `JimmyWidgetExtension.entitlements` - Widget entitlements
- `JimmyWidgetExtension-Info.plist` - Widget Info.plist

### 4. Build Configuration

Make sure to:
1. Add the widget files to the Widget Extension target only
2. Add `WidgetDataService.swift` to both targets (main app and widget)
3. Add `Episode.swift` model to both targets
4. Configure proper bundle identifiers (widget should be `com.yourcompany.jimmy.widget`)

## Usage

1. Build and run the app on a device (widgets don't work in simulator for lock screen)
2. Go to Settings → Face ID & Passcode → Customize Lock Screen
3. Tap "Add Widgets"
4. Find "Jimmy Player" and add it
5. The widget will appear on your lock screen when an episode is playing

## Technical Details

### Data Sharing

The widget uses App Groups and UserDefaults to share data between the main app and widget:
- Current episode information
- Playback state (playing/paused)
- Progress information (position/duration)

### Update Strategy

The widget updates:
- Every 30 seconds when playing
- Every 5 minutes when paused
- Immediately when user interacts with controls

### Interactive Elements

The widget uses App Intents for button interactions:
- `PlayPauseIntent` - Toggles playback
- `SeekBackwardIntent` - Seeks back 15 seconds
- `SeekForwardIntent` - Seeks forward 15 seconds

All intents communicate directly with the `AudioPlayerService` singleton.

## Troubleshooting

- **Widget not appearing**: Check App Groups configuration
- **Buttons not working**: Verify App Intents are properly registered
- **Data not syncing**: Ensure both targets have the same App Group
- **Images not loading**: Check network permissions in widget Info.plist 