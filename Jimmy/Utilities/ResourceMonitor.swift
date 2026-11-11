import Foundation
import os
import Darwin

/// Monitors various system resources such as memory, CPU, disk and network usage.
/// Provides lightweight metrics for diagnostics and performance tuning.
final class ResourceMonitor {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "ResourceMonitor")
    static let shared = ResourceMonitor()

    private var timer: Timer?

    private init() {}

    // MARK: - Public Monitoring

    /// Start periodic resource monitoring.
    /// - Parameter interval: The interval in seconds between each metric capture.
    func startMonitoring(interval: TimeInterval = 60.0) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.logCurrentUsage()
        }
    }

    /// Stop periodic resource monitoring.
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Log current resource usage metrics using `print`.
    func logCurrentUsage() {
        let memory = currentMemoryUsage()
        let cpu = currentCPUUsage()
        let disk = currentDiskUsage()
        let network = currentNetworkUsage()

        let cpuFormatted = String(format: "%.2f", cpu)
        Self.logger.debug("Memory: \(memory) bytes | CPU: \(cpuFormatted)% | Disk used: \(disk) bytes | Network sent: \(network.sent) bytes recv: \(network.received) bytes")
    }

    // MARK: - Metrics

    /// Returns the app's current memory footprint in bytes.
    func currentMemoryUsage() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return info.phys_footprint
        } else {
            return 0
        }
    }

    /// Returns the app's approximate CPU usage percentage.
    func currentCPUUsage() -> Double {
        var threadsList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadsList, &threadCount) == KERN_SUCCESS,
              let threads = threadsList else {
            return 0
        }
        var totalUsage: Double = 0
        for i in 0 ..< Int(threadCount) {
            var info = thread_basic_info_data_t()
            var infoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if result == KERN_SUCCESS {
                let threadInfo = info
                if threadInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsage += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                }
            }
        }
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.size))
        return totalUsage
    }

    /// Returns used disk space in bytes for the app's home directory.
    func currentDiskUsage() -> UInt64 {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let total = attrs[.systemSize] as? UInt64,
           let free = attrs[.systemFreeSize] as? UInt64 {
            return total - free
        }
        return 0
    }

    /// Returns the network data usage (sent and received bytes) for all interfaces.
    func currentNetworkUsage() -> (sent: UInt64, received: UInt64) {
        var addressList: UnsafeMutablePointer<ifaddrs>? = nil
        var sent: UInt64 = 0
        var received: UInt64 = 0
        if getifaddrs(&addressList) == 0, let firstAddr = addressList {
            var ptr = firstAddr
            while ptr.pointee.ifa_next != nil {
                if let data = ptr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    sent += UInt64(data.pointee.ifi_obytes)
                    received += UInt64(data.pointee.ifi_ibytes)
                }
                ptr = ptr.pointee.ifa_next
            }
            freeifaddrs(addressList)
        }
        return (sent, received)
    }
}

