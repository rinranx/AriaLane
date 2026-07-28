import Foundation

struct DownloadScheduleRepository {
    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() throws -> DownloadScheduleArchive {
        try loadResult().value
    }

    func loadResult() throws -> ArchiveLoadResult<DownloadScheduleArchive> {
        try SecureJSONArchive.load(
            DownloadScheduleArchive.self,
            from: fileURL,
            default: DownloadScheduleArchive()
        )
    }

    func save(_ archive: DownloadScheduleArchive) throws {
        try SecureJSONArchive.save(archive, to: fileURL)
    }

    static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("AriaLane", isDirectory: true)
            .appendingPathComponent("download-schedule.json")
    }
}
