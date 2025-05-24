import Foundation

extension String {
    /// Cleans episode titles by removing pipe separators and show names
    var cleanedEpisodeTitle: String {
        var cleaned = self
        
        // Remove common separators that sometimes appear between show name and episode title
        // Pattern: "Show Name | Episode Title" -> "Episode Title"
        if let pipeIndex = cleaned.firstIndex(of: "|") {
            let afterPipe = cleaned[cleaned.index(after: pipeIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !afterPipe.isEmpty {
                cleaned = String(afterPipe)
            }
        }
        
        // Pattern: "Show Name: Episode Title" -> "Episode Title" (only if colon is early in string)
        if let colonIndex = cleaned.firstIndex(of: ":") {
            let beforeColon = cleaned[..<colonIndex]
            let afterColon = cleaned[cleaned.index(after: colonIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Only remove if the part before colon looks like a show name (short and no episode indicators)
            if beforeColon.count < 50 && !beforeColon.localizedCaseInsensitiveContains("episode") && 
               !beforeColon.localizedCaseInsensitiveContains("ep.") && !afterColon.isEmpty {
                cleaned = String(afterColon)
            }
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Removes HTML tags and entities from episode descriptions
    var cleanedEpisodeDescription: String {
        var cleaned = self
        
        // Remove HTML tags using regex
        cleaned = cleaned.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        
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
            "&hellip;": "…"
        ]
        
        for (entity, replacement) in htmlEntities {
            cleaned = cleaned.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Remove extra whitespace and line breaks
        cleaned = cleaned.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression,
            range: nil
        )
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 