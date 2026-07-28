import Foundation

struct RSSSubscriptionRepository {
    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    func loadResult() throws -> ArchiveLoadResult<RSSSubscriptionArchive> {
        try SecureJSONArchive.load(
            RSSSubscriptionArchive.self,
            from: fileURL,
            default: RSSSubscriptionArchive()
        )
    }

    func save(_ archive: RSSSubscriptionArchive) throws {
        try SecureJSONArchive.save(archive, to: fileURL)
    }

    static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("AriaLane", isDirectory: true)
            .appendingPathComponent("rss-subscriptions.json")
    }
}
