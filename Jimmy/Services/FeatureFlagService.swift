import Foundation
import SwiftUI

// MARK: - Feature Flag Definitions
enum FeatureFlag: String, CaseIterable, Codable {
    // Performance Foundation Features
    case instantResponseEngine = "instant_response_engine"
    case realTimePerformanceMonitor = "real_time_performance_monitor"
    case quantumSortingEngine = "quantum_sorting_engine"
    case bulletproofErrorHandler = "bulletproof_error_handler"
    
    // Liquid Glass Design Features
    case liquidGlassTabBar = "liquid_glass_tab_bar"
    case liquidGlassEffects = "liquid_glass_effects"
    case liquidAnimations = "liquid_animations"
    case glassAccessibility = "glass_accessibility"
    
    // Featured Tab Performance Features
    case featuredTabManager = "featured_tab_manager"
    case liquidSkeletonViews = "liquid_skeleton_views"
    case intelligentCacheEngine = "intelligent_cache_engine"
    case progressiveLoading = "progressive_loading"
    
    // Library Optimization Features
    case optimizedLibrarySorting = "optimized_library_sorting"
    case sortConfigurationPersistence = "sort_configuration_persistence"
    case incrementalSortUpdates = "incremental_sort_updates"
    case sortTransitionAnimations = "sort_transition_animations"
    
    // Error Recovery Features
    case errorPreventionSystem = "error_prevention_system"
    case fallbackDataProvider = "fallback_data_provider"
    case recoveryStrategyManager = "recovery_strategy_manager"
    case errorAnalytics = "error_analytics"
    
    // Performance Monitoring Features
    case performanceDashboard = "performance_dashboard"
    case automaticOptimization = "automatic_optimization"
    case regressionDetection = "regression_detection"
    case performanceAnalytics = "performance_analytics"
    
    var displayName: String {
        switch self {
        case .instantResponseEngine: return "Instant Response Engine"
        case .realTimePerformanceMonitor: return "Real-Time Performance Monitor"
        case .quantumSortingEngine: return "Fast Sorting Engine"
        case .bulletproofErrorHandler: return "Resilient Error Handling"
        case .liquidGlassTabBar: return "Liquid Glass Tab Bar"
        case .liquidGlassEffects: return "Liquid Glass Effects"
        case .liquidAnimations: return "Liquid Animations"
        case .glassAccessibility: return "Glass Accessibility"
        case .featuredTabManager: return "Featured Tab Manager"
        case .liquidSkeletonViews: return "Liquid Skeleton Views"
        case .intelligentCacheEngine: return "Intelligent Cache Engine"
        case .progressiveLoading: return "Progressive Loading"
        case .optimizedLibrarySorting: return "Optimized Library Sorting"
        case .sortConfigurationPersistence: return "Sort Configuration Persistence"
        case .incrementalSortUpdates: return "Incremental Sort Updates"
        case .sortTransitionAnimations: return "Sort Transition Animations"
        case .errorPreventionSystem: return "Error Prevention System"
        case .fallbackDataProvider: return "Fallback Data Provider"
        case .recoveryStrategyManager: return "Recovery Strategy Manager"
        case .errorAnalytics: return "Error Analytics"
        case .performanceDashboard: return "Performance Dashboard"
        case .automaticOptimization: return "Automatic Optimization"
        case .regressionDetection: return "Regression Detection"
        case .performanceAnalytics: return "Performance Analytics"
        }
    }
    
    var description: String {
        switch self {
        case .instantResponseEngine: return "Sub-16ms response guarantee for all UI interactions"
        case .realTimePerformanceMonitor: return "Continuous performance monitoring with metrics dashboard"
        case .quantumSortingEngine: return "Optimized library sorting with a <100ms target"
        case .bulletproofErrorHandler: return "Robust error handling with automatic recovery"
        case .liquidGlassTabBar: return "Modern translucent tab bar with liquid glass effects"
        case .liquidGlassEffects: return "Dynamic blur and transparency effects throughout the app"
        case .liquidAnimations: return "Smooth liquid-style animations optimized for ProMotion"
        case .glassAccessibility: return "Accessibility support for glass effects and animations"
        case .featuredTabManager: return "Progressive loading system for featured content"
        case .liquidSkeletonViews: return "Beautiful skeleton screens with shimmer animations"
        case .intelligentCacheEngine: return "Three-tier caching with predictive preloading"
        case .progressiveLoading: return "Incremental content loading with priority queues"
        case .optimizedLibrarySorting: return "Instant library sorting with cached results"
        case .sortConfigurationPersistence: return "Persistent sort preferences across app sessions"
        case .incrementalSortUpdates: return "Efficient sorting updates for large datasets"
        case .sortTransitionAnimations: return "Smooth animations for sort state changes"
        case .errorPreventionSystem: return "Proactive error detection and prevention"
        case .fallbackDataProvider: return "Graceful degradation with offline functionality"
        case .recoveryStrategyManager: return "Context-aware error recovery strategies"
        case .errorAnalytics: return "Comprehensive error tracking and analytics"
        case .performanceDashboard: return "Real-time performance metrics and optimization suggestions"
        case .automaticOptimization: return "Automatic performance optimization based on conditions"
        case .regressionDetection: return "Automated detection of performance regressions"
        case .performanceAnalytics: return "Advanced performance analytics and insights"
        }
    }
    
    var category: FeatureFlagCategory {
        switch self {
        case .instantResponseEngine, .realTimePerformanceMonitor, .quantumSortingEngine, .bulletproofErrorHandler:
            return .performance
        case .liquidGlassTabBar, .liquidGlassEffects, .liquidAnimations, .glassAccessibility:
            return .design
        case .featuredTabManager, .liquidSkeletonViews, .intelligentCacheEngine, .progressiveLoading:
            return .featuredTab
        case .optimizedLibrarySorting, .sortConfigurationPersistence, .incrementalSortUpdates, .sortTransitionAnimations:
            return .library
        case .errorPreventionSystem, .fallbackDataProvider, .recoveryStrategyManager, .errorAnalytics:
            return .reliability
        case .performanceDashboard, .automaticOptimization, .regressionDetection, .performanceAnalytics:
            return .monitoring
        }
    }
}

enum FeatureFlagCategory: String, CaseIterable, Codable {
    case performance = "Performance"
    case design = "Design"
    case featuredTab = "Featured Tab"
    case library = "Library"
    case reliability = "Reliability"
    case monitoring = "Monitoring"
}

// MARK: - Feature Flag Configuration
struct FeatureFlagConfiguration: Codable {
    let flag: FeatureFlag
    let isEnabled: Bool
    let rolloutPercentage: Double // 0.0 to 1.0
    let enabledForBetaUsers: Bool
    let enabledForDevelopment: Bool
    let minimumAppVersion: String?
    let expirationDate: Date?
    let abTestGroup: String?
    
    init(
        flag: FeatureFlag,
        isEnabled: Bool = false,
        rolloutPercentage: Double = 0.0,
        enabledForBetaUsers: Bool = false,
        enabledForDevelopment: Bool = true,
        minimumAppVersion: String? = nil,
        expirationDate: Date? = nil,
        abTestGroup: String? = nil
    ) {
        self.flag = flag
        self.isEnabled = isEnabled
        self.rolloutPercentage = rolloutPercentage
        self.enabledForBetaUsers = enabledForBetaUsers
        self.enabledForDevelopment = enabledForDevelopment
        self.minimumAppVersion = minimumAppVersion
        self.expirationDate = expirationDate
        self.abTestGroup = abTestGroup
    }
}

// MARK: - Feature Flag Service
@MainActor
class FeatureFlagService: ObservableObject {
    static let shared = FeatureFlagService()
    
    @Published private var configurations: [FeatureFlag: FeatureFlagConfiguration] = [:]
    @Published private var userID: String = ""
    
    var userIDForTesting: String {
        return userID
    }
    @Published private var isBetaUser: Bool = false
    @Published private var isDevelopmentBuild: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let configurationKey = "FeatureFlagConfigurations"
    private let userIDKey = "FeatureFlagUserID"
    
    init() {
        loadConfigurations()
        setupUserID()
        detectBuildType()
        initializeDefaultConfigurations()
    }
    
    // MARK: - Public Interface
    
    /// Check if a feature flag is enabled for the current user
    func isEnabled(_ flag: FeatureFlag) -> Bool {
        guard let config = configurations[flag] else {
            return false
        }
        
        // Check expiration
        if let expirationDate = config.expirationDate, Date() > expirationDate {
            return false
        }
        
        // Development build override
        if isDevelopmentBuild && config.enabledForDevelopment {
            return true
        }
        
        // Beta user override
        if isBetaUser && config.enabledForBetaUsers {
            return true
        }
        
        // Global enable/disable
        if !config.isEnabled {
            return false
        }
        
        // Rollout percentage check
        if config.rolloutPercentage >= 1.0 {
            return true
        }
        
        if config.rolloutPercentage <= 0.0 {
            return false
        }
        
        // Consistent user-based rollout
        let userHash = abs(userID.hashValue) % 100
        return Double(userHash) < (config.rolloutPercentage * 100)
    }
    
    /// Update feature flag configuration
    func updateConfiguration(_ config: FeatureFlagConfiguration) {
        configurations[config.flag] = config
        saveConfigurations()
    }
    
    /// Enable a feature flag with optional rollout percentage
    func enableFlag(_ flag: FeatureFlag, rolloutPercentage: Double = 1.0) {
        var config = configurations[flag] ?? FeatureFlagConfiguration(flag: flag)
        config = FeatureFlagConfiguration(
            flag: flag,
            isEnabled: true,
            rolloutPercentage: rolloutPercentage,
            enabledForBetaUsers: true,
            enabledForDevelopment: true,
            minimumAppVersion: config.minimumAppVersion,
            expirationDate: config.expirationDate,
            abTestGroup: config.abTestGroup
        )
        updateConfiguration(config)
    }
    
    /// Disable a feature flag
    func disableFlag(_ flag: FeatureFlag) {
        var config = configurations[flag] ?? FeatureFlagConfiguration(flag: flag)
        config = FeatureFlagConfiguration(
            flag: flag,
            isEnabled: false,
            rolloutPercentage: 0.0,
            enabledForBetaUsers: false,
            enabledForDevelopment: false,
            minimumAppVersion: config.minimumAppVersion,
            expirationDate: config.expirationDate,
            abTestGroup: config.abTestGroup
        )
        updateConfiguration(config)
    }

    /// Toggle a feature flag between enabled and disabled states.
    func toggle(_ flag: FeatureFlag) {
        if isEnabled(flag) {
            disableFlag(flag)
        } else {
            enableFlag(flag)
        }
    }
    
    /// Get all configurations grouped by category
    func getConfigurationsByCategory() -> [FeatureFlagCategory: [FeatureFlagConfiguration]] {
        var result: [FeatureFlagCategory: [FeatureFlagConfiguration]] = [:]
        
        for category in FeatureFlagCategory.allCases {
            result[category] = []
        }
        
        for flag in FeatureFlag.allCases {
            let config = configurations[flag] ?? FeatureFlagConfiguration(flag: flag)
            result[flag.category]?.append(config)
        }
        
        return result
    }
    
    /// Reset all flags to default state
    func resetToDefaults() {
        configurations.removeAll()
        initializeDefaultConfigurations()
        saveConfigurations()
    }
    
    // MARK: - A/B Testing Support
    
    /// Get A/B test group for a feature
    func getABTestGroup(for flag: FeatureFlag) -> String? {
        return configurations[flag]?.abTestGroup
    }
    
    /// Set A/B test group for a feature
    func setABTestGroup(_ group: String, for flag: FeatureFlag) {
        guard var config = configurations[flag] else { return }
        config = FeatureFlagConfiguration(
            flag: flag,
            isEnabled: config.isEnabled,
            rolloutPercentage: config.rolloutPercentage,
            enabledForBetaUsers: config.enabledForBetaUsers,
            enabledForDevelopment: config.enabledForDevelopment,
            minimumAppVersion: config.minimumAppVersion,
            expirationDate: config.expirationDate,
            abTestGroup: group
        )
        updateConfiguration(config)
    }
    
    // MARK: - Private Methods
    
    private func loadConfigurations() {
        guard let data = userDefaults.data(forKey: configurationKey),
              let decoded = try? JSONDecoder().decode([String: FeatureFlagConfiguration].self, from: data) else {
            return
        }
        
        configurations = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            guard let flag = FeatureFlag(rawValue: key) else { return nil }
            return (flag, value)
        })
    }
    
    private func saveConfigurations() {
        let encoded = Dictionary(uniqueKeysWithValues: configurations.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encoded) {
            userDefaults.set(data, forKey: configurationKey)
        }
    }
    
    private func setupUserID() {
        if let existingID = userDefaults.string(forKey: userIDKey) {
            userID = existingID
        } else {
            userID = UUID().uuidString
            userDefaults.set(userID, forKey: userIDKey)
        }
    }
    
    private func detectBuildType() {
        #if DEBUG
        isDevelopmentBuild = true
        #else
        isDevelopmentBuild = false
        #endif
        
        // Detect beta users (simplified - in real app, this would check TestFlight or other indicators)
        #if DEBUG
        isBetaUser = true
        #else
        isBetaUser = Bundle.main.bundleURL.pathExtension == "appex"
        #endif
    }
    
    private func initializeDefaultConfigurations() {
        for flag in FeatureFlag.allCases {
            if configurations[flag] == nil {
                // Default configuration - disabled for production, enabled for development
                configurations[flag] = FeatureFlagConfiguration(
                    flag: flag,
                    isEnabled: false,
                    rolloutPercentage: 0.0,
                    enabledForBetaUsers: true,
                    enabledForDevelopment: true
                )
            }
        }
        saveConfigurations()
    }
}

// MARK: - SwiftUI Integration
extension View {
    /// Conditionally show content based on feature flag
    func featureFlag(_ flag: FeatureFlag, @ViewBuilder content: @escaping () -> some View) -> some View {
        FeatureFlagConditionalView(flag: flag, content: content)
    }
    
    /// Show different content based on feature flag state
    func featureFlag<EnabledContent: View, DisabledContent: View>(
        _ flag: FeatureFlag,
        @ViewBuilder enabled: @escaping () -> EnabledContent,
        @ViewBuilder disabled: @escaping () -> DisabledContent
    ) -> some View {
        FeatureFlagBranchView(flag: flag, enabled: enabled, disabled: disabled)
    }
}

struct FeatureFlagConditionalView<Content: View>: View {
    let flag: FeatureFlag
    let content: () -> Content
    @StateObject private var featureFlagService = FeatureFlagService.shared
    
    var body: some View {
        Group {
            if featureFlagService.isEnabled(flag) {
                content()
            }
        }
    }
}

struct FeatureFlagBranchView<EnabledContent: View, DisabledContent: View>: View {
    let flag: FeatureFlag
    let enabled: () -> EnabledContent
    let disabled: () -> DisabledContent
    @StateObject private var featureFlagService = FeatureFlagService.shared
    
    var body: some View {
        Group {
            if featureFlagService.isEnabled(flag) {
                enabled()
            } else {
                disabled()
            }
        }
    }
}

// MARK: - Property Wrapper for Easy Access
@propertyWrapper
struct FeatureEnabled {
    let flag: FeatureFlag
    
    var wrappedValue: Bool {
        // Simplified synchronous access for property wrapper
        // In production, you'd want to use @StateObject with the service
        return false // Default to disabled for property wrapper
    }
}

// MARK: - Usage Examples
/*
 
 // In a view:
 struct MyView: View {
     @FeatureEnabled(.liquidGlassTabBar) var isLiquidGlassEnabled
     
     var body: some View {
         VStack {
             Text("Hello World")
             
             // Method 1: Property wrapper
             if isLiquidGlassEnabled {
                 LiquidGlassTabBar()
             } else {
                 StandardTabBar()
             }
             
             // Method 2: View modifier
             Text("Feature content")
                 .featureFlag(.liquidGlassEffects) {
                     Text("This shows only if liquid glass effects are enabled")
                 }
             
             // Method 3: Conditional content
             Text("Conditional feature")
                 .featureFlag(.instantResponseEngine,
                     enabled: { Text("Fast response enabled!") },
                     disabled: { Text("Standard response") }
                 )
         }
     }
 }
 
 // In a service:
 class MyService {
     func performAction() {
         if FeatureFlagService.shared.isEnabled(.quantumSortingEngine) {
             // Use new quantum sorting
         } else {
             // Use legacy sorting
         }
     }
 }
 
 */
