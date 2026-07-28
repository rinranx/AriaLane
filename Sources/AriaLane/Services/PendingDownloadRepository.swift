import Foundation

struct PendingDownloadRepository {
    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() throws -> PendingDownloadArchive {
        try loadResult().value
    }

    func loadResult() throws -> ArchiveLoadResult<PendingDownloadArchive> {
        try SecureJSONArchive.load(
            PendingDownloadArchive.self,
            from: fileURL,
            default: PendingDownloadArchive()
        )
    }

    func save(_ archive: PendingDownloadArchive) throws {
        try SecureJSONArchive.save(archive, to: fileURL)
        if archive.entries.isEmpty {
            try? FileManager.default.removeItem(
                at: SecureJSONArchive.backupURL(for: fileURL)
            )
        }
    }

    static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("AriaLane", isDirectory: true)
            .appendingPathComponent("pending-downloads.json")
    }
}
