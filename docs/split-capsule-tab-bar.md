# Split Capsule Tab Bar Architecture

## Overview

The split capsule tab bar is an evolution of the Liquid Glass tab bar that separates navigation and search into two distinct floating capsules. This design provides a cleaner visual hierarchy and enables smooth compacting behavior when search is active.

## Architecture

### Two-Capsule Layout

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│  ┌──────────────────────┐  ┌──────────────┐       │
│  │  Tabs Capsule        │  │  Search      │       │
│  │  [5 tab items]       │  │  Capsule     │       │
│  └──────────────────────┘  └──────────────┘       │
│         (left)                  (right)            │
└─────────────────────────────────────────────────────┘
```

### Components

**Location**: `Jimmy/Views/Components/TabBar/`

1. **SplitBarContainer.swift**: Main container that lays out both capsules
2. **TabsCapsuleView.swift**: Left capsule with 5 tab items
3. **SearchCapsuleView.swift**: Right capsule with search pill/field
4. **SplitTabBarState.swift**: Observable state model

## State Management

### SplitTabBarState

**Location**: `Jimmy/Models/SplitTabBarState.swift`

Observable state model using Swift's `@Observable` macro:

```swift
@Observable
@MainActor
final class SplitTabBarState {
    var isSearchFocused: Bool = false
    var searchQuery: String = ""
    var selectedTab: Int = 0
    
    // Computed properties
    var shouldCompactTabs: Bool { isSearchFocused }
    var compactHeightMultiplier: CGFloat { shouldCompactTabs ? 0.65 : 1.0 }
    var tabLabelOpacity: Double { shouldCompactTabs ? 0.0 : 1.0 }
    var shouldShowSearchCapsule: Bool { selectedTab == 0 }
}
```

### State Flow

```
User Action → State Update → UI Reaction

1. Tap Search Pill
   → isSearchFocused = true
   → Tabs compact (height × 0.65, labels fade)
   → Search expands to field

2. Cancel Search
   → isSearchFocused = false
   → Tabs regrow (height × 1.0, labels appear)
   → Search collapses to pill

3. Switch Tab
   → selectedTab = newIndex
   → If leaving Discover: cancel search
   → Search capsule visibility updates
```

## Visual Specifications

### Tabs Capsule

| Property | Value | Description |
|----------|-------|-------------|
| Corner Radius | 24pt | Rounded capsule shape |
| Height (Normal) | 56pt (compact), 62pt (regular) | Full height |
| Height (Compact) | 36.4pt (compact), 40.3pt (regular) | 65% of normal |
| Background | Quaternary system fill @ 80% | Translucent glass |
| Stroke | Separator @ 20% | Subtle outline |
| Item Spacing | 22pt (compact), 26pt (regular) | Space between tabs |
| Min Hit Size | 44×44pt | Accessibility target |

### Search Capsule

| Property | Unfocused | Focused | Description |
|----------|-----------|---------|-------------|
| Corner Radius | 18pt | 24pt | Pill → rounded |
| Height | 32-36pt | Auto | Compact → expanded |
| Background | Quaternary fill @ 92% | System | Translucent |
| Stroke | Separator @ 14% | System | Subtle outline |
| Icon | magnifyingglass | magnifyingglass | SF Symbol |
| Placeholder | "Search" | - | Text label |

### Compacting Behavior

When `isSearchFocused == true`:

- **Tabs Capsule**:
  - Height: 56pt → 36.4pt (65%)
  - Labels: opacity 1.0 → 0.0
  - Icons: remain visible
  - Selected background: opacity 10% → 7%

- **Search Capsule**:
  - Width: compact → expanded
  - Corner radius: 18pt → 24pt
  - Shows search field with keyboard

### Gap Between Capsules

- **InterCapsuleGap**: 10-14pt (adapts to size class)
- Ensures no overlap during transitions
- Maintains visual separation

## Animations

### Spring Parameters

```swift
// Compact/Regrow
response: 0.35
dampingFraction: 0.85
duration: 160-220ms

// Reduce Motion Fallback
crossfade
duration: 100-150ms
```

### Animation Triggers

1. **Search Focus**: Tabs compact, search expands
2. **Search Dismiss**: Tabs regrow, search collapses
3. **Tab Selection**: Selected background moves
4. **Tab Switch**: Search capsule visibility

## Integration

### ContentView Integration

```swift
struct ContentView: View {
    @State private var splitState = SplitTabBarState()
    
    var body: some View {
        TabView(selection: $splitState.selectedTab) {
            // Tab content
        }
        .safeAreaInset(edge: .bottom) {
            SplitBarContainer(state: splitState)
        }
    }
}
```

### DiscoverView Integration

```swift
struct DiscoverView: View {
    @Environment(\.splitTabBarState) var splitState
    
    var body: some View {
        content
            .searchable(
                text: $splitState.searchQuery,
                isPresented: $splitState.isSearchFocused
            )
    }
}
```

## Discover-Only Behavior

The search capsule only appears when the Discover tab is active:

```swift
var shouldShowSearchCapsule: Bool {
    selectedTab == 0 // Discover tab
}
```

### Tab Switching Logic

```swift
func selectTab(_ index: Int) {
    selectedTab = index
    
    // Cancel search when leaving Discover
    if index != 0 && isSearchFocused {
        cancelSearch()
    }
}
```

This ensures:
- Search capsule hidden on non-Discover tabs
- Search cancelled when switching away
- Tabs regrow smoothly
- No layout jumps

## Accessibility

### Dynamic Type

- All text scales with Dynamic Type up to XL
- Icons scale proportionally
- Hit targets remain ≥44×44pt
- Capsule heights adjust if needed

### Reduce Transparency

- Switches to opaque backgrounds
- Increases border opacity by 10-15%
- Maintains visual hierarchy

### Increase Contrast

- Stroke opacity: 14% → 30%
- Label/icon contrast boosted
- Selected background more visible

### Reduce Motion

- Springs → crossfades
- Duration: 220ms → 150ms
- Maintains instant feedback
- No jarring transitions

### VoiceOver

**Search Pill (Unfocused)**:
- Label: "Search"
- Hint: "Double-tap to edit"
- Trait: Button

**Search Field (Focused)**:
- Standard search traits
- "Cancel" action announced
- State changes announced

**Tabs**:
- Clear labels for each tab
- Selected state announced
- Position and count communicated

## Performance

### Optimization Techniques

1. **Conditional Rendering**: Search capsule only when needed
2. **Efficient Animations**: Native SwiftUI animations
3. **State Management**: Minimal updates with `@Observable`
4. **Layout Caching**: Computed properties cached

### Performance Targets

- **Frame Rate**: 60fps minimum (120fps on ProMotion)
- **Animation Duration**: 160-220ms (feels responsive)
- **Memory**: Minimal overhead (<1MB)
- **CPU**: Smooth during rapid state changes

## Testing

### Unit Tests

**Location**: `Tests/JimmyTests/SplitTabBarStateTests.swift`

Tests cover:
- Initial state
- Search focus/unfocus
- Compact state logic
- Tab selection
- Search capsule visibility
- Integration flows

### UI Tests

Tests cover:
- Split capsule layout
- Search focus/unfocus flow
- Tabs compacting/regrowing
- Tab switching during search
- Keyboard interaction

### Snapshot Tests

Captures:
- Split layout (light/dark, compact/regular)
- Unfocused state
- Focused state (tabs compacted)
- With mini-player
- Accessibility variants

## Design Tokens

All visual constants are defined in `TabBarDesignTokens`:

```swift
// Split Layout
var interCapsuleGap: CGFloat { 12-14pt }
let tabsCapsuleCornerRadius: CGFloat = 24
let searchCapsuleFocusedCornerRadius: CGFloat = 24

// Compacting
let compactHeightMultiplier: CGFloat = 0.65
let compactLabelOpacity: Double = 0.0
let compactBackgroundOpacity: Double = 0.07
```

## Migration from Single Bar

### Before (Single Bar)

```
┌─────────────────────────────────────────────────────┐
│  [Tab1] [Tab2] [Tab3] [Tab4] [Tab5]    [Search]   │
└─────────────────────────────────────────────────────┘
```

### After (Split Capsules)

```
┌─────────────────────────────────────────────────────┐
│  ┌──────────────────────┐  ┌──────────────┐       │
│  │ [Tab1] [Tab2] [Tab3] │  │  [Search]    │       │
│  │ [Tab4] [Tab5]        │  │              │       │
│  └──────────────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────┘
```

### Benefits

1. **Visual Hierarchy**: Clear separation of navigation and search
2. **Compacting**: Tabs can shrink without affecting search
3. **Flexibility**: Each capsule can be styled independently
4. **Scalability**: Easy to add more items to either capsule

## Known Limitations

1. **Fixed Layout**: Capsules don't reflow on very small screens
2. **Discover-Only**: Search only available on Discover tab
3. **No Drag**: Capsules are fixed position (not draggable)

## Future Enhancements

- [ ] Adaptive layout for very small screens
- [ ] Search on other tabs (Library, Queue)
- [ ] Customizable capsule positions
- [ ] Drag-to-reorder tabs
- [ ] More capsule types (filters, actions)

## References

- [Apple HIG - Tab Bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [SwiftUI Observable](https://developer.apple.com/documentation/observation/observable())
- [Design Tokens Documentation](./liquid-glass-design-tokens.md)

## Version History

- v1.0 (2025-10-11): Initial split capsule implementation
