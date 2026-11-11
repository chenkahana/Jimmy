import SwiftUI

/// 🌟 Beautiful Onboarding Experience - First impressions that wow users
/// Creates an Apple-quality onboarding flow with stunning animations
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var pageAnimationPhase: CGFloat = 0
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "waveform.circle.fill",
            title: "Welcome to Jimmy",
            subtitle: "A queue-first podcast experience",
            description: "Jimmy puts your listening queue front and center, so you always know what's playing next.",
            color: .blue,
            features: [
                "Queue Management — drag, drop, play next",
                "Smart Silence Trimming — saves listening time",
                "Background Downloads — listen offline"
            ]
        ),
        OnboardingPage(
            icon: "accessibility",
            title: "Built for Everyone",
            subtitle: "Full accessibility support",
            description: "Complete VoiceOver support, dynamic type, and high-contrast mode so Jimmy works for every listener.",
            color: .purple,
            features: [
                "Full Accessibility — VoiceOver ready",
                "Dynamic Type — scales to your preference",
                "High Contrast Mode — better readability"
            ]
        ),
        OnboardingPage(
            icon: "square.and.arrow.down",
            title: "Easy Import",
            subtitle: "Bring your subscriptions with you",
            description: "Import your existing subscriptions from Apple Podcasts or any OPML-compatible app in seconds.",
            color: .orange,
            features: [
                "Import from Apple Podcasts",
                "OPML import and export",
                "No account required"
            ]
        ),
        OnboardingPage(
            icon: "play.circle.fill",
            title: "Ready to Listen?",
            subtitle: "Your podcasts, your way",
            description: "Subscribe to shows, build your queue, and start listening — it only takes a moment to get started.",
            color: .green,
            features: [
                "Variable playback speed",
                "CarPlay support",
                "Lock screen controls"
            ]
        )
    ]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dynamic gradient background
                LinearGradient(
                    colors: [
                        pages[currentPage].color.opacity(0.3),
                        pages[currentPage].color.opacity(0.1),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: currentPage)
                
                VStack(spacing: 0) {
                    // Skip button
                    HStack {
                        Spacer()
                        Button("Skip") {
                            dismissOnboarding()
                        }
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding()
                    }
                    
                    // Page content
                    TabView(selection: $currentPage) {
                        ForEach(pages.indices, id: \.self) { index in
                            OnboardingPageView(
                                page: pages[index],
                                isActive: currentPage == index,
                                geometry: geometry
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                dragOffset = 0
                                
                                let threshold: CGFloat = 50
                                if value.translation.width > threshold && currentPage > 0 {
                                    withAnimation(.motion) {
                                        currentPage -= 1
                                    }
                                } else if value.translation.width < -threshold && currentPage < pages.count - 1 {
                                    withAnimation(.motion) {
                                        currentPage += 1
                                    }
                                }
                            }
                    )
                    
                    // Page indicators and actions
                    VStack(spacing: 32) {
                        // Custom page indicator
                        HStack(spacing: 8) {
                            ForEach(pages.indices, id: \.self) { index in
                                Circle()
                                    .fill(currentPage == index ? pages[currentPage].color : Color.gray.opacity(0.3))
                                    .frame(width: currentPage == index ? 12 : 8, height: currentPage == index ? 12 : 8)
                                    .scaleEffect(currentPage == index ? 1.2 : 1.0)
                                    .animation(.motion, value: currentPage)
                            }
                        }
                        
                        // Action buttons
                        VStack(spacing: 16) {
                            if currentPage == pages.count - 1 {
                                // Get started button (final page)
                                MagneticGlassButton(action: {
                                    dismissOnboarding()
                                }) {
                                    HStack(spacing: 12) {
                                        Text("Get Started")
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                            } else {
                                // Continue button
                                MagneticGlassButton(action: {
                                    withAnimation(.motion) {
                                        currentPage = min(currentPage + 1, pages.count - 1)
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        Text("Continue")
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                            }
                            
                            // Secondary action on final page
                            if currentPage == pages.count - 1 {
                                Button("Import from Apple Podcasts") {
                                    dismissOnboarding()
                                    // Navigate to settings to trigger import after onboarding
                                    NotificationCenter.default.post(name: .init("OpenApplePodcastsImport"), object: nil)
                                }
                                .font(.system(.body, design: .rounded, weight: .medium))
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                            }
                        }
                        .animation(.motion, value: currentPage)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                }
            }
        }
        .preferredColorScheme(.dark) // Onboarding looks best in dark mode
        .onAppear {
            startPageAnimation()
        }
    }
    
    private func dismissOnboarding() {
        withAnimation(.motionGentle) {
            isPresented = false
        }
        
        // Mark onboarding as completed
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        
        Motion.mediumHaptic()
    }
    
    private func startPageAnimation() {
        withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
            pageAnimationPhase = 1.0
        }
    }
}

/// Individual onboarding page view
struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool
    let geometry: GeometryProxy
    
    @State private var hasAppeared = false
    @State private var floatingOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Hero icon with floating animation
            Image(systemName: page.icon)
                .font(.system(size: 80, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [page.color, page.color.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(hasAppeared ? 1.0 : 0.5)
                .opacity(hasAppeared ? 1.0 : 0.0)
                .blur(radius: hasAppeared ? 0 : 10)
                .offset(y: floatingOffset)
                .onAppear {
                    if isActive {
                        withAnimation(.motion.delay(0.2)) {
                            hasAppeared = true
                        }
                        startFloatingAnimation()
                    }
                }
                .onChange(of: isActive) { _, active in
                    if active {
                        withAnimation(.motion) {
                            hasAppeared = true
                        }
                        startFloatingAnimation()
                    }
                }
            
            // Content
            VStack(spacing: 16) {
                // Title
                Text(page.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .opacity(hasAppeared ? 1.0 : 0.0)
                    .offset(y: hasAppeared ? 0 : 20)
                    .animation(.motion.delay(0.4), value: hasAppeared)
                
                // Subtitle
                Text(page.subtitle)
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(hasAppeared ? 1.0 : 0.0)
                    .offset(y: hasAppeared ? 0 : 20)
                    .animation(.motion.delay(0.5), value: hasAppeared)
                
                // Description
                Text(page.description)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .opacity(hasAppeared ? 1.0 : 0.0)
                    .offset(y: hasAppeared ? 0 : 20)
                    .animation(.motion.delay(0.6), value: hasAppeared)
                
                // Features list
                VStack(spacing: 12) {
                    ForEach(page.features.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            Text(page.features[index])
                                .font(.system(.callout, design: .rounded))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .opacity(hasAppeared ? 1.0 : 0.0)
                        .offset(x: hasAppeared ? 0 : -30)
                        .animation(.motion.delay(0.7 + Double(index) * 0.1), value: hasAppeared)
                    }
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private func startFloatingAnimation() {
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            floatingOffset = -8
        }
    }
}

/// Onboarding page data model
struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let description: String
    let color: Color
    let features: [String]
}

/// Onboarding manager to handle state
class OnboardingManager: ObservableObject {
    @Published var shouldShowOnboarding: Bool
    
    init() {
        self.shouldShowOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }
    
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        shouldShowOnboarding = false
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
