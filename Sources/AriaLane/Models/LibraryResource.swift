import Foundation

struct LibraryResourceProvider: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let systemImage: String

    static let internetArchive = LibraryResourceProvider(
        id: "internetArchive",
        title: "Internet Archive",
        systemImage: "building.columns"
    )
    static let projectGutenberg = LibraryResourceProvider(
        id: "projectGutenberg",
        title: "Project Gutenberg",
        systemImage: "book.closed"
    )
    static let openLibrary = LibraryResourceProvider(
        id: "openLibrary",
        title: "Open Library",
        systemImage: "books.vertical"
    )

    static let builtInCases: [LibraryResourceProvider] = [
        .internetArchive,
        .projectGutenberg,
        .openLibrary
    ]

    static func custom(_ source: CustomLibrarySource) -> LibraryResourceProvider {
        LibraryResourceProvider(
            id: "custom:\(source.id.uuidString.lowercased())",
            title: source.displayName,
            systemImage: "books.vertical.circle"
        )
    }
}

enum LibrarySearchScope: Identifiable, Equatable, Hashable, Sendable {
    case all
    case internetArchive
    case projectGutenberg
    case openLibrary
    case custom(UUID)

    static let builtInCases: [LibrarySearchScope] = [
        .all,
        .internetArchive,
        .projectGutenberg,
        .openLibrary
    ]

    var id: String { storageValue }

    var storageValue: String {
        switch self {
        case .all: "all"
        case .internetArchive: "internetArchive"
        case .projectGutenberg: "projectGutenberg"
        case .openLibrary: "openLibrary"
        case .custom(let id): "custom:\(id.uuidString.lowercased())"
        }
    }

    init(storageValue: String) {
        switch storageValue {
        case "internetArchive": self = .internetArchive
        case "projectGutenberg": self = .projectGutenberg
        case "openLibrary": self = .openLibrary
        default:
            if storageValue.hasPrefix("custom:"),
               let id = UUID(uuidString: String(storageValue.dropFirst(7))) {
                self = .custom(id)
            } else {
                self = .all
            }
        }
    }

    func title(customSources: [CustomLibrarySource]) -> String {
        switch self {
        case .all: L10n.string("全部来源")
        case .internetArchive: "Internet Archive"
        case .projectGutenberg: "Project Gutenberg"
        case .openLibrary: "Open Library"
        case .custom(let id):
            customSources.first { $0.id == id }?.displayName
                ?? L10n.string("自定义来源")
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .internetArchive: LibraryResourceProvider.internetArchive.systemImage
        case .projectGutenberg: LibraryResourceProvider.projectGutenberg.systemImage
        case .openLibrary: LibraryResourceProvider.openLibrary.systemImage
        case .custom: "books.vertical.circle"
        }
    }
}

enum LibraryDownloadLocator: Equatable, Sendable {
    case internetArchive(String)
    case projectGutenberg(String)
    case custom(LibraryResourceDownloads)
    case unavailable
}

struct LibraryResource: Identifiable, Equatable, Sendable {
    let provider: LibraryResourceProvider
    let sourceIdentifier: String
    let title: String
    let creators: [String]
    let year: String?
    let languages: [String]
    let rightsTitle: String
    let licenseURL: URL?
    let detailsURL: URL
    let thumbnailURL: URL?
    let downloadLocator: LibraryDownloadLocator

    var id: String { "\(provider.id):\(sourceIdentifier)" }

    var creatorLine: String {
        creators.isEmpty ? L10n.string("作者未知") : creators.joined(separator: ", ")
    }

    var canResolveDownloads: Bool {
        if case .unavailable = downloadLocator { return false }
        return true
    }
}

struct LibraryResourceSearchPage: Equatable, Sendable {
    let resources: [LibraryResource]
    let totalCount: Int
    var unavailableProviders: [LibraryResourceProvider] = []
}

struct LibraryDownloadOption: Identifiable, Equatable, Sendable {
    let fileName: String
    let formatTitle: String
    let byteCount: Int64?
    let url: URL

    var id: String { fileName }
}

struct LibraryResourceDownloads: Equatable, Sendable {
    let rightsTitle: String
    let licenseURL: URL?
    let options: [LibraryDownloadOption]
}

enum LibraryLicense {
    static func title(for url: URL) -> String {
        let components = url.pathComponents
            .filter { $0 != "/" }
            .map { $0.lowercased() }

        if let publicDomainIndex = components.firstIndex(of: "publicdomain"),
           components.indices.contains(publicDomainIndex + 1) {
            switch components[publicDomainIndex + 1] {
            case "zero": return "CC0"
            case "mark": return L10n.string("公版标记")
            default: break
            }
        }

        if let licensesIndex = components.firstIndex(of: "licenses"),
           components.indices.contains(licensesIndex + 1) {
            let code = components[licensesIndex + 1].uppercased()
            let version = components.indices.contains(licensesIndex + 2)
                ? " \(components[licensesIndex + 2])"
                : ""
            return "CC \(code)\(version)"
        }

        return L10n.string("开放许可")
    }
}
