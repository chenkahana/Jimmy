import Foundation
import os

class SubscriptionImportService {
    static let shared = SubscriptionImportService()
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "SubscriptionImportService")

    private init() {}
    
    struct ParsedPodcast {
        let title: String
        let author: String
        let appleURL: String?
    }
    
    struct JSONPodcast: Codable {
        let title: String
        let publisher: String?
        let url: String?
        
        // Alternative field names for compatibility
        let name: String?
        let author: String?
        let feedURL: String?
        let rssURL: String?
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Try different field names for title
            if let title = try? container.decode(String.self, forKey: .title) {
                self.title = title
                self.name = title
            } else if let name = try? container.decode(String.self, forKey: .name) {
                self.title = name
                self.name = name
            } else {
                throw DecodingError.keyNotFound(CodingKeys.title, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing title or name field"))
            }
            
            // Try different field names for publisher/author
            self.publisher = (try? container.decode(String.self, forKey: .publisher)) ?? (try? container.decode(String.self, forKey: .author))
            self.author = self.publisher
            
            // Try different field names for URL
            if let url = try? container.decode(String.self, forKey: .url) {
                self.url = url
                self.feedURL = url
                self.rssURL = url
            } else if let feedURL = try? container.decode(String.self, forKey: .feedURL) {
                self.url = feedURL
                self.feedURL = feedURL
                self.rssURL = feedURL
            } else if let rssURL = try? container.decode(String.self, forKey: .rssURL) {
                self.url = rssURL
                self.feedURL = rssURL
                self.rssURL = rssURL
            } else {
                self.url = nil
                self.feedURL = nil
                self.rssURL = nil
            }
        }
        
        private enum CodingKeys: String, CodingKey {
            case title, publisher, url, name, author, feedURL, rssURL
        }
    }
    
    /// Parse the subscription text file and import podcasts
    func importFromSubscriptionFile(filePath: String, completion: @escaping ([Podcast], Error?) -> Void) {
        guard let fileURL = URL(string: filePath) else {
            completion([], SubscriptionImportError.fileReadError)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let data = try Data(contentsOf: fileURL)
                guard let content = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async { completion([], SubscriptionImportError.fileReadError) }
                    return
                }
                
                DispatchQueue.main.async {
                    self?.parseSubscriptions(content: content, completion: completion)
                }
            } catch {
                DispatchQueue.main.async { completion([], error) }
            }
        }
    }
    
    /// Parse subscription content directly from string
    func importFromSubscriptionContent(_ content: String, completion: @escaping ([Podcast], Error?) -> Void) {
        parseSubscriptions(content: content, completion: completion)
    }
    
    /// Import podcasts from JSON file
    /// Expected JSON format:
    /// [
    ///   {
    ///     "title": "Podcast Name",           // Required (or "name")
    ///     "publisher": "Publisher Name",     // Optional (or "author")
    ///     "url": "https://feed.url"          // Optional (or "feedURL", "rssURL")
    ///   }
    /// ]
    func importFromJSONFile(data: Data, progressHandler: ((String) -> Void)? = nil, completion: @escaping ([Podcast], Error?) -> Void) {
        do {
            progressHandler?("Parsing JSON file...")
            let jsonPodcasts = try JSONDecoder().decode([JSONPodcast].self, from: data)
            
            guard !jsonPodcasts.isEmpty else {
                completion([], SubscriptionImportError.noValidPodcasts)
                return
            }
            
            Self.logger.info("Parsed \(jsonPodcasts.count) podcasts from JSON file")
            progressHandler?("Found \(jsonPodcasts.count) podcasts in file")
            
            // Simple approach: just take URLs and fetch podcast data directly
            let validURLs = jsonPodcasts.compactMap { jsonPodcast -> String? in
                guard let urlString = jsonPodcast.url, !urlString.isEmpty else { return nil }
                return urlString
            }
            
            guard !validURLs.isEmpty else {
                completion([], SubscriptionImportError.noValidPodcasts)
                return
            }
            
            Self.logger.info("Found \(validURLs.count) valid URLs to process")
            progressHandler?("Processing \(validURLs.count) podcast URLs...")
            
            // Process URLs directly
            processURLsDirectly(validURLs, progressHandler: progressHandler, completion: completion)
            
        } catch {
            Self.logger.error("JSON parsing error: \(error)")
            
            // Provide more helpful error messages
            if error is DecodingError {
                let friendlyError = SubscriptionImportError.invalidFormat
                completion([], friendlyError)
            } else {
                completion([], error)
            }
        }
    }
    
    private func parseSubscriptions(content: String, completion: @escaping ([Podcast], Error?) -> Void) {
        // Split by the separator "--//--"
        let podcastStrings = content.components(separatedBy: "--//--")
        let parsedPodcasts = podcastStrings.compactMap { parsePodcastString($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        
        guard !parsedPodcasts.isEmpty else {
            completion([], SubscriptionImportError.noValidPodcasts)
            return
        }
        
        Self.logger.info("Parsed \(parsedPodcasts.count) podcasts from subscription file")
        
        // Convert to Podcast objects by resolving URLs
        convertParsedPodcastsToPodcasts(parsedPodcasts, completion: completion)
    }
    
    private func parsePodcastString(_ podcastString: String) -> ParsedPodcast? {
        guard !podcastString.isEmpty else { return nil }
        
        // Format: "⁨⁨TITLE⁩ by ⁨AUTHOR⁩⁩ (⁨URL⁩)"
        // Or: "TITLE by AUTHOR (URL)"
        // Or: "TITLE by AUTHOR--//--" (no URL)
        
        // Remove Unicode directional marks and other special characters
        let cleanString = podcastString
            .replacingOccurrences(of: "⁨", with: "")
            .replacingOccurrences(of: "⁩", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If the string itself is just a URL, treat it as an RSS/Apple URL
        if cleanString.hasPrefix("http://") || cleanString.hasPrefix("https://") {
            // Use host as a placeholder title
            if let url = URL(string: cleanString) {
                let hostTitle = url.host ?? cleanString
                return ParsedPodcast(title: hostTitle, author: "Unknown", appleURL: cleanString)
            } else {
                return nil
            }
        }

        // Extract URL if present (between parentheses)
        var title: String = ""
        var author: String = ""
        var appleURL: String?
        
        if let urlMatch = cleanString.range(of: #"\([^)]*https://[^)]*\)"#, options: .regularExpression) {
            let urlPart = String(cleanString[urlMatch])
            // Extract URL from parentheses
            if let urlStart = urlPart.range(of: "https://") {
                let urlString = String(urlPart[urlStart.lowerBound...])
                    .replacingOccurrences(of: ")", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                appleURL = urlString
            }
            
            // Get the part before the URL
            let titleAuthorPart = String(cleanString[..<urlMatch.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Split by " by "
            if let byRange = titleAuthorPart.range(of: " by ", options: .backwards) {
                title = String(titleAuthorPart[..<byRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                author = String(titleAuthorPart[byRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                title = titleAuthorPart
                author = "Unknown"
            }
        } else {
            // No URL, just parse title and author
            if let byRange = cleanString.range(of: " by ", options: .backwards) {
                title = String(cleanString[..<byRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                author = String(cleanString[byRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                title = cleanString
                author = "Unknown"
            }
        }
        
        guard !title.isEmpty else { return nil }
        
        return ParsedPodcast(title: title, author: author, appleURL: appleURL)
    }
    
    private func convertParsedPodcastsToPodcasts(_ parsedPodcasts: [ParsedPodcast], completion: @escaping ([Podcast], Error?) -> Void) {
        var podcasts: [Podcast] = []
        let group = DispatchGroup()
        let lock = NSLock()
        
        for parsedPodcast in parsedPodcasts {
            group.enter()
            
            if let appleURLString = parsedPodcast.appleURL {
                // Try to resolve Apple Podcasts URL to RSS feed
                PodcastURLResolver.shared.resolveToRSSFeed(from: appleURLString) { [weak self] rssURL in
                    defer { group.leave() }
                    
                    if let rssURL = rssURL {
                        let podcast = Podcast(
                            title: parsedPodcast.title,
                            author: parsedPodcast.author,
                            description: "",
                            feedURL: rssURL,
                            artworkURL: nil
                        )
                        
                        lock.lock()
                        podcasts.append(podcast)
                        lock.unlock()
                    } else {
                        // Fallback: search by title and author
                        self?.searchForPodcast(title: parsedPodcast.title, author: parsedPodcast.author) { podcast in
                            if let podcast = podcast {
                                lock.lock()
                                podcasts.append(podcast)
                                lock.unlock()
                                Self.logger.info("Found via search: \(parsedPodcast.title)")
                            } else {
                                Self.logger.warning("Could not resolve: \(parsedPodcast.title)")
                            }
                        }
                    }
                }
            } else {
                // No Apple URL, search by title and author
                searchForPodcast(title: parsedPodcast.title, author: parsedPodcast.author) { podcast in
                    defer { group.leave() }
                    
                    if let podcast = podcast {
                        lock.lock()
                        podcasts.append(podcast)
                        lock.unlock()
                        Self.logger.info("Found via search: \(parsedPodcast.title)")
                    } else {
                        Self.logger.warning("Could not find: \(parsedPodcast.title)")
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            Self.logger.info("Successfully resolved \(podcasts.count) out of \(parsedPodcasts.count) podcasts")
            
            // 🎯 AUTOMATIC TRIGGER: Notify DataFetchCoordinator that subscriptions were imported
            if !podcasts.isEmpty {
                NotificationCenter.default.post(
                    name: NSNotification.Name("subscriptionImported"),
                    object: podcasts
                )
            }
            
            completion(podcasts, nil)
        }
    }
    
    /// Process URLs directly by resolving them to RSS feeds and fetching podcast data
    private func processURLsDirectly(_ urls: [String], progressHandler: ((String) -> Void)? = nil, completion: @escaping ([Podcast], Error?) -> Void) {
        Task {
            let podcasts = await withTaskGroup(of: Podcast?.self) { group in
                var results: [Podcast] = []
                
                for urlString in urls {
                    group.addTask {
                        Self.logger.debug("Processing URL: \(urlString)")
                        
                        // Use PodcastURLResolver to convert Apple Podcasts URLs to RSS feeds
                        let rssURL = await withCheckedContinuation { continuation in
                            PodcastURLResolver.shared.resolveToRSSFeed(from: urlString) { rssURL in
                                continuation.resume(returning: rssURL)
                            }
                        }
                        
                        guard let rssURL = rssURL else {
                            Self.logger.warning("Could not resolve URL: \(urlString)")
                            return nil
                        }
                        
                        Self.logger.info("Resolved to RSS feed: \(rssURL.absoluteString)")
                        
                        do {
                            guard let podcast = try await AppModel.current?.subscribe(feedURL: rssURL) else { return nil }
                            Self.logger.info("Successfully added podcast: \(podcast.title)")
                            return podcast.asLegacyPodcast()
                        } catch {
                            Self.logger.error("Failed to add podcast: \(error.localizedDescription)")
                            return nil
                        }
                    }
                }
                
                var processedCount = 0
                for await podcast in group {
                    processedCount += 1
                    await MainActor.run {
                        progressHandler?("Processing podcast \(processedCount) of \(urls.count)...")
                    }
                    
                    if let podcast = podcast {
                        results.append(podcast)
                    }
                }
                
                return results
            }
            
            // Return to main thread for completion
            await MainActor.run {
                Self.logger.info("Successfully processed \(podcasts.count) out of \(urls.count) URLs")
                
                // 🎯 AUTOMATIC TRIGGER: Notify DataFetchCoordinator that subscriptions were imported
                if !podcasts.isEmpty {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("subscriptionImported"),
                        object: podcasts
                    )
                }
                
                completion(podcasts, nil)
            }
        }
    }
    
    private func searchForPodcast(title: String, author: String, completion: @escaping (Podcast?) -> Void) {
        // Use iTunes Search Service to find the podcast
        iTunesSearchService.shared.searchPodcasts(query: title) { results in
            // Try to find a match by title and author
            let bestMatch = results.first { podcast in
                podcast.title.lowercased().contains(title.lowercased()) ||
                title.lowercased().contains(podcast.title.lowercased()) ||
                podcast.author.lowercased().contains(author.lowercased()) ||
                author.lowercased().contains(podcast.author.lowercased())
            }
            
            completion(bestMatch?.toPodcast() ?? results.first?.toPodcast())
        }
    }
}

enum SubscriptionImportError: Error, LocalizedError {
    case fileReadError
    case noValidPodcasts
    case invalidFormat
    
    var errorDescription: String? {
        switch self {
        case .fileReadError:
            return "Could not read the subscription file"
        case .noValidPodcasts:
            return "No valid podcasts found in the file"
        case .invalidFormat:
            return "Invalid JSON format. Expected an array of objects with 'title' and optionally 'publisher' and 'url' fields."
        }
    }
} 