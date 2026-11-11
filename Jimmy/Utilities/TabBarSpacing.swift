import SwiftUI

/// Constants for tab bar spacing calculations
struct TabBarSpacing {
    /// Height of the liquid glass tab bar itself
    static let tabBarHeight: CGFloat = 50
    
    /// Bottom padding applied to the tab bar
    static let tabBarBottomPadding: CGFloat = 10
    
    /// Additional spacing for comfortable scrolling
    static let comfortableSpacing: CGFloat = 20
    
    /// Total spacing needed to prevent content from being hidden behind tab bar
    static let totalSpacing: CGFloat = tabBarHeight + tabBarBottomPadding + comfortableSpacing
}

/// A view modifier that adds appropriate bottom spacing to prevent content from being hidden behind the tab bar
struct TabBarSpacingModifier: ViewModifier {
    /// Whether to include safe area in the spacing calculation
    let includeSafeArea: Bool
    
    /// Additional custom spacing if needed
    let additionalSpacing: CGFloat
    
    init(includeSafeArea: Bool = true, additionalSpacing: CGFloat = 0) {
        self.includeSafeArea = includeSafeArea
        self.additionalSpacing = additionalSpacing
    }
    
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: TabBarSpacing.totalSpacing + additionalSpacing)
            }
    }
}

/// Extension to easily apply tab bar spacing to any view
extension View {
    /// Adds bottom spacing to prevent content from being hidden behind the custom tab bar
    /// - Parameters:
    ///   - includeSafeArea: Whether to include safe area in spacing calculation (default: true)
    ///   - additionalSpacing: Any additional spacing needed (default: 0)
    /// - Returns: Modified view with appropriate bottom spacing
    func tabBarSpacing(includeSafeArea: Bool = true, additionalSpacing: CGFloat = 0) -> some View {
        modifier(TabBarSpacingModifier(includeSafeArea: includeSafeArea, additionalSpacing: additionalSpacing))
    }
}

/// Legacy spacing for views that manually add padding.bottom
/// This provides the exact spacing value for compatibility with existing code
extension View {
    /// Adds bottom padding equivalent to the tab bar spacing
    /// Use this for views that prefer manual padding over safeAreaInset
    func tabBarBottomPadding(additionalSpacing: CGFloat = 0) -> some View {
        padding(.bottom, TabBarSpacing.totalSpacing + additionalSpacing)
    }
}

/// Preview helper to visualize tab bar spacing
#if DEBUG
struct TabBarSpacingPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(0..<20) { index in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.3))
                        .frame(height: 60)
                        .overlay(
                            Text("Content Item \(index + 1)")
                                .font(.headline)
                        )
                }
            }
            .padding(.horizontal, 16)
        }
        .tabBarSpacing()
        .background(Color(.systemBackground))
        .overlay(
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.red.opacity(0.3))
                    .frame(height: TabBarSpacing.totalSpacing)
                    .overlay(
                        Text("Tab Bar Area")
                            .font(.caption)
                            .foregroundColor(.red)
                    )
            }
        )
    }
}

#Preview("Tab Bar Spacing") {
    TabBarSpacingPreview()
}
#endif
