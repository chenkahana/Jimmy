import Foundation

/// Service that provides streaming episode loading capabilities.
/// This solves timeout and UI blocking issues by:
/// 1. Using AsyncSequence to stream episodes as they're parsed
/// 2. Running all network and parsing operations off the main thread
/// 3. Supporting cancellation and timeout handling
/// 4. Providing progressive UI updates
final class StreamingEpisodeService {
    static let shared = StreamingEpisodeService()
    
    private let streamingParser = StreamingRSSParser()
    
    private init() {}
    
    /// Streams episodes from a podcast's RSS feed URL
    /// - Parameters:
    ///   - feedURL: The RSS feed URL to stream from
    ///   - podcastID: ID of the podcast these episodes belong to
    ///   - timeout: Request timeout (default: 60 seconds)
    /// - Returns: AsyncSequence that emits episodes as they're parsed
    func streamEpisodes(from feedURL: URL, podcastID: UUID, timeout: TimeInterval = 60.0) -> StreamingEpisodeSequence {
        return streamingParser.streamEpisodes(from: feedURL, podcastID: podcastID, timeout: timeout)
    }
    
    /// Convenience method to collect all episodes from a stream into an array
    /// This is useful for compatibility with existing code that expects [Episode]
    /// - Parameters:
    ///   - feedURL: The RSS feed URL to fetch from
    ///   - podcastID: ID of the podcast these episodes belong to
    ///   - timeout: Request timeout (default: 60 seconds)
    ///   - progressHandler: Optional closure called for each episode as it's parsed
    /// - Returns: Array of all episodes and podcast metadata
    func fetchAllEpisodes(
        from feedURL: URL, 
        podcastID: UUID, 
        timeout: TimeInterval = 60.0,
        progressHandler: ((Episode, Int) -> Void)? = nil
    ) async throws -> (episodes: [Episode], metadata: PodcastMetadata?) {
        
        var episodes: [Episode] = []
        var metadata: PodcastMetadata?
        var episodeCount = 0
        
        // Stream episodes and collect them
        for try await result in streamEpisodes(from: feedURL, podcastID: podcastID, timeout: timeout) {
            // PERF-04: Check for cancellation in long-running loop
            try Task.checkCancellation()
            
            switch result {
            case .episode(let episode):
                episodes.append(episode)
                episodeCount += 1
                // Call progress handler on main thread for UI updates
                if let progressHandler = progressHandler {
                    await MainActor.run {
                        progressHandler(episode, episodeCount)
                    }
                }
                
            case .metadata(let podcastMetadata):
                metadata = podcastMetadata
                
            case .error(let error):
                throw error
                
            case .completed(let totalEpisodes):
                break
            }
        }
        
        // Sort episodes by published date (newest first)
        episodes.sort { ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) }
        
        return (episodes: episodes, metadata: metadata)
    }
    
    /// Streams episodes with built-in retry logic and error handling
    /// - Parameters:
    ///   - feedURL: The RSS feed URL to stream from
    ///   - podcastID: ID of the podcast these episodes belong to
    ///   - maxRetries: Maximum number of retry attempts (default: 3)
    ///   - timeout: Request timeout per attempt (default: 60 seconds)
    /// - Returns: AsyncSequence that emits episodes with retry logic
    func streamEpisodesWithRetry(
        from feedURL: URL, 
        podcastID: UUID, 
        maxRetries: Int = 3,
        timeout: TimeInterval = 60.0
    ) -> AsyncThrowingStream<StreamingEpisodeResult, Error> {
        
        return AsyncThrowingStream { continuation in
            Task {
                var attempt = 0
                var lastError: Error?
                var receivedAnyData = false
                
                while attempt <= maxRetries {
                    do {
                        
                        // Use shorter timeout for initial attempts to fail fast on connection issues
                        let attemptTimeout = attempt == 0 ? min(timeout, 30.0) : timeout
                        
                        // Stream episodes from current attempt
                        for try await result in streamEpisodes(from: feedURL, podcastID: podcastID, timeout: attemptTimeout) {
                            continuation.yield(result)
                            
                            // Track that we received some data
                            if case .episode = result {
                                receivedAnyData = true
                            }
                            
                            // If we get a completion, we're done
                            if case .completed = result {
                                continuation.finish()
                                return
                            }
                        }
                        
                        // If we reach here without completion, something went wrong
                        break
                        
                    } catch {
                        lastError = error
                        
                        // Check if this is a retryable error
                        let shouldRetry: Bool
                        if let streamingError = error as? StreamingRSSError {
                            shouldRetry = streamingError.isRetryable
                        } else if let urlError = error as? URLError {
                            shouldRetry = isRetryableURLError(urlError)
                        } else {
                            shouldRetry = false
                        }
                        
                        // If we received some data but then failed, don't retry
                        if receivedAnyData {
                            continuation.finish(throwing: error)
                            return
                        }
                        
                        attempt += 1
                        
                        if shouldRetry && attempt <= maxRetries {
                            // Exponential backoff with jitter
                            let baseDelay = pow(2.0, Double(attempt - 1))
                            let jitter = Double.random(in: 0.5...1.5)
                            let delay = min(baseDelay * jitter, 15.0)
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        } else {
                            continuation.finish(throwing: lastError ?? error)
                            return
                        }
                    }
                }
                
                // If we exit the retry loop without success, throw the last error
                continuation.finish(throwing: lastError ?? StreamingEpisodeServiceError.allRetriesFailed)
            }
        }
    }
    
    /// Determines if a URLError is retryable
    private func isRetryableURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, 
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .resourceUnavailable, .badServerResponse:
            return true
        case .cancelled, .userCancelledAuthentication, .userAuthenticationRequired:
            return false
        default:
            // For HTTP status code errors, check if it's a server error (5xx)
            if let statusCode = extractHTTPStatusCode(from: error) {
                return statusCode >= 500
            }
            return false
        }
    }
    
    /// Extracts HTTP status code from URLError if available
    private func extractHTTPStatusCode(from error: URLError) -> Int? {
        // For now, return nil since the userInfo key extraction is problematic
        // This can be enhanced later if needed
        return nil
    }
    
    /// Streams episodes from a podcast's RSS feed URL with conditional GET support
    /// - Parameters:
    ///   - feedURL: The RSS feed URL to stream from
    ///   - podcastID: ID of the podcast these episodes belong to
    ///   - etag: ETag from previous request for conditional GET
    ///   - lastModified: Last-Modified date from previous request
    ///   - timeout: Request timeout (default: 60 seconds)
    /// - Returns: AsyncSequence that emits episodes as they're parsed, or nil if not modified (304)
    func streamEpisodesConditional(
        from feedURL: URL, 
        podcastID: UUID, 
        etag: String? = nil,
        lastModified: Date? = nil,
        timeout: TimeInterval = 60.0
    ) -> AsyncThrowingStream<StreamingEpisodeResult?, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Convert Date to string for conditional GET
                    let lastModifiedString = lastModified.map { 
                        DateFormatter.httpDateFormatter.string(from: $0) 
                    }
                    
                    // Try conditional GET first
                    let (data, _, _) = try await UnifiedNetworkService.shared.fetchRSSFeedConditional(
                        from: feedURL,
                        etag: etag,
                        lastModified: lastModifiedString
                    )
                    
                    // If data is nil, server returned 304 Not Modified
                    guard let data = data else {
                        continuation.yield(nil) // Signal no changes
                        continuation.finish()
                        return
                    }
                    
                    // Parse the updated feed using existing parser
                    let parser = ConcreteRSSParser()
                    let (episodes, metadata) = try await parser.parse(data: data, podcastID: podcastID, feedURL: feedURL)
                    
                    // Emit metadata first
                    let podcastMetadata = PodcastMetadata(
                        title: metadata.title,
                        author: metadata.author,
                        description: metadata.description,
                        artworkURL: metadata.artworkURL
                    )
                    continuation.yield(.metadata(podcastMetadata))
                    
                    // Emit episodes one by one
                    for episode in episodes {
                        // PERF-04: Check cancellation
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        continuation.yield(.episode(episode))
                    }
                    
                    // Emit completion
                    continuation.yield(.completed(totalEpisodes: episodes.count))
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Convenience method to fetch episodes with conditional GET
    /// Returns nil if content hasn't changed (304 Not Modified)
    /// Also returns updated ETag and Last-Modified headers for caching
    func fetchEpisodesConditionalWithHeaders(
        from feedURL: URL,
        podcastID: UUID,
        etag: String? = nil,
        lastModified: Date? = nil,
        timeout: TimeInterval = 60.0,
        progressHandler: ((Episode, Int) -> Void)? = nil
    ) async throws -> (episodes: [Episode], metadata: PodcastMetadata?, etag: String?, lastModified: String?)? {
        do {
            // Try conditional GET with header capture
            let lastModifiedString = lastModified.map { 
                DateFormatter.httpDateFormatter.string(from: $0) 
            }
            
            let (data, responseETag, responseLastModified) = try await UnifiedNetworkService.shared.fetchRSSFeedConditional(
                from: feedURL,
                etag: etag,
                lastModified: lastModifiedString
            )
            
            guard let data = data else {
                // Feed not modified (304)
                return nil
            }
            
            // Parse the updated feed using existing parser
            let parser = ConcreteRSSParser()
            let (episodes, metadata) = try await parser.parse(data: data, podcastID: podcastID, feedURL: feedURL)
            
            // Call progress handler for each episode
            var episodeCount = 0
            for episode in episodes {
                // PERF-04: Check for cancellation
                try Task.checkCancellation()
                
                episodeCount += 1
                if let progressHandler = progressHandler {
                    await MainActor.run {
                        progressHandler(episode, episodeCount)
                    }
                }
            }
            
            // Convert ShowMetadata to PodcastMetadata
            let podcastMetadata = PodcastMetadata(
                title: metadata.title,
                author: metadata.author,
                description: metadata.description,
                artworkURL: metadata.artworkURL
            )
            
            return (episodes: episodes, metadata: podcastMetadata, etag: responseETag, lastModified: responseLastModified)
            
        } catch {
            throw error
        }
    }
}

// MARK: - Error Types

enum StreamingEpisodeServiceError: Error, LocalizedError {
    case allRetriesFailed
    case invalidFeedURL
    case noEpisodesFound
    
    var errorDescription: String? {
        switch self {
        case .allRetriesFailed:
            return "All retry attempts failed"
        case .invalidFeedURL:
            return "Invalid RSS feed URL"
        case .noEpisodesFound:
            return "No episodes found in RSS feed"
        }
    }
}

// MARK: - Convenience Extensions

extension StreamingEpisodeService {
    
    /// Creates a cancellable task that streams episodes and updates a callback
    /// This is useful for ViewModels that need to handle cancellation
    /// - Parameters:
    ///   - feedURL: The RSS feed URL to stream from
    ///   - podcastID: ID of the podcast these episodes belong to
    ///   - onEpisode: Callback for each episode (called on MainActor)
    ///   - onMetadata: Callback for podcast metadata (called on MainActor)
    ///   - onError: Callback for errors (called on MainActor)
    ///   - onCompletion: Callback for completion (called on MainActor)
    /// - Returns: Task that can be cancelled
    func createStreamingTask(
        feedURL: URL,
        podcastID: UUID,
        onEpisode: @escaping @MainActor (Episode, Int) -> Void,
        onMetadata: @escaping @MainActor (PodcastMetadata) -> Void,
        onError: @escaping @MainActor (Error) -> Void,
        onCompletion: @escaping @MainActor (Int) -> Void
    ) -> Task<Void, Never> {
        
        return Task {
            var episodeCount = 0
            
            do {
                for try await result in streamEpisodesWithRetry(from: feedURL, podcastID: podcastID) {
                    // Check for cancellation
                    if Task.isCancelled {
                        return
                    }
                    
                    switch result {
                    case .episode(let episode):
                        episodeCount += 1
                        await MainActor.run {
                            onEpisode(episode, episodeCount)
                        }
                        
                    case .metadata(let metadata):
                        await MainActor.run {
                            onMetadata(metadata)
                        }
                        
                    case .error(let error):
                        await MainActor.run {
                            onError(error)
                        }
                        return
                        
                    case .completed(let totalEpisodes):
                        await MainActor.run {
                            onCompletion(totalEpisodes)
                        }
                        return
                    }
                }
            } catch {
                await MainActor.run {
                    onError(error)
                }
            }
        }
    }
}

// MARK: - DateFormatter Extension
extension DateFormatter {
    static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        return formatter
    }()
} 