import Foundation

final class ConcreteRSSParser: RSSParserProtocol {
    func parse(data: Data, podcastID: UUID, feedURL: URL) async throws -> ([Episode], ShowMetadata) {
        let parser = InternalRSSParser(podcastID: podcastID, feedURL: feedURL)
        return try await parser.parse(data: data)
    }
}

// A stateful, internal parser class to encapsulate the XMLParserDelegate logic.
// This is not intended to be used directly from outside ConcreteRSSParser.
private class InternalRSSParser: NSObject, XMLParserDelegate {
    
    // MARK: - Private Properties
    private var episodes: [Episode] = []
    private var podcastID: UUID
    private var feedURL: URL
    
    private var currentElementName: String = ""
    private var isParsingItem: Bool = false
    
    // Episode properties under construction
    private var currentTitle: String = ""
    private var currentAudioURL: String = ""
    private var currentDescription: String = ""
    private var currentPubDate: String = ""
    private var currentEpisodeArtworkURL: String = ""
    private var currentDuration: TimeInterval?
    private var currentChaptersURL: String = ""
    private var currentTranscriptURL: String = ""

    // Podcast metadata
    private var podcastTitle: String = ""
    private var podcastAuthor: String = ""
    private var podcastDescription: String = ""
    private var podcastArtworkURL: String = ""
    private var podcastLanguage: String = ""
    private var podcastCategories: [String] = []
    
    private var continuation: CheckedContinuation<([Episode], ShowMetadata), Error>?
    
    init(podcastID: UUID, feedURL: URL) {
        self.podcastID = podcastID
        self.feedURL = feedURL
        super.init()
    }

    func parse(data: Data) async throws -> ([Episode], ShowMetadata) {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let parser = XMLParser(data: data)
            parser.delegate = self
            
            if !parser.parse() {
                let error = parser.parserError ?? NSError(domain: "RSSParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown parsing error"])
                finish(.failure(error))
            }
        }
    }

    /// Resumes the continuation at most once: on bad XML, `parseErrorOccurred` fires and then
    /// `parse()` returns false, and resuming twice crashes.
    private func finish(_ result: Result<([Episode], ShowMetadata), Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElementName = elementName
        if elementName == "item" {
            isParsingItem = true
            // Reset episode properties
            currentTitle = ""
            currentAudioURL = ""
            currentDescription = ""
            currentPubDate = ""
            currentEpisodeArtworkURL = ""
            currentDuration = nil
            currentChaptersURL = ""
            currentTranscriptURL = ""
        } else if isParsingItem {
            // Handle enclosure tag for audio URL
            if elementName == "enclosure" {
                if let url = attributeDict["url"], !url.isEmpty {
                    // Check if this is an audio file by looking at the type attribute
                    if let type = attributeDict["type"], type.contains("audio") {
                        currentAudioURL = url
                    } else {
                        // If no type specified, assume it might be audio (some feeds don't specify type)
                        currentAudioURL = url
                    }
                }
            }
            // Handle iTunes image for episode artwork
            else if elementName == "itunes:image", let href = attributeDict["href"] {
                currentEpisodeArtworkURL = href
            }
            // Podcasting 2.0: chapters URL
            else if elementName == "podcast:chapters", let url = attributeDict["url"] {
                currentChaptersURL = url
            }
            // Podcasting 2.0: transcript URL
            else if elementName == "podcast:transcript", let url = attributeDict["url"] {
                if currentTranscriptURL.isEmpty { // take first transcript only
                    currentTranscriptURL = url
                }
            }
        } else if !isParsingItem { // Parsing channel info
             if elementName == "itunes:image", let href = attributeDict["href"] {
                podcastArtworkURL = href
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let data = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if data.isEmpty { return }
        
        if isParsingItem {
            switch currentElementName {
            case "title": 
                // Only append if we don't already have content (CDATA takes precedence)
                if currentTitle.isEmpty {
                    currentTitle += data
                }
            case "description": 
                if currentDescription.isEmpty {
                    currentDescription += data
                }
            case "pubDate": currentPubDate += data
            case "itunes:duration": currentDuration = parseDuration(from: data)
            case "link":
                // Use link as audio URL fallback if we don't have one from enclosure
                if currentAudioURL.isEmpty && data.contains("http") {
                    currentAudioURL += data
                }
            case "enclosure":
                // This is often handled by attributes, but let's be safe.
                break
            default: break
            }
        } else { // Parsing channel info
            switch currentElementName {
            case "title": 
                // Only append if we don't already have content (CDATA takes precedence)
                if podcastTitle.isEmpty {
                    podcastTitle += data
                }
            case "itunes:author": podcastAuthor += data
            case "description": 
                if podcastDescription.isEmpty {
                    podcastDescription += data
                }
            case "language": podcastLanguage += data
            case "itunes:category":
                if !data.isEmpty {
                    podcastCategories.append(data)
                }
            default: break
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            createEpisode()
            isParsingItem = false
        } else if !isParsingItem {
            // Clean titles when we finish parsing channel elements
            if elementName == "title" {
                podcastTitle = cleanTitle(podcastTitle)
            }
        } else if isParsingItem {
            // Clean episode titles when we finish parsing item elements
            if elementName == "title" {
                currentTitle = cleanTitle(currentTitle)
            }
        }
    }
    
    func parserDidEndDocument(_ parser: XMLParser) {
        // Clean the podcast title to remove duplicates
        let cleanedPodcastTitle = cleanTitle(podcastTitle)
        
        let metadata = ShowMetadata(
            title: cleanedPodcastTitle.isEmpty ? nil : cleanedPodcastTitle,
            author: podcastAuthor.isEmpty ? nil : podcastAuthor,
            description: podcastDescription.isEmpty ? nil : podcastDescription,
            artworkURL: URL(string: podcastArtworkURL),
            language: podcastLanguage.isEmpty ? nil : podcastLanguage,
            categories: podcastCategories
        )
        finish(.success((episodes, metadata)))
    }
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        finish(.failure(parseError))
    }
    
    // MARK: - CDATA Handling
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        // Handle CDATA sections explicitly - this is crucial for Hebrew text
        guard let string = String(data: CDATABlock, encoding: .utf8) else {
            // Try with different encodings if UTF-8 fails
            if let string = String(data: CDATABlock, encoding: .utf16) {
                handleCDATAString(string)
            }
            return
        }
        handleCDATAString(string)
    }
    
    private func handleCDATAString(_ string: String) {
        let data = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if data.isEmpty { return }
        
        if isParsingItem {
            switch currentElementName {
            case "title": 
                // For CDATA, replace the current title entirely (don't append)
                currentTitle = data
            case "description": 
                // For CDATA, replace the current description entirely
                currentDescription = data
            default: 
                // For other elements, append as before
                break
            }
        } else { // Parsing channel info
            switch currentElementName {
            case "title": 
                // For CDATA, replace the podcast title entirely
                podcastTitle = data
            case "description": 
                podcastDescription = data
            default: break
            }
        }
    }

    private func createEpisode() {
        // Trim whitespace from audio URL
        let trimmedAudioURL = currentAudioURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedAudioURL.isEmpty else {
            return
        }
        
        guard let audioURL = URL(string: trimmedAudioURL) else {
            return
        }
        
        // Additional validation - ensure the URL looks like it could be an audio file
        let urlString = audioURL.absoluteString.lowercased()
        let hasAudioExtension = urlString.contains(".mp3") || urlString.contains(".m4a") || 
                               urlString.contains(".wav") || urlString.contains(".aac") ||
                               urlString.contains(".ogg") || urlString.contains(".flac")
        let hasAudioInPath = urlString.contains("audio") || urlString.contains("media") || 
                            urlString.contains("podcast") || urlString.contains("episode")
        
        // If URL doesn't look like audio and we have no other indicators, log a warning but still try
        if !hasAudioExtension && !hasAudioInPath && !urlString.contains("http") {
        }
        
        // Generate deterministic UUID based on feed URL and episode data
        let deterministicID = DeterministicUUIDGenerator.generateEpisodeID(
            feedURL: self.feedURL,
            audioURL: audioURL,
            title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            publishedDate: String.date(fromRFC822: currentPubDate)
        )
        
        let episode = Episode(
            id: deterministicID,
            title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            podcastID: self.podcastID,
            publishedDate: String.date(fromRFC822: currentPubDate),
            duration: currentDuration,
            artworkURL: URL(string: currentEpisodeArtworkURL),
            description: currentDescription,
            audioURL: audioURL
        )
        episodes.append(episode)
    }

    private func parseDuration(from string: String) -> TimeInterval? {
        let components = string.split(separator: ":").map(String.init)
        var duration: TimeInterval = 0
        if components.count == 3 { // HH:MM:SS
            duration += (Double(components[0]) ?? 0) * 3600
            duration += (Double(components[1]) ?? 0) * 60
            duration += (Double(components[2]) ?? 0)
        } else if components.count == 2 { // MM:SS
            duration += (Double(components[0]) ?? 0) * 60
            duration += (Double(components[1]) ?? 0)
        } else if let seconds = Double(string) { // Seconds
            duration = seconds
        } else {
            return nil
        }
        return duration
    }

    // MARK: - Title Cleaning Helper
    private func cleanTitle(_ title: String) -> String {
        // First decode HTML entities properly
        let decodedTitle = decodeHTMLEntities(title)
        let cleanedTitle = decodedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If the cleaned title is empty, return the original title
        guard !cleanedTitle.isEmpty else {
            return title
        }
        
        // Check if the title contains Hebrew characters
        let containsHebrew = cleanedTitle.unicodeScalars.contains { scalar in
            return (0x0590...0x05FF).contains(scalar.value) // Hebrew Unicode block
        }
        
        // If it contains Hebrew, be much more conservative about duplicate removal
        if containsHebrew {
            // For Hebrew text, only remove duplicates if it's an obvious exact repetition
            // Split by common separators that might indicate duplication
            let separators = [" - ", " | ", " – ", " — "]
            for separator in separators {
                let parts = cleanedTitle.components(separatedBy: separator)
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == parts[1].trimmingCharacters(in: .whitespaces) {
                    return parts[0].trimmingCharacters(in: .whitespaces)
                }
            }
            
            // No obvious duplication found, return as-is
            return cleanedTitle
        }
        
        // For non-Hebrew text, use the original logic
        let words = cleanedTitle.components(separatedBy: " ")
        
        // Only check for duplicates if there are at least 4 words and even count
        if words.count >= 4 && words.count % 2 == 0 {
            let halfCount = words.count / 2
            let firstHalf = Array(words[0..<halfCount]).joined(separator: " ")
            let secondHalf = Array(words[halfCount..<words.count]).joined(separator: " ")
            
            // Only remove duplicates if the halves are exactly identical
            // and the first half is at least 3 characters long
            if firstHalf == secondHalf && !firstHalf.isEmpty && firstHalf.count >= 3 {
                return firstHalf
            }
        }
        
        return cleanedTitle
    }
    
    // MARK: - HTML Entity Decoding Helper
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
}

// Date parsing utility, kept separate for clarity.
// This is now moved to StringExtensions.swift
// extension RSSParser {
//     static func dateFrom(pubDate: String) -> Date? {
//         let formats = [
//             "E, d MMM yyyy HH:mm:ss Z",
//             "E, d MMM yyyy HH:mm:ss zzz",
//             "E, d MMM yyyy HH:mm:ss z",
//             "yyyy-MM-dd'T'HH:mm:ssZ",
//             "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
//         ]
//         let formatter = DateFormatter()
//         formatter.locale = Locale(identifier: "en_US_POSIX")
//         for format in formats {
//             formatter.dateFormat = format
//             if let date = formatter.date(from: pubDate) {
//                 return date
//             }
//         }
//         return nil
//     }
// }
