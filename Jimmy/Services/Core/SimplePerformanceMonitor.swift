import Foundation
import Combine
import os

/// Simple performance monitoring service
class SimplePerformanceMonitor: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "SimplePerformanceMonitor")
    static let shared = SimplePerformanceMonitor()
    
    @Published var isMonitoring = false
    
    private var startTime: Date?
    private var memoryTimer: Timer?
    
    private init() {}
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        startTime = Date()
        
        // Check memory usage every 30 seconds
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            self.logMemoryUsage()
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        memoryTimer?.invalidate()
        memoryTimer = nil
    }
    
    private func logMemoryUsage() {
        let memoryUsage = getMemoryUsage()
        Self.logger.debug("Memory Usage: \(memoryUsage) MB")
    }
    
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        }
        return 0
    }
}