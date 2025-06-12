import SwiftUI

/// A customizable loading indicator component
struct LoadingIndicator: View {
    let size: CGFloat
    let color: Color
    
    @State private var isAnimating = false
    
    init(size: CGFloat = 20, color: Color = .primary) {
        self.size = size
        self.color = color
    }
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, lineWidth: size / 10)
            .frame(width: size, height: size)
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .animation(
                Animation.proMotionLinear(duration: 1)
                    .repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
            .onDisappear {
                isAnimating = false
            }
    }
}

struct PulsingLoadingIndicator: View {
    let size: CGFloat
    let color: Color
    @State private var isPulsing = false
    
    init(size: CGFloat = 20, color: Color = .accentColor) {
        self.size = size
        self.color = color
    }
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(isPulsing ? 1.2 : 0.8)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(
                .proMotionEaseInOut(duration: 1)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
            .onDisappear {
                isPulsing = false
            }
    }
}

struct DotsLoadingIndicator: View {
    let size: CGFloat
    let color: Color
    @State private var animatingDot = 0
    
    init(size: CGFloat = 8, color: Color = .accentColor) {
        self.size = size
        self.color = color
    }
    
    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .scaleEffect(animatingDot == index ? 1.2 : 0.8)
                    .opacity(animatingDot == index ? 1.0 : 0.6)
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            withAnimation(.proMotionEaseInOut(duration: 0.4)) {
                animatingDot = (animatingDot + 1) % 3
            }
        }
    }
}

// Enhanced 3D Loading Button
struct Enhanced3DLoadingButton: View {
    let isLoading: Bool
    let action: () -> Void
    let label: String
    let icon: String?
    
    init(isLoading: Bool, action: @escaping () -> Void, label: String, icon: String? = nil) {
        self.isLoading = isLoading
        self.action = action
        self.label = label
        self.icon = icon
    }
    
    var body: some View {
        Button(action: isLoading ? {} : action) {
            HStack(spacing: 8) {
                if isLoading {
                    LoadingIndicator(size: 16, color: .white)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                }
                
                Text(isLoading ? "Loading..." : label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: isLoading ? 
                                [Color.gray.opacity(0.6), Color.gray.opacity(0.4)] :
                                [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .disabled(isLoading)
        .buttonStyle(Enhanced3DButtonStyle(depth: isLoading ? 1 : 2))
        .animation(.proMotionEaseInOut(duration: 0.2), value: isLoading)
    }
}

#Preview {
    VStack(spacing: 20) {
        LoadingIndicator(size: 16)
        LoadingIndicator(size: 24, color: .blue)
        LoadingIndicator(size: 32, color: .red)
        
        PulsingLoadingIndicator(size: 25)
        
        DotsLoadingIndicator(size: 10)
        
        Enhanced3DLoadingButton(
            isLoading: true,
            action: {},
            label: "Play Episode",
            icon: "play.fill"
        )
        
        Enhanced3DLoadingButton(
            isLoading: false,
            action: {},
            label: "Play Episode",
            icon: "play.fill"
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
} 