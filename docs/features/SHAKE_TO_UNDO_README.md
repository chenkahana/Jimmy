# Shake to Undo Feature

## Overview
The Jimmy app now includes a shake-to-undo feature that allows users to quickly undo their last action by shaking their device. This feature works for operations performed within the last minute.

## Supported Operations
The following operations can be undone:

### Subscription Management
- **Unsubscribing from a podcast**: Shake to restore the subscription
- **Subscribing to a podcast**: Shake to remove the subscription

### Queue Management
- **Adding episode to queue**: Shake to remove the episode from queue
- **Removing episode from queue**: Shake to restore the episode at its original position
- **Reordering queue**: Shake to restore the previous queue order
- **Moving episodes in queue**: Shake to restore the episode to its original position

### Excluded Operations
- **Playback position changes**: Listening progress is not affected by shake-to-undo
- **Volume changes**: Audio settings are not undoable
- **Navigation**: Moving between screens is not undoable

## How It Works

### Time Limit
- Operations can only be undone within **60 seconds** of being performed
- After 60 seconds, the operation is no longer undoable

### Shake Detection
- Uses the device's accelerometer to detect shake gestures
- Requires a shake magnitude above 2.5G to trigger
- Includes a 1-second cooldown to prevent multiple triggers

### User Feedback
- **Haptic feedback**: Medium impact when undo is successful, light impact when no action to undo
- **Visual feedback**: Toast notification appears showing what was undone
- **Audio feedback**: No audio feedback to avoid interrupting podcast playback

### Toast Notification
- Appears at the bottom of the screen above the tab bar
- Shows for 3 seconds then automatically disappears
- Displays the description of the undone action
- Uses a dark background with white text for visibility

## Technical Implementation

### Architecture
- `ShakeUndoManager`: Singleton service that handles shake detection and undo operations
- `UndoableOperation`: Enum defining all supported operation types
- `UndoableAction`: Structure containing operation details and timestamp
- `UndoToastView`: SwiftUI view for displaying undo notifications

### Integration Points
- **QueueViewModel**: Records queue operations
- **PodcastService**: Records subscription operations
- **LibraryView**: Records unsubscription operations
- **ContentView**: Displays toast notifications

### Motion Detection
- Uses `CoreMotion` framework's `CMMotionManager`
- Monitors device motion updates at 0.1-second intervals
- Calculates acceleration magnitude to detect shake gestures
- Runs continuously while the app is active

## Usage Examples

1. **Accidentally unsubscribed from a podcast**:
   - Shake your device within 60 seconds
   - See toast: "Undid: Unsubscribed from 'Tech Talk Daily'"
   - Podcast is restored to your library

2. **Removed wrong episode from queue**:
   - Shake your device within 60 seconds
   - See toast: "Undid: Removed 'Episode Title' from queue"
   - Episode is restored to its original position in queue

3. **Reordered queue by mistake**:
   - Shake your device within 60 seconds
   - See toast: "Undid: Reordered queue"
   - Queue is restored to its previous order

## Privacy & Performance

### Privacy
- No motion data is stored or transmitted
- Shake detection only processes acceleration magnitude
- No personal data is collected through this feature

### Performance
- Minimal battery impact from motion monitoring
- Motion updates are processed efficiently on the main queue
- Undo operations are performed synchronously for immediate feedback

### Memory Usage
- Only stores the last undoable action
- Previous actions are automatically cleared when new actions are recorded
- No persistent storage of undo history

## Troubleshooting

### Shake Not Detected
- Ensure device motion is available (not available in simulator)
- Try a more vigorous shake gesture
- Check that the app is in the foreground

### No Action to Undo
- Verify the action was performed within the last 60 seconds
- Ensure the action is one of the supported operations
- Check that a new action hasn't overwritten the previous one

### Toast Not Appearing
- Ensure the app UI is not blocked by other overlays
- Check that the undo operation was successful
- Verify the toast isn't hidden behind other UI elements 