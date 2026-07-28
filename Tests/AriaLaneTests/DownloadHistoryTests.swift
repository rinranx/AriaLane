import Foundation
import XCTest
@testable import AriaLane

final class DownloadHistoryTests: XCTestCase {
    func testArchiveRecordsTerminalTasksWithoutDuplicates() {
        var archive = DownloadHistoryArchive(maximumCount: 10)
        let item = makeTransfer(gid: "done", status: .complete, name: "Archive.zip")
        let date = Date(timeIntervalSince1970: 2_000)

        XCTAssertTrue(archive.record(item, at: date))
        XCTAssertFalse(archive.record(item, at: date.addingTimeInterval(30)))
        XCTAssertEqual(archive.entries.count, 1)
        XCTAssertEqual(archive.entries.first?.recordedAt, date)
        XCTAssertEqual(archive.entries.first?.outcome, .completed)
    }

    func testArchivePersistsAndCanRemoveSelectedEntries() throws {
        var archive = DownloadHistoryArchive(maximumCount: 10)
        archive.record(
            makeTransfer(gid: "first", status: .complete, name: "First.iso"),
            at: Date(timeIntervalSince1970: 1_000)
        )
        archive.record(
            makeTransfer(gid: "second", status: .error, name: "Second.iso"),
            at: Date(timeIntervalSince1970: 2_000)
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriaLaneHistoryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = DownloadHistoryRepository(
            fileURL: directory.appendingPathComponent("history.json")
        )
        try repository.save(archive)
        var loaded = try repository.load()

        XCTAssertEqual(loaded.entries.map(\.gid), ["second", "first"])
        XCTAssertEqual(loaded.remove(ids: ["second"]), 1)
        XCTAssertEqual(loaded.entries.map(\.gid), ["first"])
        XCTAssertFalse(
            loaded.record(
                makeTransfer(gid: "second", status: .error, name: "Second.iso"),
                at: Date(timeIntervalSince1970: 3_000)
            )
        )
        XCTAssertEqual(loaded.entries.map(\.gid), ["first"])
    }

    func testHistorySearchAndSortUseNamePathAndDate() {
        var archive = DownloadHistoryArchive(maximumCount: 10)
        archive.record(
            makeTransfer(gid: "older", status: .complete, name: "Calm Data.zip"),
            at: Date(timeIntervalSince1970: 1_000)
        )
        archive.record(
            makeTransfer(gid: "newer", status: .error, name: "Night Build.dmg"),
            at: Date(timeIntervalSince1970: 2_000)
        )

        let searched = DownloadHistorySort.newest.results(
            in: archive.entries,
            searchText: "calm downloads"
        )
        XCTAssertEqual(searched.map(\.gid), ["older"])

        let oldestFirst = DownloadHistorySort.oldest.results(
            in: archive.entries,
            searchText: ""
        )
        XCTAssertEqual(oldestFirst.map(\.gid), ["older", "newer"])
    }

    private func makeTransfer(
        gid: String,
        status: TransferStatus,
        name: String
    ) -> TransferItem {
        TransferItem(
            gid: gid,
            status: status,
            totalLength: "1024",
            completedLength: status == .complete ? "1024" : "512",
            uploadLength: "0",
            downloadSpeed: "0",
            uploadSpeed: "0",
            dir: "/Users/example/Downloads",
            connections: "0",
            errorCode: status == .error ? "6" : nil,
            errorMessage: status == .error ? "Network failure" : nil,
            files: [
                TransferFile(
                    index: "1",
                    path: "/Users/example/Downloads/\(name)",
                    length: "1024",
                    completedLength: status == .complete ? "1024" : "512",
                    selected: "true",
                    uris: [
                        TransferURI(
                            uri: "https://example.com/\(name)",
                            status: "used"
                        )
                    ]
                )
            ],
            bittorrent: nil
        )
    }
}
