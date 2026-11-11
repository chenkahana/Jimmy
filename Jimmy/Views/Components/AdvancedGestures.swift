import SwiftUI

/// 🤲 Advanced Gesture System - Intuitive gestures that feel magical
/// Implements cutting-edge gesture recognition with haptic feedback
struct AdvancedGestureHandler: UIViewRepresentable {
    let onSwipeLeft: (() -> Void)?
    let onSwipeRight: (() -> Void)?
    let onSwipeUp: (() -> Void)?
    let onSwipeDown: (() -> Void)?
    let onPinch: ((CGFloat) -> Void)?
    let onRotate: ((Angle) -> Void)?
    let onLongPress: (() -> Void)?
    let onDoubleTap: (() -> Void)?
    let onTripleTap: (() -> Void)?
    
    init(
        onSwipeLeft: (() -> Void)? = nil,
        onSwipeRight: (() -> Void)? = nil,
        onSwipeUp: (() -> Void)? = nil,
        onSwipeDown: (() -> Void)? = nil,
        onPinch: ((CGFloat) -> Void)? = nil,
        onRotate: ((Angle) -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil,
        onTripleTap: (() -> Void)? = nil
    ) {
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
        self.onSwipeUp = onSwipeUp
        self.onSwipeDown = onSwipeDown
        self.onPinch = onPinch
        self.onRotate = onRotate
        self.onLongPress = onLongPress
        self.onDoubleTap = onDoubleTap
        self.onTripleTap = onTripleTap
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        
        // Swipe gestures
        if let onSwipeLeft = onSwipeLeft {
            let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeLeft))
            swipeLeft.direction = .left
            view.addGestureRecognizer(swipeLeft)
        }
        
        if let onSwipeRight = onSwipeRight {
            let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeRight))
            swipeRight.direction = .right
            view.addGestureRecognizer(swipeRight)
        }
        
        if let onSwipeUp = onSwipeUp {
            let swipeUp = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeUp))
            swipeUp.direction = .up
            view.addGestureRecognizer(swipeUp)
        }
        
        if let onSwipeDown = onSwipeDown {
            let swipeDown = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeDown))
            swipeDown.direction = .down
            view.addGestureRecognizer(swipeDown)
        }
        
        // Pinch gesture
        if let _ = onPinch {
            let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch))
            view.addGestureRecognizer(pinch)
        }
        
        // Rotation gesture
        if let _ = onRotate {
            let rotation = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotation))
            view.addGestureRecognizer(rotation)
        }
        
        // Long press gesture
        if let _ = onLongPress {
            let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress))
            longPress.minimumPressDuration = 0.5
            view.addGestureRecognizer(longPress)
        }
        
        // Tap gestures
        if let _ = onDoubleTap {
            let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap))
            doubleTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleTap)
        }
        
        if let _ = onTripleTap {
            let tripleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTripleTap))
            tripleTap.numberOfTapsRequired = 3
            view.addGestureRecognizer(tripleTap)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: AdvancedGestureHandler
        
        init(_ parent: AdvancedGestureHandler) {
            self.parent = parent
        }
        
        @objc func handleSwipeLeft() {
            Motion.lightHaptic()
            parent.onSwipeLeft?()
        }
        
        @objc func handleSwipeRight() {
            Motion.lightHaptic()
            parent.onSwipeRight?()
        }
        
        @objc func handleSwipeUp() {
            Motion.lightHaptic()
            parent.onSwipeUp?()
        }
        
        @objc func handleSwipeDown() {
            Motion.lightHaptic()
            parent.onSwipeDown?()
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .changed {
                parent.onPinch?(gesture.scale)
            }
            if gesture.state == .began {
                Motion.lightHaptic()
            }
        }
        
        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            if gesture.state == .changed {
                parent.onRotate?(Angle(radians: gesture.rotation))
            }
            if gesture.state == .began {
                Motion.lightHaptic()
            }
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began {
                Motion.mediumHaptic()
                parent.onLongPress?()
            }
        }
        
        @objc func handleDoubleTap() {
            Motion.selectionHaptic()
            parent.onDoubleTap?()
        }
        
        @objc func handleTripleTap() {
            Motion.rigidHaptic()
            parent.onTripleTap?()
        }
    }
}

/// Swipe-to-action gesture with visual feedback
struct SwipeToActionGesture<Content: View>: View {
    @ViewBuilder let content: () -> Content
    let leftAction: SwipeAction?
    let rightAction: SwipeAction?
    let threshold: CGFloat
    
    @State private var dragOffset: CGFloat = 0
    @State private var isActionTriggered = false
    @State private var actionSide: SwipeAction.Side?
    

    
    init(
        leftAction: SwipeAction? = nil,
        rightAction: SwipeAction? = nil,
        threshold: CGFloat = 80,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.leftAction = leftAction
        self.rightAction = rightAction
        self.threshold = threshold
        self.content = content
    }
    
    var body: some View {
        ZStack {
            // Background actions
            HStack {
                if let leftAction = leftAction {
                    SwipeActionBackground(
                        action: leftAction,
                        isVisible: dragOffset > threshold,
                        progress: max(0, min(1, dragOffset / threshold))
                    )
                }
                
                Spacer()
                
                if let rightAction = rightAction {
                    SwipeActionBackground(
                        action: rightAction,
                        isVisible: dragOffset < -threshold,
                        progress: max(0, min(1, abs(dragOffset) / threshold))
                    )
                }
            }
            
            // Main content
            content()
                .offset(x: dragOffset)
                .scaleEffect(isActionTriggered ? 0.95 : 1.0)
                .animation(.motionMicro, value: isActionTriggered)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let translation = value.translation.width
                            
                            // Determine if we have actions for this direction
                            let canSwipeRight = leftAction != nil && translation > 0
                            let canSwipeLeft = rightAction != nil && translation < 0
                            
                            if canSwipeRight || canSwipeLeft {
                                dragOffset = translation
                                
                                // Trigger haptic feedback at threshold
                                if abs(translation) > threshold && !isActionTriggered {
                                    isActionTriggered = true
                                    Motion.mediumHaptic()
                                } else if abs(translation) <= threshold && isActionTriggered {
                                    isActionTriggered = false
                                }
                            }
                        }
                        .onEnded { value in
                            let translation = value.translation.width
                            
                            if abs(translation) > threshold {
                                // Trigger action
                                if translation > 0 && leftAction != nil {
                                    leftAction?.action()
                                    Motion.rigidHaptic()
                                } else if translation < 0 && rightAction != nil {
                                    rightAction?.action()
                                    Motion.rigidHaptic()
                                }
                            }
                            
                            // Reset
                            withAnimation(.motion) {
                                dragOffset = 0
                                isActionTriggered = false
                            }
                        }
                )
        }
        .animation(.motion, value: dragOffset)
    }
}

/// Background view for swipe actions
struct SwipeActionBackground: View {
    let action: SwipeAction
    let isVisible: Bool
    let progress: CGFloat
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: action.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            
            Text(action.title)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: 60)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(action.color)
                .scaleEffect(y: progress)
        }
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.6)
        .animation(.motionMicro, value: isVisible)
        .animation(.motionMicro, value: progress)
    }
}

/// Pinch-to-zoom gesture with smooth scaling
struct PinchToZoomGesture<Content: View>: View {
    @ViewBuilder let content: () -> Content
    let minScale: CGFloat
    let maxScale: CGFloat
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    init(
        minScale: CGFloat = 0.5,
        maxScale: CGFloat = 3.0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.minScale = minScale
        self.maxScale = maxScale
        self.content = content
    }
    
    var body: some View {
        content()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                SimultaneousGesture(
                    // Pinch gesture
                    MagnificationGesture()
                        .onChanged { value in
                            let newScale = lastScale * value
                            scale = max(minScale, min(maxScale, newScale))
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale < 1.0 {
                                withAnimation(.motion) {
                                    scale = 1.0
                                    lastScale = 1.0
                                }
                            }
                        },
                    
                    // Drag gesture (only when zoomed)
                    DragGesture()
                        .onChanged { value in
                            if scale > 1.0 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
            )
            .onTapGesture(count: 2) {
                withAnimation(.motion) {
                    if scale > 1.0 {
                        scale = 1.0
                        offset = .zero
                        lastScale = 1.0
                        lastOffset = .zero
                    } else {
                        scale = 2.0
                        lastScale = 2.0
                    }
                }
                Motion.mediumHaptic()
            }
    }
}

/// Extension for easy gesture integration
// Shared SwipeAction struct
struct SwipeAction {
    enum Side { case left, right }
    
    let icon: String
    let title: String
    let color: Color
    let side: Side
    let action: () -> Void
    
    init(icon: String, title: String, color: Color, side: Side, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.color = color
        self.side = side
        self.action = action
    }
}

extension View {
    func advancedGestures(
        onSwipeLeft: (() -> Void)? = nil,
        onSwipeRight: (() -> Void)? = nil,
        onSwipeUp: (() -> Void)? = nil,
        onSwipeDown: (() -> Void)? = nil,
        onPinch: ((CGFloat) -> Void)? = nil,
        onRotate: ((Angle) -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil,
        onTripleTap: (() -> Void)? = nil
    ) -> some View {
        self.background {
            AdvancedGestureHandler(
                onSwipeLeft: onSwipeLeft,
                onSwipeRight: onSwipeRight,
                onSwipeUp: onSwipeUp,
                onSwipeDown: onSwipeDown,
                onPinch: onPinch,
                onRotate: onRotate,
                onLongPress: onLongPress,
                onDoubleTap: onDoubleTap,
                onTripleTap: onTripleTap
            )
        }
    }
    
    func swipeToAction(
        leftAction: SwipeAction? = nil,
        rightAction: SwipeAction? = nil,
        threshold: CGFloat = 80
    ) -> some View {
        SwipeToActionGesture(
            leftAction: leftAction,
            rightAction: rightAction,
            threshold: threshold
        ) {
            self
        }
    }
    
    func pinchToZoom(
        minScale: CGFloat = 0.5,
        maxScale: CGFloat = 3.0
    ) -> some View {
        PinchToZoomGesture(
            minScale: minScale,
            maxScale: maxScale
        ) {
            self
        }
    }
}
