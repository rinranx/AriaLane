import Foundation
import XCTest
@testable import AriaLane

final class TransferItemTests: XCTestCase {
    func testDecodesAria2TaskAndCalculatesProgress() throws {
        let json = """
        {
          "gid": "2089b05ecca3d829",
          "status": "active",
          "totalLength": "1000",
          "completedLength": "250",
          "uploadLength": "0",
          "downloadSpeed": "125",
          "uploadSpeed": "0",
          "dir": "/Users/example/Downloads",
          "connections": "4",
          "files": [
            {
              "index": "1",
              "path": "/Users/example/Downloads/quiet-river.zip",
              "length": "1000",
              "completedLength": "250",
              "selected": "true",
              "uris": [
                {
                  "uri": "https://example.com/quiet-river.zip",
                  "status": "used"
                }
              ]
            }
          ]
        }
        """

        let item = try JSONDecoder().decode(TransferItem.self, from: Data(json.utf8))

        XCTAssertEqual(item.displayName, "quiet-river.zip")
        XCTAssertEqual(item.progress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(item.remainingSeconds), 6, accuracy: 0.0001)
        XCTAssertTrue(item.isPausable)
        XCTAssertEqual(item.sourceURI, "https://example.com/quiet-river.zip")
    }

    func testUsesTorrentDisplayName() throws {
        let json = """
        {
          "gid": "abc",
          "status": "waiting",
          "totalLength": "0",
          "completedLength": "0",
          "downloadSpeed": "0",
          "uploadSpeed": "0",
          "files": [],
          "bittorrent": {
            "info": {
              "name": "A Calm Dataset"
            }
          }
        }
        """

        let item = try JSONDecoder().decode(TransferItem.self, from: Data(json.utf8))

        XCTAssertEqual(item.displayName, "A Calm Dataset")
        XCTAssertEqual(item.progress, 0)
    }

    func testDecodesPieceMapAndSummarizesBuckets() throws {
        let json = """
        {
          "gid": "pieces",
          "status": "active",
          "totalLength": "4194304",
          "completedLength": "2097152",
          "pieceLength": "1048576",
          "numPieces": "4",
          "bitfield": "A",
          "verifiedLength": "1048576",
          "connections": "3",
          "bittorrent": {"info": {"name": "Pieces"}}
        }
        """

        let item = try JSONDecoder().decode(TransferItem.self, from: Data(json.utf8))
        XCTAssertTrue(item.isBitTorrent)
        XCTAssertEqual(item.pieceCount, 4)
        XCTAssertEqual(item.pieceLengthValue, 1_048_576)
        XCTAssertEqual(item.verifiedByteCount, 1_048_576)
        XCTAssertEqual(item.pieceProgressBuckets(maximumCount: 4), [1, 0, 1, 0])
        XCTAssertEqual(item.pieceProgressBuckets(maximumCount: 2), [0.5, 0.5])
    }

    func testDecodesPeerAndServerDetails() throws {
        let peersJSON = """
        [{
          "peerId": "peer-1",
          "ip": "2001:db8::1",
          "port": "6881",
          "downloadSpeed": "2048",
          "uploadSpeed": "1024",
          "seeder": "true"
        }]
        """
        let serversJSON = """
        [{
          "index": "1",
          "servers": [{
            "uri": "https://example.com/file.zip",
            "currentUri": "https://cdn.example.com/file.zip",
            "downloadSpeed": "4096"
          }]
        }]
        """

        let peers = try JSONDecoder().decode([Aria2Peer].self, from: Data(peersJSON.utf8))
        let groups = try JSONDecoder().decode(
            [Aria2ServerGroup].self,
            from: Data(serversJSON.utf8)
        )

        XCTAssertEqual(peers[0].address, "[2001:db8::1]:6881")
        XCTAssertTrue(peers[0].isSeeder)
        XCTAssertEqual(peers[0].downloadSpeedValue, 2_048)
        XCTAssertEqual(groups[0].servers[0].displayHost, "cdn.example.com")
        XCTAssertEqual(groups[0].servers[0].downloadSpeedValue, 4_096)
    }
}
