import SwiftUI

/// Tab item definition for the liquid glass tab bar
struct TabItem {
    let icon: String
    let title: String
    let tag: Int
}

/// Custom Liquid-Glass Tab Bar with pill-shaped selection indicator that
/// follows your finger while long-pressing, inspired by Apple's WWDC24 demo.
struct LiquidGlassTabBar: View {
    // MARK: – Public API
    @Binding var selectedIndex: Int

    /// Tab definition: SF Symbol, title, and unique tag (index).
    let tabs: [TabItem]

    // MARK: – Private State
    @State private var animatedSelection: Int
    @State private var isPressing = false
    @State private var hoveredIndex: Int?
    @State private var dragLocation: CGPoint = .zero

    init(selectedIndex: Binding<Int>, tabs: [TabItem]) {
        self._selectedIndex = selectedIndex
        self.tabs = tabs
        self._animatedSelection = State(initialValue: selectedIndex.wrappedValue)
    }

    // MARK: – Computed Properties
    private var tabCount: Int { tabs.count }

    // MARK: – Helper Methods
    private func tabMetrics(in geo: GeometryProxy) -> (width: CGFloat, spacing: CGFloat, hPadding: CGFloat, vPadding: CGFloat) {
        let hPadding: CGFloat = 16
        let spacing: CGFloat = 8
        let availableWidth = geo.size.width - (hPadding * 2) - (spacing * CGFloat(tabCount - 1))
        let tabWidth = availableWidth / CGFloat(tabCount)
        let vPadding: CGFloat = 12
        
        return (tabWidth, spacing, hPadding, vPadding)
    }

    private func pillPosition(for index: Int, metrics: (width: CGFloat, spacing: CGFloat, hPadding: CGFloat, vPadding: CGFloat)) -> CGPoint {
        let tabCenterX = metrics.hPadding + (CGFloat(index) * (metrics.width + metrics.spacing)) + (metrics.width / 2)
        let tabCenterY: CGFloat = 37  //DONT TOUCH WITH APPROVAL!!!
        return CGPoint(x: tabCenterX, y: tabCenterY)
    }

    private func pillSize(tabWidth: CGFloat) -> CGSize {
        let height: CGFloat = 52   //DONT TOUCH WITH APPROVAL!!!
        let width = tabWidth*1.2 //DONT TOUCH WITH APPROVAL!!!
        return CGSize(width: width, height: height)
    }

    // MARK: – Body
    var body: some View {
        GeometryReader { geo in
            let metrics = tabMetrics(in: geo)

            ZStack {
                // Background Glass Bar - much more rounded like Apple's reference
                RoundedRectangle(cornerRadius: 40, style: .continuous)  // much more rounded (was 28)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)

                // Pill indicator - almost fills the tab bar
                let currentIndex = isPressing ? (hoveredIndex ?? animatedSelection) : animatedSelection
                let pillPos = pillPosition(for: currentIndex, metrics: metrics)
                let pillSize = pillSize(tabWidth: metrics.width)

                Capsule()  // Capsule for proper pill shape like Apple's reference
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.25), lineWidth: isPressing ? 2 : 1)
                    )
                    .frame(width: pillSize.width, height: pillSize.height)
                    .shadow(color: .black.opacity(isPressing ? 0.25 : 0.15), radius: 8, x: 0, y: 4)
                    .position(pillPos)
                    .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: pillPos)
                    .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.9), value: isPressing)
                    .allowsHitTesting(false)

                // Tabs
                HStack(spacing: metrics.spacing) {
                    ForEach(tabs, id: \.tag) { tab in
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: metrics.width, height: pillSize.height)
                        .foregroundStyle(selectedIndex == tab.tag ? Color.accentColor : Color.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.35, bounce: 0.5)) {
                                selectedIndex = tab.tag
                                animatedSelection = tab.tag
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.hPadding)
                .padding(.vertical, metrics.vPadding)
            }
            .gesture(longPressGesture(in: geo))
        }
        .frame(height: 70)  // narrower tab bar (was 80)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    // MARK: – Gesture
    private func longPressGesture(in geo: GeometryProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    isPressing = true
                    // Light haptic when long press starts
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                case .second(true, let drag?):
                    dragLocation = drag.location
                    let newHoveredIndex = hitTest(location: drag.location, in: geo)
                    
                    if newHoveredIndex != hoveredIndex {
                        hoveredIndex = newHoveredIndex
                        
                        // Navigate in real-time during drag
                        if let targetIndex = newHoveredIndex {
                            selectedIndex = targetIndex
                            animatedSelection = targetIndex
                            // Selection haptic feedback
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                default: break
                }
            }
            .onEnded { _ in
                isPressing = false
                // Final confirmation haptic
                if hoveredIndex != nil {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                hoveredIndex = nil
            }
    }

    private func hitTest(location: CGPoint, in geo: GeometryProxy) -> Int? {
        let metrics = tabMetrics(in: geo)
        let x = location.x - metrics.hPadding
        guard x >= 0 else { return nil }
        let slot = Int((metrics.width + metrics.spacing) > 0 ? x / (metrics.width + metrics.spacing) : 0)
        return (slot >= 0 && slot < tabs.count) ? tabs[slot].tag : nil
    }
} 