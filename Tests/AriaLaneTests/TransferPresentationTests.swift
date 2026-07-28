import Foundation
import XCTest
@testable import AriaLane

final class TransferPresentationTests: XCTestCase {
    func testSpeedSeriesReplacesDenseSamplesAndKeepsRecentWindow() {
        var series = SpeedSampleSeries(
            retentionInterval: 3,
            maximumCount: 3,
            minimumSpacing: 0.5
        )
        let start = Date(timeIntervalSince1970: 1_000)

        series.record(
            downloadBytesPerSecond: 10,
            uploadBytesPerSecond: 5,
            at: start
        )
        series.record(
            downloadBytesPerSecond: 20,
            uploadBytesPerSecond: -1,
            at: start.addingTimeInterval(0.2)
        )

        XCTAssertEqual(series.samples.count, 1)
        XCTAssertEqual(series.samples.first?.downloadBytesPerSecond, 20)
        XCTAssertEqual(series.samples.first?.uploadBytesPerSecond, 0)

        for offset in [1.0, 2.0, 4.0] {
            series.record(
                downloadBytesPerSecond: Int64(offset * 100),
                uploadBytesPerSecond: 0,
                at: start.addingTimeInterval(offset)
            )
        }

        XCTAssertEqual(series.samples.count, 3)
        XCTAssertEqual(
            series.samples.map(\.downloadBytesPerSecond),
            [100, 200, 400]
        )
    }

    func testTransferQuerySearchesMetadataAndSortsBySpeed() {
        let items = [
            makeTransfer(
                gid: "alpha",
                status: .active,
                name: "Alpha Package.zip",
                total: 1_000,
                completed: 300,
                speed: 150,
                source: "https://example.com/releases/alpha.zip"
            ),
            makeTransfer(
                gid: "beta",
                status: .active,
                name: "Beta Image.dmg",
                total: 2_000,
                completed: 1_000,
                speed: 900,
                source: "https://cdn.example.net/beta.dmg"
            ),
            makeTransfer(
                gid: "done",
                status: .complete,
                name: "Finished.pdf",
                total: 300,
                completed: 300,
                speed: 0,
                source: "https://docs.example.org/finished.pdf"
            )
        ]

        let searched = TransferListQuery.results(
            in: items,
            filter: .all,
            searchText: "example alpha",
            sortField: .queue,
            direction: .ascending
        )
        XCTAssertEqual(searched.map(\.gid), ["alpha"])

        let bySpeed = TransferListQuery.results(
            in: items,
            filter: .active,
            searchText: "",
            sortField: .speed,
            direction: .descending
        )
        XCTAssertEqual(bySpeed.map(\.gid), ["beta", "alpha"])

        let completed = TransferListQuery.results(
            in: items,
            filter: .completed,
            searchText: "",
            sortField: .name,
            direction: .ascending
        )
        XCTAssertEqual(completed.map(\.gid), ["done"])
    }

    private func makeTransfer(
        gid: String,
        status: TransferStatus,
        name: String,
        total: Int64,
        completed: Int64,
        speed: Int64,
        source: String
    ) -> TransferItem {
        TransferItem(
            gid: gid,
            status: status,
            totalLength: String(total),
            completedLength: String(completed),
            uploadLength: "0",
            downloadSpeed: String(speed),
            uploadSpeed: "0",
            dir: "/Users/example/Downloads",
            connections: "4",
            errorCode: nil,
            errorMessage: nil,
            files: [
                TransferFile(
                    index: "1",
                    path: "/Users/example/Downloads/\(name)",
                    length: String(total),
                    completedLength: String(completed),
                    selected: "true",
                    uris: [TransferURI(uri: source, status: "used")]
                )
            ],
            bittorrent: nil
        )
    }
}
