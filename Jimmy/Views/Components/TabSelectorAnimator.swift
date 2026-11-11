import SwiftUI
import UIKit

/// Isolated ObservableObject that drives the 1→1.15→1 scale spring animation and fires haptics
@MainActor
class TabSelectorAnimator: ObservableObject {
    @Published var scale: CGFloat = 1.0
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    
    init() {
        selectionFeedback.prepare()
        impactFeedback.prepare()
    }
    
    /// Triggers the scale animation and haptic feedback for long press
    func triggerSelection() {
        // Haptic on press
        Motion.selectionHaptic() // haptic feedback refactored
        
        // Scale animation: 1 → 1.15 → 1
        withAnimation(.motion) { // spring animation refactored
            scale = 1.15
        }
        
        // Auto-revert to 1 after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            withAnimation(.motion) { // spring animation refactored
                self?.scale = 1.0
            }
            
            // Haptic on release
            Motion.lightHaptic() // haptic feedback refactored
        }
    }
} 