//
//  TabBarDesignTokens.swift
//  Jimmy
//
//  Design tokens for Liquid Glass tab bar implementation
//

import SwiftUI

/// Design tokens for the Liquid Glass tab bar
/// Values adapt based on horizontal size class (compact vs regular)
struct TabBarDesignTokens {
    
    // MARK: - Size Class
    
    let sizeClass: UserInterfaceSizeClass
    
    init(sizeClass: UserInterfaceSizeClass = .compact) {
        self.sizeClass = sizeClass
    }
    
    // MARK: - Bar Metrics
    
    /// Height of the tab bar (excluding safe area)
    var barHeight: CGFloat {
        switch sizeClass {
        case .compact:
            return 56
        case .regular:
            return 62
        @unknown default:
            return 56
        }
    }
    
    /// Corner radius for the floating pill shape
    var pillCornerRadius: CGFloat {
        switch sizeClass {
        case .compact:
            return 24
        case .regular:
            return 28
        @unknown default:
            return 24
        }
    }
    
    /// Horizontal edge inset to prevent edge hugging
    var horizontalEdgeInset: CGFloat {
        switch sizeClass {
        case .compact:
            return 14
        case .regular:
            return 16
        @unknown default:
            return 14
        }
    }
    
    /// Extra bottom safe area inset (only if needed)
    var bottomSafeInsetExtra: CGFloat {
        return 10 // Use sparingly, prefer system defaults
    }
    
    // MARK: - Item Spacing
    
    /// Spacing between tab items
    var itemInterSpacing: CGFloat {
        switch sizeClass {
        case .compact:
            return 22
        case .regular:
            return 26
        @unknown default:
            return 22
        }
    }
    
    /// Minimum hit target size for accessibility
    let itemMinHitSize: CGSize = CGSize(width: 44, height: 44)
    
    // MARK: - Icon Metrics
    
    /// Point size for tab icons
    var iconPointSize: CGFloat {
        switch sizeClass {
        case .compact:
            return 20
        case .regular:
            return 22
        @unknown default:
            return 20
        }
    }
    
    /// Font weight for unselected icons
    let iconWeightUnselected: Font.Weight = .regular
    
    /// Font weight for selected icons
    let iconWeightSelected: Font.Weight = .semibold
    
    // MARK: - Label Metrics
    
    /// Font for tab labels (Footnote: 11-12pt)
    let labelFont: Font = .footnote
    
    /// Font weight for unselected labels
    let labelWeightUnselected: Font.Weight = .regular
    
    /// Font weight for selected labels
    let labelWeightSelected: Font.Weight = .semibold
    
    // MARK: - Opacity
    
    /// Opacity for unselected items
    let unselectedOpacity: Double = 0.78
    
    /// Opacity for selected items
    let selectedOpacity: Double = 1.0
    
    // MARK: - Selection Capsule
    
    /// Fill opacity for selection capsule (quaternary system fill)
    let capsuleFillOpacity: Double = 0.10 // ~8-12%
    
    /// Stroke width for selection capsule
    let capsuleStrokeWidth: CGFloat = 1.0
    
    /// Stroke opacity for selection capsule (normal)
    let capsuleStrokeOpacity: Double = 0.14 // ~12-16%
    
    /// Stroke opacity for selection capsule (Increase Contrast)
    let capsuleStrokeOpacityHighContrast: Double = 0.30
    
    /// Horizontal padding around selection capsule
    let capsuleHorizontalPadding: CGFloat = 9
    
    // MARK: - Animation
    
    /// Animation duration for selection changes (milliseconds)
    let animationDurationMs: Double = 200 // 180-220ms range
    
    /// Spring response for animations
    let springResponse: Double = 0.35
    
    /// Spring damping for animations
    let springDamping: Double = 0.85
    
    /// Animation for selection changes
    var selectionAnimation: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }
    
    /// Crossfade animation for Reduce Motion
    var crossfadeAnimation: Animation {
        .easeInOut(duration: animationDurationMs / 1000.0)
    }
    
    // MARK: - Discover Search Pill
    
    /// Height of the unfocused search pill
    var searchPillHeight: CGFloat {
        switch sizeClass {
        case .compact:
            return 34
        case .regular:
            return 36
        @unknown default:
            return 34
        }
    }
    
    /// Corner radius for search pill
    let searchPillCornerRadius: CGFloat = 18
    
    /// Horizontal padding inside search pill
    var searchPillHorizontalPadding: CGFloat {
        switch sizeClass {
        case .compact:
            return 12
        case .regular:
            return 14
        @unknown default:
            return 12
        }
    }
    
    /// Opacity for search pill
    let searchPillOpacity: Double = 0.92
    
    /// Placeholder text for search pill
    let searchPillPlaceholder: String = "Search"
    
    // MARK: - Split Layout
    
    /// Gap between tabs capsule and search capsule
    var interCapsuleGap: CGFloat {
        switch sizeClass {
        case .compact:
            return 12
        case .regular:
            return 14
        @unknown default:
            return 12
        }
    }
    
    /// Corner radius for tabs capsule
    let tabsCapsuleCornerRadius: CGFloat = 24
    
    /// Corner radius for search capsule when focused
    let searchCapsuleFocusedCornerRadius: CGFloat = 24
    
    // MARK: - Minimize/Regrow Animation
    
    /// Spring response for minimize animation
    let minimizeSpringResponse: Double = 0.35
    
    /// Spring damping for minimize animation
    let minimizeSpringDamping: Double = 0.85
    
    /// Spring response for regrow animation
    let regrowSpringResponse: Double = 0.4
    
    /// Spring damping for regrow animation
    let regrowSpringDamping: Double = 0.8
    
    /// Animation for minimize
    var minimizeAnimation: Animation {
        .spring(response: minimizeSpringResponse, dampingFraction: minimizeSpringDamping)
    }
    
    /// Animation for regrow
    var regrowAnimation: Animation {
        .spring(response: regrowSpringResponse, dampingFraction: regrowSpringDamping)
    }
    
    // MARK: - Accessibility Overrides
    
    /// Get animation based on Reduce Motion setting
    func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? crossfadeAnimation : selectionAnimation
    }
    
    /// Get capsule stroke opacity based on Increase Contrast setting
    func capsuleStrokeOpacity(increaseContrast: Bool) -> Double {
        increaseContrast ? capsuleStrokeOpacityHighContrast : capsuleStrokeOpacity
    }
}

// MARK: - Environment Key

private struct TabBarDesignTokensKey: EnvironmentKey {
    static let defaultValue = TabBarDesignTokens()
}

extension EnvironmentValues {
    var tabBarDesignTokens: TabBarDesignTokens {
        get { self[TabBarDesignTokensKey.self] }
        set { self[TabBarDesignTokensKey.self] = newValue }
    }
}

extension View {
    /// Apply tab bar design tokens based on size class
    func tabBarDesignTokens(_ sizeClass: UserInterfaceSizeClass) -> some View {
        environment(\.tabBarDesignTokens, TabBarDesignTokens(sizeClass: sizeClass))
    }
}
