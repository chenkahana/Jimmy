import SwiftUI

// MARK: - Tab Definition

struct TabDefinitionV3<TabIdentifier: Hashable>: Identifiable {
    let id: TabIdentifier
    let icon: String
    let label: String
    let accessibilityLabel: String?
    let accessibilityHint: String?
    var badge: TabBadgeContent?
    
    init(
        id: TabIdentifier,
        icon: String,
        label: String,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        badge: TabBadgeContent? = nil
    ) {
        self.id = id
        self.icon = icon
        self.label = label
        self.accessibilityLabel = accessibilityLabel ?? label
        self.accessibilityHint = accessibilityHint
        self.badge = badge
    }
}

// MARK: - Badge Content

enum TabBadgeContent {
    case count(Int)
    case alert
}

// MARK: - Tab Bar State

enum TabBarState: Equatable {
    case full
    case minimized
    case withAccessory(height: CGFloat)
}

// MARK: - Tab Bar Dimensions

struct TabBarDimensionsV3 {
    static let heightFull: CGFloat = 64
    static let heightMinimized: CGFloat = 32
    static let cornerRadiusFull: CGFloat = 26
    static let cornerRadiusMinimized: CGFloat = 20
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 10
    static let iconSizeUnselected: CGFloat = 24
    static let iconSizeSelected: CGFloat = 28
    static let labelFontSize: CGFloat = 10
    static let iconLabelSpacing: CGFloat = 4
    static let selectionCornerRadius: CGFloat = 14
    static let selectionVerticalPadding: CGFloat = 8
    static let borderWidth: CGFloat = 0.5
}

// MARK: - Tab Bar Colors

struct TabBarColorsV3 {
    static func iconColor(isSelected: Bool) -> Color {
        isSelected ? .primary : .secondary
    }
    
    static func labelColor(isSelected: Bool) -> Color {
        isSelected ? .primary : .secondary
    }
    
    static func borderOpacity(lightMode: Bool, reduceTransparency: Bool) -> Double {
        if reduceTransparency {
            return 0.4
        }
        return lightMode ? 0.25 : 0.35
    }
    
    static let selectionGradientTop = Color.white.opacity(0.2)
    static let selectionGradientBottom = Color.white.opacity(0.05)
    static let selectionBorderColor = Color.white.opacity(0.3)
}

// MARK: - Tab Bar Animations

struct TabBarAnimationsV3 {
    static let minimization = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let restoration = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let selection = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let press = Animation.spring(response: 0.2, dampingFraction: 0.8)
    static let reducedMotionFade = Animation.easeInOut(duration: 0.15)
    
    static func animation(reduceMotion: Bool, type: AnimationType) -> Animation {
        guard !reduceMotion else { return reducedMotionFade }
        switch type {
        case .minimization: return minimization
        case .restoration: return restoration
        case .selection: return selection
        case .press: return press
        }
    }
    
    enum AnimationType {
        case minimization, restoration, selection, press
    }
}

// MARK: - Tab Bar Error

enum TabBarError: Error {
    case invalidTabCount(Int)
    case missingIcon(String)
    case missingAccessibilityLabel(String)
}
