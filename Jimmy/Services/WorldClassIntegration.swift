import Foundation
import SwiftUI
import OSLog

/// Integration layer to seamlessly connect the World-Class Podcast Engine with existing codebase
/// This ensures backward compatibility while providing enhanced performance
final class WorldClassIntegration: ObservableObject {
    private let logger = Logger(subsystem: "Jimmy.Integration", category: "WorldClass")
    
    // MARK: - Core Engine
    private let podcastEngine = PodcastEngine.shared
    
    // MARK: - Core Integration - No Legacy Fallbacks
    
    // MARK: - Migration State
    @Published private(set) var migrationStatus: MigrationStatus = .notStarted
    @Published private(set) var isWorldClassEnabled = true // Enable by default
    
    static let shared = WorldClassIntegration()
    
    private init() {
        setupIntegration()
    }
    
    // MARK: - Public API
    
    /// Enable world-class engine
    func enableWorldClassEngine() async {
        await MainActor.run {
            migrationStatus = .completed
        }
    }
    
    /// Fetch podcasts using world-class engine
    func fetchPodcasts(forceRefresh: Bool = false) async throws -> [Podcast] {
        do {
            let enhancedPodcasts = try await podcastEngine.fetchPodcasts(
                priority: .high,
                forceRefresh: forceRefresh
            )
            
            return enhancedPodcasts.map { $0.basePodcast }
        } catch {
            Log.data.error("WorldClass-PodcastFetch failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    /// Stream podcasts progressively for multi-threaded loading
    /// Each podcast appears in the UI as soon as it's loaded
    func streamPodcasts(
        forceRefresh: Bool = false,
        progressHandler: @escaping (Podcast, Int) -> Void
    ) async throws {
        try await podcastEngine.streamPodcasts(
            priority: .high,
            forceRefresh: forceRefresh,
            progressHandler: progressHandler
        )
    }
    
    /// Stream podcasts with true non-blocking progressive loading - NEVER blocks UI
    func streamPodcastsNonBlocking(
        forceRefresh: Bool = false,
        progressHandler: @escaping (Podcast, Int) async -> Void
    ) async {
        await podcastEngine.streamPodcastsNonBlocking(
            priority: .high,
            forceRefresh: forceRefresh,
            progressHandler: progressHandler
        )
    }
    
    /// Fetch episodes using world-class engine
    func fetchEpisodes(
        for podcast: Podcast,
        progressHandler: ((Episode, Int) -> Void)? = nil
    ) async throws -> [Episode] {
        do {
            let enhancedPodcast = EnhancedPodcast(
                base: podcast,
                latestEpisodeDate: podcast.lastEpisodeDate,
                freshnessScore: 0.8,
                fetchPriority: .normal,
                lastSuccessfulFetch: Date(),
                errorCount: 0
            )
            
            return try await podcastEngine.fetchEpisodes(
                for: enhancedPodcast,
                priority: .normal,
                progressHandler: progressHandler
            )
        } catch {
            Log.data.error("WorldClass-EpisodeFetch failed for \(podcast.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    /// Get sorted podcasts using world-class engine
    func getSortedPodcasts() async -> [Podcast] {
        let enhancedPodcasts = await podcastEngine.getSortedPodcasts(
            sortType: .latestEpisode
        )
        
        return enhancedPodcasts.map { $0.basePodcast }
    }
    
    /// Subscribe to new podcast using world-class engine
    func subscribe(to feedURL: URL) async throws -> (Podcast, [Episode]) {
        do {
            let (enhancedPodcast, episodes) = try await podcastEngine.subscribe(to: feedURL)
            
            return (enhancedPodcast.basePodcast, episodes)
        } catch {
            Log.data.error("WorldClass-Subscribe failed for \(feedURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    /// Get performance metrics
    func getPerformanceMetrics() -> EnginePerformanceMetrics {
        return podcastEngine.performanceMetrics
    }
    
    /// Get engine status
    func getEngineStatus() -> EngineStatus {
        return podcastEngine.engineStatus
    }
    
    // MARK: - Private Methods
    
    private func setupIntegration() {
        // World-Class Integration ready - no setup needed
    }
    

}

// MARK: - Migration Status

enum MigrationStatus: Equatable {
    case notStarted
    case migrating
    case completed
    case failed(Error)
    
    static func == (lhs: MigrationStatus, rhs: MigrationStatus) -> Bool {
        switch (lhs, rhs) {
        case (.notStarted, .notStarted),
             (.migrating, .migrating),
             (.completed, .completed):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

// MARK: - Integration Errors

enum IntegrationError: Error, LocalizedError {
    case noExistingData
    case corruptedData(UUID)
    case engineNotReady
    case functionalityTestFailed(String)
    case migrationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noExistingData:
            return "No existing podcast data found"
        case .corruptedData(let id):
            return "Corrupted podcast data for ID: \(id)"
        case .engineNotReady:
            return "World-Class engine failed to initialize"
        case .functionalityTestFailed(let reason):
            return "Functionality test failed: \(reason)"
        case .migrationFailed(let reason):
            return "Migration failed: \(reason)"
        }
    }
}

// MARK: - SwiftUI Integration

extension WorldClassIntegration {
    /// SwiftUI view modifier to enable world-class features
    func worldClassModifier() -> some ViewModifier {
        return WorldClassViewModifier(integration: self)
    }
}

private struct WorldClassViewModifier: ViewModifier {
    let integration: WorldClassIntegration
    
    func body(content: Content) -> some View {
        content
            .environmentObject(integration)
            .onAppear {
                Task {
                    await integration.enableWorldClassEngine()
                }
            }
    }
}

// MARK: - Performance Dashboard View

struct WorldClassPerformanceDashboard: View {
    @ObservedObject private var integration = WorldClassIntegration.shared
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "speedometer")
                    .foregroundColor(.blue)
                Text("World-Class Performance")
                    .font(.headline)
                
                Spacer()
                
                Button("Details") {
                    showingDetails = true
                }
            }
            
            if integration.isWorldClassEnabled {
                PerformanceMetricsView(metrics: integration.getPerformanceMetrics())
            } else {
                Text("World-Class Engine not enabled")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showingDetails) {
            DetailedPerformanceView()
        }
    }
}

private struct PerformanceMetricsView: View {
    let metrics: EnginePerformanceMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetricRow(title: "Avg Fetch Time", value: String(format: "%.2fms", metrics.averageFetchTime * 1000))
            MetricRow(title: "Cache Hit Rate", value: String(format: "%.1f%%", metrics.cacheHitRate * 100))
            MetricRow(title: "Error Rate", value: String(format: "%.1f%%", metrics.errorRate * 100))
            MetricRow(title: "Throughput", value: String(format: "%.1f ops/s", metrics.throughput))
        }
    }
}

private struct MetricRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

private struct DetailedPerformanceView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Detailed Performance Metrics")
                    .font(.title2)
                
                // Add detailed metrics here
                
                Spacer()
            }
            .navigationTitle("Performance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
