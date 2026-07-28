import XCTest
@testable import AriaLane

final class ServerProfileAndDockTests: XCTestCase {
    func testRPCAddressNormalizationAcceptsHTTPAndWebSocketTransports() {
        XCTAssertEqual(
            AppPreferences.normalizedEndpointURL("127.0.0.1:6800")?.absoluteString,
            "http://127.0.0.1:6800/jsonrpc"
        )
        XCTAssertEqual(
            AppPreferences.normalizedEndpointURL("https://nas.example.test/rpc")?.absoluteString,
            "https://nas.example.test/rpc"
        )
        XCTAssertEqual(
            AppPreferences.normalizedEndpointURL(
                "ws://nas.example.test/jsonrpc"
            )?.absoluteString,
            "http://nas.example.test/jsonrpc"
        )
        XCTAssertEqual(
            AppPreferences.normalizedEndpointURL(
                "wss://nas.example.test/jsonrpc"
            )?.absoluteString,
            "https://nas.example.test/jsonrpc"
        )
        XCTAssertNil(AppPreferences.normalizedEndpointURL("file:///tmp/socket"))
    }

    func testWebSocketEndpointConversionPreservesRPCPath() {
        XCTAssertEqual(
            Aria2WebSocketClient.webSocketURL(
                from: URL(string: "https://nas.example.test:6800/rpc")!
            )?.absoluteString,
            "wss://nas.example.test:6800/rpc"
        )
        XCTAssertEqual(
            Aria2WebSocketClient.webSocketURL(
                from: URL(string: "http://127.0.0.1:6800")!
            )?.absoluteString,
            "ws://127.0.0.1:6800/jsonrpc"
        )
    }

    func testDownloadInputParserAcceptsSFTP() {
        let parsed = DownloadInputParser.parse(
            "sftp://example.test/files/archive.zip"
        )
        XCTAssertEqual(
            parsed.urls,
            ["sftp://example.test/files/archive.zip"]
        )
        XCTAssertEqual(parsed.rejectedCount, 0)
    }

    func testServerProfileRoundTripsWithoutSecret() throws {
        let profile = Aria2ServerProfile(
            name: "NAS",
            endpoint: "https://nas.example.test:6800/jsonrpc",
            autoStartLocalAria2: false
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Aria2ServerProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.hostDescription, "nas.example.test")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret"))
    }

    func testServerProfileBuildsCompactSwitcherEndpointSummary() {
        let local = Aria2ServerProfile(
            name: "本机",
            endpoint: "http://127.0.0.1:6800/jsonrpc",
            autoStartLocalAria2: true
        )
        let nas = Aria2ServerProfile(
            name: "群晖 NAS",
            endpoint: "http://192.168.1.8:6800/jsonrpc",
            autoStartLocalAria2: false
        )
        let customPort = Aria2ServerProfile(
            name: "远程 VPS",
            endpoint: "https://downloads.example.test:7443/jsonrpc",
            autoStartLocalAria2: false
        )

        XCTAssertEqual(local.endpointSummary, ":6800")
        XCTAssertEqual(nas.endpointSummary, "192.168.1.8")
        XCTAssertEqual(customPort.endpointSummary, "downloads.example.test:7443")
    }

    func testDockProgressIsWeightedByTaskSize() throws {
        let smaller = try makeTransfer(
            gid: "small",
            status: .active,
            total: 100,
            completed: 100
        )
        let larger = try makeTransfer(
            gid: "large",
            status: .waiting,
            total: 900,
            completed: 0
        )

        let snapshot = DockProgressSnapshot(transfers: [smaller, larger])
        XCTAssertEqual(snapshot.progress, 0.1, accuracy: 0.0001)
        XCTAssertEqual(snapshot.liveCount, 2)
        XCTAssertEqual(snapshot.activeCount, 1)
    }

    func testDockProgressIgnoresCompletedAndFailedItems() throws {
        let completed = try makeTransfer(
            gid: "done",
            status: .complete,
            total: 100,
            completed: 100
        )
        let failed = try makeTransfer(
            gid: "failed",
            status: .error,
            total: 100,
            completed: 50
        )

        let snapshot = DockProgressSnapshot(transfers: [completed, failed])
        XCTAssertEqual(snapshot.progress, 0)
        XCTAssertEqual(snapshot.liveCount, 0)
        XCTAssertEqual(snapshot.activeCount, 0)
    }

    private func makeTransfer(
        gid: String,
        status: TransferStatus,
        total: Int,
        completed: Int
    ) throws -> TransferItem {
        let json = """
        {
          "gid": "\(gid)",
          "status": "\(status.rawValue)",
          "totalLength": "\(total)",
          "completedLength": "\(completed)"
        }
        """
        return try JSONDecoder().decode(TransferItem.self, from: Data(json.utf8))
    }
}
