# Liquid Glass Tab Bar Design Tokens

## Overview

This document describes the design tokens used for the Liquid Glass tab bar implementation. These tokens ensure consistent visual design across different device sizes and accessibility settings.

## Design Token Structure

The `TabBarDesignTokens` struct provides centralized constants for all visual aspects of the tab bar. Values automatically adapt based on horizontal size class (compact vs regular).

### Location

- **Implementation**: `Jimmy/Utilities/TabBarDesignTokens.swift`
- **Tests**: `Tests/JimmyTests/TabBarDesignTokensTests.swift`

## Token Categories

### Bar Metrics

| Token | Compact | Regular | Description |
|-------|---------|---------|-------------|
| `barHeight` | 56pt | 62pt | Height of the tab bar (excluding safe area) |
| `pillCornerRadius` | 24pt | 28pt | Corner radius for the floating pill shape |
| `horizontalEdgeInset` | 14pt | 16pt | Horizontal edge inset to prevent edge hugging |
| `bottomSafeInsetExtra` | 10pt | 10pt | Extra bottom safe area inset (use sparingly) |

### Item Spacing

| Token | Compact | Regular | Description |
|-------|---------|---------|-------------|
| `itemInterSpacing` | 22pt | 26pt | Spacing between tab items |
| `itemMinHitSize` | 44x44pt | 44x44pt | Minimum hit target size for accessibility |

### Icon Metrics

| Token | Compact | Regular | Description |
|-------|---------|---------|-------------|
| `iconPointSize` | 20pt | 22pt | Point size for tab icons |
| `iconWeightUnselected` | Regular | Regular | Font weight for unselected icons |
| `iconWeightSelected` | Semibold | Semibold | Font weight for selected icons |

### Label Metrics

| Token | Value | Description |
|-------|-------|-------------|
| `labelFont` | Footnote (11-12pt) | Font for tab labels |
| `labelWeightUnselected` | Regular | Font weight for unselected labels |
| `labelWeightSelected` | Semibold | Font weight for selected labels |

### Opacity

| Token | Value | Description |
|-------|-------|-------------|
| `unselectedOpacity` | 0.78 | Opacity for unselected items |
| `selectedOpacity` | 1.0 | Opacity for selected items |

### Selection Capsule

| Token | Value | Description |
|-------|-------|-------------|
| `capsuleFillOpacity` | 0.10 (8-12%) | Fill opacity for selection capsule |
| `capsuleStrokeWidth` | 1pt | Stroke width for selection capsule |
| `capsuleStrokeOpacity` | 0.14 (12-16%) | Stroke opacity (normal) |
| `capsuleStrokeOpacityHighContrast` | 0.30 | Stroke opacity (Increase Contrast) |
| `capsuleHorizontalPadding` | 9pt | Horizontal padding around capsule |

### Animation

| Token | Value | Description |
|-------|-------|-------------|
| `animationDurationMs` | 200ms | Animation duration (180-220ms range) |
| `springResponse` | 0.35 | Spring response for animations |
| `springDamping` | 0.85 | Spring damping for animations |
| `minimizeSpringResponse` | 0.35 | Spring response for minimize |
| `minimizeSpringDamping` | 0.85 | Spring damping for minimize |
| `regrowSpringResponse` | 0.4 | Spring response for regrow |
| `regrowSpringDamping` | 0.8 | Spring damping for regrow |

### Search Pill

| Token | Compact | Regular | Description |
|-------|---------|---------|-------------|
| `searchPillHeight` | 34pt | 36pt | Height of the unfocused search pill |
| `searchPillCornerRadius` | 18pt | 18pt | Corner radius for search pill |
| `searchPillHorizontalPadding` | 12pt | 14pt | Horizontal padding inside search pill |
| `searchPillOpacity` | 0.92 | 0.92 | Opacity for search pill |
| `searchPillPlaceholder` | "Search" | "Search" | Placeholder text |

## Usage

### Basic Usage

```swift
import SwiftUI

struct MyView: View {
    @Environment(\.horizontalSizeClass) var sizeClass
    
    private var tokens: TabBarDesignTokens {
        TabBarDesignTokens(sizeClass: sizeClass ?? .compact)
    }
    
    var body: some View {
        Text("Hello")
            .frame(height: tokens.barHeight)
            .cornerRadius(tokens.pillCornerRadius)
    }
}
```

### Environment Integration

```swift
// Apply tokens to environment
someView
    .tabBarDesignTokens(.regular)
    
// Access from environment
@Environment(\.tabBarDesignTokens) var tokens
```

### Accessibility Overrides

```swift
// Get animation based on Reduce Motion
let animation = tokens.animation(reduceMotion: UIAccessibility.isReduceMotionEnabled)

// Get capsule stroke opacity based on Increase Contrast
let strokeOpacity = tokens.capsuleStrokeOpacity(increaseContrast: UIAccessibility.isDarkerSystemColorsEnabled)
```

## Accessibility Support

The design tokens automatically adapt to accessibility settings:

### Reduce Motion
- Uses crossfade animations instead of spring animations
- Duration: 100-150ms

### Increase Contrast
- Capsule stroke opacity increases from 14% to 30%
- Label and icon contrast is boosted

### Dynamic Type
- All fonts scale with Dynamic Type up to XL
- Hit targets remain ≥44x44pt

### Reduce Transparency
- Switches from `.ultraThinMaterial` to `.regularMaterial`
- Or uses opaque background

## Testing

Unit tests verify:
- Size class-specific values
- Constant values
- Opacity ranges
- Animation parameters
- Accessibility overrides

Run tests:
```bash
xcodebuild test -scheme Jimmy -only-testing:JimmyTests/TabBarDesignTokensTests
```

## References

- [Apple Human Interface Guidelines - Tab Bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [Apple Human Interface Guidelines - Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple Human Interface Guidelines - Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
