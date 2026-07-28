import Foundation

struct ParsedRSSFeed: Equatable, Sendable {
    var title: String
    var items: [RSSFeedItem]
}

enum RSSFeedServiceError: LocalizedError {
    case invalidURL
    case unsupportedResponse
    case httpStatus(Int)
    case responseTooLarge
    case invalidFeed

    var errorDescription: String? {
        switch self {
        case .invalidURL: L10n.string("RSS 地址无效")
        case .unsupportedResponse: L10n.string("RSS 服务器返回了无法识别的响应")
        case .httpStatus(let status): L10n.string("RSS 服务器返回 HTTP \(status)")
        case .responseTooLarge: L10n.string("RSS 内容超过 5 MB，已停止读取")
        case .invalidFeed: L10n.string("没有识别到有效的 RSS 或 Atom 内容")
        }
    }
}

enum RSSFeedService {
    static func fetch(from url: URL) async throws -> ParsedRSSFeed {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw RSSFeedServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue(
            "AriaLane/1.0 (+RSS reader)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.5",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RSSFeedServiceError.unsupportedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RSSFeedServiceError.httpStatus(httpResponse.statusCode)
        }
        guard data.count <= 5 * 1_024 * 1_024 else {
            throw RSSFeedServiceError.responseTooLarge
        }
        return try RSSFeedParser.parse(data)
    }
}

enum RSSFeedParser {
    static func parse(_ data: Data) throws -> ParsedRSSFeed {
        let delegate = RSSXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse(), delegate.didRecognizeFeed else {
            throw parser.parserError ?? RSSFeedServiceError.invalidFeed
        }
        return ParsedRSSFeed(
            title: delegate.feedTitle.trimmed,
            items: Array(delegate.items.prefix(100))
        )
    }
}

private final class RSSXMLParserDelegate: NSObject, XMLParserDelegate {
    private struct ItemBuilder {
        var title = ""
        var identifier = ""
        var link: String?
        var enclosureURL: String?
        var publishedAt: Date?
    }

    private(set) var feedTitle = ""
    private(set) var items: [RSSFeedItem] = []
    private(set) var didRecognizeFeed = false

    private var currentItem: ItemBuilder?
    private var currentElement = ""
    private var currentText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = Self.normalizedName(qName ?? elementName)
        currentElement = name
        currentText = ""

        switch name {
        case "rss", "rdf", "feed":
            didRecognizeFeed = true
        case "item", "entry":
            currentItem = ItemBuilder()
        case "enclosure":
            currentItem?.enclosureURL = Self.normalizedURLString(attributeDict["url"])
        case "content":
            if currentItem?.enclosureURL == nil {
                currentItem?.enclosureURL = Self.normalizedURLString(attributeDict["url"])
            }
        case "link":
            guard currentItem != nil,
                  let href = Self.normalizedURLString(attributeDict["href"]) else {
                return
            }
            let relation = attributeDict["rel"]?.lowercased() ?? "alternate"
            if relation == "enclosure" {
                currentItem?.enclosureURL = href
            } else if relation == "alternate" || currentItem?.link == nil {
                currentItem?.link = href
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = Self.normalizedName(qName ?? elementName)
        let value = currentText.trimmed

        if var item = currentItem {
            switch name {
            case "title":
                item.title += value
            case "guid", "id":
                item.identifier += value
            case "link":
                if item.link == nil {
                    item.link = Self.normalizedURLString(value)
                }
            case "pubdate", "published", "updated", "date":
                item.publishedAt = item.publishedAt ?? Self.parseDate(value)
            case "item", "entry":
                append(item)
                currentItem = nil
                currentElement = ""
                currentText = ""
                return
            default:
                break
            }
            currentItem = item
        } else if name == "title", feedTitle.isEmpty {
            feedTitle = value
        }

        currentElement = ""
        currentText = ""
    }

    private func append(_ builder: ItemBuilder) {
        let link = Self.normalizedURLString(builder.link)
        let enclosure = Self.normalizedURLString(builder.enclosureURL)
        let downloadURL = enclosure ?? link.flatMap {
            Self.isDirectDownloadCandidate($0) ? $0 : nil
        }
        let identifier = [
            builder.identifier.trimmed,
            downloadURL ?? "",
            link ?? "",
            builder.title.trimmed,
            builder.publishedAt?.timeIntervalSince1970.description ?? ""
        ].first { !$0.isEmpty } ?? UUID().uuidString

        guard !builder.title.trimmed.isEmpty || link != nil || downloadURL != nil else {
            return
        }
        items.append(
            RSSFeedItem(
                id: identifier,
                title: builder.title.trimmed,
                link: link,
                downloadURL: downloadURL,
                publishedAt: builder.publishedAt
            )
        )
    }

    private static func normalizedName(_ name: String) -> String {
        name
            .split(separator: ":")
            .last
            .map(String.init)?
            .lowercased()
            ?? name.lowercased()
    }

    private static func normalizedURLString(_ value: String?) -> String? {
        guard let normalized = value?.trimmed, !normalized.isEmpty else {
            return nil
        }
        guard let scheme = URL(string: normalized)?.scheme?.lowercased(),
              ["http", "https", "ftp", "sftp", "magnet"].contains(scheme) else {
            return nil
        }
        return normalized
    }

    private static func isDirectDownloadCandidate(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        if ["magnet", "ftp", "sftp"].contains(url.scheme?.lowercased() ?? "") {
            return true
        }
        let extensions = [
            "torrent", "metalink", "meta4", "zip", "7z", "rar", "tar", "gz",
            "bz2", "xz", "dmg", "pkg", "iso", "mp4", "mkv", "mp3", "flac",
            "pdf", "epub"
        ]
        return extensions.contains(url.pathExtension.lowercased())
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        for formatter in dateFormatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static let dateFormatters: [DateFormatter] = {
        [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss Z"
        ].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()
}
