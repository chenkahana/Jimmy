import SwiftUI
import UIKit

/// Service for managing accessibility features and enhancements
@MainActor
final class AccessibilityService: ObservableObject {
    static let shared = AccessibilityService()
    
    // MARK: - Published Properties
    @Published var isVoiceOverEnabled: Bool = false
    @Published var isReduceMotionEnabled: Bool = false
    @Published var isLargeTextEnabled: Bool = false
    @Published var preferredContentSizeCategory: ContentSizeCategory = .medium
    
    // MARK: - Private Properties
    private var notificationObservers: [NSObjectProtocol] = []
    
    private init() {
        setupAccessibilityObservers()
        updateAccessibilitySettings()
    }
    
    isolated deinit {
        removeNotificationObservers()
    }
    
    // MARK: - Public Methods
    
    /// Announce a message for VoiceOver users
    func announce(_ message: String) {
        guard isVoiceOverEnabled else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
    
    /// Post a layout change notification
    func announceLayoutChange(focusElement: Any? = nil) {
        UIAccessibility.post(notification: .layoutChanged, argument: focusElement)
    }
    
    /// Post a screen change notification
    func announceScreenChange(focusElement: Any? = nil) {
        UIAccessibility.post(notification: .screenChanged, argument: focusElement)
    }
    
    /// Check if accessibility features require special handling
    func shouldUseReducedAnimations() -> Bool {
        return isReduceMotionEnabled
    }
    
    /// Get appropriate font size for current accessibility settings
    func scaledFont(for textStyle: Font.TextStyle, size: CGFloat? = nil) -> Font {
        if let size = size {
            return Font.system(size: size).weight(.regular)
        }
        return Font.system(textStyle)
    }
    
    /// Get minimum touch target size for accessibility
    func minimumTouchTargetSize() -> CGSize {
        return CGSize(width: 44, height: 44)
    }
    
    /// Create accessibility-friendly button with proper sizing
    func accessibleButton<Content: View>(
        action: @escaping () -> Void,
        label: String,
        hint: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(.isButton)
    }
    
    // MARK: - Private Methods
    
    private func setupAccessibilityObservers() {
        let notificationCenter = NotificationCenter.default
        
        // VoiceOver status changes
        let voiceOverObserver = notificationCenter.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateAccessibilitySettings()
            }
        }
        notificationObservers.append(voiceOverObserver)
        
        // Reduce motion changes
        let reduceMotionObserver = notificationCenter.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateAccessibilitySettings()
            }
        }
        notificationObservers.append(reduceMotionObserver)
        
        // Content size category changes
        let contentSizeObserver = notificationCenter.addObserver(
            forName: UIContentSizeCategory.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateAccessibilitySettings()
            }
        }
        notificationObservers.append(contentSizeObserver)
    }
    
    private func updateAccessibilitySettings() {
        isVoiceOverEnabled = UIAccessibility.isVoiceOverRunning
        isReduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
        
        let currentCategory = UIApplication.shared.preferredContentSizeCategory
        preferredContentSizeCategory = ContentSizeCategory(currentCategory)
        isLargeTextEnabled = currentCategory.isAccessibilityCategory
    }
    
    private func removeNotificationObservers() {
        notificationObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }
}

// MARK: - ContentSizeCategory Extension
extension ContentSizeCategory {
    init(_ uiContentSizeCategory: UIContentSizeCategory) {
        switch uiContentSizeCategory {
        case .extraSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .extraLarge: self = .extraLarge
        case .extraExtraLarge: self = .extraExtraLarge
        case .extraExtraExtraLarge: self = .extraExtraExtraLarge
        case .accessibilityMedium: self = .accessibilityMedium
        case .accessibilityLarge: self = .accessibilityLarge
        case .accessibilityExtraLarge: self = .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: self = .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: self = .accessibilityExtraExtraExtraLarge
        default: self = .medium
        }
    }
}

// MARK: - View Extensions for Accessibility
extension View {
    /// Apply accessibility enhancements with proper labels and hints
    func accessibilityEnhanced(
        label: String,
        hint: String? = nil,
        traits: AccessibilityTraits = [],
        identifier: String? = nil
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(traits)
            .accessibilityIdentifier(identifier ?? "")
    }
    
    /// Make view accessible for navigation
    func accessibleNavigation(
        label: String,
        hint: String = "Navigate to this section"
    ) -> some View {
        self.accessibilityEnhanced(
            label: label,
            hint: hint,
            traits: [.isButton, .isHeader]
        )
    }
    
    /// Make view accessible for actions
    func accessibleAction(
        label: String,
        hint: String? = nil
    ) -> some View {
        self.accessibilityEnhanced(
            label: label,
            hint: hint,
            traits: .isButton
        )
    }
    
    /// Apply minimum touch target size
    func minimumTouchTarget() -> some View {
        self.frame(minWidth: 44, minHeight: 44)
    }
    
    /// Apply accessibility-friendly animations
    func accessibleAnimation<V: Equatable>(
        _ animation: Animation?,
        value: V
    ) -> some View {
        let accessibilityService = AccessibilityService.shared
        let finalAnimation = accessibilityService.shouldUseReducedAnimations() ? nil : animation
        return self.animation(finalAnimation, value: value)
    }
}