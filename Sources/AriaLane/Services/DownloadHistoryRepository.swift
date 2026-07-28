import Foundation

struct DownloadHistoryRepository {
    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() throws -> DownloadHistoryArchive {
        try loadResult().value
    }

    func loadResult() throws -> ArchiveLoadResult<DownloadHistoryArchive> {
        try SecureJSONArchive.load(
            DownloadHistoryArchive.self,
            from: fileURL,
            default: DownloadHistoryArchive()
        )
    }

    func save(_ archive: DownloadHistoryArchive) throws {
        try SecureJSONArchive.save(archive, to: fileURL)
    }

    static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("AriaLane", isDirectory: true)
            .appendingPathComponent("download-history.json")
    }
}
