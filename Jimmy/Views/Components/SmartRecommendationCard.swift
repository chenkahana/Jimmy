import SwiftUI

/// 🤖 Smart Recommendation Card - AI-powered suggestions that feel magical
/// Creates intelligent, personalized recommendations with beautiful animations
struct SmartRecommendationCard: View {
    let recommendation: Recommendation
    let onTap: () -> Void
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    @State private var sparkleOffset: CGFloat = 0
    @State private var aiGlowIntensity: Double = 0.3
    @State private var isDismissing = false
    
    struct Recommendation {
        let id: String
        let type: RecommendationType
        let title: String
        let subtitle: String
        let description: String
        let confidence: Double
        let artworkURL: URL?
        let metadata: [String: String]
        
        enum RecommendationType {
            case podcast
            case episode
            case category
            case continuation
            
            var icon: String {
                switch self {
                case .podcast: return "sparkles"
                case .episode: return "waveform.circle"
                case .category: return "grid.circle"
                case .continuation: return "play.circle"
                }
            }
            
            var color: Color {
                switch self {
                case .podcast: return .purple
                case .episode: return .blue
                case .category: return .orange
                case .continuation: return .green
                }
            }
            
            var label: String {
                switch self {
                case .podcast: return "New Podcast"
                case .episode: return "Suggested Episode"
                case .category: return "Explore Category"
                case .continuation: return "Continue Listening"
                }
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // AI-enhanced artwork
            artworkSection
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // AI badge and title
                HStack(spacing: 8) {
                    AIBadge(
                        type: recommendation.type,
                        confidence: recommendation.confidence
                    )
                    
                    Spacer()
                    
                    dismissButton
                }
                
                // Title
                Text(recommendation.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                // Subtitle
                Text(recommendation.subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                // Description
                Text(recommendation.description)
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                Spacer()
                
                // Action button
                MagneticGlassButton(action: onTap) {
                    HStack(spacing: 6) {
                        Image(systemName: recommendation.type.icon)
                            .font(.system(size: 12, weight: .medium))
                        Text("Explore")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                    }
                }
            }
        }
        .padding(16)
        .background {
            // Magical AI-enhanced background
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    // AI glow effect
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    recommendation.type.color.opacity(aiGlowIntensity),
                                    recommendation.type.color.opacity(aiGlowIntensity * 0.5),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .blur(radius: 2)
                }
                .overlay {
                    // Sparkle overlay
                    SparkleOverlay(
                        color: recommendation.type.color,
                        isActive: isVisible
                    )
                }
                .shadow(color: recommendation.type.color.opacity(0.2), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1.0 : 0.0)
        .blur(radius: isVisible ? 0 : 2)
        .rotation3DEffect(
            .degrees(isVisible ? 0 : -15),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.8
        )
        .onAppear {
            withAnimation(.motion.delay(0.1)) {
                isVisible = true
            }
            startAIAnimation()
        }
        .onTapGesture {
            onTap()
        }
        .swipeToAction(
            rightAction: SwipeAction(
                icon: "xmark",
                title: "Dismiss",
                color: .gray,
                side: .right,
                action: {
                    dismissRecommendation()
                }
            )
        )
    }
    
    private var artworkSection: some View {
        Group {
            if let artworkURL = recommendation.artworkURL {
                BulletproofAsyncImage(url: artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    artworkPlaceholder
                }
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            // AI indicator
            Circle()
                .fill(recommendation.type.color)
                .frame(width: 20, height: 20)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(x: 6, y: -6)
                .scaleEffect(isVisible ? 1.0 : 0.0)
                .animation(.motion.delay(0.3), value: isVisible)
        }
    }
    
    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(
                LinearGradient(
                    colors: [
                        recommendation.type.color.opacity(0.6),
                        recommendation.type.color.opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: recommendation.type.icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
    }
    
    private var dismissButton: some View {
        Button(action: dismissRecommendation) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background {
                    Circle()
                        .fill(.regularMaterial)
                }
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.motion.delay(0.4), value: isVisible)
    }
    
    private func dismissRecommendation() {
        withAnimation(.motionGentle) {
            isDismissing = true
            isVisible = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
        
        Motion.lightHaptic()
    }
    
    private func startAIAnimation() {
        // Pulsing AI glow
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            aiGlowIntensity = 0.8
        }
        
        // Sparkle movement
        withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
            sparkleOffset = 1.0
        }
    }
}

/// AI Badge with confidence indicator
struct AIBadge: View {
    let type: SmartRecommendationCard.Recommendation.RecommendationType
    let confidence: Double
    
    @State private var isGlowing = false
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
            
            Text("AI")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            type.color,
                            type.color.opacity(0.7)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay {
                    if isGlowing {
                        Capsule()
                            .stroke(type.color.opacity(0.6), lineWidth: 1)
                            .blur(radius: 2)
                    }
                }
        }
        .scaleEffect(isGlowing ? 1.05 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
    }
}

/// Sparkle overlay effect for magical feel
struct SparkleOverlay: View {
    let color: Color
    let isActive: Bool
    
    @State private var sparkles: [SparkleParticle] = []
    
    struct SparkleParticle {
        let id = UUID()
        var position: CGPoint
        var scale: CGFloat
        var opacity: Double
        var rotationAngle: Double
    }
    
    var body: some View {
        ZStack {
            ForEach(sparkles, id: \.id) { sparkle in
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color.opacity(sparkle.opacity))
                    .scaleEffect(sparkle.scale)
                    .rotationEffect(.degrees(sparkle.rotationAngle))
                    .position(sparkle.position)
            }
        }
        .onAppear {
            if isActive {
                generateSparkles()
            }
        }
        .onChange(of: isActive) { active in
            if active {
                generateSparkles()
            } else {
                sparkles.removeAll()
            }
        }
    }
    
    private func generateSparkles() {
        for _ in 0..<5 {
            let sparkle = SparkleParticle(
                position: CGPoint(
                    x: CGFloat.random(in: 20...200),
                    y: CGFloat.random(in: 20...80)
                ),
                scale: CGFloat.random(in: 0.5...1.0),
                opacity: Double.random(in: 0.3...0.8),
                rotationAngle: Double.random(in: 0...360)
            )
            sparkles.append(sparkle)
        }
        
        // Animate sparkles
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            // Scheduled from the view, so it fires on the main run loop.
            guard MainActor.assumeIsolated({ isActive }) else {
                timer.invalidate()
                return
            }

            MainActor.assumeIsolated {
                for i in sparkles.indices {
                    sparkles[i].opacity *= 0.95
                    sparkles[i].scale *= 0.98
                    sparkles[i].rotationAngle += 10
                
                    if sparkles[i].opacity < 0.1 {
                        sparkles[i] = SparkleParticle(
                            position: CGPoint(
                                x: CGFloat.random(in: 20...200),
                                y: CGFloat.random(in: 20...80)
                            ),
                            scale: CGFloat.random(in: 0.5...1.0),
                            opacity: Double.random(in: 0.3...0.8),
                            rotationAngle: Double.random(in: 0...360)
                        )
                    }
                }
            }
        }
    }
}

/// Collection view for recommendations
struct SmartRecommendationsList: View {
    let recommendations: [SmartRecommendationCard.Recommendation]
    let onTap: (SmartRecommendationCard.Recommendation) -> Void
    let onDismiss: (SmartRecommendationCard.Recommendation) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.purple)
                    
                    Text("AI Recommendations")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                Text("\(recommendations.count) suggestions")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            
            // Recommendations
            LazyVStack(spacing: 12) {
                ForEach(recommendations, id: \.id) { recommendation in
                    SmartRecommendationCard(
                        recommendation: recommendation,
                        onTap: { onTap(recommendation) },
                        onDismiss: { onDismiss(recommendation) }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

#Preview {
    ScrollView {
        SmartRecommendationsList(
            recommendations: [
                SmartRecommendationCard.Recommendation(
                    id: "1",
                    type: .podcast,
                    title: "The Daily Science Update",
                    subtitle: "Based on your listening history",
                    description: "You've enjoyed similar science podcasts. This one covers daily breakthroughs in an engaging format.",
                    confidence: 0.92,
                    artworkURL: nil,
                    metadata: [:]
                ),
                SmartRecommendationCard.Recommendation(
                    id: "2",
                    type: .episode,
                    title: "The Future of AI in Healthcare",
                    subtitle: "From Tech Talk Weekly",
                    description: "Continues your interest in AI and technology topics from your recent listening patterns.",
                    confidence: 0.87,
                    artworkURL: nil,
                    metadata: [:]
                )
            ],
            onTap: { _ in },
            onDismiss: { _ in }
        )
    }
    .background(Color(.systemGroupedBackground))
}
