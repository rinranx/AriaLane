import Foundation

enum ProjectGutenbergServiceError: LocalizedError {
    case invalidQuery
    case unsupportedResponse
    case httpStatus(Int)
    case responseTooLarge
    case invalidData
    case notPublicDomain

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            L10n.string("请输入书名、作者或主题")
        case .unsupportedResponse:
            L10n.string("Project Gutenberg 返回了无法识别的响应")
        case .httpStatus(let status):
            L10n.string("Project Gutenberg 返回 HTTP \(status)")
        case .responseTooLarge:
            L10n.string("Project Gutenberg 响应过大，已停止读取")
        case .invalidData:
            L10n.string("Project Gutenberg 目录格式无效")
        case .notPublicDomain:
            L10n.string("此版本未明确标注为美国公版，已停用直接下载")
        }
    }
}

struct ProjectGutenbergService {
    private static let responseLimit = 8 * 1_024 * 1_024
    private static let baseURL = URL(string: "https://www.gutenberg.org")!

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String, limit: Int = 25) async throws -> LibraryResourceSearchPage {
        guard let url = Self.searchURL(query: query) else {
            throw ProjectGutenbergServiceError.invalidQuery
        }
        let data = try await fetch(url)
        return try Self.decodeSearchPage(data, limit: limit)
    }

    func downloads(bookID: String) async throws -> LibraryResourceDownloads {
        guard let url = Self.bookURL(bookID: bookID) else {
            throw ProjectGutenbergServiceError.invalidData
        }
        let data = try await fetch(url)
        return try Self.decodeDownloads(data, bookID: bookID)
    }

    static func searchURL(query: String) -> URL? {
        let query = query.trimmed
        guard !query.isEmpty else { return nil }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("ebooks/search.opds/"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "query", value: query)]
        return components?.url
    }

    static func bookURL(bookID: String) -> URL? {
        guard !bookID.isEmpty, bookID.allSatisfy(\.isNumber) else { return nil }
        return baseURL
            .appendingPathComponent("ebooks")
            .appendingPathComponent("\(bookID).opds")
    }

    static func decodeSearchPage(
        _ data: Data,
        limit: Int = 25
    ) throws -> LibraryResourceSearchPage {
        let parserDelegate = GutenbergSearchParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            throw ProjectGutenbergServiceError.invalidData
        }

        let resources = parserDelegate.entries
            .prefix(min(max(limit, 1), 25))
            .map { entry in
                LibraryResource(
                    provider: .projectGutenberg,
                    sourceIdentifier: entry.bookID,
                    title: entry.title,
                    creators: entry.creator.map { [$0] } ?? [],
                    year: nil,
                    languages: [],
                    rightsTitle: L10n.string("下载前验证权利"),
                    licenseURL: nil,
                    detailsURL: baseURL
                        .appendingPathComponent("ebooks")
                        .appendingPathComponent(entry.bookID),
                    thumbnailURL: nil,
                    downloadLocator: .projectGutenberg(entry.bookID)
                )
            }

        return LibraryResourceSearchPage(
            resources: resources,
            totalCount: resources.count
        )
    }

    static func decodeDownloads(
        _ data: Data,
        bookID: String
    ) throws -> LibraryResourceDownloads {
        let parserDelegate = GutenbergBookParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            throw ProjectGutenbergServiceError.invalidData
        }

        let publicDomainEntries = parserDelegate.entries.filter {
            $0.rights.localizedCaseInsensitiveContains("public domain")
        }
        guard !publicDomainEntries.isEmpty else {
            throw ProjectGutenbergServiceError.notPublicDomain
        }

        var seenURLs = Set<URL>()
        let rankedOptions = publicDomainEntries.flatMap(\.links).compactMap {
            link -> GutenbergRankedDownload? in
            guard let url = resolvedDownloadURL(link.href),
                  seenURLs.insert(url).inserted,
                  let descriptor = downloadDescriptor(
                    mediaType: link.mediaType,
                    title: link.title
                  ) else {
                return nil
            }

            return GutenbergRankedDownload(
                option: LibraryDownloadOption(
                    fileName: url.lastPathComponent,
                    formatTitle: descriptor.title,
                    byteCount: link.length.flatMap(Int64.init),
                    url: url
                ),
                priority: descriptor.priority
            )
        }

        let options = rankedOptions
            .sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                return $0.option.fileName.localizedStandardCompare(
                    $1.option.fileName
                ) == .orderedAscending
            }
            .map(\.option)

        return LibraryResourceDownloads(
            rightsTitle: L10n.string("美国公版"),
            licenseURL: URL(string: "https://www.gutenberg.org/policy/license.html"),
            options: options
        )
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue(
            "AriaLane/1.0 (+Project Gutenberg OPDS reader)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "application/atom+xml;profile=opds-catalog, application/atom+xml;q=0.9",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProjectGutenbergServiceError.unsupportedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProjectGutenbergServiceError.httpStatus(httpResponse.statusCode)
        }
        guard data.count <= Self.responseLimit else {
            throw ProjectGutenbergServiceError.responseTooLarge
        }
        return data
    }

    private static func resolvedDownloadURL(_ value: String) -> URL? {
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "www.gutenberg.org" || host == "gutenberg.org" else {
            return nil
        }
        return url
    }

    private static func downloadDescriptor(
        mediaType: String,
        title: String?
    ) -> (title: String, priority: Int)? {
        let normalizedType = mediaType
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased()
            ?? mediaType.lowercased()
        let normalizedTitle = title?.lowercased() ?? ""

        switch normalizedType {
        case "application/epub+zip":
            return (normalizedTitle.contains("epub3") ? "EPUB3" : "EPUB", 0)
        case "application/x-mobipocket-ebook":
            return ("Kindle", 1)
        case "text/plain":
            return (L10n.string("纯文本"), 2)
        case "text/html", "application/xhtml+xml":
            return ("HTML", 3)
        case "application/pdf":
            return ("PDF", 4)
        default:
            return nil
        }
    }
}

private struct GutenbergSearchEntry {
    let bookID: String
    let title: String
    let creator: String?
}

private final class GutenbergSearchParserDelegate: NSObject, XMLParserDelegate {
    private struct Builder {
        var id = ""
        var title = ""
        var content = ""
        var subsectionHref: String?
    }

    private(set) var entries: [GutenbergSearchEntry] = []
    private var builder: Builder?
    private var currentElement = ""
    private var currentText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalizedXMLName(qName ?? elementName)
        currentElement = name
        currentText = ""

        if name == "entry" {
            builder = Builder()
        } else if name == "link", builder != nil,
                  attributeDict["rel"] == "subsection" {
            builder?.subsectionHref = attributeDict["href"]
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
        let name = normalizedXMLName(qName ?? elementName)
        let value = currentText.trimmed

        if var builder {
            switch name {
            case "id": builder.id += value
            case "title": builder.title += value
            case "content": builder.content += value
            case "entry":
                append(builder)
                self.builder = nil
                currentElement = ""
                currentText = ""
                return
            default: break
            }
            self.builder = builder
        }

        currentElement = ""
        currentText = ""
    }

    private func append(_ builder: Builder) {
        guard let bookID = Self.bookID(from: builder.subsectionHref ?? builder.id),
              !builder.title.trimmed.isEmpty else {
            return
        }
        let content = builder.content.trimmed
        let creator = content.isEmpty
            || content.localizedCaseInsensitiveContains("downloads")
            ? nil
            : content
        entries.append(
            GutenbergSearchEntry(
                bookID: bookID,
                title: builder.title.trimmed,
                creator: creator
            )
        )
    }

    private static func bookID(from value: String) -> String? {
        let path = URL(string: value, relativeTo: URL(string: "https://www.gutenberg.org"))?
            .path ?? value
        guard let component = path.split(separator: "/").last else { return nil }
        let candidate = component.replacingOccurrences(of: ".opds", with: "")
        return candidate.allSatisfy(\.isNumber) ? candidate : nil
    }
}

private struct GutenbergAcquisitionLink {
    let mediaType: String
    let title: String?
    let length: String?
    let href: String
}

private struct GutenbergBookEntry {
    let rights: String
    let links: [GutenbergAcquisitionLink]
}

private final class GutenbergBookParserDelegate: NSObject, XMLParserDelegate {
    private struct Builder {
        var rights = ""
        var links: [GutenbergAcquisitionLink] = []
    }

    private(set) var entries: [GutenbergBookEntry] = []
    private var builder: Builder?
    private var currentText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalizedXMLName(qName ?? elementName)
        currentText = ""

        if name == "entry" {
            builder = Builder()
        } else if name == "link", var builder,
                  attributeDict["rel"]?.contains("acquisition") == true,
                  let mediaType = attributeDict["type"],
                  let href = attributeDict["href"] {
            builder.links.append(
                GutenbergAcquisitionLink(
                    mediaType: mediaType,
                    title: attributeDict["title"],
                    length: attributeDict["length"],
                    href: href
                )
            )
            self.builder = builder
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
        let name = normalizedXMLName(qName ?? elementName)
        if var builder {
            if name == "rights" {
                builder.rights += currentText.trimmed
                self.builder = builder
            } else if name == "entry" {
                entries.append(
                    GutenbergBookEntry(
                        rights: builder.rights.trimmed,
                        links: builder.links
                    )
                )
                self.builder = nil
            }
        }
        currentText = ""
    }
}

private struct GutenbergRankedDownload {
    let option: LibraryDownloadOption
    let priority: Int
}

private func normalizedXMLName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init)?.lowercased()
        ?? name.lowercased()
}
