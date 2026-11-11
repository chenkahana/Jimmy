import Foundation

final class EpisodeParser {

    func parse(data: Data, podcast: Podcast) throws -> [Episode] {
        guard let rssString = String(data: data, encoding: .utf8),
              rssString.contains("<rss") || rssString.contains("<feed") else {
            throw NSError(domain: "RSSParseError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid RSS format"])
        }
        
        var episodes: [Episode] = []
        let itemComponents = rssString.components(separatedBy: "<item>")
        
        for index in 1..<itemComponents.count {
            autoreleasepool {
                let itemString = itemComponents[index]
                
                let title = extractValue(from: itemString, tag: "title") ?? "Episode \(index)"
                let description = extractValue(from: itemString, tag: "description")
                let audioURLString = extractAttribute(from: itemString, tag: "enclosure", attribute: "url")
                let pubDateString = extractValue(from: itemString, tag: "pubDate")
                let durationString = extractValue(from: itemString, tag: "itunes:duration")
                
                let episodeArtworkURL = extractEpisodeArtwork(from: itemString, fallbackURL: podcast.artworkURL)
                
                let publishedDate = parsePubDate(pubDateString) ?? Date().addingTimeInterval(-Double(index) * 86400)
                let duration = parseDuration(durationString) ?? 3600
                
                // Skip episodes without valid audio URLs
                guard let audioURLString = audioURLString,
                      !audioURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let audioURL = URL(string: audioURLString) else {
                    return
                }
                
                // Generate deterministic UUID based on feed URL and episode data
                let deterministicID = DeterministicUUIDGenerator.generateEpisodeID(
                    feedURL: podcast.feedURL,
                    audioURL: audioURL,
                    title: title,
                    publishedDate: publishedDate
                )
                
                let episode = Episode(
                    id: deterministicID,
                    title: title,
                    podcastID: podcast.id,
                    publishedDate: publishedDate,
                    duration: duration,
                    artworkURL: episodeArtworkURL,
                    description: description,
                    audioURL: audioURL
                )
                
                episodes.append(episode)
            }
        }
        
        episodes.sort { ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) }
        return episodes
    }
    
    private func extractValue(from xmlString: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        
        let range = NSRange(location: 0, length: xmlString.count)
        guard let match = regex.firstMatch(in: xmlString, options: [], range: range) else { return nil }
        
        let matchRange = match.range(at: 1)
        guard let swiftRange = Range(matchRange, in: xmlString) else { return nil }
        
        let value = String(xmlString[swiftRange])
        return cleanHTMLTags(from: value)
    }
    
    private func extractAttribute(from xmlString: String, tag: String, attribute: String) -> String? {
        // For enclosure tags, we want to be more specific and check for audio type
        if tag == "enclosure" && attribute == "url" {
            // Look for enclosure with audio type first
            let audioPattern = "<\(tag)[^>]*type\\s*=\\s*[\"'][^\"']*audio[^\"']*[\"'][^>]*\(attribute)\\s*=\\s*[\"']([^\"']*)[\"'][^>]*>"
            if let regex = try? NSRegularExpression(pattern: audioPattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: xmlString.count)
                if let match = regex.firstMatch(in: xmlString, options: [], range: range) {
                    let matchRange = match.range(at: 1)
                    if let swiftRange = Range(matchRange, in: xmlString) {
                        return String(xmlString[swiftRange])
                    }
                }
            }
            
            // Fallback to any enclosure URL if no audio type specified
            let fallbackPattern = "<\(tag)[^>]*\(attribute)\\s*=\\s*[\"']([^\"']*)[\"'][^>]*>"
            if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: xmlString.count)
                if let match = regex.firstMatch(in: xmlString, options: [], range: range) {
                    let matchRange = match.range(at: 1)
                    if let swiftRange = Range(matchRange, in: xmlString) {
                        return String(xmlString[swiftRange])
                    }
                }
            }
            
            return nil
        }
        
        // Standard attribute extraction for other tags
        let pattern = "<\(tag)[^>]*\(attribute)=[\"']([^\"']*)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        
        let range = NSRange(location: 0, length: xmlString.count)
        guard let match = regex.firstMatch(in: xmlString, options: [], range: range) else { return nil }
        
        let matchRange = match.range(at: 1)
        guard let swiftRange = Range(matchRange, in: xmlString) else { return nil }
        
        return String(xmlString[swiftRange])
    }
    
    private func cleanHTMLTags(from string: String) -> String {
        // First remove HTML tags
        let pattern = "<[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return string }
        
        let range = NSRange(location: 0, length: string.count)
        let cleanString = regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: "")
        
        // Then decode HTML entities with comprehensive support for Hebrew
        return decodeHTMLEntities(cleanString).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        
        // Decode common HTML entities
        let htmlEntities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " ",
            "&#39;": "'",
            "&#x27;": "'",
            "&rsquo;": "'",
            "&lsquo;": "'",
            "&rdquo;": "\u{201D}",
            "&ldquo;": "\u{201C}",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "…",
            "&#8211;": "–",
            "&#8212;": "—",
            "&#8216;": "'",
            "&#8217;": "'",
            "&#8220;": "\u{201C}",
            "&#8221;": "\u{201D}",
            "&#8230;": "…"
        ]
        
        for (entity, replacement) in htmlEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Handle numeric HTML entities (&#123;) - crucial for Hebrew characters
        let numericEntityPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: numericEntityPattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.count))
            
            // Process matches in reverse order to avoid index shifting
            for match in matches.reversed() {
                guard let numberRange = Range(match.range(at: 1), in: result),
                      let number = Int(String(result[numberRange])),
                      let scalar = UnicodeScalar(number),
                      let fullRange = Range(match.range, in: result) else {
                    continue
                }
                result.replaceSubrange(fullRange, with: String(scalar))
            }
        }
        
        // Handle hex HTML entities (&#x123;) - also important for Hebrew
        let hexEntityPattern = "&#x([0-9a-fA-F]+);"
        if let regex = try? NSRegularExpression(pattern: hexEntityPattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.count))
            
            // Process matches in reverse order to avoid index shifting
            for match in matches.reversed() {
                guard let numberRange = Range(match.range(at: 1), in: result),
                      let number = Int(String(result[numberRange]), radix: 16),
                      let scalar = UnicodeScalar(number),
                      let fullRange = Range(match.range, in: result) else {
                    continue
                }
                result.replaceSubrange(fullRange, with: String(scalar))
            }
        }
        
        return result
    }
    
    private func parsePubDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        let formatter = DateFormatter()
        
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = formatter.date(from: dateString) { return date }
        
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let date = formatter.date(from: dateString) { return date }
        
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
    
    private func parseDuration(_ durationString: String?) -> TimeInterval? {
        guard let durationString = durationString else { return nil }
        
        let components = durationString.components(separatedBy: ":")
        if components.count == 3,
           let hours = Double(components[0]),
           let minutes = Double(components[1]),
           let seconds = Double(components[2]) {
            return hours * 3600 + minutes * 60 + seconds
        }
        
        if components.count == 2,
           let minutes = Double(components[0]),
           let seconds = Double(components[1]) {
            return minutes * 60 + seconds
        }
        
        if let seconds = Double(durationString) {
            return seconds
        }
        
        return nil
    }
    
    private func extractEpisodeArtwork(from xmlString: String, fallbackURL: URL?) -> URL? {
        if let itunesImageURL = extractAttribute(from: xmlString, tag: "itunes:image", attribute: "href") {
            if let url = URL(string: itunesImageURL) { return url }
        }
        
        return fallbackURL
    }
} 