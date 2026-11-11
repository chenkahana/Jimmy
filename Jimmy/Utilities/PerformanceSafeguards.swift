import SwiftUI
import UIKit
import os.log

/// Monitors system performance and automatically adjusts app behavior for optimal experience
@MainActor
class PerformanceSafeguards: ObservableObject {
    static let shared = PerformanceSafeguards()
    
    // MARK: - Published Properties
    @Published private(set) var currentPerformanceMode: PerformanceMode = .optimal
    @Published private(set) var memoryPressure: MemoryPressureLevel = .normal
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var isLowPowerModeActive: Bool = false
    @Published private(set) var devicePerformanceClass: DevicePerformanceClass = .high
    
    // MARK: - Performance Modes
    enum PerformanceMode: String, CaseIterable {
        case optimal = "Optimal"
        case balanced = "Balanced"
        case conservative = "Conservative"
        case minimal = "Minimal"
        
        var description: String {
            switch self {
            case .optimal:
                return "Full performance with all animations and effects"
            case .balanced:
                return "Good performance with reduced complexity"
            case .conservative:
                return "Basic performance with minimal effects"
            case .minimal:
                return "Essential functionality only"
            }
        }
        
        var maxSkeletonCount: Int {
            switch self {
            case .optimal: return 10
            case .balanced: return 6
            case .conservative: return 3
            case .minimal: return 1
            }
        }
        
        var enableComplexAnimations: Bool {
            switch self {
            case .optimal, .balanced: return true
            case .conservative, .minimal: return false
            }
        }
        
        var enableProMotionOptimizations: Bool {
            switch self {
            case .optimal: return true
            case .balanced, .conservative, .minimal: return false
            }
        }
    }
    
    enum MemoryPressureLevel: String {
        case normal = "Normal"
        case warning = "Warning"
        case critical = "Critical"
        
        var color: Color {
            switch self {
            case .normal: return .green
            case .warning: return .orange
            case .critical: return .red
            }
        }
    }
    
    enum DevicePerformanceClass {
        case high      // iPhone 13 Pro and newer
        case medium    // iPhone 12 and similar
        case low       // iPhone SE and older
        
        var description: String {
            switch self {
            case .high: return "High Performance Device"
            case .medium: return "Medium Performance Device"
            case .low: return "Low Performance Device"
            }
        }
    }
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "Jimmy", category: "PerformanceSafeguards")
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var thermalStateObserver: NSObjectProtocol?
    private var lowPowerModeObserver: NSObjectProtocol?
    private let performanceMonitor = PerformanceMonitor.shared
    
    private init() {
        setupDevicePerformanceClass()
        setupMemoryPressureMonitoring()
        setupThermalStateMonitoring()
        setupLowPowerModeMonitoring()
        updatePerformanceMode()
    }
    
    deinit {
        memoryPressureSource?.cancel()
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = lowPowerModeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Device Performance Classification
    
    private func setupDevicePerformanceClass() {
        let device = UIDevice.current
        let modelName = device.model
        
        // Simple heuristic based on available memory and processor
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let processorCount = ProcessInfo.processInfo.processorCount
        
        if totalMemory >= 6_000_000_000 && processorCount >= 6 { // 6GB+ RAM, 6+ cores
            devicePerformanceClass = .high
        } else if totalMemory >= 3_000_000_000 && processorCount >= 4 { // 3GB+ RAM, 4+ cores
            devicePerformanceClass = .medium
        } else {
            devicePerformanceClass = .low
        }
        
        logger.info("Device Performance Class: \(self.devicePerformanceClass.description)")
    }
    
    // MARK: - Memory Pressure Monitoring
    
    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        
        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            let event = self.memoryPressureSource?.mask
            
            if event?.contains(.critical) == true {
                self.memoryPressure = .critical
                self.handleCriticalMemoryPressure()
            } else if event?.contains(.warning) == true {
                self.memoryPressure = .warning
                self.handleMemoryWarning()
            }
            
            self.updatePerformanceMode()
        }
        
        memoryPressureSource?.resume()
    }
    
    private func handleMemoryWarning() {
        logger.warning("Memory pressure warning detected")
        
        // Reduce skeleton animation count
        // Clear image caches
        // Reduce animation complexity
        
        performanceMonitor.logCustomEvent(
            name: "MemoryPressureWarning",
            duration: 0,
            metadata: ["action": "reduced_performance"]
        )
    }
    
    private func handleCriticalMemoryPressure() {
        logger.error("Critical memory pressure detected")
        
        // Aggressive memory cleanup
        // Disable all non-essential animations
        // Clear all caches
        
        performanceMonitor.logCustomEvent(
            name: "CriticalMemoryPressure",
            duration: 0,
            metadata: ["action": "minimal_performance"]
        )
    }
    
    // MARK: - Thermal State Monitoring
    
    private func setupThermalStateMonitoring() {
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateThermalState()
        }
        
        updateThermalState()
    }
    
    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
        
        switch thermalState {
        case .serious, .critical:
            logger.warning("High thermal state detected: \(String(self.thermalState.rawValue))")
        default:
            break
        }
        
        updatePerformanceMode()
    }
    
    // MARK: - Low Power Mode Monitoring
    
    private func setupLowPowerModeMonitoring() {
        lowPowerModeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateLowPowerModeStatus()
        }
        
        updateLowPowerModeStatus()
    }
    
    private func updateLowPowerModeStatus() {
        isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled
        updatePerformanceMode()
    }
    
    // MARK: - Performance Mode Management
    
    private func updatePerformanceMode() {
        let newMode = calculateOptimalPerformanceMode()
        
        if newMode != currentPerformanceMode {
            logger.info("Performance mode changed: \(String(self.currentPerformanceMode.rawValue)) -> \(String(newMode.rawValue))")
            currentPerformanceMode = newMode
            
            performanceMonitor.logCustomEvent(
                name: "PerformanceModeChange",
                duration: 0,
                metadata: [
                    "newMode": newMode.rawValue,
                    "memoryPressure": memoryPressure.rawValue,
                    "thermalState": thermalState.rawValue,
                    "lowPowerMode": isLowPowerModeActive,
                    "deviceClass": devicePerformanceClass.description
                ]
            )
        }
    }
    
    private func calculateOptimalPerformanceMode() -> PerformanceMode {
        // Critical conditions force minimal mode
        if memoryPressure == .critical || thermalState == .critical {
            return .minimal
        }
        
        // Serious thermal or memory warning
        if memoryPressure == .warning || thermalState == .serious {
            return .conservative
        }
        
        // Low power mode or low-end device
        if isLowPowerModeActive || devicePerformanceClass == .low {
            return .balanced
        }
        
        // High thermal state but not critical
        if thermalState == .fair {
            return .balanced
        }
        
        // Optimal conditions
        return .optimal
    }
    
    // MARK: - Public API
    
    /// Returns the maximum number of skeleton views to show based on current performance mode
    func maxSkeletonCount(requested: Int) -> Int {
        return min(requested, currentPerformanceMode.maxSkeletonCount)
    }
    
    /// Returns whether complex animations should be enabled
    func shouldEnableComplexAnimations() -> Bool {
        return currentPerformanceMode.enableComplexAnimations && !UIAccessibility.isReduceMotionEnabled
    }
    
    /// Returns whether ProMotion optimizations should be used
    func shouldUseProMotionOptimizations() -> Bool {
        return currentPerformanceMode.enableProMotionOptimizations && ProMotionManager.shared.isProMotionAvailable
    }
    
    /// Returns an optimized animation based on current performance mode
    func optimizedAnimation(_ baseAnimation: Animation) -> Animation {
        if !shouldEnableComplexAnimations() {
            return .easeInOut(duration: 0.2) // Simple fallback
        }
        
        if shouldUseProMotionOptimizations() {
            return baseAnimation // Use ProMotion optimizations
        }
        
        return baseAnimation
    }
    
    /// Forces a performance mode (for testing/debugging)
    func forcePerformanceMode(_ mode: PerformanceMode) {
        currentPerformanceMode = mode
        logger.info("Performance mode forced to: \(String(mode.rawValue))")
    }
    
    /// Resets to automatic performance mode calculation
    func resetToAutomatic() {
        updatePerformanceMode()
        logger.info("Performance mode reset to automatic")
    }
    
    // MARK: - Debug Information
    
    var debugInfo: String {
        """
        Performance Safeguards Debug Info:
        - Current Mode: \(currentPerformanceMode.rawValue)
        - Memory Pressure: \(memoryPressure.rawValue)
        - Thermal State: \(thermalState.rawValue)
        - Low Power Mode: \(isLowPowerModeActive)
        - Device Class: \(devicePerformanceClass.description)
        - Complex Animations: \(shouldEnableComplexAnimations())
        - ProMotion Optimizations: \(shouldUseProMotionOptimizations())
        """
    }
}

// MARK: - View Modifiers

struct PerformanceAdaptive: ViewModifier {
    @StateObject private var safeguards = PerformanceSafeguards.shared
    let baseSkeletonCount: Int
    
    func body(content: Content) -> some View {
        content
            .environment(\.performanceSafeguards, safeguards)
            .environment(\.maxSkeletonCount, safeguards.maxSkeletonCount(requested: baseSkeletonCount))
            .environment(\.enableComplexAnimations, safeguards.shouldEnableComplexAnimations())
    }
}

// MARK: - Environment Keys

@MainActor
private struct PerformanceSafeguardsKey: EnvironmentKey {
    static let defaultValue = PerformanceSafeguards.shared
}

private struct MaxSkeletonCountKey: EnvironmentKey {
    static let defaultValue = 10
}

private struct EnableComplexAnimationsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var performanceSafeguards: PerformanceSafeguards {
        get { self[PerformanceSafeguardsKey.self] }
        set { self[PerformanceSafeguardsKey.self] = newValue }
    }
    
    var maxSkeletonCount: Int {
        get { self[MaxSkeletonCountKey.self] }
        set { self[MaxSkeletonCountKey.self] = newValue }
    }
    
    var enableComplexAnimations: Bool {
        get { self[EnableComplexAnimationsKey.self] }
        set { self[EnableComplexAnimationsKey.self] = newValue }
    }
}

// MARK: - View Extensions

extension View {
    /// Applies performance adaptations based on system conditions
    func performanceAdaptive(baseSkeletonCount: Int = 10) -> some View {
        modifier(PerformanceAdaptive(baseSkeletonCount: baseSkeletonCount))
    }
}

// MARK: - Performance Debug View

struct PerformanceSafeguardsDebugView: View {
    @StateObject private var safeguards = PerformanceSafeguards.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Current Status
                    statusSection
                    
                    // Performance Mode
                    performanceModeSection
                    
                    // System Conditions
                    systemConditionsSection
                    
                    // Manual Override
                    manualOverrideSection
                }
                .padding()
            }
            .navigationTitle("Performance Safeguards")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Status")
                .font(.headline)
            
            HStack {
                Circle()
                    .fill(safeguards.currentPerformanceMode == .optimal ? .green : 
                          safeguards.currentPerformanceMode == .balanced ? .blue :
                          safeguards.currentPerformanceMode == .conservative ? .orange : .red)
                    .frame(width: 12, height: 12)
                
                Text(safeguards.currentPerformanceMode.rawValue)
                    .font(.title2.bold())
                
                Spacer()
            }
            
            Text(safeguards.currentPerformanceMode.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }
    
    private var performanceModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Settings")
                .font(.headline)
            
            VStack(spacing: 8) {
                InfoRow(label: "Max Skeleton Count", value: "\(safeguards.maxSkeletonCount(requested: 10))")
                InfoRow(label: "Complex Animations", value: safeguards.shouldEnableComplexAnimations() ? "Enabled" : "Disabled")
                InfoRow(label: "ProMotion Optimizations", value: safeguards.shouldUseProMotionOptimizations() ? "Enabled" : "Disabled")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }
    
    private var systemConditionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Conditions")
                .font(.headline)
            
            VStack(spacing: 8) {
                InfoRow(label: "Memory Pressure", value: safeguards.memoryPressure.rawValue, color: safeguards.memoryPressure.color)
                InfoRow(label: "Thermal State", value: String(safeguards.thermalState.rawValue))
                InfoRow(label: "Low Power Mode", value: safeguards.isLowPowerModeActive ? "ON" : "OFF")
                InfoRow(label: "Device Class", value: safeguards.devicePerformanceClass.description)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }
    
    private var manualOverrideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual Override")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(PerformanceSafeguards.PerformanceMode.allCases, id: \.self) { mode in
                    Button(action: {
                        safeguards.forcePerformanceMode(mode)
                    }) {
                        HStack {
                            Text(mode.rawValue)
                            Spacer()
                            if safeguards.currentPerformanceMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Button("Reset to Automatic") {
                    safeguards.resetToAutomatic()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }
    
    private struct InfoRow: View {
        let label: String
        let value: String
        let color: Color?
        
        init(label: String, value: String, color: Color? = nil) {
            self.label = label
            self.value = value
            self.color = color
        }
        
        var body: some View {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundColor(color ?? .primary)
            }
        }
    }
}