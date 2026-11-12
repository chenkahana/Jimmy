import Foundation

nonisolated extension String {
    /// Removes HTML tags and entities from episode descriptions
    var cleanedEpisodeDescription: String {
        return self.cleanedDescription
    }
    
    /// Cleans episode and podcast titles by removing duplicates and handling Hebrew text properly
    var cleanedTitle: String {
        // First decode HTML entities properly
        let decodedTitle = self.cleanedDescription // Reuse existing HTML entity decoding
        let cleanedTitle = decodedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If the cleaned title is empty, return the original title
        guard !cleanedTitle.isEmpty else {
            return self
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
    
    /// Removes HTML tags and entities from any description (episodes, podcasts, etc.)
    var cleanedDescription: String {
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
            "&hellip;": "…",
            "&bull;": "•",
            "&copy;": "©",
            "&reg;": "®",
            "&trade;": "™",
            "&#8211;": "–",
            "&#8212;": "—",
            "&#8216;": "'",
            "&#8217;": "'",
            "&#8220;": "\u{201C}",
            "&#8221;": "\u{201D}",
            "&#8230;": "…"
        ]
        
        for (entity, replacement) in htmlEntities {
            cleaned = cleaned.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Handle numeric HTML entities (&#123;)
        let numericEntityPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: numericEntityPattern, options: []) {
            var result = cleaned
            let matches = regex.matches(in: cleaned, options: [], range: NSRange(location: 0, length: cleaned.count))
            
            // Process matches in reverse order to avoid index shifting
            for match in matches.reversed() {
                guard let numberRange = Range(match.range(at: 1), in: cleaned),
                      let number = Int(String(cleaned[numberRange])),
                      let scalar = UnicodeScalar(number),
                      let fullRange = Range(match.range, in: cleaned) else {
                    continue
                }
                result.replaceSubrange(fullRange, with: String(scalar))
                cleaned = result
            }
        }
        
        // Handle hex HTML entities (&#x123;)
        let hexEntityPattern = "&#x([0-9a-fA-F]+);"
        if let regex = try? NSRegularExpression(pattern: hexEntityPattern, options: []) {
            var result = cleaned
            let matches = regex.matches(in: cleaned, options: [], range: NSRange(location: 0, length: cleaned.count))
            
            // Process matches in reverse order to avoid index shifting
            for match in matches.reversed() {
                guard let numberRange = Range(match.range(at: 1), in: cleaned),
                      let number = Int(String(cleaned[numberRange]), radix: 16),
                      let scalar = UnicodeScalar(number),
                      let fullRange = Range(match.range, in: cleaned) else {
                    continue
                }
                result.replaceSubrange(fullRange, with: String(scalar))
                cleaned = result
            }
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

    /// Parses a date from a string using a list of common RSS date formats.
    static func date(fromRFC822 string: String) -> Date? {
        let formats = [
            "E, d MMM yyyy HH:mm:ss Z",
            "E, d MMM yyyy HH:mm:ss zzz",
            "E, d MMM yyyy HH:mm:ss z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
} 