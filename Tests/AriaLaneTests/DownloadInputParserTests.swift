import XCTest
@testable import AriaLane

final class DownloadInputParserTests: XCTestCase {
    func testParsesSupportedLinksAndRemovesDuplicates() {
        let input = """
        https://example.com/archive.zip
        magnet:?xt=urn:btih:ABC123&dn=Sample
        https://example.com/archive.zip
        not-a-link
        """

        let result = DownloadInputParser.parse(input)

        XCTAssertEqual(
            result.urls,
            [
                "https://example.com/archive.zip",
                "magnet:?xt=urn:btih:ABC123&dn=Sample"
            ]
        )
        XCTAssertEqual(result.rejectedCount, 1)
    }

    func testIgnoresBlankLines() {
        let result = DownloadInputParser.parse("\n  \nftp://example.com/file.iso\n")

        XCTAssertEqual(result.urls, ["ftp://example.com/file.iso"])
        XCTAssertEqual(result.rejectedCount, 0)
    }
}
