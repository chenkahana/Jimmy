import Foundation

/// Discover's recent searches: the last few submitted queries, newest first. Stored as newline-joined text so
/// it fits in `@AppStorage`.
nonisolated struct RecentSearches: Equatable, Sendable {
    static let limit = 8

    private(set) var queries: [String]

    init(storage: String) {
        queries = storage.split(separator: "\n").map(String.init)
    }

    var storage: String {
        queries.joined(separator: "\n")
    }

    /// Puts `query` first, dropping an earlier copy that differs only in case, and keeps the newest `limit`.
    mutating func add(_ query: String) {
        let cleaned = query
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }
        queries.removeAll { $0.caseInsensitiveCompare(cleaned) == .orderedSame }
        queries.insert(cleaned, at: 0)
        queries = Array(queries.prefix(Self.limit))
    }

    mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where queries.indices.contains(index) {
            queries.remove(at: index)
        }
    }

    mutating func clear() {
        queries = []
    }
}
