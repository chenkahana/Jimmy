import Foundation

enum SpotifyListParser {
    static func parse(data: Data) -> [URL] {
        guard let string = String(data: data, encoding: .utf8) else { return [] }
        return string
            .split(whereSeparator: { $0.isNewline })
            .compactMap { line -> URL? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.lowercased().hasPrefix("http") else { return nil }
                return URL(string: trimmed)
            }
    }
}
