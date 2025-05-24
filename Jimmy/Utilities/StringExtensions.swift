import Foundation

extension String {
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