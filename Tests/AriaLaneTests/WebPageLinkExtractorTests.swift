import XCTest
@testable import AriaLane

final class WebPageLinkExtractorTests: XCTestCase {
    func testPageInputParserAcceptsHTTPPagesAndRemovesDuplicates() {
        let parsed = WebPageInputParser.parse(
            """
            https://example.com/downloads
            http://mirror.example.com/files
            https://example.com/downloads
            ftp://example.com/index.html
            not-a-page
            """
        )

        XCTAssertEqual(
            parsed.urls.map(\.absoluteString),
            [
                "https://example.com/downloads",
                "http://mirror.example.com/files"
            ]
        )
        XCTAssertEqual(parsed.rejectedCount, 2)
        XCTAssertEqual(parsed.omittedCount, 0)
    }

    func testPageInputParserLimitsBatchSize() {
        let input = (0...WebPageInputParser.maximumPageCount)
            .map { "https://example.com/page-\($0)" }
            .joined(separator: "\n")

        let parsed = WebPageInputParser.parse(input)

        XCTAssertEqual(
            parsed.urls.count,
            WebPageInputParser.maximumPageCount
        )
        XCTAssertEqual(parsed.rejectedCount, 0)
        XCTAssertEqual(parsed.omittedCount, 1)
    }

    func testDownloadScopeResolvesRelativeLinksAndFiltersNavigation() throws {
        let html = """
        <html>
          <body>
            <a href="/docs/manual.pdf">User manual</a>
            <a href="/products">Products</a>
            <a href="archive.zip#files">Archive</a>
            <a href="archive.zip#details">Duplicate archive</a>
            <a href="/asset?id=42&amp;download=1">Download build</a>
          </body>
        </html>
        """

        let links = HTMLDownloadLinkParser.extract(
            from: html,
            baseURL: try XCTUnwrap(
                URL(string: "https://example.com/releases/index.html")
            ),
            scope: .downloads
        )

        XCTAssertEqual(
            links.map(\.url),
            [
                "https://example.com/docs/manual.pdf",
                "https://example.com/releases/archive.zip",
                "https://example.com/asset?id=42&download=1"
            ]
        )
        XCTAssertEqual(links.first?.label, "User manual")
    }

    func testDownloadScopeRecognizesExplicitAndSemanticDownloadLinks() throws {
        let html = """
        <a href="/generated/42" download="release.bin">Save</a>
        <a href="/api/build/42">Download latest build</a>
        <a href="magnet:?xt=urn:btih:ABC123">Magnet</a>
        <a href="sftp://files.example.com/build">Secure mirror</a>
        """

        let links = HTMLDownloadLinkParser.extract(
            from: html,
            baseURL: try XCTUnwrap(URL(string: "https://example.com")),
            scope: .downloads
        )

        XCTAssertEqual(
            links.map(\.url),
            [
                "https://example.com/generated/42",
                "https://example.com/api/build/42",
                "magnet:?xt=urn:btih:ABC123",
                "sftp://files.example.com/build"
            ]
        )
        XCTAssertEqual(links.first?.isExplicitDownload, true)
    }

    func testDocumentBaseAndProtocolRelativeLinksAreResolved() throws {
        let html = """
        <base href="https://cdn.example.com/releases/">
        <a href="mac/app.dmg">Mac</a>
        <a href="//mirror.example.com/windows/app.exe">Windows</a>
        """

        let links = HTMLDownloadLinkParser.extract(
            from: html,
            baseURL: try XCTUnwrap(
                URL(string: "https://example.com/downloads")
            ),
            scope: .downloads
        )

        XCTAssertEqual(
            links.map(\.url),
            [
                "https://cdn.example.com/releases/mac/app.dmg",
                "https://mirror.example.com/windows/app.exe"
            ]
        )
    }

    func testAllLinksScopeKeepsSupportedLinksOnly() throws {
        let html = """
        <a href="/products">Products</a>
        <a href="ftp://example.com/pub">FTP</a>
        <a href="mailto:team@example.com">Email</a>
        <a href="javascript:void(0)">Action</a>
        """

        let links = HTMLDownloadLinkParser.extract(
            from: html,
            baseURL: try XCTUnwrap(URL(string: "https://example.com")),
            scope: .allSupportedLinks
        )

        XCTAssertEqual(
            links.map(\.url),
            [
                "https://example.com/products",
                "ftp://example.com/pub"
            ]
        )
    }
}
