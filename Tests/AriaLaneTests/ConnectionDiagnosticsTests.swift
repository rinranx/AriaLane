import Foundation
import XCTest
@testable import AriaLane

final class ConnectionDiagnosticsTests: XCTestCase {
    func testDiagnosticEndpointRemovesCredentialsAndQuery() {
        let endpoint = URL(
            string: "https://user:password@nas.example.com:6800/jsonrpc?token=secret#details"
        )

        XCTAssertEqual(
            ConnectionDiagnosticReport.sanitizedEndpoint(endpoint),
            "https://nas.example.com:6800/jsonrpc"
        )
    }

    func testShareableReportContainsStatusButNoSecret() {
        let report = ConnectionDiagnosticReport(
            generatedAt: Date(timeIntervalSince1970: 0),
            profileName: "NAS",
            endpoint: "https://nas.example.com:6800/jsonrpc",
            aria2Version: "1.37.0",
            enabledFeatures: ["BitTorrent", "HTTPS"],
            elapsedMilliseconds: 42,
            activeCount: 2,
            waitingCount: 3
        )

        XCTAssertTrue(report.shareableText.contains("aria2：1.37.0"))
        XCTAssertTrue(report.shareableText.contains("42 ms"))
        XCTAssertTrue(report.shareableText.contains("2 个进行中，3 个等待中"))
        XCTAssertTrue(report.shareableText.contains("BitTorrent"))
        XCTAssertFalse(report.shareableText.lowercased().contains("secret"))
    }
}
