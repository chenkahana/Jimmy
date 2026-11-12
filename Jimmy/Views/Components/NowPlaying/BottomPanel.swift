import SwiftUI

/// The one panel Now Playing opens for speed, sleep and chapters. Ported from Boaz's `BottomPanel`.
///
///     if let panel {
///         BottomPanel(tint: backdrop, maxHeight: 0.6, onDismiss: { panel = nil }) { PanelContent() }
///     }
///     // and animate the state that inserts it with `BottomPanelStyle.motion`
///
/// - Dims the player above it slightly. Tapping the dimmed player or dragging the panel down calls `onDismiss`.
/// - Glass tinted with the artwork color, 8 pt from the screen edges. Slides up from the bottom (insert it with `if`;
///   it brings its own transitions).
/// - `maxHeight` is a fraction of the screen height. Content keeps its natural height up to that; greedy content
///   (a `ScrollView`) fills it.
struct BottomPanel<Content: View>: View {
    let tint: ArtworkContrast?
    let maxHeight: CGFloat
    let onDismiss: () -> Void
    let content: Content

    init(tint: ArtworkContrast? = nil, maxHeight: CGFloat = 1, onDismiss: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.maxHeight = maxHeight
        self.onDismiss = onDismiss
        self.content = content()
    }

    /// Live downward drag of the panel.
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.18)
                    .contentShape(.rect)
                    .onTapGesture(perform: onDismiss)
                    // The panel's escape action covers this for VoiceOver.
                    .accessibilityHidden(true)
                    .ignoresSafeArea()
                    .transition(.opacity)
                MaxHeight(proxy.size.height * maxHeight - 16) { content.frame(maxWidth: .infinity) }
                    .glassEffect(.regular.tint(tint?.color.opacity(0.4)),
                                 in: .rect(cornerRadius: BottomPanelStyle.cornerRadius))
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape, onDismiss)
                    .padding(8)
                    .offset(y: drag)
                    .gesture(dragToDismiss)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var dragToDismiss: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let down = value.translation.height
                guard abs(down) > abs(value.translation.width) else { return }
                // Follows a drag down; resists a drag up.
                drag = down > 0 ? down : -12 * (1 - exp(down / 40))
            }
            .onEnded { value in
                if value.translation.height > 80 || value.predictedEndTranslation.height > 220 {
                    onDismiss()
                }
                withAnimation(BottomPanelStyle.motion(reduceMotion: reduceMotion)) { drag = 0 }
            }
    }
}

/// Caps its content's height without stretching it (a `maxHeight` frame grows to the cap).
private struct MaxHeight: Layout {
    let limit: CGFloat
    init(_ limit: CGFloat) { self.limit = max(limit, 0) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = min(proposal.height ?? limit, limit)
        return subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: height)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// The panel's shared motion and shape.
enum BottomPanelStyle {
    static let cornerRadius: CGFloat = 28

    static func motion(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .snappy(duration: 0.3)
    }
}
