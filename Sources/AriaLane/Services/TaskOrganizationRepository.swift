import Foundation

struct TaskOrganizationRepository {
    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    func loadResult() throws -> ArchiveLoadResult<TaskOrganizationArchive> {
        try SecureJSONArchive.load(
            TaskOrganizationArchive.self,
            from: fileURL,
            default: TaskOrganizationArchive()
        )
    }

    func save(_ archive: TaskOrganizationArchive) throws {
        try SecureJSONArchive.save(archive, to: fileURL)
    }

    static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("AriaLane", isDirectory: true)
            .appendingPathComponent("task-organization.json")
    }
}
