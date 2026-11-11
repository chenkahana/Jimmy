import SwiftUI

/// Re-usable view that renders a sculpted icon (primary/secondary fill) and manages the long-press scale animation
struct TabIconView: View {
    let systemName: String
    let isSelected: Bool
    
    @StateObject private var animator = TabSelectorAnimator()
    
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .medium)) // Slightly smaller for better alignment
            .symbolRenderingMode(symbolRenderingMode)
            .foregroundStyle(foregroundStyle)
            .scaleEffect(animator.scale)
            .frame(width: 24, height: 24) // Fixed frame for consistent alignment
            .offset(y: iconVerticalOffset)
            .onLongPressGesture(minimumDuration: 0.15) {
                animator.triggerSelection()
            }
    }
    
    /// Vertical offset to align specific icons properly
    private var iconVerticalOffset: CGFloat {
        switch systemName {
        case "globe":
            return 0 // Discover icon - centered
        case "list.bullet":
            return 1.0  // Queue icon - slightly down for optical alignment
        case "play.circle":
            return 0 // Now Playing icon - centered  
        case "waveform":
            return 0 // Library icon - centered
        case "gear":
            return 0 // Settings icon - centered
        default:
            return 0
        }
    }
    
    /// Symbol rendering mode with iOS version fallback
    private var symbolRenderingMode: SymbolRenderingMode {
        if #available(iOS 18, *) {
            return .hierarchical
        } else {
            return .monochrome
        }
    }
    
    /// Foreground style based on selection state
    private var foregroundStyle: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(.primary)
        } else {
            return AnyShapeStyle(.secondary)
        }
    }
} 