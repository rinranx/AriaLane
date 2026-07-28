import Foundation
import XCTest
@testable import AriaLane

final class DownloadImportTests: XCTestCase {
    func testRecognizesSupportedImportExtensions() {
        XCTAssertEqual(
            DownloadImportKind(url: URL(fileURLWithPath: "/tmp/sample.torrent")),
            .torrent
        )
        XCTAssertEqual(
            DownloadImportKind(url: URL(fileURLWithPath: "/tmp/sample.META4")),
            .metalink
        )
        XCTAssertNil(DownloadImportKind(url: URL(fileURLWithPath: "/tmp/sample.zip")))
    }

    func testImportedFileChoiceBuildsCompactDisplayPath() {
        let choice = ImportedFileChoice(
            gid: "abc",
            index: 2,
            path: "/Users/example/Downloads/Collection/video.mp4",
            byteCount: 1_024,
            isSelected: true
        )

        XCTAssertEqual(choice.id, "abc:2")
        XCTAssertEqual(choice.displayPath, "Collection/video.mp4")
    }

    @MainActor
    func testTorrentWebSeedsAreDeduplicatedAndValidated() {
        let draft = PendingDownloadImport(
            sourceURL: URL(fileURLWithPath: "/tmp/sample.torrent"),
            kind: .torrent,
            title: "Sample",
            gids: ["gid"],
            files: []
        )
        let model = ImportSelectionModel(draft: draft)
        model.webSeedURIsText = """
        https://seed.example.test/files/
        https://seed.example.test/files/
        ftp://seed.example.test/files/
        """

        XCTAssertEqual(
            model.webSeedURIs,
            [
                "https://seed.example.test/files/",
                "ftp://seed.example.test/files/"
            ]
        )
        XCTAssertNil(model.webSeedValidationMessage)

        model.webSeedURIsText = "sftp://seed.example.test/files/"
        XCTAssertEqual(
            model.webSeedValidationMessage,
            "Web Seed 只支持 HTTP、HTTPS 或 FTP"
        )
    }

    func testErrorTaskProvidesReadableRecoveryState() throws {
        let json = """
        {
          "gid": "failed",
          "status": "error",
          "errorCode": "9",
          "errorMessage": "Not enough disk space",
          "files": [
            {
              "index": "1",
              "path": "/tmp/archive.zip",
              "uris": [{"uri": "https://example.com/archive.zip"}]
            }
          ]
        }
        """

        let item = try JSONDecoder().decode(TransferItem.self, from: Data(json.utf8))

        XCTAssertEqual(item.userFacingError, "磁盘可用空间不足")
        XCTAssertTrue(item.isRetryable)
        XCTAssertFalse(item.isResumable)
    }

    func testUnknownConnectionErrorStillGetsReadableMessage() throws {
        let json = """
        {
          "gid": "failed",
          "status": "error",
          "errorCode": "1",
          "errorMessage": "Failed to establish connection, cause: Connection refused",
          "files": []
        }
        """

        let item = try JSONDecoder().decode(TransferItem.self, from: Data(json.utf8))

        XCTAssertEqual(item.userFacingError, "无法连接到服务器")
    }
}
