import Foundation
import XCTest
@testable import AriaLane

final class CustomLibrarySourceTests: XCTestCase {
    func testSearchTemplateEncodesQueryAndAcceptsOpenSearchToken() throws {
        let source = CustomLibrarySource(
            name: "Example Catalog",
            searchURLTemplate: "https://catalog.example/search?q={searchTerms}&lang=en"
        )

        let url = try source.searchURL(query: "Jane Austen & friends")
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(components.host, "catalog.example")
        XCTAssertEqual(
            components.queryItems?.first { $0.name == "q" }?.value,
            "Jane Austen & friends"
        )
    }

    func testRemoteHTTPAndEmbeddedCredentialsAreRejected() {
        let remoteHTTP = CustomLibrarySource(
            name: "Unsafe",
            searchURLTemplate: "http://catalog.example/search?q={query}"
        )
        XCTAssertThrowsError(try remoteHTTP.validated()) { error in
            XCTAssertEqual(
                error as? CustomLibrarySourceValidationError,
                .insecureRemoteHTTP
            )
        }

        let credentials = CustomLibrarySource(
            name: "Credentials",
            searchURLTemplate: "https://user:secret@catalog.example/search?q={query}"
        )
        XCTAssertThrowsError(try credentials.validated()) { error in
            XCTAssertEqual(
                error as? CustomLibrarySourceValidationError,
                .credentialsNotAllowed
            )
        }

        let localhost = CustomLibrarySource(
            name: "Local",
            searchURLTemplate: "http://localhost:8080/opds?q={query}"
        )
        XCTAssertNoThrow(try localhost.validated())
    }

    func testOPDSParserOnlyExposesDownloadsForVerifiedOpenRights() throws {
        let source = CustomLibrarySource(
            name: "Example Catalog",
            searchURLTemplate: "https://catalog.example/search?q={query}"
        )
        let data = Data(
            """
            <feed xmlns="http://www.w3.org/2005/Atom"
                  xmlns:dc="http://purl.org/dc/terms/"
                  xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/">
              <opensearch:totalResults>2</opensearch:totalResults>
              <entry>
                <id>urn:book:open</id>
                <title>Open Book</title>
                <author><name>First Author</name></author>
                <dc:creator>Second Author</dc:creator>
                <published>1912-04-03</published>
                <dc:language>eng</dc:language>
                <rights>Public domain worldwide</rights>
                <link rel="alternate" href="/books/open" type="text/html" />
                <link rel="http://opds-spec.org/image/thumbnail"
                      href="/covers/open.jpg" type="image/jpeg" />
                <link rel="http://opds-spec.org/acquisition"
                      href="https://cdn.example/open.epub"
                      type="application/epub+zip" length="2048" />
              </entry>
              <entry>
                <id>urn:book:closed</id>
                <title>Closed Book</title>
                <rights>All rights reserved</rights>
                <link rel="alternate" href="/books/closed" />
                <link rel="http://opds-spec.org/acquisition"
                      href="https://cdn.example/closed.pdf"
                      type="application/pdf" />
              </entry>
            </feed>
            """.utf8
        )

        let page = try CustomOPDSService.decodeSearchPage(
            data,
            source: source,
            baseURL: URL(string: "https://catalog.example/search?q=open")!
        )

        XCTAssertEqual(page.totalCount, 2)
        XCTAssertEqual(page.resources.count, 2)

        let open = page.resources[0]
        XCTAssertEqual(open.provider, .custom(source))
        XCTAssertEqual(open.creators, ["First Author", "Second Author"])
        XCTAssertEqual(open.year, "1912")
        XCTAssertEqual(open.languages, ["eng"])
        XCTAssertEqual(open.rightsTitle, "公版")
        XCTAssertEqual(
            open.detailsURL.absoluteString,
            "https://catalog.example/books/open"
        )
        XCTAssertEqual(
            open.thumbnailURL?.absoluteString,
            "https://catalog.example/covers/open.jpg"
        )
        guard case .custom(let downloads) = open.downloadLocator else {
            return XCTFail("Expected verified custom downloads")
        }
        XCTAssertEqual(downloads.options.map(\.formatTitle), ["EPUB"])
        XCTAssertEqual(downloads.options.first?.byteCount, 2_048)

        let closed = page.resources[1]
        XCTAssertEqual(closed.rightsTitle, "权利状态未验证")
        XCTAssertEqual(closed.downloadLocator, .unavailable)
    }

    func testCreativeCommonsLicenseLinkVerifiesDownloads() throws {
        let source = CustomLibrarySource(
            name: "Example Catalog",
            searchURLTemplate: "https://catalog.example/search?q={query}"
        )
        let data = Data(
            """
            <feed xmlns="http://www.w3.org/2005/Atom">
              <entry>
                <id>urn:book:cc</id>
                <title>CC Book</title>
                <link rel="license"
                      href="https://creativecommons.org/licenses/by/4.0/" />
                <link rel="http://opds-spec.org/acquisition"
                      href="https://cdn.example/cc.pdf"
                      type="application/pdf" />
              </entry>
            </feed>
            """.utf8
        )

        let resource = try XCTUnwrap(
            CustomOPDSService.decodeSearchPage(
                data,
                source: source,
                baseURL: URL(string: "https://catalog.example/search?q=cc")!
            ).resources.first
        )

        XCTAssertEqual(resource.rightsTitle, "CC BY 4.0")
        XCTAssertTrue(resource.canResolveDownloads)
    }
}
