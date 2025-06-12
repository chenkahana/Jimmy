import SwiftUI

/// Debug view for monitoring ProMotion/120Hz display status
struct ProMotionDebugView: View {
    @StateObject private var proMotionManager = ProMotionManager.shared
    @StateObject private var fpsMonitor = FPSMonitor()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection
                    
                    // Display Information
                    displayInfoSection
                    
                    // Real-time FPS Monitor
                    fpsMonitorSection
                    
                    // Animation Test
                    animationTestSection
                    
                    // Performance Tips
                    performanceTipsSection
                }
                .padding()
            }
            .navigationTitle("ProMotion Debug")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            fpsMonitor.startMonitoring()
        }
        .onDisappear {
            fpsMonitor.stopMonitoring()
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: proMotionManager.isProMotionAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(proMotionManager.isProMotionAvailable ? .green : .red)
                    .font(.title2)
                
                Text("ProMotion Status")
                    .font(.title2.bold())
                
                Spacer()
            }
            
            Text(proMotionManager.isProMotionAvailable ? "120Hz display detected" : "Standard 60Hz display")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var displayInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display Information")
                .font(.headline)
            
            VStack(spacing: 8) {
                InfoRow(label: "Max Frame Rate", value: "\(proMotionManager.currentMaxFrameRate)Hz")
                InfoRow(label: "Effective Frame Rate", value: "\(proMotionManager.effectiveMaxFrameRate)Hz")
                InfoRow(label: "Low Power Mode", value: proMotionManager.isLowPowerModeActive ? "ON" : "OFF")
                InfoRow(label: "ProMotion Available", value: proMotionManager.isProMotionAvailable ? "YES" : "NO")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }
    
    private var fpsMonitorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Real-time FPS Monitor")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Current FPS")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "%.1f", fpsMonitor.currentFPS))
                        .font(.title.bold().monospacedDigit())
                        .foregroundColor(fpsMonitor.currentFPS > 100 ? .green : fpsMonitor.currentFPS > 50 ? .orange : .red)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Frame Count")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("\(fpsMonitor.frameCount)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundColor(.primary)
                }
            }
            
            // FPS Indicator Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.red, .orange, .green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * min(fpsMonitor.currentFPS / 120, 1.0), height: 8)
                        .animation(.proMotionEaseInOut(duration: 0.1), value: fpsMonitor.currentFPS)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }
    
    @State private var animationOffset: CGFloat = 0
    @State private var isAnimating = false
    
    private var animationTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Animation Test")
                .font(.headline)
            
            VStack(spacing: 16) {
                // Smooth animation test
                HStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 20, height: 20)
                        .offset(x: animationOffset)
                        .animation(.proMotionLinear(duration: 2).repeatForever(autoreverses: true), value: animationOffset)
                    
                    Spacer()
                }
                .frame(height: 20)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                Button(action: {
                    isAnimating.toggle()
                    animationOffset = isAnimating ? 200 : 0
                }) {
                    Text(isAnimating ? "Stop Animation" : "Start Animation")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }
    
    private var performanceTipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Tips")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                TipRow(
                    icon: "checkmark.circle.fill",
                    text: "Use .proMotionSpring() for optimized animations",
                    color: .green
                )
                
                TipRow(
                    icon: "info.circle.fill",
                    text: "120Hz only works when not in Low Power Mode",
                    color: .blue
                )
                
                TipRow(
                    icon: "exclamationmark.triangle.fill",
                    text: "Heavy animations may reduce frame rate",
                    color: .orange
                )
                
                TipRow(
                    icon: "battery.25",
                    text: "Higher frame rates consume more battery",
                    color: .red
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }
    
    // MARK: - Helper Views
    
    private struct InfoRow: View {
        let label: String
        let value: String
        
        var body: some View {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
            }
        }
    }
    
    private struct TipRow: View {
        let icon: String
        let text: String
        let color: Color
        
        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                    .frame(width: 16)
                
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
        }
    }
    
}

// MARK: - FPS Monitor Class

class FPSMonitor: ObservableObject {
    @Published var currentFPS: Double = 0
    @Published var frameCount = 0
    
    private var displayLink: CADisplayLink?
    private var lastFrameTime = CACurrentMediaTime()
    
    func startMonitoring() {
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCallback))
        displayLink?.preferredFramesPerSecond = 0 // Use maximum available
        
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60,
                maximum: 120,
                preferred: 120
            )
        }
        
        displayLink?.add(to: .main, forMode: .common)
    }
    
    func stopMonitoring() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func displayLinkCallback() {
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastFrameTime
        
        if deltaTime > 0 {
            DispatchQueue.main.async {
                self.currentFPS = 1.0 / deltaTime
                self.frameCount += 1
            }
        }
        
        lastFrameTime = currentTime
    }
}

// MARK: - Preview

#Preview {
    ProMotionDebugView()
} 