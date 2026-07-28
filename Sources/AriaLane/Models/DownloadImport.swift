import Foundation

enum DownloadImportKind: String, Sendable {
    case torrent
    case metalink

    static let supportedExtensions = Set(["torrent", "metalink", "meta4"])

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "torrent":
            self = .torrent
        case "metalink", "meta4":
            self = .metalink
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .torrent: "Torrent"
        case .metalink: "Metalink"
        }
    }

    var systemImage: String {
        switch self {
        case .torrent: "point.3.connected.trianglepath.dotted"
        case .metalink: "link.badge.plus"
        }
    }
}

struct ImportedFileChoice: Identifiable, Equatable, Sendable {
    let gid: String
    let index: Int
    let path: String
    let byteCount: Int64
    var isSelected: Bool

    var id: String { "\(gid):\(index)" }

    var displayPath: String {
        let components = URL(fileURLWithPath: path).pathComponents
        guard components.count > 2 else {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return components.suffix(2).joined(separator: "/")
    }
}

struct PendingDownloadImport: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceURL: URL
    let kind: DownloadImportKind
    let title: String
    let gids: [String]
    let files: [ImportedFileChoice]

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        kind: DownloadImportKind,
        title: String,
        gids: [String],
        files: [ImportedFileChoice]
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.kind = kind
        self.title = title
        self.gids = gids
        self.files = files
    }

    var totalByteCount: Int64 {
        files.reduce(Int64(0)) { $0 + $1.byteCount }
    }
}
