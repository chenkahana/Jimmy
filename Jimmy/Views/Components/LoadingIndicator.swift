import SwiftUI

struct LoadingIndicator: View {
    let size: CGFloat
    let color: Color
    let message: String?
    @State private var isAnimating = false
    
    init(size: CGFloat = 20, color: Color = .accentColor, message: String? = nil) {
        self.size = size
        self.color = color
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 2)
                    .frame(width: size, height: size)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.1), color],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(
                        .linear(duration: 1)
                        .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            }
            
            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
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
                .easeInOut(duration: 1)
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
            withAnimation(.easeInOut(duration: 0.4)) {
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
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

#Preview {
    VStack(spacing: 30) {
        LoadingIndicator(size: 30, message: "Loading episode...")
        
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