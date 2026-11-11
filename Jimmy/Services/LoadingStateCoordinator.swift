import SwiftUI
import Combine
import os

/// Centralized coordinator for managing loading states across the app
/// Provides consistent loading experiences and prevents conflicting states
@MainActor
class LoadingStateCoordinator: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "LoadingStateCoordinator")
    static let shared = LoadingStateCoordinator()
    
    // MARK: - Published Properties
    
    @Published var activeLoadingOperations: [LoadingOperation] = []
    @Published var globalLoadingState: GlobalLoadingState = .idle
    
    // MARK: - Loading Operation Model
    
    struct LoadingOperation: Identifiable, Equatable {
        let id = UUID()
        let key: String
        let type: LoadingType
        let message: String
        let progress: Double?
        let canCancel: Bool
        let onCancel: (() -> Void)?
        let priority: Priority
        let startTime: Date
        
        enum LoadingType {
            case appInitialization
            case dataRefresh
            case contentLoading
            case imageLoading
            case networkRequest
            case fileOperation
            case backgroundSync
            
            var timeout: TimeInterval {
                switch self {
                case .appInitialization: return 30.0
                case .dataRefresh: return 15.0
                case .contentLoading: return 10.0
                case .imageLoading: return 5.0
                case .networkRequest: return 10.0
                case .fileOperation: return 5.0
                case .backgroundSync: return 60.0
                }
            }
        }
        
        enum Priority: Int, Comparable {
            case low = 0
            case normal = 1
            case high = 2
            case critical = 3
            
            static func < (lhs: Priority, rhs: Priority) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }
        
        static func == (lhs: LoadingOperation, rhs: LoadingOperation) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    // MARK: - Global Loading State
    
    enum GlobalLoadingState {
        case idle
        case loading(String)
        case error(String)
        case success(String)
        
        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var operationTimeouts: [UUID: Timer] = [:]
    
    // MARK: - Initialization
    
    private init() {
        setupGlobalStateMonitoring()
    }
    
    // MARK: - Public Interface
    
    /// Start a loading operation
    func startLoading(
        key: String,
        type: LoadingOperation.LoadingType,
        message: String,
        progress: Double? = nil,
        canCancel: Bool = false,
        onCancel: (() -> Void)? = nil,
        priority: LoadingOperation.Priority = .normal
    ) {
        // Remove existing operation with same key
        stopLoading(key: key)
        
        let operation = LoadingOperation(
            key: key,
            type: type,
            message: message,
            progress: progress,
            canCancel: canCancel,
            onCancel: onCancel,
            priority: priority,
            startTime: Date()
        )
        
        activeLoadingOperations.append(operation)
        
        // Setup timeout
        setupTimeout(for: operation)
        
        // Update global state
        updateGlobalState()
        
        // Show user feedback for high priority operations
        if priority >= .high {
            UserFeedbackService.shared.showProgress(
                title: message,
                isIndeterminate: progress == nil,
                canCancel: canCancel,
                onCancel: onCancel
            )
        }
    }
    
    /// Update progress for an existing operation
    func updateProgress(key: String, progress: Double, message: String? = nil) {
        guard let index = activeLoadingOperations.firstIndex(where: { $0.key == key }) else {
            return
        }
        
        let operation = activeLoadingOperations[index]
        let updatedOperation = LoadingOperation(
            key: operation.key,
            type: operation.type,
            message: message ?? operation.message,
            progress: progress,
            canCancel: operation.canCancel,
            onCancel: operation.onCancel,
            priority: operation.priority,
            startTime: operation.startTime
        )
        
        activeLoadingOperations[index] = updatedOperation
        
        // Update user feedback for high priority operations
        if operation.priority >= .high {
            UserFeedbackService.shared.updateProgress(progress, message: message)
        }
    }
    
    /// Stop a loading operation
    func stopLoading(key: String, success: Bool = true, message: String? = nil) {
        guard let index = activeLoadingOperations.firstIndex(where: { $0.key == key }) else {
            return
        }
        
        let operation = activeLoadingOperations[index]
        activeLoadingOperations.remove(at: index)
        
        // Clear timeout
        if let timer = operationTimeouts[operation.id] {
            timer.invalidate()
            operationTimeouts.removeValue(forKey: operation.id)
        }
        
        // Update global state
        updateGlobalState()
        
        // Show completion feedback for high priority operations
        if operation.priority >= .high {
            UserFeedbackService.shared.dismissProgress()
            
            if let message = message {
                if success {
                    UserFeedbackService.shared.showSuccess(message)
                } else {
                    UserFeedbackService.shared.showError(message)
                }
            }
        }
    }
    
    /// Stop all loading operations
    func stopAllLoading() {
        _ = activeLoadingOperations
        activeLoadingOperations.removeAll()
        
        // Clear all timeouts
        for timer in operationTimeouts.values {
            timer.invalidate()
        }
        operationTimeouts.removeAll()
        
        // Dismiss any active progress
        UserFeedbackService.shared.dismissProgress()
        
        updateGlobalState()
    }
    
    /// Check if a specific operation is loading
    func isLoading(key: String) -> Bool {
        return activeLoadingOperations.contains { $0.key == key }
    }
    
    /// Get loading operation by key
    func getOperation(key: String) -> LoadingOperation? {
        return activeLoadingOperations.first { $0.key == key }
    }
    
    /// Get all operations of a specific type
    func getOperations(ofType type: LoadingOperation.LoadingType) -> [LoadingOperation] {
        return activeLoadingOperations.filter { $0.type == type }
    }
    
    // MARK: - Convenience Methods
    
    /// Start app initialization loading
    func startAppInitialization(message: String = "Initializing app...") {
        startLoading(
            key: "app_init",
            type: .appInitialization,
            message: message,
            priority: .critical
        )
    }
    
    /// Start data refresh loading
    func startDataRefresh(key: String, message: String = "Refreshing data...") {
        startLoading(
            key: key,
            type: .dataRefresh,
            message: message,
            priority: .normal
        )
    }
    
    /// Start content loading
    func startContentLoading(key: String, message: String = "Loading content...") {
        startLoading(
            key: key,
            type: .contentLoading,
            message: message,
            priority: .normal
        )
    }
    
    /// Start network request
    func startNetworkRequest(key: String, message: String = "Loading...") {
        startLoading(
            key: key,
            type: .networkRequest,
            message: message,
            priority: .normal
        )
    }
    
    // MARK: - Private Methods
    
    private func setupGlobalStateMonitoring() {
        $activeLoadingOperations
            .sink { [weak self] operations in
                self?.updateGlobalState()
            }
            .store(in: &cancellables)
    }
    
    private func updateGlobalState() {
        if activeLoadingOperations.isEmpty {
            globalLoadingState = .idle
        } else {
            // Find highest priority operation
            let highestPriorityOperation = activeLoadingOperations.max { $0.priority < $1.priority }
            if let operation = highestPriorityOperation {
                globalLoadingState = .loading(operation.message)
            }
        }
    }
    
    private func setupTimeout(for operation: LoadingOperation) {
        let timer = Timer.scheduledTimer(withTimeInterval: operation.type.timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleTimeout(for: operation)
            }
        }
        
        operationTimeouts[operation.id] = timer
    }
    
    private func handleTimeout(for operation: LoadingOperation) {
        // Remove timed out operation
        activeLoadingOperations.removeAll { $0.id == operation.id }
        operationTimeouts.removeValue(forKey: operation.id)
        
        // Show timeout error for high priority operations
        if operation.priority >= .high {
            UserFeedbackService.shared.dismissProgress()
            UserFeedbackService.shared.showError("Operation timed out: \(operation.message)")
        }
        
        updateGlobalState()
        
        Self.logger.warning("Loading operation timed out: \(operation.key) - \(operation.message)")
    }
    
    // MARK: - Analytics and Monitoring
    
    /// Get loading statistics
    func getLoadingStatistics() -> LoadingStatistics {
        let totalOperations = activeLoadingOperations.count
        let operationsByType = Dictionary(grouping: activeLoadingOperations) { $0.type }
        let averageDuration = activeLoadingOperations.map { Date().timeIntervalSince($0.startTime) }.reduce(0, +) / Double(max(totalOperations, 1))
        
        return LoadingStatistics(
            totalActiveOperations: totalOperations,
            operationsByType: operationsByType.mapValues { $0.count },
            averageDuration: averageDuration,
            longestRunningOperation: activeLoadingOperations.max { $0.startTime > $1.startTime }
        )
    }
}

// MARK: - Loading Statistics

struct LoadingStatistics {
    let totalActiveOperations: Int
    let operationsByType: [LoadingStateCoordinator.LoadingOperation.LoadingType: Int]
    let averageDuration: TimeInterval
    let longestRunningOperation: LoadingStateCoordinator.LoadingOperation?
    
    var hasLongRunningOperations: Bool {
        guard let longest = longestRunningOperation else { return false }
        return Date().timeIntervalSince(longest.startTime) > 10.0
    }
}

// MARK: - SwiftUI Integration

/// View modifier that automatically manages loading state
struct AutoLoadingStateModifier: ViewModifier {
    let key: String
    let type: LoadingStateCoordinator.LoadingOperation.LoadingType
    let message: String
    @Binding var isLoading: Bool
    
    @StateObject private var coordinator = LoadingStateCoordinator.shared
    
    func body(content: Content) -> some View {
        content
            .onChange(of: isLoading) { _, newValue in
                if newValue {
                    coordinator.startLoading(
                        key: key,
                        type: type,
                        message: message
                    )
                } else {
                    coordinator.stopLoading(key: key)
                }
            }
            .onDisappear {
                coordinator.stopLoading(key: key)
            }
    }
}

extension View {
    /// Automatically manage loading state with coordinator
    func autoLoadingState(
        key: String,
        type: LoadingStateCoordinator.LoadingOperation.LoadingType = .contentLoading,
        message: String = "Loading...",
        isLoading: Binding<Bool>
    ) -> some View {
        modifier(AutoLoadingStateModifier(
            key: key,
            type: type,
            message: message,
            isLoading: isLoading
        ))
    }
}

// MARK: - Global Loading Overlay

/// Global loading overlay that shows critical loading operations
struct GlobalLoadingOverlay: View {
    @ObservedObject private var coordinator = LoadingStateCoordinator.shared
    
    var body: some View {
        if case .loading(let message) = coordinator.globalLoadingState {
            // Only show for critical operations
            let criticalOperations = coordinator.activeLoadingOperations.filter { $0.priority == .critical }
            
            if !criticalOperations.isEmpty {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ContextualLoadingIndicator(
                        type: .contentLoading,
                        message: message,
                        showCancel: false
                    )
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: coordinator.globalLoadingState.isLoading)
            }
        }
    }
}

extension View {
    /// Add global loading overlay
    func withGlobalLoadingOverlay() -> some View {
        self.overlay(GlobalLoadingOverlay())
    }
}