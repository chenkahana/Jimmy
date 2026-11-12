import SwiftUI
import UIKit

@MainActor
class NativeTabBarManager: ObservableObject {
    static let shared = NativeTabBarManager()
    
    @Published var isSearchActive: Bool = false
    
    private var tokens: TabBarDesignTokens {
        // Default to compact, will be updated based on actual size class
        TabBarDesignTokens(sizeClass: .compact)
    }
    
    private init() {
        setupAccessibilityObservers()
    }
    
    private func setupAccessibilityObservers() {
        // Observe reduce transparency changes
        NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on `.main`, per the `queue:` argument.
            MainActor.assumeIsolated { self?.configureNativeAppearance() }
        }
        
        // Observe increase contrast changes
        NotificationCenter.default.addObserver(
            forName: UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on `.main`, per the `queue:` argument.
            MainActor.assumeIsolated { self?.configureNativeAppearance() }
        }
    }
    
    func configureNativeAppearance(sizeClass: UserInterfaceSizeClass = .compact) {
        let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        let increaseContrast = UIAccessibility.isDarkerSystemColorsEnabled
        let tokens = TabBarDesignTokens(sizeClass: sizeClass)
        
        let appearance = UITabBarAppearance()
        
        if reduceTransparency {
            // Use opaque background for reduce transparency
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .systemBackground
        } else {
            // Use translucent background with liquid glass effect
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        }
        
        // Configure item appearance with design tokens
        let itemAppearance = UITabBarItemAppearance()
        
        // Apply opacity from tokens
        let unselectedAlpha = CGFloat(tokens.unselectedOpacity)
        let selectedAlpha = CGFloat(tokens.selectedOpacity)
        
        if increaseContrast {
            // Boost contrast for accessibility
            itemAppearance.normal.iconColor = .secondaryLabel.withAlphaComponent(unselectedAlpha)
            itemAppearance.selected.iconColor = .label.withAlphaComponent(selectedAlpha)
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.secondaryLabel.withAlphaComponent(unselectedAlpha),
                .font: UIFont.systemFont(ofSize: 11, weight: .regular)
            ]
            itemAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor.label.withAlphaComponent(selectedAlpha),
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
            ]
        } else {
            // Standard appearance with tokens
            itemAppearance.normal.iconColor = .secondaryLabel.withAlphaComponent(unselectedAlpha)
            itemAppearance.selected.iconColor = .tintColor.withAlphaComponent(selectedAlpha)
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.secondaryLabel.withAlphaComponent(unselectedAlpha),
                .font: UIFont.systemFont(ofSize: 11, weight: .regular)
            ]
            itemAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor.tintColor.withAlphaComponent(selectedAlpha),
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
            ]
        }
        
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().isTranslucent = !reduceTransparency
    }
    
    func minimizeForSearch() {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        
        if reduceMotion {
            // Use simple fade for reduce motion
            withAnimation(.easeInOut(duration: 0.15)) {
                isSearchActive = true
            }
        } else {
            // Use spring animation
            withAnimation(.spring(response: 0.18, dampingFraction: 0.85)) {
                isSearchActive = true
            }
        }
    }
    
    func restoreFromSearch() {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        
        if reduceMotion {
            // Use simple fade for reduce motion
            withAnimation(.easeInOut(duration: 0.15)) {
                isSearchActive = false
            }
        } else {
            // Use spring animation
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isSearchActive = false
            }
        }
    }
}
