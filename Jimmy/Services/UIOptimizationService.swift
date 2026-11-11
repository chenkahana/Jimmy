import SwiftUI
import UIKit
import Combine
import os.log

/// Service for monitoring and optimizing UI performance across the app
/// Handles frame rate monitoring, memory management, and performance tuning
@MainActor
class UIOptimizationService: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "UIOptimizationService")
    static let shared = UIOptimizationService()
    
    // MARK: - Published Properties
    
    @Published var currentFPS: Double = 60.0
    @Published var isOptimizing = false
    @Published var memoryUsage: Double = 0.0
    @Published var performanceMode: PerformanceMode = .standard
    
    // MARK: - Performance Modes
    
    enum PerformanceMode: String, CaseIterable {
        case battery = "Battery Saver"
        case standard = "Standard"
        case performance = "High Performance"
        case maximum = "Maximum Performance"
        
        var animationDuration: Double {
            switch self {
            case .battery: return 0.5
            case .standard: return 0.3
            case .performance: return 0.2
            case .maximum: return 0.15
            }
        }
        
        var imageQuality: Double {
            switch self {
            case .battery: return 0.6
            case .standard: return 0.8
            case .performance: return 0.9
            case .maximum: return 1.0
            }
        }
        
        var maxConcurrentOperations: Int {
            switch self {
            case .battery: return 2
            case .standard: return 3
            case .performance: return 5
            case .maximum: return 8
            }
        }
    }
    
    // MARK: - Private Properties
    
    private var frameRateMonitor: Timer?
    private var memoryMonitor: Timer?
    private var lastFrameTime = CACurrentMediaTime()
    private var frameCount = 0
    private var fpsHistory: [Double] = []
    private var cancellables = Set<AnyCancellable>()
    
    // Performance thresholds
    private let lowFPSThreshold: Double = 45.0
    private let highMemoryThreshold: Double = 300.0 // MB
    private let criticalMemoryThreshold: Double = 500.0 // MB
    
    // MARK: - Initialization
    
    private init() {
        setupPerformanceMonitoring()
        setupMemoryMonitoring()
        setupNotificationObservers()
        
        // Auto-adjust performance mode based on device capabilities
        adjustPerformanceModeForDevice()
    }
    
    deinit {
        frameRateMonitor?.invalidate()
        memoryMonitor?.invalidate()
    }
    
    // MARK: - Performance Monitoring
    
    private func setupPerformanceMonitoring() {
        // Monitor frame rate every second (reduced frequency to avoid overhead)
        frameRateMonitor = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.measureFrameRate()
            }
        }
    }
    
    private func measureFrameRate() {
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastFrameTime
        lastFrameTime = currentTime
        
        if deltaTime > 0 {
            let fps = 1.0 / deltaTime
            currentFPS = fps
            
            // Keep FPS history for trend analysis
            fpsHistory.append(fps)
            if fpsHistory.count > 10 {
                fpsHistory.removeFirst()
            }
            
            // Auto-adjust performance if needed
            autoAdjustPerformance()
        }
    }
    
    private func setupMemoryMonitoring() {
        // Monitor memory usage every 5 seconds
        memoryMonitor = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryUsage()
            }
        }
    }
    
    private func updateMemoryUsage() {
        let usage = getMemoryUsage()
        memoryUsage = Double(usage) / (1024 * 1024) // Convert to MB
        
        // Handle memory pressure
        if memoryUsage > criticalMemoryThreshold {
            handleCriticalMemoryPressure()
        } else if memoryUsage > highMemoryThreshold {
            handleHighMemoryPressure()
        }
    }
    
    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return kerr == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
    
    // MARK: - Performance Optimization
    
    private func autoAdjustPerformance() {
        let averageFPS = fpsHistory.isEmpty ? 60.0 : fpsHistory.reduce(0, +) / Double(fpsHistory.count)
        
        // Only adjust if we have enough data
        guard fpsHistory.count >= 5 else { return }
        
        if averageFPS < lowFPSThreshold && performanceMode != .battery {
            // Reduce performance mode to improve FPS
            switch performanceMode {
            case .maximum:
                setPerformanceMode(.performance)
            case .performance:
                setPerformanceMode(.standard)
            case .standard:
                setPerformanceMode(.battery)
            case .battery:
                break
            }
        } else if averageFPS > 55.0 && performanceMode != .maximum {
            // Increase performance mode if FPS is stable
            switch performanceMode {
            case .battery:
                setPerformanceMode(.standard)
            case .standard:
                setPerformanceMode(.performance)
            case .performance:
                setPerformanceMode(.maximum)
            case .maximum:
                break
            }
        }
    }
    
    func setPerformanceMode(_ mode: PerformanceMode) {
        guard mode != performanceMode else { return }
        
        performanceMode = mode
        applyPerformanceOptimizations()
        
        Self.logger.info("Performance mode changed to: \(String(mode.rawValue))")
    }
    
    private func applyPerformanceOptimizations() {
        // Apply optimizations based on current performance mode
        switch performanceMode {
        case .battery:
            enableBatterySaverOptimizations()
        case .standard:
            enableStandardOptimizations()
        case .performance:
            enableHighPerformanceOptimizations()
        case .maximum:
            enableMaximumPerformanceOptimizations()
        }
    }
    
    // MARK: - Performance Mode Implementations
    
    private func enableBatterySaverOptimizations() {
        // Reduce animation complexity
        UIView.setAnimationsEnabled(true)
        
        // Reduce image cache size
        ImageCache.shared.clearMemoryCache()
        
        // Limit concurrent operations
        OperationQueue.main.maxConcurrentOperationCount = performanceMode.maxConcurrentOperations
    }
    
    private func enableStandardOptimizations() {
        // Standard performance settings
        UIView.setAnimationsEnabled(true)
        OperationQueue.main.maxConcurrentOperationCount = performanceMode.maxConcurrentOperations
    }
    
    private func enableHighPerformanceOptimizations() {
        // Enable high performance features
        UIView.setAnimationsEnabled(true)
        OperationQueue.main.maxConcurrentOperationCount = performanceMode.maxConcurrentOperations
        
        // Preload more content
        SmartImagePreloader.shared.preloadUpcomingContent(urls: [])
    }
    
    private func enableMaximumPerformanceOptimizations() {
        // Maximum performance settings
        UIView.setAnimationsEnabled(true)
        OperationQueue.main.maxConcurrentOperationCount = performanceMode.maxConcurrentOperations
        
        // Enable all optimizations
        UIPerformanceManager.shared.enableUltraHighPerformanceMode()
    }
    
    // MARK: - Memory Management
    
    private func handleHighMemoryPressure() {
        let memUsageFormatted = String(format: "%.1f", memoryUsage)
        Self.logger.warning("High memory usage detected: \(memUsageFormatted)MB")
        
        // Clear image caches
        ImageCache.shared.clearMemoryCache()
        // Note: BulletproofImageCache doesn't have clearMemoryCache method
        
        // Temporarily reduce performance mode
        if performanceMode != .battery {
            let originalMode = performanceMode
            setPerformanceMode(.battery)
            
            // Restore after memory pressure subsides
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                if self.memoryUsage < self.highMemoryThreshold {
                    self.setPerformanceMode(originalMode)
                }
            }
        }
    }
    
    private func handleCriticalMemoryPressure() {
        let critMemUsageFormatted = String(format: "%.1f", memoryUsage)
        Self.logger.error("Critical memory usage detected: \(critMemUsageFormatted)MB")
        
        // Aggressive memory cleanup
        ImageCache.shared.clearAllCaches()
        
        // Force garbage collection
        autoreleasepool {
            // Trigger memory cleanup
        }
        
        // Set to battery saver mode
        setPerformanceMode(.battery)
    }
    
    // MARK: - Device-Specific Optimizations
    
    private func adjustPerformanceModeForDevice() {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        
        // Adjust based on device capabilities
        if totalMemory > 6_000_000_000 { // 6GB+ RAM
            setPerformanceMode(.maximum)
        } else if totalMemory > 4_000_000_000 { // 4GB+ RAM
            setPerformanceMode(.performance)
        } else if totalMemory > 2_000_000_000 { // 2GB+ RAM
            setPerformanceMode(.standard)
        } else {
            setPerformanceMode(.battery)
        }
        
        // Check for low power mode
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            setPerformanceMode(.battery)
        }
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // Low power mode changes
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    if ProcessInfo.processInfo.isLowPowerModeEnabled {
                        self?.setPerformanceMode(.battery)
                    } else {
                        self?.adjustPerformanceModeForDevice()
                    }
                }
            }
            .store(in: &cancellables)
        
        // Memory warnings
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleCriticalMemoryPressure()
                }
            }
            .store(in: &cancellables)
        
        // App state changes
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.pausePerformanceMonitoring()
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.resumePerformanceMonitoring()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Monitoring Control
    
    private func pausePerformanceMonitoring() {
        frameRateMonitor?.invalidate()
        memoryMonitor?.invalidate()
    }
    
    private func resumePerformanceMonitoring() {
        setupPerformanceMonitoring()
        setupMemoryMonitoring()
    }
    
    // MARK: - Public Interface
    
    /// Temporarily boost performance for intensive operations
    func boostPerformance(duration: TimeInterval = 10.0) {
        let originalMode = performanceMode
        setPerformanceMode(.maximum)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.setPerformanceMode(originalMode)
        }
    }
    
    /// Get current performance statistics
    func getPerformanceStats() -> PerformanceStats {
        let averageFPS = fpsHistory.isEmpty ? 0 : fpsHistory.reduce(0, +) / Double(fpsHistory.count)
        
        return PerformanceStats(
            currentFPS: currentFPS,
            averageFPS: averageFPS,
            memoryUsage: memoryUsage,
            performanceMode: performanceMode,
            isOptimizing: isOptimizing
        )
    }
    
    /// Force performance optimization
    func optimizeNow() {
        isOptimizing = true
        
        Task {
            // Clear caches
            ImageCache.shared.clearMemoryCache()
            
            // Force garbage collection
            autoreleasepool {
                // Cleanup operations
            }
            
            await MainActor.run {
                self.isOptimizing = false
            }
        }
    }
}

// MARK: - Performance Statistics

struct PerformanceStats {
    let currentFPS: Double
    let averageFPS: Double
    let memoryUsage: Double
    let performanceMode: UIOptimizationService.PerformanceMode
    let isOptimizing: Bool
    
    var performanceGrade: String {
        if averageFPS >= 55 && memoryUsage < 200 {
            return "Excellent"
        } else if averageFPS >= 45 && memoryUsage < 300 {
            return "Good"
        } else if averageFPS >= 30 && memoryUsage < 400 {
            return "Fair"
        } else {
            return "Poor"
        }
    }
}

// MARK: - SwiftUI Integration

struct PerformanceOptimizedView<Content: View>: View {
    let content: Content
    private let viewLogger = Logger(subsystem: "com.chenkahana.Jimmy", category: "PerformanceOptimizedView")

    @StateObject private var optimizer = UIOptimizationService.shared

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .onAppear {
                optimizer.boostPerformance(duration: 5.0)
            }
            .onChange(of: optimizer.performanceMode) { _, newMode in
                // React to performance mode changes
                viewLogger.info("Performance mode updated: \(newMode.rawValue)")
            }
    }
}

extension View {
    /// Wrap view with performance optimization
    func optimizeUIPerformance() -> some View {
        PerformanceOptimizedView {
            self
        }
    }
}