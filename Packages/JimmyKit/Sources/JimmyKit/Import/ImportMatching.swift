import Foundation

/// Folds a show or episode title down to what two apps would agree on: case, accents,
/// punctuation and runs of whitespace dropped.
public nonisolated enum TitleNormalizer {
    public static func key(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var key = ""
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                key.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                key.append(" ")
                lastWasSpace = true
            }
        }
        return key.trimmingCharacters(in: .whitespaces)
    }
}

/// Finds the feed episode another app's history entry refers to.
///
/// Tries, in order: the enclosure URL with tracking redirects stripped (Podtrac, Chartable,
/// Podsights and friends wrap the real file differently in different apps), then the title
/// within three days of the publish date, then the title alone when exactly one episode has it.
public nonisolated enum EpisodeMatcher {
    public static func match(_ state: ImportedEpisodeState, in episodes: [Episode]) -> Episode? {
        if let enclosureURL = state.enclosureURL {
            let key = enclosureKey(enclosureURL)
            let byURL = episodes.filter { $0.audioURL.map(enclosureKey) == key }
            // A feed that tells episodes apart only by query string (`download.php?id=…`) gives
            // them all one key; fall through to the title for those.
            if byURL.count == 1 { return byURL[0] }
        }

        let titleKey = TitleNormalizer.key(state.title)
        guard !titleKey.isEmpty else { return nil }
        let sameTitle = episodes.filter { TitleNormalizer.key($0.title) == titleKey }

        if let date = state.publishedDate {
            let threeDays: TimeInterval = 3 * 24 * 60 * 60
            let close = sameTitle.filter { episode in
                guard let published = episode.publishedDate else { return false }
                return abs(published.timeIntervalSince(date)) <= threeDays
            }
            if let first = close.first { return first }
        }
        return sameTitle.count == 1 ? sameTitle[0] : nil
    }

    /// The enclosure URL from its real host on: no scheme, no query, no tracking prefixes.
    ///
    /// A tracking prefix embeds the real URL in its path
    /// (`dts.podtrac.com/redirect.mp3/traffic.megaphone.fm/ABC.mp3`), so the key starts at the
    /// last path segment that is a host name rather than a file.
    static func enclosureKey(_ url: URL) -> String {
        var segments = [url.host?.lowercased() ?? ""]
        segments += url.path.split(separator: "/").map(String.init)
        let fileIndex = segments.count - 1
        var start = 0
        for index in segments.indices where index < fileIndex && looksLikeHost(segments[index]) {
            start = index
        }
        var key = segments[start...].joined(separator: "/").lowercased()
        if key.hasPrefix("www.") { key.removeFirst(4) }
        return key
    }

    private static let fileExtensions: Set<String> = ["mp3", "m4a", "mp4", "aac", "ogg", "opus", "wav", "m4v", "mov", "php", "aspx"]

    private static func looksLikeHost(_ segment: String) -> Bool {
        let parts = segment.split(separator: ".")
        guard parts.count >= 2, let tld = parts.last else { return false }
        guard (2...6).contains(tld.count), tld.allSatisfy(\.isLetter) else { return false }
        return !fileExtensions.contains(tld.lowercased())
    }
}

/// Picks the directory result that is the show the listener named.
public nonisolated enum DirectoryMatcher {
    /// The result whose title matches `name` exactly once normalized, preferring one by the same
    /// publisher. Falls back to a title that contains the name (or the other way round) from
    /// the same publisher. `nil` rather than a guess.
    public static func bestMatch(for name: ImportedShowName, in results: [PodcastDirectoryResult]) -> PodcastDirectoryResult? {
        let titleKey = TitleNormalizer.key(name.title)
        guard !titleKey.isEmpty else { return nil }
        let publisherKey = name.publisher.map(TitleNormalizer.key) ?? ""

        func samePublisher(_ result: PodcastDirectoryResult) -> Bool {
            guard !publisherKey.isEmpty else { return false }
            let author = TitleNormalizer.key(result.author)
            return author == publisherKey || author.contains(publisherKey) || publisherKey.contains(author)
        }

        let exact = results.filter { TitleNormalizer.key($0.title) == titleKey }
        if let match = exact.first(where: samePublisher) ?? exact.first {
            return match
        }

        return results.first { result in
            let key = TitleNormalizer.key(result.title)
            return (key.contains(titleKey) || titleKey.contains(key)) && samePublisher(result)
        }
    }
}
