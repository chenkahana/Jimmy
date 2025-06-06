import Foundation

class PodcastURLResolver {
    static let shared = PodcastURLResolver()
    
    private init() {}
    
    func resolveToRSSFeed(from urlString: String, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        // If it's already an RSS feed URL, try it directly
        if urlString.contains("/rss") || urlString.contains("/feed") || urlString.contains(".xml") || urlString.hasSuffix(".rss") {
            testRSSFeed(url: url, completion: completion)
            return
        }
        
        // Handle Apple Podcasts URLs
        if url.host?.contains("podcasts.apple.com") == true {
            resolveApplePodcastsURL(url: url, completion: completion)
            return
        }
        
        // Handle Spotify URLs
        if url.host?.contains("spotify.com") == true {
            resolveSpotifyURL(url: url, completion: completion)
            return
        }
        
        // Handle Google Podcasts URLs
        if url.host?.contains("podcasts.google.com") == true {
            resolveGooglePodcastsURL(url: url, completion: completion)
            return
        }
        
        // Handle general podcast URLs by trying to find RSS feeds
        findRSSFeedInWebpage(url: url, completion: completion)
    }
    
    private func resolveApplePodcastsURL(url: URL, completion: @escaping (URL?) -> Void) {
        // Extract podcast ID from Apple Podcasts URL
        // Format: https://podcasts.apple.com/us/podcast/podcast-name/id123456789
        let urlString = url.absoluteString
        
        // Try to extract the ID
        if let idRange = urlString.range(of: "/id") {
            let idPart = String(urlString[idRange.upperBound...])
            let podcastID = idPart.components(separatedBy: "?").first ?? idPart
            
            if let id = Int(podcastID) {
                // Use iTunes Search API to get the RSS feed URL
                let searchURL = "https://itunes.apple.com/lookup?id=\(id)"
                
                guard let searchAPIURL = URL(string: searchURL) else {
                    completion(nil)
                    return
                }
                
                URLSession.shared.dataTask(with: searchAPIURL) { data, response, error in
                    guard let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let results = json["results"] as? [[String: Any]],
                          let first = results.first,
                          let feedURLString = first["feedUrl"] as? String,
                          let feedURL = URL(string: feedURLString) else {
                        completion(nil)
                        return
                    }
                    
                    completion(feedURL)
                }.resume()
                
                return
            }
        }
        
        // Fallback: extract podcast name and search for it
        extractPodcastNameFromAppleURL(url: url, completion: completion)
    }
    
    private func extractPodcastNameFromAppleURL(url: URL, completion: @escaping (URL?) -> Void) {
        // Extract podcast name from URL path
        let pathComponents = url.pathComponents
        if pathComponents.count >= 4,
           pathComponents[1] == "us" || pathComponents[1] == "podcast",
           pathComponents[2] == "podcast" {
            let podcastName = pathComponents[3]
                .replacingOccurrences(of: "-", with: " ")
                .removingPercentEncoding ?? ""
            
            // Search for this podcast using iTunes Search API
            iTunesSearchService.shared.searchPodcasts(query: podcastName) { results in
                completion(results.first?.feedURL)
            }
        } else {
            completion(nil)
        }
    }
    
    private func resolveSpotifyURL(url: URL, completion: @escaping (URL?) -> Void) {
        // Attempt to extract show title from Spotify page metadata
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let html = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }

            // Extract show title and author from meta tags
            let title = self.extractMetaContent(html: html, property: "og:title")
            let author = self.extractMetaContent(html: html, property: "music:creator")

            let searchQuery: String
            if let title = title, let author = author {
                searchQuery = "\(title) \(author)"
            } else if let title = title {
                searchQuery = title
            } else {
                completion(nil)
                return
            }

            // Search iTunes directory for a matching podcast
            iTunesSearchService.shared.searchPodcasts(query: searchQuery) { results in
                let feedURL = results.first?.feedURL
                completion(feedURL)
            }
        }.resume()
    }

    private func extractMetaContent(html: String, property: String) -> String? {
        let pattern = "<meta[^>]*property=\"\(property)\"[^>]*content=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }
        return nil
    }
    
    private func resolveGooglePodcastsURL(url: URL, completion: @escaping (URL?) -> Void) {
        // Google Podcasts URLs can sometimes be parsed for show names
        // But Google Podcasts has been discontinued, so this is less useful
        completion(nil)
    }
    
    private func findRSSFeedInWebpage(url: URL, completion: @escaping (URL?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let html = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }
            
            // Look for RSS feed links in the HTML
            let rssPatterns = [
                #"<link[^>]*type=["\']application/rss\+xml["\'][^>]*href=["\']([^"\']*)["\']"#,
                #"<link[^>]*href=["\']([^"\']*)["\'][^>]*type=["\']application/rss\+xml["\']"#,
                #"<link[^>]*rel=["\']alternate["\'][^>]*type=["\']application/rss\+xml["\'][^>]*href=["\']([^"\']*)["\']"#
            ]
            
            for pattern in rssPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
                   let urlRange = Range(match.range(at: 1), in: html) {
                    let rssURLString = String(html[urlRange])
                    
                    // Resolve relative URLs
                    if let rssURL = URL(string: rssURLString, relativeTo: url) {
                        completion(rssURL)
                        return
                    }
                }
            }
            
            completion(nil)
        }.resume()
    }
    
    private func testRSSFeed(url: URL, completion: @escaping (URL?) -> Void) {
        // Test if the URL is actually a valid RSS feed
        var request = URLRequest(url: url)
        request.setValue("Jimmy Podcast Player/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15.0
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let string = String(data: data, encoding: .utf8) else {
                print("❌ Failed to fetch RSS data for \(url.absoluteString)")
                completion(nil)
                return
            }
            
            // Basic check for RSS/XML content
            if string.contains("<rss") || string.contains("<feed") || string.contains("<channel") {
                print("✅ Valid RSS feed detected: \(url.absoluteString)")
                completion(url)
            } else {
                print("❌ Not a valid RSS feed, got: \(string.prefix(200))")
                completion(nil)
            }
        }.resume()
    }
} 