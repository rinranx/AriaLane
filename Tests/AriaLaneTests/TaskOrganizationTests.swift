import Foundation
import XCTest
@testable import AriaLane

final class TaskOrganizationTests: XCTestCase {
    func testContentTypeUsesLargestSelectedFile() {
        let files = [
            TransferFile(
                index: "1",
                path: "/Downloads/readme.pdf",
                length: "100",
                completedLength: "100",
                selected: "true",
                uris: nil
            ),
            TransferFile(
                index: "2",
                path: "/Downloads/Movie.mkv",
                length: "5000",
                completedLength: "5000",
                selected: "true",
                uris: nil
            ),
            TransferFile(
                index: "3",
                path: "/Downloads/ignored.pkg",
                length: "9000",
                completedLength: "0",
                selected: "false",
                uris: nil
            )
        ]

        XCTAssertEqual(TaskContentType.classify(files: files), .video)
        XCTAssertEqual(TaskContentType.classify(path: "Xcode.xip"), .installer)
        XCTAssertEqual(TaskContentType.classify(path: "manual.docx"), .document)
    }

    func testSmartFolderCombinesContentProtocolDomainDateAndLifecycle() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let tagID = UUID()
        let key = TaskAttemptKey(serverProfileID: UUID(), gid: "gid")
        var entity = TaskEntityRecord(
            attempts: [key],
            primaryAttempt: key,
            name: "Xcode.dmg",
            sourceURI: "https://downloads.github.com/releases/Xcode.dmg",
            destinationPath: "/Downloads/Xcode.dmg",
            byteCount: 1024,
            contentType: .installer,
            transferProtocol: .http,
            lifecycle: .completed,
            addedAt: now.addingTimeInterval(-2 * 86_400),
            addedAtIsInferred: false,
            completedAt: now.addingTimeInterval(-86_400)
        )
        entity.tagIDs.insert(tagID)

        let folder = SmartFolder(
            name: "最近的 GitHub 安装包",
            matchMode: .all,
            rules: [
                SmartFolderRule(
                    field: .tag,
                    selectedValues: [tagID.uuidString]
                ),
                SmartFolderRule(
                    field: .contentType,
                    selectedValues: [TaskContentType.installer.rawValue]
                ),
                SmartFolderRule(
                    field: .transferProtocol,
                    selectedValues: [TaskTransferProtocol.http.rawValue]
                ),
                SmartFolderRule(
                    field: .sourceDomain,
                    comparison: .includesSubdomains,
                    textValue: "github.com"
                ),
                SmartFolderRule(
                    field: .addedDate,
                    comparison: .withinLastDays,
                    dayCount: 7
                ),
                SmartFolderRule(
                    field: .lifecycle,
                    selectedValues: [TaskLifecycle.completed.rawValue]
                )
            ]
        )

        XCTAssertTrue(folder.matches(entity, now: now))

        entity.transferProtocol = .torrent
        XCTAssertFalse(folder.matches(entity, now: now))
    }

    @MainActor
    func testLiveAndHistorySnapshotsStayOneTaggedEntity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriaLaneOrganization-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = TaskOrganizationRepository(
            fileURL: directory.appendingPathComponent("organization.json")
        )
        let store = TaskOrganizationStore(repository: repository)
        let profileID = UUID()
        let active = makeTransfer(
            gid: "same-task",
            status: .active,
            name: "Xcode.dmg",
            source: "https://github.com/apple/Xcode.dmg"
        )

        store.reconcile(
            transfers: [active],
            historyEntries: [],
            profileID: profileID,
            at: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(store.entities.count, 1)

        let entityID = try XCTUnwrap(store.entities.first?.id)
        let tag = try XCTUnwrap(store.createTag(name: "开发工具", color: .purple))
        store.addTag(tag.id, to: [entityID])

        let completed = makeTransfer(
            gid: "same-task",
            status: .complete,
            name: "Xcode.dmg",
            source: "https://github.com/apple/Xcode.dmg"
        )
        let history = try XCTUnwrap(
            DownloadHistoryEntry(
                item: completed,
                recordedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        store.reconcile(
            transfers: [completed],
            historyEntries: [history],
            profileID: profileID,
            at: Date(timeIntervalSince1970: 2_000)
        )
        store.reconcile(
            transfers: [],
            historyEntries: [history],
            profileID: profileID,
            at: Date(timeIntervalSince1970: 3_000)
        )

        XCTAssertEqual(store.entities.count, 1)
        XCTAssertEqual(store.entities.first?.id, entityID)
        XCTAssertEqual(store.entities.first?.contentType, .installer)
        XCTAssertEqual(store.entities.first?.lifecycle, .completed)
        XCTAssertEqual(store.entities.first?.tagIDs, Set([tag.id]))
        XCTAssertTrue(store.entities.first?.hasHistory == true)

        let folder = try XCTUnwrap(
            store.createSmartFolder(
                name: "GitHub 安装包",
                matchMode: .all,
                rules: [
                    SmartFolderRule(
                        field: .contentType,
                        selectedValues: [TaskContentType.installer.rawValue]
                    ),
                    SmartFolderRule(
                        field: .sourceDomain,
                        comparison: .includesSubdomains,
                        textValue: "github.com"
                    )
                ]
            )
        )
        XCTAssertEqual(store.count(for: folder), 1)

        let reloaded = TaskOrganizationStore(repository: repository)
        XCTAssertEqual(reloaded.entities.first?.id, entityID)
        XCTAssertEqual(reloaded.entities.first?.tagIDs, Set([tag.id]))
    }

    @MainActor
    func testRetryKeepsStableEntityAndTags() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriaLaneOrganizationRetry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TaskOrganizationStore(
            repository: TaskOrganizationRepository(
                fileURL: directory.appendingPathComponent("organization.json")
            )
        )
        let profileID = UUID()
        let pending = PendingDownload(
            url: "magnet:?xt=urn:btih:abc&dn=Example",
            taskOptions: .defaults(
                directory: "/Downloads",
                split: 4,
                maxConnectionPerServer: 4
            ),
            submissionGID: "old-gid",
            targetProfileID: profileID,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        store.registerSubmission(pending, activeProfileID: profileID)
        let entityID = try XCTUnwrap(store.entities.first?.id)
        let tag = try XCTUnwrap(store.createTag(name: "长期保留", color: .mint))
        store.addTag(tag.id, to: [entityID])

        store.registerRetry(
            from: "old-gid",
            to: "new-gid",
            sourceURI: pending.url,
            profileID: profileID
        )
        store.removeLiveAttempt(
            gid: "old-gid",
            profileID: profileID,
            historyGIDs: []
        )

        XCTAssertEqual(store.entities.count, 1)
        XCTAssertEqual(store.entities.first?.id, entityID)
        XCTAssertEqual(store.entities.first?.primaryAttempt?.gid, "new-gid")
        XCTAssertEqual(store.entities.first?.tagIDs, Set([tag.id]))
        XCTAssertEqual(store.entities.first?.transferProtocol, .magnet)
    }

    @MainActor
    func testRemovingOneRetryHistoryPreservesEntityAndTags() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriaLaneOrganizationHistory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TaskOrganizationStore(
            repository: TaskOrganizationRepository(
                fileURL: directory.appendingPathComponent("organization.json")
            )
        )
        let profileID = UUID()
        let oldTransfer = makeTransfer(
            gid: "old-gid",
            status: .error,
            name: "archive.zip",
            source: "https://example.com/archive.zip"
        )
        let oldHistory = try XCTUnwrap(DownloadHistoryEntry(item: oldTransfer))

        store.reconcile(
            transfers: [oldTransfer],
            historyEntries: [oldHistory],
            profileID: profileID
        )
        let entityID = try XCTUnwrap(store.entities.first?.id)
        let tag = try XCTUnwrap(store.createTag(name: "保留", color: .orange))
        store.addTag(tag.id, to: [entityID])

        store.registerRetry(
            from: "old-gid",
            to: "new-gid",
            sourceURI: "https://example.com/archive.zip",
            profileID: profileID
        )
        let newTransfer = makeTransfer(
            gid: "new-gid",
            status: .complete,
            name: "archive.zip",
            source: "https://example.com/archive.zip"
        )
        let newHistory = try XCTUnwrap(DownloadHistoryEntry(item: newTransfer))
        store.reconcile(
            transfers: [],
            historyEntries: [oldHistory, newHistory],
            profileID: profileID
        )

        store.removeHistory(
            gids: ["old-gid"],
            remainingHistoryGIDs: ["new-gid"]
        )

        XCTAssertEqual(store.entities.count, 1)
        XCTAssertEqual(store.entities.first?.id, entityID)
        XCTAssertEqual(store.entities.first?.tagIDs, Set([tag.id]))
        XCTAssertEqual(store.entities.first?.primaryAttempt?.gid, "new-gid")
        XCTAssertTrue(store.entities.first?.hasHistory == true)
    }

    @MainActor
    func testLiveTorrentMetadataUpgradesHTTPButKeepsMagnetProtocol() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriaLaneOrganizationProtocol-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TaskOrganizationStore(
            repository: TaskOrganizationRepository(
                fileURL: directory.appendingPathComponent("organization.json")
            )
        )
        let profileID = UUID()
        let options = DownloadTaskOptions.defaults(
            directory: "/Downloads",
            split: 4,
            maxConnectionPerServer: 4
        )
        store.registerSubmission(
            PendingDownload(
                url: "https://example.com/release.torrent",
                taskOptions: options,
                submissionGID: "http-torrent",
                targetProfileID: profileID
            ),
            activeProfileID: profileID
        )
        store.registerSubmission(
            PendingDownload(
                url: "magnet:?xt=urn:btih:abc&dn=Release",
                taskOptions: options,
                submissionGID: "magnet-torrent",
                targetProfileID: profileID
            ),
            activeProfileID: profileID
        )

        store.reconcile(
            transfers: [
                makeTransfer(
                    gid: "http-torrent",
                    status: .active,
                    name: "Release.iso",
                    source: "https://example.com/release.torrent",
                    isTorrent: true
                ),
                makeTransfer(
                    gid: "magnet-torrent",
                    status: .active,
                    name: "Release.iso",
                    source: "magnet:?xt=urn:btih:abc&dn=Release",
                    isTorrent: true
                )
            ],
            historyEntries: [],
            profileID: profileID
        )

        let httpEntityID = try XCTUnwrap(
            store.entityID(gid: "http-torrent", profileID: profileID)
        )
        let magnetEntityID = try XCTUnwrap(
            store.entityID(gid: "magnet-torrent", profileID: profileID)
        )
        XCTAssertEqual(store.entity(id: httpEntityID)?.transferProtocol, .torrent)
        XCTAssertEqual(store.entity(id: magnetEntityID)?.transferProtocol, .magnet)
    }

    private func makeTransfer(
        gid: String,
        status: TransferStatus,
        name: String,
        source: String,
        isTorrent: Bool = false
    ) -> TransferItem {
        TransferItem(
            gid: gid,
            status: status,
            totalLength: "1024",
            completedLength: status == .complete ? "1024" : "512",
            uploadLength: "0",
            downloadSpeed: status == .active ? "128" : "0",
            uploadSpeed: "0",
            dir: "/Downloads",
            connections: "2",
            errorCode: nil,
            errorMessage: nil,
            files: [
                TransferFile(
                    index: "1",
                    path: "/Downloads/\(name)",
                    length: "1024",
                    completedLength: status == .complete ? "1024" : "512",
                    selected: "true",
                    uris: [TransferURI(uri: source, status: "used")]
                )
            ],
            bittorrent: isTorrent
                ? BitTorrentInfo(info: BitTorrentInfo.Info(name: name))
                : nil
        )
    }
}
