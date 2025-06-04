import Foundation

enum SpotifyListParser {
    static func parse(data: Data) -> [URL] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .split(whereSeparator: { $0.isNewline })
            .compactMap { line -> URL? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.lowercased().hasPrefix("http") else { return nil }
                return URL(string: trimmed)
            }
    }
}
