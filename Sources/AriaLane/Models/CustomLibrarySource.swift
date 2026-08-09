import Foundation

struct CustomLibrarySource: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var searchURLTemplate: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        searchURLTemplate: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.searchURLTemplate = searchURLTemplate
        self.isEnabled = isEnabled
    }

    var displayName: String {
        let value = name.trimmed
        return value.isEmpty ? L10n.string("未命名来源") : value
    }

    var endpointSummary: String {
        guard let url = try? searchURL(query: "catalog") else {
            return searchURLTemplate.trimmed
        }
        return url.host ?? url.absoluteString
    }

    func validated() throws -> CustomLibrarySource {
        var source = self
        source.name = name.trimmed
        source.searchURLTemplate = searchURLTemplate.trimmed

        guard !source.name.isEmpty else {
            throw CustomLibrarySourceValidationError.emptyName
        }
        _ = try source.searchURL(query: "AriaLane")
        return source
    }

    func searchURL(query: String) throws -> URL {
        let query = query.trimmed
        guard !query.isEmpty else {
            throw CustomLibrarySourceValidationError.emptyQuery
        }

        let template = searchURLTemplate.trimmed
        guard !template.isEmpty else {
            throw CustomLibrarySourceValidationError.emptyTemplate
        }

        let token: String
        if template.contains("{query}") {
            token = "{query}"
        } else if template.contains("{searchTerms}") {
            token = "{searchTerms}"
        } else {
            throw CustomLibrarySourceValidationError.missingQueryPlaceholder
        }

        guard let encodedQuery = query.addingPercentEncoding(
            withAllowedCharacters: Self.unreservedCharacters
        ) else {
            throw CustomLibrarySourceValidationError.invalidURL
        }

        let rendered = template.replacingOccurrences(
            of: token,
            with: encodedQuery
        )
        guard let components = URLComponents(string: rendered),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              let url = components.url else {
            if URLComponents(string: rendered)?.user != nil
                || URLComponents(string: rendered)?.password != nil {
                throw CustomLibrarySourceValidationError.credentialsNotAllowed
            }
            throw CustomLibrarySourceValidationError.invalidURL
        }

        guard scheme == "https" || scheme == "http" else {
            throw CustomLibrarySourceValidationError.unsupportedScheme
        }
        if scheme == "http", !Self.isLoopbackHost(host) {
            throw CustomLibrarySourceValidationError.insecureRemoteHTTP
        }
        return url
    }

    private static let unreservedCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-._~"))

    private static func isLoopbackHost(_ host: String) -> Bool {
        host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host.hasSuffix(".localhost")
    }
}

enum CustomLibrarySourceValidationError: LocalizedError, Equatable {
    case emptyName
    case emptyQuery
    case emptyTemplate
    case missingQueryPlaceholder
    case invalidURL
    case credentialsNotAllowed
    case unsupportedScheme
    case insecureRemoteHTTP

    var errorDescription: String? {
        switch self {
        case .emptyName:
            L10n.string("请输入来源名称")
        case .emptyQuery:
            L10n.string("请输入书名、作者或主题")
        case .emptyTemplate:
            L10n.string("请输入 OPDS 搜索地址")
        case .missingQueryPlaceholder:
            L10n.string("搜索地址必须包含 {query} 占位符")
        case .invalidURL:
            L10n.string("OPDS 搜索地址无效")
        case .credentialsNotAllowed:
            L10n.string("搜索地址不能包含用户名或密码")
        case .unsupportedScheme:
            L10n.string("OPDS 搜索地址只支持 HTTPS，或本机 HTTP")
        case .insecureRemoteHTTP:
            L10n.string("远程 OPDS 来源必须使用 HTTPS")
        }
    }
}
