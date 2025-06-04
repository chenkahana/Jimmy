import Foundation

struct SpotifyListParser {
    static func parse(data: Data) -> [URL] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: .newlines)
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return URL(string: trimmed)
        }
    }
}
