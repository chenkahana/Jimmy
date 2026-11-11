import Foundation
import Combine

// MARK: - Service Monitor
// Monitors service health, performance, and provides diagnostics

final class ServiceMonitor: ObservableObject {
    static let shared = ServiceMonitor()
    
    private let loggingService = LoggingService.shared
    private let errorHandler = ErrorHandlingService.shared
    
    // Service health tracking
    @Published private(set) var serviceHealth: [String: ServiceHealthStatus] = [:]
    private let healthLock = NSLock()
    
    // Performance monitoring
    private var performanceTrackers: [String: PerformanceTracker] = [:]
    private let trackerLock = NSLock()
    
    // Health check timer
    private var healthCheckTimer: Timer?
    private let healthCheckInterval: TimeInterval = 60.0 // 1 minute
    
    private init() {
        startHealthMonitoring()
    }
    
    deinit {
        stopHealthMonitoring()
    }
    
    // MARK: - Service Health Monitoring
    func registerService(_ serviceName: String, healthChecker: @escaping () async -> Bool) {
        healthLock.lock()
        defer { healthLock.unlock() }
        
        serviceHealth[serviceName] = ServiceHealthStatus(
            name: serviceName,
            isHealthy: true,
            lastCheck: Date(),
            errorCount: 0,
            healthChecker: healthChecker
        )
        
        loggingService.info("Service registered for monitoring: \(serviceName)", category: .service)
    }
    
    func updateServiceHealth(_ serviceName: String, isHealthy: Bool, error: Error? = nil) {
        healthLock.lock()
        defer { healthLock.unlock() }
        
        if var status = serviceHealth[serviceName] {
            status.isHealthy = isHealthy
            status.lastCheck = Date()
            
            if !isHealthy {
                status.errorCount += 1
                if let error = error {
                    status.lastError = error
                }
            } else {
                status.errorCount = 0
                status.lastError = nil
            }
            
            serviceHealth[serviceName] = status
            
            // Log health changes
            if !isHealthy {
                loggingService.warning("Service health degraded: \(serviceName)", category: .service)
                if let error = error {
                    errorHandler.logError(error, context: "ServiceMonitor-\(serviceName)", userInfo: nil)
                }
            } else if status.errorCount == 0 {
                loggingService.info("Service health restored: \(serviceName)", category: .service)
            }
        }
    }
    
    // MARK: - Performance Monitoring
    func startOperation(_ operationName: String, service: String) -> String {
        let operationId = UUID().uuidString
        let tracker = loggingService.startPerformanceTracking(for: "\(service).\(operationName)")
        
        trackerLock.lock()
        performanceTrackers[operationId] = tracker
        trackerLock.unlock()
        
        return operationId
    }
    
    func endOperation(_ operationId: String) {
        trackerLock.lock()
        let tracker = performanceTrackers.removeValue(forKey: operationId)
        trackerLock.unlock()
        
        if let tracker = tracker {
            loggingService.endPerformanceTracking(tracker)
        }
    }
    
    // MARK: - Health Checks
    private func startHealthMonitoring() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performHealthChecks()
            }
        }
    }
    
    private func stopHealthMonitoring() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }
    
    private func performHealthChecks() async {
        let services = await withCheckedContinuation { continuation in
            healthLock.lock()
            let services = Array(serviceHealth.values)
            healthLock.unlock()
            continuation.resume(returning: services)
        }
        
        for service in services {
            if let healthChecker = service.healthChecker {
                do {
                    let isHealthy = await healthChecker()
                    updateServiceHealth(service.name, isHealthy: isHealthy)
                } catch {
                    updateServiceHealth(service.name, isHealthy: false, error: error)
                }
            }
        }
    }
    
    // MARK: - Diagnostics
    func getServiceDiagnostics() -> ServiceDiagnostics {
        healthLock.lock()
        let currentHealth = serviceHealth
        healthLock.unlock()
        
        let performanceMetrics = loggingService.getPerformanceMetrics()
        
        let healthyServices = currentHealth.values.filter { $0.isHealthy }.count
        let totalServices = currentHealth.count
        let unhealthyServices = currentHealth.values.filter { !$0.isHealthy }
        
        return ServiceDiagnostics(
            totalServices: totalServices,
            healthyServices: healthyServices,
            unhealthyServices: Array(unhealthyServices),
            performanceMetrics: performanceMetrics,
            lastUpdate: Date()
        )
    }
    
    func getServiceHealth(_ serviceName: String) -> ServiceHealthStatus? {
        healthLock.lock()
        defer { healthLock.unlock() }
        
        return serviceHealth[serviceName]
    }
    
    // MARK: - Alerts
    func checkForAlerts() -> [ServiceAlert] {
        healthLock.lock()
        let currentHealth = serviceHealth
        healthLock.unlock()
        
        var alerts: [ServiceAlert] = []
        
        for (_, status) in currentHealth {
            // Check for unhealthy services
            if !status.isHealthy {
                alerts.append(ServiceAlert(
                    type: .serviceDown,
                    serviceName: status.name,
                    message: "Service \(status.name) is unhealthy",
                    severity: status.errorCount > 5 ? .critical : .warning,
                    timestamp: Date()
                ))
            }
            
            // Check for services with high error rates
            if status.errorCount > 10 {
                alerts.append(ServiceAlert(
                    type: .highErrorRate,
                    serviceName: status.name,
                    message: "Service \(status.name) has high error rate: \(status.errorCount) errors",
                    severity: .critical,
                    timestamp: Date()
                ))
            }
        }
        
        return alerts
    }
}

// MARK: - Supporting Types

struct ServiceHealthStatus {
    let name: String
    var isHealthy: Bool
    var lastCheck: Date
    var errorCount: Int
    var lastError: Error?
    let healthChecker: (() async -> Bool)?
}

struct ServiceDiagnostics {
    let totalServices: Int
    let healthyServices: Int
    let unhealthyServices: [ServiceHealthStatus]
    let performanceMetrics: [PerformanceMetric]
    let lastUpdate: Date
    
    var healthPercentage: Double {
        guard totalServices > 0 else { return 100.0 }
        return Double(healthyServices) / Double(totalServices) * 100.0
    }
}

struct ServiceAlert {
    let type: AlertType
    let serviceName: String
    let message: String
    let severity: AlertSeverity
    let timestamp: Date
    
    enum AlertType {
        case serviceDown
        case highErrorRate
        case slowPerformance
        case memoryLeak
    }
    
    enum AlertSeverity {
        case info
        case warning
        case critical
    }
}

// MARK: - Service Monitor Extensions

extension ServiceMonitor {
    /// Register core app services for monitoring
    func registerCoreServices() {
        // Register database service
        registerService("DatabaseManager") {
            return DatabaseManager.shared.isReady
        }
        
        // Register podcast service
        registerService("PodcastService") {
            // Simple health check - try to load podcasts count
            do {
                let _ = PodcastService.shared?.loadPodcasts() ?? []
                return true // If we can access the service, it's healthy
            } catch {
                return false
            }
        }
        
        // Register network service
        registerService("NetworkService") {
            // Simple connectivity check
            do {
                let url = URL(string: "https://www.apple.com")!
                let (_, response) = try await URLSession.shared.data(from: url)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }
    }
}