import Foundation

class SubscriptionImportService {
    static let shared = SubscriptionImportService()
    
    private init() {}
    
    struct ParsedPodcast {
        let title: String
        let author: String
        let appleURL: String?
    }
    
    /// Parse the subscription text file and import podcasts
    func importFromSubscriptionFile(filePath: String, completion: @escaping ([Podcast], Error?) -> Void) {
        guard let fileURL = URL(string: filePath),
              let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            completion([], SubscriptionImportError.fileReadError)
            return
        }
        
        parseSubscriptions(content: content, completion: completion)
    }
    
    /// Parse subscription content directly from string
    func importFromSubscriptionContent(_ content: String, completion: @escaping ([Podcast], Error?) -> Void) {
        parseSubscriptions(content: content, completion: completion)
    }
    
    private func parseSubscriptions(content: String, completion: @escaping ([Podcast], Error?) -> Void) {
        // Split by the separator "--//--"
        let podcastStrings = content.components(separatedBy: "--//--")
        let parsedPodcasts = podcastStrings.compactMap { parsePodcastString($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        
        guard !parsedPodcasts.isEmpty else {
            completion([], SubscriptionImportError.noValidPodcasts)
            return
        }
        
        print("📋 Parsed \(parsedPodcasts.count) podcasts from subscription file")
        
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
                        
                        print("✅ Resolved: \(parsedPodcast.title) -> \(rssURL.absoluteString)")
                    } else {
                        // Fallback: search by title and author
                        self?.searchForPodcast(title: parsedPodcast.title, author: parsedPodcast.author) { podcast in
                            if let podcast = podcast {
                                lock.lock()
                                podcasts.append(podcast)
                                lock.unlock()
                                print("🔍 Found via search: \(parsedPodcast.title)")
                            } else {
                                print("❌ Could not resolve: \(parsedPodcast.title)")
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
                        print("🔍 Found via search: \(parsedPodcast.title)")
                    } else {
                        print("❌ Could not find: \(parsedPodcast.title)")
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            print("📋 Successfully resolved \(podcasts.count) out of \(parsedPodcasts.count) podcasts")
            completion(podcasts, nil)
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
            return "Invalid file format"
        }
    }
} 