# Discover Search Pill Integration

## Overview

The Discover tab features an unfocused search pill that provides quick access to search functionality. When tapped, it activates the search field, minimizes the tab bar, and displays the keyboard. On dismissal, the tab bar regrows smoothly.

## Components

### DiscoverSearchPill

**Location**: `Jimmy/Views/Components/TabBar/DiscoverSearchPill.swift`

A compact, pill-shaped button that appears on the Discover tab when search is not active.

#### Visual Specifications

- **Height**: 34pt (compact), 36pt (regular)
- **Corner Radius**: 18pt
- **Horizontal Padding**: 12pt (compact), 14pt (regular)
- **Opacity**: 0.92
- **Background**: Quaternary system fill
- **Stroke**: 1pt separator @ 14% opacity
- **Icon**: SF Symbol `magnifyingglass` (16pt, medium weight)
- **Placeholder**: "Search"

#### Accessibility

- **Label**: "Search"
- **Hint**: "Double-tap to edit"
- **Button Style**: Plain (no default button styling)

#### Usage

```swift
DiscoverSearchPill {
    // Handle tap - activate search
    isSearchActive = true
}
```

## Integration

### ContentView Integration

The search pill is integrated into `ContentView` as an overlay that appears only when:
1. The Discover tab is selected (`viewModel.selection == 0`)
2. The keyboard is not visible (`!isKeyboardVisible`)
3. Search is not active (`!isSearchActive`)

```swift
// Search pill overlay for Discover tab
if viewModel.selection == 0 && !isKeyboardVisible && !isSearchActive {
    VStack {
        Spacer()
        HStack {
            Spacer()
            DiscoverSearchPill {
                isSearchActive = true
            }
            .frame(width: 200)
            .padding(.trailing, 16)
            .padding(.bottom, 8)
        }
    }
    .transition(.opacity)
}
```

### DiscoverView Integration

The `DiscoverView` uses SwiftUI's `.searchable()` modifier to provide the search functionality:

```swift
.searchable(text: $viewModel.searchText, prompt: "Search for podcasts")
```

## Behavior

### Search Activation Flow

1. User taps the search pill
2. `isSearchActive` is set to `true`
3. Search pill fades out (`.transition(.opacity)`)
4. Search field appears in navigation bar
5. Keyboard appears
6. Tab bar minimizes (hidden via `.toolbar(.hidden, for: .tabBar)`)

### Search Dismissal Flow

1. User taps "Cancel" or dismisses keyboard
2. Keyboard disappears
3. `isKeyboardVisible` becomes `false`
4. Tab bar regrows (shown via `.toolbar(.visible, for: .tabBar)`)
5. Search pill fades in

### Tab Switching During Search

When the user switches tabs while search is active:

```swift
.onChange(of: viewModel.selection) { _ in
    // Cancel search when switching tabs
    if isSearchActive {
        isSearchActive = false
    }
}
```

This ensures:
- Search is cancelled
- Keyboard dismisses
- Tab bar regrows
- No layout jumps

## Animations

### Search Pill Transitions

- **Fade In/Out**: `.transition(.opacity)`
- **Duration**: Inherits from parent animation context

### Tab Bar Minimize/Regrow

- **Minimize**: Spring animation (response: 0.18, damping: 0.85)
- **Regrow**: Spring animation (response: 0.18, damping: 0.85)
- **Reduce Motion**: Crossfade (duration: 150ms)

```swift
.animation(.spring(response: 0.18, dampingFraction: 0.85), value: isKeyboardVisible)
```

## Keyboard Observers

The `ContentView` sets up keyboard observers to track keyboard visibility:

```swift
private func setupKeyboardObservers() {
    NotificationCenter.default.addObserver(
        forName: UIResponder.keyboardWillShowNotification,
        object: nil,
        queue: .main
    ) { _ in
        isKeyboardVisible = true
    }
    
    NotificationCenter.default.addObserver(
        forName: UIResponder.keyboardWillHideNotification,
        object: nil,
        queue: .main
    ) { _ in
        isKeyboardVisible = false
    }
}
```

## Edge Cases

### 1. Rapid Tab Switching
- Search is cancelled immediately when switching tabs
- No lingering keyboard or search state

### 2. App Backgrounding During Search
- Keyboard dismisses automatically (iOS behavior)
- Tab bar regrows when app returns to foreground

### 3. Orientation Changes
- Search pill adapts to new size class
- Layout remains stable

### 4. Accessibility Settings

#### Reduce Motion
- Uses crossfade instead of spring animations
- Duration reduced to 100-150ms

#### Dynamic Type
- Search pill scales with text size
- Maintains minimum hit target (44x44pt)

#### VoiceOver
- Clear accessibility labels
- Announces state changes
- Proper focus order

## Testing

### UI Tests

**Location**: `Tests/JimmyUITests/TabBarUITests.swift`

Tests cover:
- Search pill visibility on Discover tab
- Search pill hidden on other tabs
- Search activation flow
- Search dismissal flow
- Tab switching during search
- Text entry in search field

Run tests:
```bash
xcodebuild test -scheme Jimmy -only-testing:JimmyUITests/TabBarUITests
```

### Manual Testing Checklist

- [ ] Search pill appears on Discover tab
- [ ] Search pill hidden on other tabs
- [ ] Tapping pill activates search
- [ ] Keyboard appears when search activates
- [ ] Tab bar minimizes when search activates
- [ ] Cancel button dismisses search
- [ ] Tab bar regrows when search dismisses
- [ ] Search pill reappears after dismissal
- [ ] Switching tabs cancels search
- [ ] No layout jumps during transitions
- [ ] Works with Reduce Motion enabled
- [ ] Works with Dynamic Type XL
- [ ] VoiceOver announces correctly

## Performance

### Optimization Techniques

1. **Conditional Rendering**: Search pill only renders when needed
2. **Transition Animations**: Uses efficient `.opacity` transition
3. **State Management**: Minimal state updates
4. **Keyboard Observers**: Lightweight notification observers

### Performance Targets

- **Frame Rate**: 60fps minimum (120fps on ProMotion)
- **Animation Duration**: 180-220ms (feels responsive)
- **Memory**: Minimal overhead (single view instance)

## Future Enhancements

Potential improvements:
- [ ] Add microphone icon for voice search
- [ ] Animate pill width on hover (iPad)
- [ ] Add search suggestions dropdown
- [ ] Persist search history
- [ ] Add search filters

## References

- [Apple Human Interface Guidelines - Search](https://developer.apple.com/design/human-interface-guidelines/search)
- [SwiftUI Searchable Modifier](https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:))
- [Keyboard Notifications](https://developer.apple.com/documentation/uikit/uiresponder/1621576-keyboardwillshownotification)
