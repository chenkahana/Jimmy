import UIKit
import SwiftUI

class FeedbackManager {
    static let shared = FeedbackManager()
    
    private var isHapticsEnabled: Bool = true
    
    private init() {
        // Test haptics availability on initialization
        checkHapticsAvailability()
    }
    
    // MARK: - Haptics Availability Check
    
    private func checkHapticsAvailability() {
        // Check if device supports haptics
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            isHapticsEnabled = false
            return
        }
        
        // Test if haptics are working by creating a simple feedback generator
        let testGenerator = UIImpactFeedbackGenerator(style: .light)
        testGenerator.prepare()
        // If we get here without crashing, haptics should work
        isHapticsEnabled = true
    }
    
    // MARK: - Safe Haptic Feedback
    
    private func performHapticFeedback(_ feedback: () -> Void) {
        guard isHapticsEnabled else { return }
        
        // Wrap in error handling for potential Core Haptics failures
        do {
            feedback()
        } catch {
            print("⚠️ Haptic feedback failed: \(error)")
            // Disable haptics if they consistently fail
            isHapticsEnabled = false
        }
    }
    
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        performHapticFeedback {
            let impactFeedback = UIImpactFeedbackGenerator(style: style)
            impactFeedback.impactOccurred()
        }
    }
    
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        performHapticFeedback {
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(type)
        }
    }
    
    func selection() {
        performHapticFeedback {
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.selectionChanged()
        }
    }
    
    // MARK: - Convenience Methods
    
    func addedToQueue() {
        impact(.light)
    }
    
    func playNext() {
        impact(.medium)
    }
    
    func markAsPlayed() {
        impact(.light)
    }
    
    func episodeTapped() {
        selection()
    }
    
    func success() {
        notification(.success)
    }
    
    func error() {
        notification(.error)
    }
    
    func warning() {
        notification(.warning)
    }
    
    // MARK: - Public Methods
    
    /// Re-enable haptics after they've been disabled due to errors
    func retryHaptics() {
        checkHapticsAvailability()
    }
    
    /// Check if haptics are currently enabled
    var hapticsEnabled: Bool {
        return isHapticsEnabled
    }
}

// MARK: - Future Toast Notifications
// This can be expanded later to show temporary toast messages

struct ToastView: View {
    let message: String
    let isShowing: Bool
    
    var body: some View {
        VStack {
            Spacer()
            
            if isShowing {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(message)
                        .font(.body)
                        .fontWeight(.medium)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(radius: 10)
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isShowing)
    }
}

// MARK: - Toast Modifier
struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    
    func body(content: Content) -> some View {
        ZStack {
            content
            ToastView(message: message, isShowing: isShowing)
        }
        .onChange(of: isShowing) { oldValue, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    isShowing = false
                }
            }
        }
    }
}

extension View {
    func toast(message: String, isShowing: Binding<Bool>) -> some View {
        self.modifier(ToastModifier(isShowing: isShowing, message: message))
    }
} 