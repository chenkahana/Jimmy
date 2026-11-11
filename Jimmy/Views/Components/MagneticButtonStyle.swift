import SwiftUI

/// 🧲 Magnetic Button Style - Creates buttons that feel alive and responsive
/// Inspired by Apple's latest design language with magnetic attraction effects
struct MagneticButtonStyle: ButtonStyle {
    let magneticStrength: CGFloat
    let hapticIntensity: UIImpactFeedbackGenerator.FeedbackStyle
    
    @State private var dragLocation: CGPoint = .zero
    @State private var isPressed = false
    @State private var isMagnetic = false
    
    init(
        magneticStrength: CGFloat = 8.0,
        hapticIntensity: UIImpactFeedbackGenerator.FeedbackStyle = .medium
    ) {
        self.magneticStrength = magneticStrength
        self.hapticIntensity = hapticIntensity
    }
    
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.92 : (isMagnetic ? 1.08 : 1.0))
                .offset(x: isMagnetic ? dragLocation.x * 0.1 : 0,
                       y: isMagnetic ? dragLocation.y * 0.1 : 0)
                .blur(radius: configuration.isPressed ? 0.5 : 0)
                .brightness(configuration.isPressed ? -0.1 : 0)
                .shadow(
                    color: .black.opacity(configuration.isPressed ? 0.4 : 0.2),
                    radius: configuration.isPressed ? 12 : 8,
                    x: 0,
                    y: configuration.isPressed ? 8 : 4
                )
                .animation(.motion, value: configuration.isPressed)
                .animation(.motionMicro, value: isMagnetic)
                .animation(.motionMicro, value: dragLocation)
                .onChange(of: configuration.isPressed) { pressed in
                    if pressed {
                        triggerHaptic()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            let distance = sqrt(pow(value.location.x - center.x, 2) + pow(value.location.y - center.y, 2))
                            
                            if distance < magneticStrength {
                                if !isMagnetic {
                                    withAnimation(.motionMicro) {
                                        isMagnetic = true
                                        Motion.lightHaptic()
                                    }
                                }
                                dragLocation = CGPoint(
                                    x: (value.location.x - center.x) / magneticStrength,
                                    y: (value.location.y - center.y) / magneticStrength
                                )
                            } else if isMagnetic {
                                withAnimation(.motion) {
                                    isMagnetic = false
                                    dragLocation = .zero
                                }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.motion) {
                                isMagnetic = false
                                dragLocation = .zero
                            }
                        }
                )
        }
    }
    
    private func triggerHaptic() {
        let impactFeedback = UIImpactFeedbackGenerator(style: hapticIntensity)
        impactFeedback.impactOccurred()
    }
}

/// Magnetic button with beautiful gradient and glass effects
struct MagneticGlassButton<Label: View>: View {
    let action: () -> Void
    let isEnabled: Bool
    @ViewBuilder let label: () -> Label
    
    @State private var isGlowing = false
    
    init(
        action: @escaping () -> Void,
        isEnabled: Bool = true,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.action = action
        self.isEnabled = isEnabled
        self.label = label
    }
    
    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(.white)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(0.8),
                                            Color.accentColor.opacity(0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        }
                        .overlay {
                            if isGlowing {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
                                    .blur(radius: 4)
                            }
                        }
                }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.6)
        .buttonStyle(MagneticButtonStyle())
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isGlowing.toggle()
            }
        }
    }
}

extension View {
    func magneticButtonStyle(
        strength: CGFloat = 8.0,
        haptic: UIImpactFeedbackGenerator.FeedbackStyle = .medium
    ) -> some View {
        buttonStyle(MagneticButtonStyle(magneticStrength: strength, hapticIntensity: haptic))
    }
}
