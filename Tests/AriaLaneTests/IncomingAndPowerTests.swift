import Foundation
import XCTest
@testable import AriaLane

final class IncomingAndPowerTests: XCTestCase {
    func testCustomURLBuildsValidatedDownloadRequest() throws {
        var components = URLComponents()
        components.scheme = "arialane"
        components.host = "add"
        components.queryItems = [
            URLQueryItem(name: "url", value: "https://example.com/archive.zip"),
            URLQueryItem(name: "url", value: "magnet:?xt=urn:btih:ABC123&dn=Sample"),
            URLQueryItem(name: "text", value: "not-a-download")
        ]

        let request = try XCTUnwrap(
            IncomingDownloadRequest.parse(try XCTUnwrap(components.url))
        )

        XCTAssertEqual(
            request.urls,
            [
                "https://example.com/archive.zip",
                "magnet:?xt=urn:btih:ABC123&dn=Sample"
            ]
        )
    }

    func testCustomURLRejectsUnknownRoutesAndEmptyInputs() {
        XCTAssertNil(IncomingDownloadRequest.parse(URL(string: "arialane://settings")!))
        XCTAssertNil(IncomingDownloadRequest.parse(URL(string: "arialane://add?url=hello")!))
        XCTAssertNil(IncomingDownloadRequest.parse(URL(string: "https://example.com/file")!))
    }

    func testPowerPolicyOnlyKeepsAwakeForLiveDownloads() throws {
        let active = try makeTransfer(
            gid: "active",
            status: .active,
            total: 1_000,
            completed: 250
        )
        let waiting = try makeTransfer(
            gid: "waiting",
            status: .waiting,
            total: 1_000,
            completed: 0
        )
        let seeding = try makeTransfer(
            gid: "seeding",
            status: .active,
            total: 1_000,
            completed: 1_000,
            seeder: true
        )

        XCTAssertTrue(
            DownloadPowerPolicy.shouldPreventSystemSleep(
                enabled: true,
                transfers: [active]
            )
        )
        XCTAssertFalse(
            DownloadPowerPolicy.shouldPreventSystemSleep(
                enabled: false,
                transfers: [active]
            )
        )
        XCTAssertFalse(
            DownloadPowerPolicy.shouldPreventSystemSleep(
                enabled: true,
                transfers: [waiting, seeding]
            )
        )
    }

    private func makeTransfer(
        gid: String,
        status: TransferStatus,
        total: Int,
        completed: Int,
        seeder: Bool = false
    ) throws -> TransferItem {
        let json = """
        {
          "gid": "\(gid)",
          "status": "\(status.rawValue)",
          "totalLength": "\(total)",
          "completedLength": "\(completed)",
          "seeder": "\(seeder)"
        }
        """
        return try JSONDecoder().decode(TransferItem.self, from: Data(json.utf8))
    }
}
