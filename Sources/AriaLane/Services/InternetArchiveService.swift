import Foundation

enum InternetArchiveServiceError: LocalizedError {
    case invalidQuery
    case unsupportedResponse
    case httpStatus(Int)
    case responseTooLarge
    case invalidData
    case restrictedItem
    case unverifiedLicense

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            L10n.string("请输入书名、作者或主题")
        case .unsupportedResponse:
            L10n.string("Internet Archive 返回了无法识别的响应")
        case .httpStatus(let status):
            L10n.string("Internet Archive 返回 HTTP \(status)")
        case .responseTooLarge:
            L10n.string("Internet Archive 响应过大，已停止读取")
        case .invalidData:
            L10n.string("Internet Archive 数据格式无效")
        case .restrictedItem:
            L10n.string("此馆藏受限，不能直接加入下载")
        case .unverifiedLicense:
            L10n.string("无法确认此馆藏的开放许可，已停用直接下载")
        }
    }
}

struct InternetArchiveService {
    private static let searchResponseLimit = 3 * 1_024 * 1_024
    private static let metadataResponseLimit = 16 * 1_024 * 1_024

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String, limit: Int = 30) async throws -> LibraryResourceSearchPage {
        guard let url = Self.searchURL(query: query, limit: limit) else {
            throw InternetArchiveServiceError.invalidQuery
        }
        let data = try await fetch(url, maximumSize: Self.searchResponseLimit)
        return try Self.decodeSearchPage(data)
    }

    func downloads(identifier: String) async throws -> LibraryResourceDownloads {
        let baseURL = URL(string: "https://archive.org")!
        let url = baseURL
            .appendingPathComponent("metadata")
            .appendingPathComponent(identifier)
        let data = try await fetch(url, maximumSize: Self.metadataResponseLimit)
        return try Self.decodeDownloads(data, identifier: identifier)
    }

    static func searchURL(query: String, limit: Int = 30) -> URL? {
        let terms = query
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(12)
            .map { "\"\(escapeSolrQuotedTerm(String($0)))\"" }
        guard !terms.isEmpty else { return nil }

        let termExpression = terms.joined(separator: " AND ")
        let archiveQuery = """
        (title:(\(termExpression)) OR creator:(\(termExpression)) OR subject:(\(termExpression))) AND mediatype:texts AND licenseurl:(*creativecommons.org*)
        """

        var components = URLComponents()
        components.scheme = "https"
        components.host = "archive.org"
        components.path = "/advancedsearch.php"
        components.queryItems = [
            URLQueryItem(name: "q", value: archiveQuery),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "creator"),
            URLQueryItem(name: "fl[]", value: "date"),
            URLQueryItem(name: "fl[]", value: "year"),
            URLQueryItem(name: "fl[]", value: "language"),
            URLQueryItem(name: "fl[]", value: "licenseurl"),
            URLQueryItem(name: "rows", value: String(min(max(limit, 1), 50))),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "output", value: "json")
        ]
        return components.url
    }

    static func decodeSearchPage(_ data: Data) throws -> LibraryResourceSearchPage {
        let payload: IAAdvancedSearchPayload
        do {
            payload = try JSONDecoder().decode(IAAdvancedSearchPayload.self, from: data)
        } catch {
            throw InternetArchiveServiceError.invalidData
        }

        var seen = Set<String>()
        let resources = payload.response.docs.compactMap { document -> LibraryResource? in
            guard seen.insert(document.identifier).inserted,
                  let licenseURL = creativeCommonsLicenseURL(
                    from: document.licenseURL?.values ?? []
                  ) else {
                return nil
            }

            return LibraryResource(
                provider: .internetArchive,
                sourceIdentifier: document.identifier,
                title: document.title?.value.trimmed.isEmpty == false
                    ? document.title!.value.trimmed
                    : document.identifier,
                creators: document.creator?.values ?? [],
                year: displayYear(year: document.year?.value, date: document.date?.value),
                languages: document.language?.values ?? [],
                rightsTitle: LibraryLicense.title(for: licenseURL),
                licenseURL: licenseURL,
                detailsURL: URL(string: "https://archive.org")!
                    .appendingPathComponent("details")
                    .appendingPathComponent(document.identifier),
                thumbnailURL: URL(string: "https://archive.org")!
                    .appendingPathComponent("services")
                    .appendingPathComponent("img")
                    .appendingPathComponent(document.identifier),
                downloadLocator: .internetArchive(document.identifier)
            )
        }

        return LibraryResourceSearchPage(
            resources: resources,
            totalCount: payload.response.numFound
        )
    }

    static func decodeDownloads(
        _ data: Data,
        identifier: String
    ) throws -> LibraryResourceDownloads {
        let payload: IAMetadataPayload
        do {
            payload = try JSONDecoder().decode(IAMetadataPayload.self, from: data)
        } catch {
            throw InternetArchiveServiceError.invalidData
        }

        guard payload.isDark?.value != true,
              payload.noDownload?.value != true,
              payload.metadata.accessRestrictedItem?.value != true,
              payload.metadata.noDownload?.value != true else {
            throw InternetArchiveServiceError.restrictedItem
        }

        guard let licenseURL = creativeCommonsLicenseURL(
            from: payload.metadata.licenseURL?.values ?? []
        ) else {
            throw InternetArchiveServiceError.unverifiedLicense
        }

        let downloadRoot = URL(string: "https://archive.org")!
            .appendingPathComponent("download")
            .appendingPathComponent(identifier)

        let rankedOptions = payload.files.compactMap { file -> RankedDownloadOption? in
            guard file.isPrivate?.value != true,
                  file.source?.lowercased() != "metadata",
                  !file.name.hasPrefix("__"),
                  let descriptor = downloadDescriptor(
                    fileName: file.name,
                    archiveFormat: file.format
                  ) else {
                return nil
            }

            return RankedDownloadOption(
                option: LibraryDownloadOption(
                    fileName: file.name,
                    formatTitle: descriptor.title,
                    byteCount: file.size.flatMap(Int64.init),
                    url: downloadRoot.appendingPathComponent(file.name)
                ),
                priority: descriptor.priority,
                isOriginal: file.source?.lowercased() == "original"
            )
        }

        var seenNames = Set<String>()
        let options = rankedOptions
            .sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                if $0.isOriginal != $1.isOriginal { return $0.isOriginal }
                return $0.option.fileName.localizedStandardCompare(
                    $1.option.fileName
                ) == .orderedAscending
            }
            .compactMap { ranked -> LibraryDownloadOption? in
                guard seenNames.insert(ranked.option.fileName).inserted else {
                    return nil
                }
                return ranked.option
            }

        return LibraryResourceDownloads(
            rightsTitle: LibraryLicense.title(for: licenseURL),
            licenseURL: licenseURL,
            options: options
        )
    }

    private func fetch(_ url: URL, maximumSize: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue(
            "AriaLane/1.0 (+Internet Archive resource search)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InternetArchiveServiceError.unsupportedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw InternetArchiveServiceError.httpStatus(httpResponse.statusCode)
        }
        guard data.count <= maximumSize else {
            throw InternetArchiveServiceError.responseTooLarge
        }
        return data
    }

    private static func escapeSolrQuotedTerm(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func creativeCommonsLicenseURL(from values: [String]) -> URL? {
        values.compactMap(URL.init(string:)).first { url in
            guard let host = url.host?.lowercased(),
                  host == "creativecommons.org"
                    || host.hasSuffix(".creativecommons.org") else {
                return false
            }
            let path = url.path.lowercased()
            return path.hasPrefix("/licenses/") || path.hasPrefix("/publicdomain/")
        }
    }

    private static func displayYear(year: String?, date: String?) -> String? {
        if let year = year?.trimmed, !year.isEmpty {
            return String(year.prefix(4))
        }
        guard let date = date?.trimmed, !date.isEmpty else { return nil }
        let prefix = String(date.prefix(4))
        return prefix.allSatisfy(\.isNumber) ? prefix : nil
    }

    private static func downloadDescriptor(
        fileName: String,
        archiveFormat: String?
    ) -> (title: String, priority: Int)? {
        let fileExtension = URL(fileURLWithPath: fileName)
            .pathExtension
            .lowercased()
        let format = archiveFormat?.lowercased() ?? ""
        guard !format.contains("metadata") else { return nil }

        switch fileExtension {
        case "epub": return ("EPUB", 0)
        case "pdf": return ("PDF", 1)
        case "mobi": return ("MOBI", 2)
        case "azw3": return ("AZW3", 3)
        case "djvu": return ("DjVu", 4)
        case "txt": return (L10n.string("纯文本"), 5)
        case "rtf": return ("RTF", 6)
        default: return nil
        }
    }
}

private struct RankedDownloadOption {
    let option: LibraryDownloadOption
    let priority: Int
    let isOriginal: Bool
}

private struct IAAdvancedSearchPayload: Decodable {
    struct Response: Decodable {
        let numFound: Int
        let docs: [Document]
    }

    struct Document: Decodable {
        let identifier: String
        let title: FlexibleString?
        let creator: FlexibleStringList?
        let date: FlexibleString?
        let year: FlexibleString?
        let language: FlexibleStringList?
        let licenseURL: FlexibleStringList?

        enum CodingKeys: String, CodingKey {
            case identifier
            case title
            case creator
            case date
            case year
            case language
            case licenseURL = "licenseurl"
        }
    }

    let response: Response
}

private struct IAMetadataPayload: Decodable {
    struct Metadata: Decodable {
        let licenseURL: FlexibleStringList?
        let accessRestrictedItem: FlexibleBool?
        let noDownload: FlexibleBool?

        enum CodingKeys: String, CodingKey {
            case licenseURL = "licenseurl"
            case accessRestrictedItem = "access-restricted-item"
            case noDownload = "no-download"
            case noDownloadCompact = "nodownload"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            licenseURL = try container.decodeIfPresent(
                FlexibleStringList.self,
                forKey: .licenseURL
            )
            accessRestrictedItem = try container.decodeIfPresent(
                FlexibleBool.self,
                forKey: .accessRestrictedItem
            )
            noDownload = try container.decodeIfPresent(
                FlexibleBool.self,
                forKey: .noDownload
            ) ?? container.decodeIfPresent(
                FlexibleBool.self,
                forKey: .noDownloadCompact
            )
        }
    }

    struct File: Decodable {
        let name: String
        let source: String?
        let format: String?
        let size: String?
        let isPrivate: FlexibleBool?

        enum CodingKeys: String, CodingKey {
            case name
            case source
            case format
            case size
            case isPrivate = "private"
        }
    }

    let files: [File]
    let metadata: Metadata
    let isDark: FlexibleBool?
    let noDownload: FlexibleBool?

    enum CodingKeys: String, CodingKey {
        case files
        case metadata
        case isDark = "is_dark"
        case noDownload = "nodownload"
    }
}

private struct FlexibleStringList: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let values = try? container.decode([String].self) {
            self.values = values
            return
        }
        if let value = try? container.decode(String.self) {
            values = [value]
            return
        }
        if let values = try? container.decode([Int].self) {
            self.values = values.map(String.init)
            return
        }
        if let value = try? container.decode(Int.self) {
            values = [String(value)]
            return
        }
        throw DecodingError.typeMismatch(
            [String].self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected a string or an array of strings"
            )
        )
    }
}

private struct FlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = String(value)
        } else if let values = try? container.decode([String].self),
                  let value = values.first {
            self.value = value
        } else if let values = try? container.decode([Int].self),
                  let value = values.first {
            self.value = String(value)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a string or integer"
                )
            )
        }
    }
}

private struct FlexibleBool: Decodable {
    let value: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = value != 0
        } else if let value = try? container.decode(String.self) {
            self.value = ["1", "true", "yes"].contains(value.lowercased())
        } else {
            throw DecodingError.typeMismatch(
                Bool.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a boolean-compatible value"
                )
            )
        }
    }
}
