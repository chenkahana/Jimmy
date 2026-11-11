import Foundation
import Combine
import os

/// Centralized subscription state manager that coordinates subscription states across all UI components
@MainActor
final class SubscriptionStateManager: ObservableObject {
    static let shared = SubscriptionStateManager()
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "SubscriptionStateManager")
    
    // MARK: - Published Properties
    @Published private(set) var subscriptionStates: [URL: Bool] = [:]
    @Published private(set) var processingStates: [URL: Bool] = [:]
    @Published private(set) var errorStates: [URL: SubscriptionError?] = [:]
    
    // MARK: - Private Properties
    private let subscriptionRepository: SubscriptionRepositoryProtocol
    private let podcastRepository: PodcastRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // Performance optimization properties
    private var lastRefreshTime: Date = Date.distantPast
    private let refreshCooldownInterval: TimeInterval = 5.0 // Minimum 5 seconds between refreshes
    private var pendingRefreshTask: Task<Void, Never>?
    
    // MARK: - Initialization
    private init(
        subscriptionRepository: SubscriptionRepositoryProtocol = DIContainer.shared.subscriptionRepository,
        podcastRepository: PodcastRepositoryProtocol = DIContainer.shared.podcastRepository
    ) {
        self.subscriptionRepository = subscriptionRepository
        self.podcastRepository = podcastRepository
        setupSubscriptionChangeListener()
        
        // Load initial subscription states
        Task {
            await refreshSubscriptionStates()
        }
    }
    
    deinit {
        // Cancel any pending tasks to prevent memory leaks
        pendingRefreshTask?.cancel()
        cancellables.removeAll()
    }
    
    // MARK: - Public Methods
    
    /// Subscribe to a podcast from search result
    func subscribe(to result: PodcastSearchResult) async throws {
        let feedURL = result.feedURL
        
        // Check if already subscribed
        if subscriptionStates[feedURL] == true {
            throw SubscriptionError.alreadySubscribed
        }
        
        // Set processing state
        processingStates[feedURL] = true
        errorStates[feedURL] = nil
        
        do {
            // Add timeout to prevent hanging operations
            try await withTimeout(seconds: 30) {
                // Fetch podcast with episodes and save to database
                let (podcast, _) = try await self.podcastRepository.fetchPodcastWithEpisodes(from: feedURL)
                
                // CRITICAL: Must call addSubscription to trigger subscriptionChangesPublisher
                // This ensures all downstream consumers (SubscriptionViewModel, views, etc.) get notified
                try await self.subscriptionRepository.addSubscription(podcast)
            }
            
            // Update local state
            subscriptionStates[feedURL] = true
            processingStates[feedURL] = false
            
            Self.logger.info("SubscriptionStateManager: Successfully subscribed to \(result.title)")
            
        } catch {
            // Handle error
            processingStates[feedURL] = false
            let subscriptionError = mapError(error)
            errorStates[feedURL] = subscriptionError
            
            Self.logger.error("SubscriptionStateManager: Failed to subscribe to \(result.title): \(error)")
            throw subscriptionError
        }
    }
    
    /// Subscribe to a podcast from existing podcast object
    func subscribe(to podcast: Podcast) async throws {
        let feedURL = podcast.feedURL
        
        // Check if already subscribed
        if subscriptionStates[feedURL] == true {
            throw SubscriptionError.alreadySubscribed
        }
        
        // Set processing state
        processingStates[feedURL] = true
        errorStates[feedURL] = nil
        
        do {
            // Add timeout to prevent hanging operations
            try await withTimeout(seconds: 15) {
                try await self.subscriptionRepository.addSubscription(podcast)
            }
            
            // Update local state
            subscriptionStates[feedURL] = true
            processingStates[feedURL] = false
            
            Self.logger.info("SubscriptionStateManager: Successfully subscribed to \(podcast.title)")
            
        } catch {
            // Handle error
            processingStates[feedURL] = false
            let subscriptionError = mapError(error)
            errorStates[feedURL] = subscriptionError
            
            Self.logger.error("SubscriptionStateManager: Failed to subscribe to \(podcast.title): \(error)")
            throw subscriptionError
        }
    }
    
    /// Unsubscribe from a podcast
    func unsubscribe(from feedURL: URL) async throws {
        // Check if not subscribed
        if subscriptionStates[feedURL] != true {
            throw SubscriptionError.notSubscribed
        }
        
        // Set processing state
        processingStates[feedURL] = true
        errorStates[feedURL] = nil
        
        do {
            // Find the podcast by feedURL and remove it
            let subscriptions = try await subscriptionRepository.fetchSubscriptions(ignoreCache: false)
            guard let podcast = subscriptions.first(where: { $0.feedURL == feedURL }) else {
                throw SubscriptionError.notFound
            }
            
            try await subscriptionRepository.removeSubscription(id: podcast.id)
            
            // Update local state
            subscriptionStates[feedURL] = false
            processingStates[feedURL] = false
            
            Self.logger.info("SubscriptionStateManager: Successfully unsubscribed from \(podcast.title)")
            
        } catch {
            // Handle error
            processingStates[feedURL] = false
            let subscriptionError = mapError(error)
            errorStates[feedURL] = subscriptionError
            
            Self.logger.error("SubscriptionStateManager: Failed to unsubscribe from feedURL: \(error)")
            throw subscriptionError
        }
    }
    
    /// Unsubscribe from a podcast by ID
    func unsubscribe(podcastID: UUID) async throws {
        // Find the podcast to get its feedURL
        let subscriptions = try await subscriptionRepository.fetchSubscriptions(ignoreCache: false)
        guard let podcast = subscriptions.first(where: { $0.id == podcastID }) else {
            throw SubscriptionError.notFound
        }
        
        let feedURL = podcast.feedURL
        
        // Set processing state
        processingStates[feedURL] = true
        errorStates[feedURL] = nil
        
        do {
            try await subscriptionRepository.removeSubscription(id: podcastID)
            
            // Update local state
            subscriptionStates[feedURL] = false
            processingStates[feedURL] = false
            
            Self.logger.info("SubscriptionStateManager: Successfully unsubscribed from \(podcast.title)")
            
        } catch {
            // Handle error
            processingStates[feedURL] = false
            let subscriptionError = mapError(error)
            errorStates[feedURL] = subscriptionError
            
            Self.logger.error("SubscriptionStateManager: Failed to unsubscribe podcast \(podcastID): \(error)")
            throw subscriptionError
        }
    }
    
    /// Check if subscribed to a podcast
    func isSubscribed(to feedURL: URL) -> Bool {
        return subscriptionStates[feedURL] == true
    }
    
    /// Check if subscribed to a podcast by search result
    func isSubscribed(to result: PodcastSearchResult) -> Bool {
        return isSubscribed(to: result.feedURL)
    }
    
    /// Check if subscription operation is in progress
    func isProcessing(feedURL: URL) -> Bool {
        return processingStates[feedURL] == true
    }
    
    /// Get error state for a feed URL
    func getError(for feedURL: URL) -> SubscriptionError? {
        return errorStates[feedURL] ?? nil
    }
    
    /// Clear error state for a feed URL
    func clearError(for feedURL: URL) {
        errorStates[feedURL] = nil
    }
    
    /// Refresh all subscription states from database with debouncing
    func refreshSubscriptionStates() async {
        // Cancel any pending refresh task
        pendingRefreshTask?.cancel()
        
        // Check cooldown to prevent excessive refreshes
        let now = Date()
        if now.timeIntervalSince(lastRefreshTime) < refreshCooldownInterval {
            // Schedule a delayed refresh instead
            pendingRefreshTask = Task {
                let remainingCooldown = refreshCooldownInterval - now.timeIntervalSince(lastRefreshTime)
                try? await Task.sleep(nanoseconds: UInt64(remainingCooldown * 1_000_000_000))
                
                if !Task.isCancelled {
                    await performRefresh()
                }
            }
            return
        }
        
        await performRefresh()
    }
    
    /// Perform the actual refresh operation
    private func performRefresh() async {
        do {
            let subscriptions = try await subscriptionRepository.fetchSubscriptions(ignoreCache: false)
            let newStates = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.feedURL, true) })
            
            // Update subscription states
            subscriptionStates = newStates
            
            // Clear processing states for subscribed podcasts
            for feedURL in newStates.keys {
                processingStates[feedURL] = false
            }
            
            lastRefreshTime = Date()
            
            Self.logger.info("SubscriptionStateManager: Refreshed \(subscriptions.count) subscription states")
            
        } catch {
            Self.logger.error("SubscriptionStateManager: Failed to refresh subscription states: \(error)")
        }
    }
    
    /// Get subscription states for multiple feed URLs (batch operation)
    func getSubscriptionStates(for feedURLs: [URL]) -> [URL: Bool] {
        return Dictionary(uniqueKeysWithValues: feedURLs.map { ($0, isSubscribed(to: $0)) })
    }
    
    // MARK: - Private Methods
    
    private func setupSubscriptionChangeListener() {
        subscriptionRepository.subscriptionChangesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] podcasts in
                self?.handleSubscriptionChanges(podcasts)
            }
            .store(in: &cancellables)
    }
    
    private func handleSubscriptionChanges(_ podcasts: [Podcast]) {
        // Batch update subscription states for better performance
        let newStates = Dictionary(uniqueKeysWithValues: podcasts.map { ($0.feedURL, true) })
        
        // Find removed subscriptions efficiently
        let currentFeedURLs = Set(podcasts.map { $0.feedURL })
        let previousFeedURLs = Set(subscriptionStates.keys)
        let removedFeedURLs = previousFeedURLs.subtracting(currentFeedURLs)
        
        // Batch update states to minimize UI updates
        var updatedStates = newStates
        var updatedProcessingStates = processingStates
        
        // Mark removed subscriptions as false
        for feedURL in removedFeedURLs {
            updatedStates[feedURL] = false
            updatedProcessingStates[feedURL] = false
        }
        
        // Apply all changes at once
        subscriptionStates = updatedStates
        processingStates = updatedProcessingStates
        
        Self.logger.info("SubscriptionStateManager: Updated states for \(podcasts.count) subscriptions")
    }
    
    private func mapError(_ error: Error) -> SubscriptionError {
        if let subscriptionError = error as? SubscriptionError {
            return subscriptionError
        }
        
        // Map common errors to subscription errors
        if error.localizedDescription.contains("network") || error.localizedDescription.contains("internet") {
            return .networkError(error.localizedDescription)
        }
        
        if error.localizedDescription.contains("database") || error.localizedDescription.contains("save") {
            return .databaseError(error.localizedDescription)
        }
        
        if error.localizedDescription.contains("timeout") {
            return .timeout
        }
        
        if error.localizedDescription.contains("not found") {
            return .notFound
        }
        
        // Default to generic error
        return .unknownError(error.localizedDescription)
    }
    
    /// Add timeout to async operations to prevent hanging
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SubscriptionError.timeout
            }
            
            guard let result = try await group.next() else {
                throw SubscriptionError.timeout
            }
            
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Subscription Error Types

enum SubscriptionError: Error, LocalizedError, Equatable {
    case networkError(String)
    case databaseError(String)
    case alreadySubscribed
    case notSubscribed
    case notFound
    case timeout
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network error. Please check your connection and try again."
        case .databaseError:
            return "Unable to save subscription. Please try again."
        case .alreadySubscribed:
            return "You're already subscribed to this podcast."
        case .notSubscribed:
            return "You're not subscribed to this podcast."
        case .notFound:
            return "Podcast not found. Please try again."
        case .timeout:
            return "Operation timed out. Please try again."
        case .unknownError(let message):
            return "An error occurred: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Check your internet connection and try again."
        case .databaseError:
            return "Try restarting the app or contact support if the problem persists."
        case .alreadySubscribed:
            return "You can find this podcast in your library."
        case .notSubscribed:
            return "Subscribe to this podcast first."
        case .notFound:
            return "Make sure the podcast URL is correct."
        case .timeout:
            return "Try again with a better internet connection."
        case .unknownError:
            return "Try again or contact support if the problem persists."
        }
    }
}

// MARK: - Subscription Error Handler

struct SubscriptionErrorHandler {
    static func handle(_ error: SubscriptionError, for podcastTitle: String) -> String {
        switch error {
        case .networkError:
            return "Network error while subscribing to \(podcastTitle). Please check your connection and try again."
        case .databaseError:
            return "Unable to save subscription to \(podcastTitle). Please try again."
        case .alreadySubscribed:
            return "You're already subscribed to \(podcastTitle)."
        case .notSubscribed:
            return "You're not subscribed to \(podcastTitle)."
        case .notFound:
            return "\(podcastTitle) not found. Please try again."
        case .timeout:
            return "Subscription to \(podcastTitle) timed out. Please try again."
        case .unknownError(let message):
            return "Failed to subscribe to \(podcastTitle): \(message)"
        }
    }
    
    static func handleUnsubscribe(_ error: SubscriptionError, for podcastTitle: String) -> String {
        switch error {
        case .networkError:
            return "Network error while unsubscribing from \(podcastTitle). Please check your connection and try again."
        case .databaseError:
            return "Unable to remove subscription to \(podcastTitle). Please try again."
        case .alreadySubscribed:
            return "You're still subscribed to \(podcastTitle)."
        case .notSubscribed:
            return "You're not subscribed to \(podcastTitle)."
        case .notFound:
            return "\(podcastTitle) not found in your subscriptions."
        case .timeout:
            return "Unsubscribe from \(podcastTitle) timed out. Please try again."
        case .unknownError(let message):
            return "Failed to unsubscribe from \(podcastTitle): \(message)"
        }
    }
}