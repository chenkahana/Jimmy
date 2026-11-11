import Foundation

enum RequestType: String {
    case fetchEpisodes = "Fetch Episodes"
    case refreshEpisodes = "Refresh Episodes"
}

enum Priority: String {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

/// Temporary FetchEpisodesRequest stub for build compatibility
struct FetchEpisodesRequest {
    let id = UUID()
    let requestType: RequestType = .fetchEpisodes
    let priority: Priority = .medium
    let timestamp: Date = Date()
} 