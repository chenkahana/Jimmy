import Foundation
import SwiftUI

// MARK: - Component Rollback Service
/// Provides component-level rollback capabilities for individual features
@MainActor
class ComponentRollbackService: ObservableObject {
    static let shared = ComponentRollbackService()
    
    @Published private var componentStates: [String: ComponentState] = [:]
    @Published private var rollbackHistory: [RollbackEvent] = []
    
    private let userDefaults = UserDefaults.standard
    private let statesKey = "ComponentRollbackStates"
    private let historyKey = "ComponentRollbackHistory"
    
    init() {
        loadStates()
        loadHistory()
    }
    
    // MARK: - Public Interface
    
    /// Register a component with its current state
    func registerComponent(_ component: RollbackableComponent, state: ComponentState) {
        componentStates[component.identifier] = state
        saveStates()
    }
    
    /// Check if a component can be rolled back
    func canRollback(_ component: RollbackableComponent) -> Bool {
        guard let state = componentStates[component.identifier] else { return false }
        return state.previousVersion != nil
    }
    
    /// Rollback a specific component to its previous state
    func rollbackComponent(_ component: RollbackableComponent) async -> RollbackResult {
        guard let currentState = componentStates[component.identifier] else {
            return .failure(.componentNotFound)
        }
        
        guard let previousVersion = currentState.previousVersion else {
            return .failure(.noPreviousVersion)
        }
        
        do {
            // Create backup of current state
            let backupState = ComponentState(
                version: currentState.version,
                configuration: currentState.configuration,
                isEnabled: currentState.isEnabled,
                previousVersion: nil, // Don't chain backups
                createdAt: currentState.createdAt,
                metadata: currentState.metadata
            )
            
            // Attempt rollback
            let rollbackSuccess = await component.performRollback(to: previousVersion)
            
            if rollbackSuccess {
                // Update state to previous version
                var rolledBackState = previousVersion
                rolledBackState.previousVersion = backupState
                
                componentStates[component.identifier] = rolledBackState
                saveStates()
                
                // Record rollback event
                let event = RollbackEvent(
                    componentId: component.identifier,
                    fromVersion: currentState.version,
                    toVersion: previousVersion.version,
                    reason: "Manual rollback",
                    timestamp: Date(),
                    success: true
                )
                
                rollbackHistory.append(event)
                saveHistory()
                
                return .success(rolledBackState)
            } else {
                // Record failed rollback
                let event = RollbackEvent(
                    componentId: component.identifier,
                    fromVersion: currentState.version,
                    toVersion: previousVersion.version,
                    reason: "Manual rollback",
                    timestamp: Date(),
                    success: false
                )
                
                rollbackHistory.append(event)
                saveHistory()
                
                return .failure(.rollbackFailed)
            }
        } catch {
            return .failure(.rollbackFailed)
        }
    }
    
    /// Rollback component due to error or failure
    func rollbackComponentOnError(_ component: RollbackableComponent, error: Error) async -> RollbackResult {
        guard let currentState = componentStates[component.identifier] else {
            return .failure(.componentNotFound)
        }
        
        guard let previousVersion = currentState.previousVersion else {
            // If no previous version, disable the component
            return await disableComponent(component, reason: "Error occurred: \(error.localizedDescription)")
        }
        
        let rollbackSuccess = await component.performRollback(to: previousVersion)
        
        if rollbackSuccess {
            componentStates[component.identifier] = previousVersion
            saveStates()
            
            let event = RollbackEvent(
                componentId: component.identifier,
                fromVersion: currentState.version,
                toVersion: previousVersion.version,
                reason: "Error: \(error.localizedDescription)",
                timestamp: Date(),
                success: true
            )
            
            rollbackHistory.append(event)
            saveHistory()
            
            return .success(previousVersion)
        } else {
            // If rollback fails, disable component
            return await disableComponent(component, reason: "Rollback failed after error: \(error.localizedDescription)")
        }
    }
    
    /// Disable a component as a fallback
    func disableComponent(_ component: RollbackableComponent, reason: String) async -> RollbackResult {
        guard var currentState = componentStates[component.identifier] else {
            return .failure(.componentNotFound)
        }
        
        let disableSuccess = await component.performDisable()
        
        if disableSuccess {
            currentState.isEnabled = false
            currentState.metadata["disabledReason"] = reason
            currentState.metadata["disabledAt"] = ISO8601DateFormatter().string(from: Date())
            
            componentStates[component.identifier] = currentState
            saveStates()
            
            let event = RollbackEvent(
                componentId: component.identifier,
                fromVersion: currentState.version,
                toVersion: "disabled",
                reason: reason,
                timestamp: Date(),
                success: true
            )
            
            rollbackHistory.append(event)
            saveHistory()
            
            return .success(currentState)
        } else {
            return .failure(.disableFailed)
        }
    }
    
    /// Get rollback history for a component
    func getRollbackHistory(for component: RollbackableComponent) -> [RollbackEvent] {
        return rollbackHistory.filter { $0.componentId == component.identifier }
    }
    
    /// Get all rollback events
    func getAllRollbackHistory() -> [RollbackEvent] {
        return rollbackHistory.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Clear rollback history
    func clearHistory() {
        rollbackHistory.removeAll()
        saveHistory()
    }
    
    /// Get component state
    func getComponentState(_ component: RollbackableComponent) -> ComponentState? {
        return componentStates[component.identifier]
    }
    
    /// Update component configuration
    func updateComponentConfiguration(_ component: RollbackableComponent, configuration: [String: Any]) {
        guard var state = componentStates[component.identifier] else { return }
        
        // Save current state as previous version
        let previousState = ComponentState(
            version: state.version,
            configuration: state.configuration,
            isEnabled: state.isEnabled,
            previousVersion: state.previousVersion,
            createdAt: state.createdAt,
            metadata: state.metadata
        )
        
        // Update to new configuration
        state.configuration = configuration.mapValues { AnyCodable($0) }
        state.version = generateVersion()
        state.previousVersion = previousState
        state.metadata["lastUpdated"] = ISO8601DateFormatter().string(from: Date())
        
        componentStates[component.identifier] = state
        saveStates()
    }
    
    // MARK: - Private Methods
    
    private func loadStates() {
        guard let data = userDefaults.data(forKey: statesKey),
              let decoded = try? JSONDecoder().decode([String: ComponentState].self, from: data) else {
            return
        }
        componentStates = decoded
    }
    
    private func saveStates() {
        if let data = try? JSONEncoder().encode(componentStates) {
            userDefaults.set(data, forKey: statesKey)
        }
    }
    
    private func loadHistory() {
        guard let data = userDefaults.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([RollbackEvent].self, from: data) else {
            return
        }
        rollbackHistory = decoded
        
        // Keep only last 100 events
        if rollbackHistory.count > 100 {
            rollbackHistory = Array(rollbackHistory.suffix(100))
        }
    }
    
    private func saveHistory() {
        // Keep only last 100 events
        if rollbackHistory.count > 100 {
            rollbackHistory = Array(rollbackHistory.suffix(100))
        }
        
        if let data = try? JSONEncoder().encode(rollbackHistory) {
            userDefaults.set(data, forKey: historyKey)
        }
    }
    
    private func generateVersion() -> String {
        return "v\(Int(Date().timeIntervalSince1970))"
    }
}

// MARK: - Data Models

class ComponentState: Codable {
    var version: String
    var configuration: [String: AnyCodable]
    var isEnabled: Bool
    var previousVersion: ComponentState?
    let createdAt: Date
    var metadata: [String: String]
    
    init(version: String, configuration: [String: Any], isEnabled: Bool, previousVersion: ComponentState?, createdAt: Date, metadata: [String: String]) {
        self.version = version
        self.configuration = configuration.mapValues { AnyCodable($0) }
        self.isEnabled = isEnabled
        self.previousVersion = previousVersion
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

struct RollbackEvent: Codable, Identifiable {
    var id = UUID()
    let componentId: String
    let fromVersion: String
    let toVersion: String
    let reason: String
    let timestamp: Date
    let success: Bool
}

enum RollbackResult {
    case success(ComponentState)
    case failure(RollbackError)
}

enum RollbackError: Error, LocalizedError {
    case componentNotFound
    case noPreviousVersion
    case rollbackFailed
    case disableFailed
    
    var errorDescription: String? {
        switch self {
        case .componentNotFound:
            return "Component not found in rollback registry"
        case .noPreviousVersion:
            return "No previous version available for rollback"
        case .rollbackFailed:
            return "Failed to perform rollback operation"
        case .disableFailed:
            return "Failed to disable component"
        }
    }
}

// Helper for encoding Any values
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = "unknown"
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encode("unknown")
        }
    }
}

// MARK: - Rollbackable Component Protocol

protocol RollbackableComponent {
    var identifier: String { get }
    var displayName: String { get }
    var currentVersion: String { get }
    
    /// Perform rollback to a previous state
    func performRollback(to state: ComponentState) async -> Bool
    
    /// Disable the component
    func performDisable() async -> Bool
    
    /// Get current configuration
    func getCurrentConfiguration() -> [String: Any]
}

// MARK: - Example Implementation for Feature Flags

@MainActor
extension FeatureFlagService: RollbackableComponent {
    nonisolated var identifier: String { "feature_flag_service" }
    nonisolated var displayName: String { "Feature Flag Service" }
    nonisolated var currentVersion: String { "v1.0.0" }
    
    func performRollback(to state: ComponentState) async -> Bool {
        // Rollback feature flag configurations
        // Reset all flags to previous state
        for flag in FeatureFlag.allCases {
            disableFlag(flag)
        }
        
        // Apply previous configuration if available
        if let enabledFlags = state.configuration["enabledFlags"]?.value as? [String] {
            for flagRawValue in enabledFlags {
                if let flag = FeatureFlag(rawValue: flagRawValue) {
                    enableFlag(flag)
                }
            }
        }
        
        return true
    }
    
    func performDisable() async -> Bool {
        // Disable all feature flags
        for flag in FeatureFlag.allCases {
            disableFlag(flag)
        }
        return true
    }
    
    nonisolated func getCurrentConfiguration() -> [String: Any] {
        // Return a simplified configuration for nonisolated access
        return [
            "totalFlags": FeatureFlag.allCases.count
        ]
    }
}

// MARK: - SwiftUI Integration

struct ComponentRollbackView: View {
    @StateObject private var rollbackService = ComponentRollbackService.shared
    @State private var selectedComponent: String?
    
    var body: some View {
        NavigationView {
            List {
                Section("Rollback History") {
                    ForEach(rollbackService.getAllRollbackHistory().prefix(10), id: \.id) { event in
                        RollbackEventRow(event: event)
                    }
                }
                
                Section("Actions") {
                    Button("Clear History") {
                        rollbackService.clearHistory()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Component Rollback")
        }
    }
}

struct RollbackEventRow: View {
    let event: RollbackEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.componentId)
                    .font(.headline)
                
                Spacer()
                
                Image(systemName: event.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(event.success ? .green : .red)
            }
            
            Text("From \(event.fromVersion) to \(event.toVersion)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(event.reason)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(event.timestamp, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#if DEBUG
struct ComponentRollbackView_Previews: PreviewProvider {
    static var previews: some View {
        ComponentRollbackView()
    }
}
#endif