import SwiftUI

/// 🎯 Contextual Menus - Beautiful, context-aware menus with haptic feedback
/// Creates Apple-style contextual menus that feel native and responsive
struct ContextualMenu: View {
    let items: [ContextualMenuItem]
    let isPresented: Binding<Bool>
    let sourceRect: CGRect
    
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0
    @State private var translation: CGSize = .zero
    
    struct ContextualMenuItem {
        let icon: String
        let title: String
        let subtitle: String?
        let action: () -> Void
        let isDestructive: Bool
        let isDisabled: Bool
        
        init(
            icon: String,
            title: String,
            subtitle: String? = nil,
            isDestructive: Bool = false,
            isDisabled: Bool = false,
            action: @escaping () -> Void
        ) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
            self.isDestructive = isDestructive
            self.isDisabled = isDisabled
            self.action = action
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                
                Button(action: {
                    item.action()
                    dismissMenu()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(item.isDestructive ? .red : .primary)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(.body, design: .rounded, weight: .medium))
                                .foregroundStyle(item.isDestructive ? .red : .primary)
                                .multilineTextAlignment(.leading)
                            
                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.system(.caption, design: .default))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                    }
                }
                .disabled(item.isDisabled)
                .opacity(item.isDisabled ? 0.5 : 1.0)
                .buttonStyle(.plain)
                
                if index < items.count - 1 {
                    Divider()
                        .opacity(0.3)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .offset(translation)
        .onAppear {
            withAnimation(.motion) {
                scale = 1.0
                opacity = 1.0
            }
            Motion.lightHaptic()
        }
        .onTapGesture {
            // Tap outside to dismiss
        }
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissMenu()
                }
        }
    }
    
    private func dismissMenu() {
        withAnimation(.motionGentle) {
            scale = 0.8
            opacity = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented.wrappedValue = false
        }
        
        Motion.lightHaptic()
    }
}

/// Long press gesture with contextual menu
struct LongPressContextMenu<Content: View>: View {
    @ViewBuilder let content: () -> Content
    let menuItems: [ContextualMenu.ContextualMenuItem]
    
    @State private var showingMenu = false
    @State private var pressLocation: CGPoint = .zero
    @State private var sourceRect: CGRect = .zero
    @State private var isPressed = false
    
    var body: some View {
        content()
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .blur(radius: isPressed ? 0.5 : 0)
            .animation(.motionMicro, value: isPressed)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onTapGesture { location in
                            pressLocation = location
                            sourceRect = geometry.frame(in: .global)
                        }
                }
            }
            .onLongPressGesture(
                minimumDuration: 0.5,
                maximumDistance: 10
            ) {
                showContextMenu()
            } onPressingChanged: { pressing in
                withAnimation(.motionMicro) {
                    isPressed = pressing
                }
                
                if pressing {
                    Motion.lightHaptic()
                }
            }
            .overlay {
                if showingMenu {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ContextualMenu(
                                items: menuItems,
                                isPresented: $showingMenu,
                                sourceRect: sourceRect
                            )
                            .position(x: pressLocation.x, y: pressLocation.y + 50)
                        }
                        .transition(.opacity)
                }
            }
    }
    
    private func showContextMenu() {
        withAnimation(.motionGentle) {
            showingMenu = true
        }
        Motion.mediumHaptic()
    }
}

/// Quick Actions Menu for floating action button
struct QuickActionsMenu: View {
    let isExpanded: Binding<Bool>
    let actions: [QuickAction]
    
    @State private var animationPhase: CGFloat = 0
    
    struct QuickAction {
        let icon: String
        let title: String
        let color: Color
        let action: () -> Void
        
        init(icon: String, title: String, color: Color = .accentColor, action: @escaping () -> Void) {
            self.icon = icon
            self.title = title
            self.color = color
            self.action = action
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(actions.indices.reversed(), id: \.self) { index in
                let action = actions[index]
                
                HStack(spacing: 12) {
                    Spacer()
                    
                    // Action label
                    Text(action.title)
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
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                        .opacity(isExpanded.wrappedValue ? 1.0 : 0.0)
                        .scaleEffect(isExpanded.wrappedValue ? 1.0 : 0.8)
                        .offset(x: isExpanded.wrappedValue ? 0 : 20)
                    
                    // Action button
                    Button(action: {
                        action.action()
                        withAnimation(.motion) {
                            isExpanded.wrappedValue = false
                        }
                    }) {
                        Image(systemName: action.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background {
                                Circle()
                                    .fill(.regularMaterial)
                                    .overlay {
                                        Circle()
                                            .fill(action.color.opacity(0.8))
                                    }
                                    .overlay {
                                        Circle()
                                            .stroke(.white.opacity(0.3), lineWidth: 1)
                                    }
                                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            }
                    }
                    .scaleEffect(isExpanded.wrappedValue ? 1.0 : 0.1)
                    .opacity(isExpanded.wrappedValue ? 1.0 : 0.0)
                    .offset(x: isExpanded.wrappedValue ? 0 : 30)
                    .rotation3DEffect(
                        .degrees(isExpanded.wrappedValue ? 0 : 180),
                        axis: (x: 0, y: 1, z: 0)
                    )
                }
                .animation(
                    .motion.delay(Double(actions.count - index - 1) * 0.05),
                    value: isExpanded.wrappedValue
                )
            }
        }
    }
}

/// View modifier for easy contextual menu integration
struct ContextualMenuModifier: ViewModifier {
    let menuItems: [ContextualMenu.ContextualMenuItem]
    
    func body(content: Content) -> some View {
        LongPressContextMenu(content: {
            content
        }, menuItems: menuItems)
    }
}

extension View {
    func contextualMenu(_ items: [ContextualMenu.ContextualMenuItem]) -> some View {
        modifier(ContextualMenuModifier(menuItems: items))
    }
    
    func quickActions(_ actions: [QuickActionsMenu.QuickAction], isExpanded: Binding<Bool>) -> some View {
        VStack(spacing: 16) {
            QuickActionsMenu(isExpanded: isExpanded, actions: actions)
            self
        }
    }
}
