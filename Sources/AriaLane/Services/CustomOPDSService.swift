import Foundation

enum CustomOPDSServiceError: LocalizedError {
    case unsupportedResponse
    case httpStatus(Int)
    case responseTooLarge
    case invalidCatalog
    case unsafeRedirect

    var errorDescription: String? {
        switch self {
        case .unsupportedResponse:
            L10n.string("OPDS 来源返回了无法识别的响应")
        case .httpStatus(let status):
            L10n.string("OPDS 来源返回 HTTP \(status)")
        case .responseTooLarge:
            L10n.string("OPDS 响应过大，已停止读取")
        case .invalidCatalog:
            L10n.string("OPDS 目录格式无效")
        case .unsafeRedirect:
            L10n.string("OPDS 来源重定向到了不安全的地址")
        }
    }
}

struct CustomOPDSService {
    private static let responseLimit = 8 * 1_024 * 1_024

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(
        source: CustomLibrarySource,
        query: String,
        limit: Int = 25
    ) async throws -> LibraryResourceSearchPage {
        let source = try source.validated()
        let url = try source.searchURL(query: query)
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue(
            "AriaLane/1.0 (+custom OPDS catalog search)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "application/atom+xml;profile=opds-catalog, application/atom+xml;q=0.9, application/xml;q=0.8",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CustomOPDSServiceError.unsupportedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CustomOPDSServiceError.httpStatus(httpResponse.statusCode)
        }
        guard Self.isAllowedCatalogURL(httpResponse.url) else {
            throw CustomOPDSServiceError.unsafeRedirect
        }
        guard data.count <= Self.responseLimit else {
            throw CustomOPDSServiceError.responseTooLarge
        }
        return try Self.decodeSearchPage(
            data,
            source: source,
            baseURL: httpResponse.url ?? url,
            limit: limit
        )
    }

    static func decodeSearchPage(
        _ data: Data,
        source: CustomLibrarySource,
        baseURL: URL,
        limit: Int = 25
    ) throws -> LibraryResourceSearchPage {
        let delegate = CustomOPDSParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            throw CustomOPDSServiceError.invalidCatalog
        }

        let resources = delegate.entries
            .prefix(min(max(limit, 1), 50))
            .compactMap { entry in
                resource(from: entry, source: source, baseURL: baseURL)
            }

        return LibraryResourceSearchPage(
            resources: resources,
            totalCount: delegate.totalResults ?? resources.count
        )
    }

    private static func resource(
        from entry: CustomOPDSEntry,
        source: CustomLibrarySource,
        baseURL: URL
    ) -> LibraryResource? {
        let title = entry.title.trimmed
        guard !title.isEmpty else { return nil }

        let detailsURL = preferredDetailsURL(entry.links, relativeTo: baseURL)
            ?? safeWebURL(entry.id, relativeTo: baseURL)
            ?? catalogFallbackURL(baseURL)
        let thumbnailURL = preferredImageURL(entry.links, relativeTo: baseURL)
        let verifiedRights = verifiedRights(for: entry, baseURL: baseURL)
        let options = downloadOptions(from: entry.links, relativeTo: baseURL)
        let rightsTitle = verifiedRights?.title
            ?? L10n.string("权利状态未验证")
        let downloads = LibraryResourceDownloads(
            rightsTitle: rightsTitle,
            licenseURL: verifiedRights?.licenseURL,
            options: options
        )
        let locator: LibraryDownloadLocator = verifiedRights != nil && !options.isEmpty
            ? .custom(downloads)
            : .unavailable
        let identifier = entry.id.trimmed.isEmpty
            ? "\(detailsURL.absoluteString)#\(title)"
            : entry.id.trimmed

        return LibraryResource(
            provider: .custom(source),
            sourceIdentifier: identifier,
            title: title,
            creators: uniqueNonempty(entry.creators),
            year: displayYear(entry.date),
            languages: Array(uniqueNonempty(entry.languages).prefix(6)),
            rightsTitle: rightsTitle,
            licenseURL: verifiedRights?.licenseURL,
            detailsURL: detailsURL,
            thumbnailURL: thumbnailURL,
            downloadLocator: locator
        )
    }

    private static func verifiedRights(
        for entry: CustomOPDSEntry,
        baseURL: URL
    ) -> CustomOPDSVerifiedRights? {
        let licenseURL = entry.links.first {
            relTokens($0.rel).contains("license")
        }.flatMap {
            safeWebURL($0.href, relativeTo: baseURL)
        }

        if let creativeCommonsURL = [licenseURL, safeWebURL(entry.rights, relativeTo: baseURL)]
            .compactMap({ $0 })
            .first(where: isCreativeCommonsURL) {
            return CustomOPDSVerifiedRights(
                title: LibraryLicense.title(for: creativeCommonsURL),
                licenseURL: creativeCommonsURL
            )
        }

        let rights = entry.rights.trimmed.lowercased()
        if rights.contains("public domain")
            || rights.contains("public-domain")
            || rights.contains("公版") {
            return CustomOPDSVerifiedRights(
                title: L10n.string("公版"),
                licenseURL: licenseURL
            )
        }
        if rights.contains("creative commons")
            || rights.contains("cc0")
            || rights.contains("cc by") {
            return CustomOPDSVerifiedRights(
                title: "Creative Commons",
                licenseURL: licenseURL
            )
        }
        return nil
    }

    private static func downloadOptions(
        from links: [CustomOPDSLink],
        relativeTo baseURL: URL
    ) -> [LibraryDownloadOption] {
        var seen = Set<URL>()
        return links.compactMap { link -> CustomOPDSRankedDownload? in
            guard isAcquisitionRel(link.rel),
                  let url = safeWebURL(link.href, relativeTo: baseURL),
                  seen.insert(url).inserted,
                  let descriptor = downloadDescriptor(
                    mediaType: link.mediaType,
                    url: url
                  ) else {
                return nil
            }
            let fileName = url.lastPathComponent.isEmpty
                ? L10n.string("下载文件")
                : url.lastPathComponent
            return CustomOPDSRankedDownload(
                option: LibraryDownloadOption(
                    fileName: fileName,
                    formatTitle: descriptor.title,
                    byteCount: link.length.flatMap(Int64.init),
                    url: url
                ),
                priority: descriptor.priority
            )
        }
        .sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.option.fileName.localizedStandardCompare(
                $1.option.fileName
            ) == .orderedAscending
        }
        .map(\.option)
    }

    private static func downloadDescriptor(
        mediaType: String?,
        url: URL
    ) -> (title: String, priority: Int)? {
        let normalizedType = mediaType?
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased()
        switch normalizedType {
        case "application/epub+zip": return ("EPUB", 0)
        case "application/pdf": return ("PDF", 1)
        case "application/x-mobipocket-ebook": return ("MOBI", 2)
        case "text/plain": return (L10n.string("纯文本"), 3)
        case "text/html", "application/xhtml+xml": return ("HTML", 4)
        default:
            switch url.pathExtension.lowercased() {
            case "epub": return ("EPUB", 0)
            case "pdf": return ("PDF", 1)
            case "mobi": return ("MOBI", 2)
            case "azw3": return ("AZW3", 3)
            case "txt": return (L10n.string("纯文本"), 4)
            case "html", "htm": return ("HTML", 5)
            default: return nil
            }
        }
    }

    private static func preferredDetailsURL(
        _ links: [CustomOPDSLink],
        relativeTo baseURL: URL
    ) -> URL? {
        for preferredRel in ["alternate", "subsection", "self"] {
            if let url = links.first(where: {
                relTokens($0.rel).contains(preferredRel)
            }).flatMap({ safeWebURL($0.href, relativeTo: baseURL) }) {
                return url
            }
        }
        return nil
    }

    private static func preferredImageURL(
        _ links: [CustomOPDSLink],
        relativeTo baseURL: URL
    ) -> URL? {
        let thumbnail = links.first {
            relTokens($0.rel).contains { $0.contains("image/thumbnail") }
        }
        let image = links.first {
            relTokens($0.rel).contains { token in
                token == "image" || token.hasSuffix("/image")
            }
        }
        return (thumbnail ?? image).flatMap {
            safeWebURL($0.href, relativeTo: baseURL)
        }
    }

    private static func safeWebURL(_ value: String, relativeTo baseURL: URL) -> URL? {
        guard !value.trimmed.isEmpty,
              let url = URL(string: value.trimmed, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }

    private static func catalogFallbackURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    private static func relTokens(_ value: String) -> [String] {
        value.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func isAcquisitionRel(_ value: String) -> Bool {
        relTokens(value).contains { $0.contains("acquisition") }
    }

    private static func isCreativeCommonsURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "creativecommons.org"
            || host.hasSuffix(".creativecommons.org")
    }

    private static func displayYear(_ value: String?) -> String? {
        guard let value = value?.trimmed, !value.isEmpty else { return nil }
        for component in value.split(whereSeparator: { !$0.isNumber }) {
            if component.count == 4 { return String(component) }
        }
        return nil
    }

    private static func uniqueNonempty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap {
            let value = $0.trimmed
            guard !value.isEmpty,
                  seen.insert(value.localizedLowercase).inserted else {
                return nil
            }
            return value
        }
    }

    private static func isAllowedCatalogURL(_ url: URL?) -> Bool {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              url.user == nil,
              url.password == nil else {
            return false
        }
        if scheme == "https" { return true }
        return scheme == "http"
            && (host == "localhost"
                || host == "127.0.0.1"
                || host == "::1"
                || host.hasSuffix(".localhost"))
    }
}

private struct CustomOPDSLink {
    let rel: String
    let mediaType: String?
    let href: String
    let title: String?
    let length: String?
}

private struct CustomOPDSEntry {
    let id: String
    let title: String
    let creators: [String]
    let date: String?
    let languages: [String]
    let rights: String
    let links: [CustomOPDSLink]
}

private struct CustomOPDSVerifiedRights {
    let title: String
    let licenseURL: URL?
}

private struct CustomOPDSRankedDownload {
    let option: LibraryDownloadOption
    let priority: Int
}

private final class CustomOPDSParserDelegate: NSObject, XMLParserDelegate {
    private struct Builder {
        var id = ""
        var title = ""
        var creators: [String] = []
        var date: String?
        var languages: [String] = []
        var rights = ""
        var links: [CustomOPDSLink] = []
    }

    private(set) var entries: [CustomOPDSEntry] = []
    private(set) var totalResults: Int?
    private var builder: Builder?
    private var elementNames: [String] = []
    private var elementTexts: [String] = []
    private var isInsideAuthor = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalizedCustomOPDSName(qName ?? elementName)
        elementNames.append(name)
        elementTexts.append("")

        if name == "entry" {
            builder = Builder()
        } else if name == "author", builder != nil {
            isInsideAuthor = true
        } else if name == "link", var builder,
                  let href = attributeDict["href"] {
            builder.links.append(
                CustomOPDSLink(
                    rel: attributeDict["rel"] ?? "",
                    mediaType: attributeDict["type"],
                    href: href,
                    title: attributeDict["title"],
                    length: attributeDict["length"]
                )
            )
            self.builder = builder
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !elementTexts.isEmpty else { return }
        elementTexts[elementTexts.count - 1] += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = normalizedCustomOPDSName(qName ?? elementName)
        let value = elementTexts.popLast()?.trimmed ?? ""
        _ = elementNames.popLast()

        if var builder {
            switch name {
            case "id": builder.id += value
            case "title": builder.title += value
            case "name" where isInsideAuthor:
                if !value.isEmpty { builder.creators.append(value) }
            case "creator":
                if !value.isEmpty { builder.creators.append(value) }
            case "published", "issued", "date":
                if builder.date == nil, !value.isEmpty { builder.date = value }
            case "language":
                if !value.isEmpty { builder.languages.append(value) }
            case "rights": builder.rights += value
            case "author": isInsideAuthor = false
            case "entry":
                entries.append(
                    CustomOPDSEntry(
                        id: builder.id.trimmed,
                        title: builder.title.trimmed,
                        creators: builder.creators,
                        date: builder.date,
                        languages: builder.languages,
                        rights: builder.rights.trimmed,
                        links: builder.links
                    )
                )
                self.builder = nil
                isInsideAuthor = false
                return
            default: break
            }
            self.builder = builder
        } else if name == "totalresults", let value = Int(value) {
            totalResults = value
        }
    }
}

private func normalizedCustomOPDSName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init)?.lowercased()
        ?? name.lowercased()
}
