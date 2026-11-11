import Foundation
import GRDB

struct Show: Codable, Equatable, FetchableRecord, PersistableRecord {
    var feedURL: URL
    var showDescription: String
    var author: String
    var language: String
    var updatedAt: Date

    static var databaseTableName: String = "shows"

    enum Columns: String, ColumnExpression {
        case feedURL, showDescription, author, language, updatedAt
    }

    init(feedURL: URL, showDescription: String, author: String, language: String, updatedAt: Date = Date()) {
        self.feedURL = feedURL
        self.showDescription = showDescription
        self.author = author
        self.language = language
        self.updatedAt = updatedAt
    }

    init(row: Row) {
        feedURL = row[Columns.feedURL]
        showDescription = row[Columns.showDescription]
        author = row[Columns.author]
        language = row[Columns.language]
        updatedAt = row[Columns.updatedAt]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.feedURL] = feedURL
        container[Columns.showDescription] = showDescription
        container[Columns.author] = author
        container[Columns.language] = language
        container[Columns.updatedAt] = updatedAt
    }
} 