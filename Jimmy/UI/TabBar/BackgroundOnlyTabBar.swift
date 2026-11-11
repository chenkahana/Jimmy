//
//  BackgroundOnlyTabBar.swift
//  Jimmy
//
//  Background-only tab bar that provides Liquid Glass material without system UI elements
//

import UIKit

/// Custom UITabBar subclass that provides only the Liquid Glass background material.
/// All system UI elements (buttons, indicators, labels) are removed to allow custom overlay.
final class BackgroundOnlyTabBar: UITabBar {
    
    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLiquidGlass()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLiquidGlass()
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureLiquidGlass()
    }
    
    // MARK: - Configuration
    
    /// Configure authentic Liquid Glass appearance
    private func configureLiquidGlass() {
        // Enable translucency for Liquid Glass effect
        isTranslucent = true
        
        // Create transparent appearance with system thin material
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        appearance.backgroundColor = .clear
        
        // Remove selection indicator
        appearance.selectionIndicatorImage = UIImage()
        appearance.selectionIndicatorTintColor = .clear
        
        // Clear all item appearances
        clearItemAppearance(appearance.stackedLayoutAppearance)
        clearItemAppearance(appearance.inlineLayoutAppearance)
        clearItemAppearance(appearance.compactInlineLayoutAppearance)
        
        // Apply appearance
        standardAppearance = appearance
        scrollEdgeAppearance = appearance
        
        // Clear tint colors
        tintColor = .clear
        unselectedItemTintColor = .clear
    }
    
    /// Clear all visual states for a tab bar item appearance
    private func clearItemAppearance(_ itemAppearance: UITabBarItemAppearance) {
        // Clear icon colors
        itemAppearance.normal.iconColor = .clear
        itemAppearance.selected.iconColor = .clear
        itemAppearance.disabled.iconColor = .clear
        itemAppearance.focused.iconColor = .clear
        
        // Clear title text
        let clearTextAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.clear]
        itemAppearance.normal.titleTextAttributes = clearTextAttributes
        itemAppearance.selected.titleTextAttributes = clearTextAttributes
        itemAppearance.disabled.titleTextAttributes = clearTextAttributes
        itemAppearance.focused.titleTextAttributes = clearTextAttributes
        
        // Clear badge
        itemAppearance.normal.badgeBackgroundColor = .clear
        itemAppearance.selected.badgeBackgroundColor = .clear
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        removeSystemUIElements()
    }
    
    /// Remove all system UI elements (buttons, indicators) from the tab bar
    private func removeSystemUIElements() {
        for subview in subviews {
            let className = String(describing: type(of: subview))
            
            // Skip our custom overlay (identified by tag 0x517ABA7)
            if subview.tag == 0x517ABA7 {
                continue
            }
            
            // Remove UITabBarButton and SelectionIndicator subviews
            if className.contains("UITabBarButton") || className.contains("SelectionIndicator") {
                subview.removeFromSuperview()
            } else {
                // Disable interaction and hide remaining system subviews (but not our overlay)
                subview.isUserInteractionEnabled = false
                subview.isHidden = true
            }
        }
    }
}
