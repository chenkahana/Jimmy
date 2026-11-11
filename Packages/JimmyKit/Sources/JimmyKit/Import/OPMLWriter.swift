import Foundation

/// Writes feeds out as an OPML subscription export that `OPMLParser` can read back.
public nonisolated enum OPMLWriter {
    public static func write(_ feeds: [ImportedFeed]) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<opml version=\"1.0\">\n"
        xml += "  <head>\n    <title>Jimmy Subscriptions</title>\n  </head>\n"
        xml += "  <body>\n"
        for feed in feeds {
            let title = escape(feed.title ?? feed.feedURL.absoluteString)
            let url = escape(feed.feedURL.absoluteString)
            xml += "    <outline text=\"\(title)\" xmlUrl=\"\(url)\" />\n"
        }
        xml += "  </body>\n"
        xml += "</opml>\n"
        return Data(xml.utf8)
    }

    private static func escape(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
        return escaped
    }
}
