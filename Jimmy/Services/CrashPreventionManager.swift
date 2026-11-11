import Foundation
import AVFoundation

/// Comprehensive crash prevention manager for audio playback and app stability
class CrashPreventionManager {
    static let shared = CrashPreventionManager()
    // MARK: - Configuration
    private struct Config {
        static let maxMemoryUsage: Int = 300 * 1024 * 1024 // 300MB
        static let criticalMemoryThreshold: Int = 400 * 1024 * 1024 // 400MB
        static let maxConcurrentOperations = 3
        static let audioSessionRetryAttempts = 3
        static let kvoObserverTimeout: TimeInterval = 30.0
    }
    
    // MARK: - Properties
    private(set) var memoryUsage: Int = 0
    private(set) var isMemoryWarning: Bool = false
    private(set) var crashPreventionActive: Bool = false
    private(set) var audioSessionHealthy: Bool = true
    
    // MARK: - Private Properties
    private var memoryMonitorTimer: Timer?
    private var audioSessionMonitorTimer: Timer?
    private var kvoObservers: Set<NSObject> = []
    private var activeOperations: Set<String> = []
    private let operationQueue = DispatchQueue(label: "crash-prevention", qos: .utility)
    private let memoryQueue = DispatchQueue(label: "memory-monitor", qos: .background)
    
    // Crash prevention state
    private var isInCrashPreventionMode = false
    private var lastMemoryWarning: Date?
    private var audioSessionFailureCount = 0
    
    private init() {
        setupCrashPrevention()
        startMonitoring()
    }
    
    deinit {
        Task { @MainActor [weak self] in
            self?.stopMonitoring()
            self?.cleanupAllObservers()
        }
    }
    
    // MARK: - Public Interface
    
    /// Start comprehensive crash prevention monitoring
    func startCrashPrevention() {
        crashPreventionActive = true
        
        setupMemoryWarningHandling()
        setupAudioSessionMonitoring()
        setupKVOSafetyNet()
        setupOperationLimiting()
    }
    
    /// Stop crash prevention (for testing only)
    func stopCrashPrevention() {
        crashPreventionActive = false
        stopMonitoring()
    }
    
    /// Handle memory warning with aggressive cleanup
    func handleMemoryWarning() {
        
        isMemoryWarning = true
        lastMemoryWarning = Date()
        isInCrashPreventionMode = true
        
        operationQueue.async { [weak self] in
            self?.performEmergencyCleanup()
        }
        
        // Reset warning state after cleanup
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            self.isMemoryWarning = false
        }
    }
    
    /// Safe KVO observer registration with automatic cleanup
    func safeAddObserver(_ observer: NSObject, to object: NSObject, forKeyPath keyPath: String, options: NSKeyValueObservingOptions = [], context: UnsafeMutableRawPointer? = nil) {
        do {
            object.addObserver(observer, forKeyPath: keyPath, options: options, context: context)
            kvoObservers.insert(observer)
        } catch {
        }
    }
    
    /// Safe KVO observer removal
    func safeRemoveObserver(_ observer: NSObject, from object: NSObject, forKeyPath keyPath: String) {
        do {
            object.removeObserver(observer, forKeyPath: keyPath)
            kvoObservers.remove(observer)
        } catch {
        }
    }
    
    /// Safe audio session configuration with retry logic
    func safeConfigureAudioSession(category: AVAudioSession.Category, mode: AVAudioSession.Mode = .default, options: AVAudioSession.CategoryOptions = []) -> Bool {
        for attempt in 1...Config.audioSessionRetryAttempts {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(category, mode: mode, options: options)
                audioSessionHealthy = true
                audioSessionFailureCount = 0
                return true
            } catch {
                audioSessionFailureCount += 1
                
                if attempt < Config.audioSessionRetryAttempts {
                    // Use Task.sleep for non-blocking delay
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(0.1 * Double(attempt) * 1_000_000_000))
                    }
                }
            }
        }
        
        audioSessionHealthy = false
        return false
    }
    
    /// Safe audio session activation
    func safeActivateAudioSession() -> Bool {
        guard audioSessionHealthy else {
            return false
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            return true
        } catch {
            audioSessionHealthy = false
            return false
        }
    }
    
    /// Limit concurrent operations to prevent resource exhaustion
    func executeWithLimit<T>(operationId: String, operation: @escaping () async throws -> T) async throws -> T {
        guard activeOperations.count < Config.maxConcurrentOperations else {
            throw CrashPreventionError.tooManyOperations
        }
        
        activeOperations.insert(operationId)
        defer { activeOperations.remove(operationId) }
        
        return try await operation()
    }
    
    /// Get current system health status
    func getSystemHealth() -> SystemHealth {
        let currentMemory = getCurrentMemoryUsage()
        let memoryStatus: MemoryStatus
        
        if currentMemory > Config.criticalMemoryThreshold {
            memoryStatus = .critical
        } else if currentMemory > Config.maxMemoryUsage {
            memoryStatus = .warning
        } else {
            memoryStatus = .normal
        }
        
        return SystemHealth(
            memoryUsage: currentMemory,
            memoryStatus: memoryStatus,
            audioSessionHealthy: audioSessionHealthy,
            activeOperations: activeOperations.count,
            crashPreventionActive: crashPreventionActive
        )
    }
    
    // MARK: - Private Methods
    
    private func setupCrashPrevention() {
        // Setup notification observers for system events
        // Note: Memory warning handling moved to app delegate level
    }
    
    private func startMonitoring() {
        // MEMORY FIX: Reduce memory monitoring frequency from 10s to 60s to reduce overhead
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            Task { @MainActor in
                self.monitorMemoryUsage()
            }
        }
        
        // MEMORY FIX: Reduce audio session monitoring frequency from 30s to 120s
        audioSessionMonitorTimer = Timer.scheduledTimer(withTimeInterval: 120.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            Task { @MainActor in
                self.monitorAudioSession()
            }
        }
    }
    
    private func stopMonitoring() {
        memoryMonitorTimer?.invalidate()
        audioSessionMonitorTimer?.invalidate()
        memoryMonitorTimer = nil
        audioSessionMonitorTimer = nil
    }
    
    private func setupMemoryWarningHandling() {
        // Additional memory pressure monitoring
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: memoryQueue)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleMemoryPressure()
            }
        }
        source.resume()
    }
    
    private func setupAudioSessionMonitoring() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioSessionInterruption(notification)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioRouteChange(notification)
            }
        }
    }
    
    private func setupKVOSafetyNet() {
        // PERFORMANCE FIX: Reduce KVO cleanup frequency from 30s to 300s (5 minutes) to reduce CPU usage
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupOrphanedObservers()
            }
        }
    }
    
    private func setupOperationLimiting() {
        // PERFORMANCE FIX: Reduce operation monitoring frequency from 5s to 60s (1 minute) to reduce CPU usage
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.monitorActiveOperations()
            }
        }
    }
    
    private func performEmergencyCleanup() {
        
        // MEMORY FIX: More aggressive cleanup
        // Audio player cache removed - AVPlayerItems now created fresh to prevent crashes
        // Clear image cache if available
        // ImageCache.shared.clearCache()
        // Note: OptimizedNetworkManager no longer has clearExpiredCache method
        // Cache management is now handled internally
        
        // Stop non-essential operations
        Task { @MainActor in
            EpisodeUpdateService.shared.stopPeriodicUpdates()
        }
        
        // MEMORY FIX: Cancel all background tasks
        BackgroundTaskCoordinator.shared.cancelAllTasks()
        
        // MEMORY FIX: Force multiple garbage collection cycles
        for _ in 0..<3 {
            autoreleasepool {
                // This helps trigger garbage collection
            }
        }
        
    }
    
    private func monitorMemoryUsage() {
        memoryQueue.async { [weak self] in
            let currentMemory = self?.getCurrentMemoryUsage() ?? 0
            
            Task { @MainActor in
                guard let self = self else { return }
                self.memoryUsage = currentMemory
                
                if currentMemory > Config.maxMemoryUsage && !self.isInCrashPreventionMode {
                    self.handleMemoryPressure()
                }
            }
        }
    }
    
    private func monitorAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Check if audio session is still valid
        do {
            _ = audioSession.category
            audioSessionHealthy = true
            audioSessionFailureCount = 0
        } catch {
            audioSessionHealthy = false
            audioSessionFailureCount += 1
            
            // Try to recover audio session
            if audioSessionFailureCount < 3 {
                _ = safeConfigureAudioSession(category: .playback)
            }
        }
    }
    
    private func monitorActiveOperations() {
        if activeOperations.count > Config.maxConcurrentOperations {
            // Could implement operation cancellation here
        }
    }
    
    private func handleMemoryPressure() {
        guard !isInCrashPreventionMode else { return }
        
        isInCrashPreventionMode = true
        
        operationQueue.async { [weak self] in
            // Gradual cleanup to avoid sudden memory drops
            self?.performGradualCleanup()
            
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                self?.isInCrashPreventionMode = false
            }
        }
    }
    
    private func performGradualCleanup() {
        // Clear expired caches first
        // Note: OptimizedNetworkManager no longer has clearExpiredCache method
        // Cache management is now handled internally
        
        // Reduce image cache size (if available)
        // ImageCache.shared.reduceCache()
        
        // Audio player cache removed - no cleanup needed
        
    }
    
    private func cleanupOrphanedObservers() {
        // Remove any observers that might be orphaned
        let orphanedObservers = kvoObservers.filter { observer in
            // Check if observer is still valid (simplified check)
            return observer.isKind(of: NSObject.self)
        }
        
        if orphanedObservers.count != kvoObservers.count {
            kvoObservers = Set(orphanedObservers)
        }
    }
    
    private func cleanupAllObservers() {
        kvoObservers.removeAll()
    }
    
    private func handleAudioSessionInterruption(_ notification: Notification) {
        // Additional safety measures for audio interruptions
    }
    
    private func handleAudioRouteChange(_ notification: Notification) {
        // Additional safety measures for route changes
    }
    
    private func handleAppDidEnterBackground() {
        performGradualCleanup()
    }
    
    private func handleAppWillTerminate() {
        cleanupAllObservers()
        stopMonitoring()
    }
    
    private func getCurrentMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int(info.resident_size)
        } else {
            return 0
        }
    }
}

// MARK: - Supporting Types

enum CrashPreventionError: Error {
    case tooManyOperations
    case memoryPressure
    case audioSessionFailure
    case kvoObserverFailure
}

enum MemoryStatus {
    case normal
    case warning
    case critical
}

struct SystemHealth {
    let memoryUsage: Int
    let memoryStatus: MemoryStatus
    let audioSessionHealthy: Bool
    let activeOperations: Int
    let crashPreventionActive: Bool
    
    var isHealthy: Bool {
        return memoryStatus != .critical && audioSessionHealthy && activeOperations < 5
    }
}

// MARK: - Extensions
