import SwiftUI
import UIKit

/// Service for managing keyboard navigation and shortcuts
@MainActor
final class KeyboardNavigationService: ObservableObject {
    static let shared = KeyboardNavigationService()
    
    // MARK: - Published Properties
    @Published var isKeyboardVisible: Bool = false
    @Published var keyboardHeight: CGFloat = 0
    
    // MARK: - Private Properties
    private var notificationObservers: [NSObjectProtocol] = []
    
    private init() {
        setupKeyboardObservers()
    }
    
    deinit {
        Task { @MainActor in
            removeNotificationObservers()
        }
    }
    
    // MARK: - Public Methods
    
    /// Setup keyboard shortcuts for the app
    func setupKeyboardShortcuts() {
        // This would be implemented with UIKeyCommand in a real app
        // For now, we'll focus on basic keyboard navigation support
    }
    
    /// Handle keyboard navigation between focusable elements
    func navigateToNext() {
        // Move focus to next focusable element
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }
    
    /// Handle keyboard navigation to previous focusable element
    func navigateToPrevious() {
        // Move focus to previous focusable element
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }
    
    /// Dismiss keyboard
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    // MARK: - Private Methods
    
    private func setupKeyboardObservers() {
        let notificationCenter = NotificationCenter.default
        
        // Keyboard will show
        let keyboardWillShowObserver = notificationCenter.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleKeyboardWillShow(notification)
            }
        }
        notificationObservers.append(keyboardWillShowObserver)
        
        // Keyboard will hide
        let keyboardWillHideObserver = notificationCenter.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleKeyboardWillHide(notification)
            }
        }
        notificationObservers.append(keyboardWillHideObserver)
    }
    
    private func handleKeyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        
        isKeyboardVisible = true
        keyboardHeight = keyboardFrame.height
    }
    
    private func handleKeyboardWillHide(_ notification: Notification) {
        isKeyboardVisible = false
        keyboardHeight = 0
    }
    
    private func removeNotificationObservers() {
        notificationObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }
}

// MARK: - View Extensions for Keyboard Navigation
extension View {
    /// Add keyboard navigation support to a view
    func keyboardNavigable(
        onNext: (() -> Void)? = nil,
        onPrevious: (() -> Void)? = nil,
        onEscape: (() -> Void)? = nil
    ) -> some View {
        self.onKeyPress(.tab) {
            onNext?()
            return .handled
        }
        .onKeyPress(.escape) {
            onEscape?()
            return .handled
        }
    }
    
    /// Adjust view for keyboard presence
    func keyboardAware() -> some View {
        self.modifier(KeyboardAwareModifier())
    }
}

// MARK: - Keyboard Aware Modifier
struct KeyboardAwareModifier: ViewModifier {
    @StateObject private var keyboardService = KeyboardNavigationService.shared
    
    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardService.isKeyboardVisible ? keyboardService.keyboardHeight : 0)
            .animation(.easeInOut(duration: 0.3), value: keyboardService.isKeyboardVisible)
    }
}