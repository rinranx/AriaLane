import Foundation

enum OpenLibraryServiceError: LocalizedError {
    case invalidQuery
    case unsupportedResponse
    case httpStatus(Int)
    case responseTooLarge
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            L10n.string("请输入书名、作者或主题")
        case .unsupportedResponse:
            L10n.string("Open Library 返回了无法识别的响应")
        case .httpStatus(let status):
            L10n.string("Open Library 返回 HTTP \(status)")
        case .responseTooLarge:
            L10n.string("Open Library 响应过大，已停止读取")
        case .invalidData:
            L10n.string("Open Library 数据格式无效")
        }
    }
}

struct OpenLibraryService {
    private static let responseLimit = 6 * 1_024 * 1_024
    private static let baseURL = URL(string: "https://openlibrary.org")!

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String, limit: Int = 25) async throws -> LibraryResourceSearchPage {
        guard let url = Self.searchURL(query: query, limit: limit) else {
            throw OpenLibraryServiceError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue(
            "AriaLane/1.0 (+Open Library catalog search)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenLibraryServiceError.unsupportedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenLibraryServiceError.httpStatus(httpResponse.statusCode)
        }
        guard data.count <= Self.responseLimit else {
            throw OpenLibraryServiceError.responseTooLarge
        }
        return try Self.decodeSearchPage(data)
    }

    static func searchURL(query: String, limit: Int = 25) -> URL? {
        let query = query.trimmed
        guard !query.isEmpty else { return nil }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("search.json"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: "\(query) ebook_access:public"),
            URLQueryItem(
                name: "fields",
                value: [
                    "key",
                    "title",
                    "author_name",
                    "first_publish_year",
                    "cover_i",
                    "ebook_access",
                    "language",
                    "editions",
                    "editions.key",
                    "editions.ebook_access",
                    "editions.ia"
                ].joined(separator: ",")
            ),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
            URLQueryItem(
                name: "lang",
                value: L10n.resolvedLanguage == .simplifiedChinese ? "zh" : "en"
            )
        ]
        return components?.url
    }

    static func decodeSearchPage(_ data: Data) throws -> LibraryResourceSearchPage {
        let payload: OpenLibrarySearchPayload
        do {
            payload = try JSONDecoder().decode(OpenLibrarySearchPayload.self, from: data)
        } catch {
            throw OpenLibraryServiceError.invalidData
        }

        let resources = payload.docs.compactMap { document -> LibraryResource? in
            guard document.ebookAccess?.lowercased() == "public",
                  let detailsURL = detailsURL(for: document.key) else {
                return nil
            }

            let publicEdition = document.editions?.docs.first {
                $0.ebookAccess?.lowercased() == "public"
            }
            let archiveIdentifier = publicEdition?.internetArchiveIDs?
                .map(\.trimmed)
                .first { !$0.isEmpty }
            let locator = archiveIdentifier.map(LibraryDownloadLocator.internetArchive)
                ?? .unavailable
            let title = document.title?.trimmed
            let displayTitle = title.flatMap { $0.isEmpty ? nil : $0 }
                ?? document.key

            return LibraryResource(
                provider: .openLibrary,
                sourceIdentifier: document.key,
                title: displayTitle,
                creators: document.authorNames ?? [],
                year: document.firstPublishYear?.value,
                languages: Array((document.languages ?? []).prefix(6)),
                rightsTitle: L10n.string("公开阅读"),
                licenseURL: nil,
                detailsURL: detailsURL,
                thumbnailURL: document.coverID.map(coverURL),
                downloadLocator: locator
            )
        }

        return LibraryResourceSearchPage(
            resources: resources,
            totalCount: payload.numFound
        )
    }

    private static func detailsURL(for key: String) -> URL? {
        let path: String
        if key.hasPrefix("/works/") || key.hasPrefix("/books/") {
            path = key
        } else if key.hasPrefix("OL"), key.hasSuffix("W") {
            path = "/works/\(key)"
        } else if key.hasPrefix("OL"), key.hasSuffix("M") {
            path = "/books/\(key)"
        } else {
            return nil
        }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    private static func coverURL(_ coverID: Int) -> URL {
        URL(string: "https://covers.openlibrary.org")!
            .appendingPathComponent("b")
            .appendingPathComponent("id")
            .appendingPathComponent("\(coverID)-M.jpg")
    }
}

private struct OpenLibrarySearchPayload: Decodable {
    struct Document: Decodable {
        struct Editions: Decodable {
            struct Edition: Decodable {
                let ebookAccess: String?
                let internetArchiveIDs: [String]?

                enum CodingKeys: String, CodingKey {
                    case ebookAccess = "ebook_access"
                    case internetArchiveIDs = "ia"
                }
            }

            let docs: [Edition]
        }

        let key: String
        let title: String?
        let authorNames: [String]?
        let firstPublishYear: OpenLibraryFlexibleString?
        let coverID: Int?
        let ebookAccess: String?
        let languages: [String]?
        let editions: Editions?

        enum CodingKeys: String, CodingKey {
            case key
            case title
            case authorNames = "author_name"
            case firstPublishYear = "first_publish_year"
            case coverID = "cover_i"
            case ebookAccess = "ebook_access"
            case languages = "language"
            case editions
        }
    }

    let numFound: Int
    let docs: [Document]

    private enum CodingKeys: String, CodingKey {
        case numFound
        case numFoundSnake = "num_found"
        case docs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(Int.self, forKey: .numFound) {
            numFound = value
        } else if let value = try container.decodeIfPresent(
            Int.self,
            forKey: .numFoundSnake
        ) {
            numFound = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.numFound,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected numFound or num_found"
                )
            )
        }
        docs = try container.decode([Document].self, forKey: .docs)
    }
}

private struct OpenLibraryFlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
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
