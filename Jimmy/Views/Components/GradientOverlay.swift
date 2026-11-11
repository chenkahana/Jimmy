import SwiftUI

struct GradientOverlay: View {
    enum Edge { case top, bottom }
    let edge: Edge
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(stops: edge == .top ? [
                .init(color: Color(.systemBackground), location: 0.0),
                .init(color: Color(.systemBackground).opacity(0.85), location: 0.3),
                .init(color: Color(.systemBackground).opacity(0.4), location: 0.65),
                .init(color: Color(.systemBackground).opacity(0.1), location: 0.85),
                .init(color: Color(.systemBackground).opacity(0.0), location: 1.0)
            ] : [
                .init(color: Color(.systemBackground).opacity(0.0), location: 0.0),
                .init(color: Color(.systemBackground).opacity(0.1), location: 0.15),
                .init(color: Color(.systemBackground).opacity(0.4), location: 0.35),
                .init(color: Color(.systemBackground).opacity(0.85), location: 0.7),
                .init(color: Color(.systemBackground), location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false) // Ensure gradients don't interfere with button interactions
        .opacity(UIAccessibility.isReduceTransparencyEnabled ? 0 : 1) // Respect accessibility settings
    }
}

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()
        
        VStack {
            GradientOverlay(edge: .top)
                .frame(height: 70)
            
            Spacer()
            
            GradientOverlay(edge: .bottom)
                .frame(height: 50)
        }
    }
} 