import SwiftUI

// MARK: - Enhanced 3D Button Styles

struct Enhanced3DButtonStyle: ButtonStyle {
    let depth: CGFloat
    let shadowRadius: CGFloat
    
    init(depth: CGFloat = 2, shadowRadius: CGFloat = 4) {
        self.depth = depth
        self.shadowRadius = shadowRadius
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .offset(y: configuration.isPressed ? depth * 0.5 : 0)
            .shadow(
                color: .black.opacity(0.3),
                radius: configuration.isPressed ? shadowRadius * 0.5 : shadowRadius,
                x: 0,
                y: configuration.isPressed ? depth * 0.5 : depth
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct NeumorphicButtonStyle: ButtonStyle {
    let isPressed: Bool
    
    init(isPressed: Bool = false) {
        self.isPressed = isPressed
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .shadow(
                color: .black.opacity(0.2),
                radius: configuration.isPressed ? 2 : 6,
                x: configuration.isPressed ? 1 : 3,
                y: configuration.isPressed ? 1 : 3
            )
            .shadow(
                color: Color("SurfaceHighlighted").opacity(0.1),
                radius: configuration.isPressed ? 2 : 6,
                x: configuration.isPressed ? -1 : -3,
                y: configuration.isPressed ? -1 : -3
            )
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Enhanced 3D Background Styles

struct Enhanced3DCardBackground: ViewModifier {
    let cornerRadius: CGFloat
    let elevation: CGFloat
    
    init(cornerRadius: CGFloat = 16, elevation: CGFloat = 4) {
        self.cornerRadius = cornerRadius
        self.elevation = elevation
    }
    
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.1), radius: elevation, x: 0, y: elevation/2)
            }
    }
}

struct NeumorphicBackground: ViewModifier {
    let cornerRadius: CGFloat
    let isPressed: Bool
    
    init(cornerRadius: CGFloat = 16, isPressed: Bool = false) {
        self.cornerRadius = cornerRadius
        self.isPressed = isPressed
    }
    
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color("SurfaceElevated"))
                    
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color("SurfaceHighlighted").opacity(isPressed ? 0.05 : 0.1),
                                    Color.black.opacity(isPressed ? 0.1 : 0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(
                    color: .black.opacity(0.2),
                    radius: isPressed ? 2 : 8,
                    x: isPressed ? 2 : 4,
                    y: isPressed ? 2 : 4
                )
                .shadow(
                    color: Color("SurfaceHighlighted").opacity(0.1),
                    radius: isPressed ? 2 : 8,
                    x: isPressed ? -2 : -4,
                    y: isPressed ? -2 : -4
                )
            }
    }
}

// MARK: - Enhanced 3D List Styles

struct Enhanced3DListRowBackground: ViewModifier {
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: isSelected ? [
                                Color.accentColor.opacity(0.1),
                                Color.accentColor.opacity(0.05)
                            ] : [
                                Color("SurfaceElevated"),
                                Color("SurfaceElevated").opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color("SurfaceHighlighted").opacity(0.2),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    }
                    .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
            }
    }
}

// MARK: - Extension for easy use

extension View {
    func enhanced3DCard(cornerRadius: CGFloat = 16, elevation: CGFloat = 4) -> some View {
        self.modifier(Enhanced3DCardBackground(cornerRadius: cornerRadius, elevation: elevation))
    }
    
    func neumorphic(cornerRadius: CGFloat = 16, isPressed: Bool = false) -> some View {
        self.modifier(NeumorphicBackground(cornerRadius: cornerRadius, isPressed: isPressed))
    }
    
    func enhanced3DListRow(isSelected: Bool = false) -> some View {
        self.modifier(Enhanced3DListRowBackground(isSelected: isSelected))
    }
}

// MARK: - Enhanced 3D Progress View

struct Enhanced3DProgressView: View {
    let progress: Double
    let height: CGFloat
    let cornerRadius: CGFloat
    
    init(progress: Double, height: CGFloat = 6, cornerRadius: CGFloat = 3) {
        self.progress = progress
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track with inset effect
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.2),
                                Color("DarkBackground"),
                                Color.black.opacity(0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: height)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                            .frame(height: height)
                    }
                
                // Progress fill with raised effect
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.9),
                                Color.accentColor,
                                Color.accentColor.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: geometry.size.width * progress, height: height)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: geometry.size.width * progress, height: height * 0.5)
                            .offset(y: -height * 0.25)
                    }
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 2, x: 0, y: 0)
            }
        }
        .frame(height: height)
    }
} 