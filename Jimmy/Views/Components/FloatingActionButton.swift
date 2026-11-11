import SwiftUI

/// 🚀 Floating Action Button - Apple-style floating action with physics
/// Creates a delightful floating button that responds to gestures and scroll
struct FloatingActionButton: View {
    let icon: String
    let action: () -> Void
    let size: CGFloat
    let color: Color
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isPressed = false
    @State private var rotationAngle: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var isVisible = true
    
    init(
        icon: String,
        action: @escaping () -> Void,
        size: CGFloat = 56,
        color: Color = .accentColor
    ) {
        self.icon = icon
        self.action = action
        self.size = size
        self.color = color
    }
    
    var body: some View {
        Button(action: {
            action()
            triggerPressAnimation()
        }) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            color.opacity(0.9),
                                            color.opacity(0.7)
                                        ],
                                        center: .topLeading,
                                        startRadius: 0,
                                        endRadius: size
                                    )
                                )
                        }
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
                        .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 4)
                }
        }
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotationAngle))
        .offset(dragOffset)
        .opacity(isVisible ? 1.0 : 0.3)
        .animation(.motion, value: dragOffset)
        .animation(.motionMicro, value: scale)
        .animation(.motionMicro, value: rotationAngle)
        .animation(.motionGentle, value: isVisible)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        withAnimation(.motionMicro) {
                            scale = 1.1
                            rotationAngle = 5
                        }
                        Motion.lightHaptic()
                    }
                    
                    dragOffset = value.translation
                    
                    // Add some rotation based on drag direction
                    let rotationFactor = value.translation.width / 100
                    rotationAngle = 5 + rotationFactor * 10
                }
                .onEnded { value in
                    isDragging = false
                    
                    // Spring back with physics
                    withAnimation(.motion) {
                        dragOffset = .zero
                        scale = 1.0
                        rotationAngle = 0
                    }
                    
                    // If dragged far enough, trigger action
                    let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                    if dragDistance > 100 {
                        action()
                        triggerPressAnimation()
                        Motion.rigidHaptic()
                    } else {
                        Motion.lightHaptic()
                    }
                }
        )
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            startBreathingAnimation()
        }
        .onAppear {
            startBreathingAnimation()
        }
    }
    
    private func triggerPressAnimation() {
        withAnimation(.motionMicro) {
            scale = 0.8
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.motion) {
                scale = 1.0
            }
        }
        
        Motion.mediumHaptic()
    }
    
    private func startBreathingAnimation() {
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            scale = 1.05
        }
    }
    
    /// Hide/show based on scroll direction
    func hideOnScroll(_ isScrollingDown: Bool) -> some View {
        self.onChange(of: isScrollingDown) { _, scrolling in
            withAnimation(.motionGentle) {
                isVisible = !scrolling
            }
        }
    }
}

/// Floating Action Button with expandable menu
struct ExpandableFloatingActionButton: View {
    let mainIcon: String
    let menuItems: [FloatingMenuItem]
    let size: CGFloat
    let color: Color
    
    @State private var isExpanded = false
    @State private var scale: CGFloat = 1.0
    
    struct FloatingMenuItem {
        let icon: String
        let label: String
        let action: () -> Void
        let color: Color
        
        init(icon: String, label: String, color: Color = .accentColor, action: @escaping () -> Void) {
            self.icon = icon
            self.label = label
            self.color = color
            self.action = action
        }
    }
    
    init(
        mainIcon: String,
        menuItems: [FloatingMenuItem],
        size: CGFloat = 56,
        color: Color = .accentColor
    ) {
        self.mainIcon = mainIcon
        self.menuItems = menuItems
        self.size = size
        self.color = color
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Menu items (shown when expanded)
            ForEach(menuItems.indices.reversed(), id: \.self) { index in
                let item = menuItems[index]
                
                HStack {
                    Spacer()
                    
                    // Label
                    Text(item.label)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(.regularMaterial)
                                .overlay {
                                    Capsule()
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                }
                        }
                        .opacity(isExpanded ? 1.0 : 0.0)
                        .scaleEffect(isExpanded ? 1.0 : 0.8)
                    
                    // Menu item button
                    Button(action: {
                        item.action()
                        collapseMenu()
                    }) {
                        Image(systemName: item.icon)
                            .font(.system(size: size * 0.3, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: size * 0.7, height: size * 0.7)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Circle()
                                            .fill(item.color.opacity(0.8))
                                    }
                                    .overlay {
                                        Circle()
                                            .stroke(.white.opacity(0.3), lineWidth: 1)
                                    }
                                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            }
                    }
                    .scaleEffect(isExpanded ? 1.0 : 0.1)
                    .opacity(isExpanded ? 1.0 : 0.0)
                    .offset(x: isExpanded ? 0 : 30)
                }
                .animation(.motion.delay(Double(index) * 0.05), value: isExpanded)
            }
            
            // Main button
            FloatingActionButton(
                icon: isExpanded ? "xmark" : mainIcon,
                action: toggleMenu,
                size: size,
                color: color
            )
            .scaleEffect(scale)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
    }
    
    private func toggleMenu() {
        withAnimation(.motion) {
            isExpanded.toggle()
        }
        
        // Pulse animation on main button
        withAnimation(.motionMicro) {
            scale = 0.9
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.motion) {
                scale = 1.0
            }
        }
        
        Motion.mediumHaptic()
    }
    
    private func collapseMenu() {
        withAnimation(.motion) {
            isExpanded = false
        }
        Motion.lightHaptic()
    }
}
