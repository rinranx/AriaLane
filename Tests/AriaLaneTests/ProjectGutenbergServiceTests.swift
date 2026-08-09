import Foundation
import XCTest
@testable import AriaLane

final class ProjectGutenbergServiceTests: XCTestCase {
    func testSearchURLUsesOfficialOPDSCatalog() throws {
        let url = try XCTUnwrap(
            ProjectGutenbergService.searchURL(query: "pride prejudice")
        )
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(components.host, "www.gutenberg.org")
        XCTAssertEqual(components.path, "/ebooks/search.opds/")
        XCTAssertEqual(
            components.queryItems?.first { $0.name == "query" }?.value,
            "pride prejudice"
        )
    }

    func testDecodesSearchEntriesWithoutHotlinkingThumbnails() throws {
        let data = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
              <entry>
                <id>https://www.gutenberg.org/ebooks/1342.opds</id>
                <title>Pride and Prejudice</title>
                <content type="text">Jane Austen</content>
                <link rel="subsection" href="/ebooks/1342.opds" />
              </entry>
              <entry>
                <id>https://www.gutenberg.org/ebooks/10471.opds</id>
                <title>The World's Greatest Books</title>
                <content type="text">1589 downloads</content>
                <link rel="subsection" href="/ebooks/10471.opds" />
              </entry>
            </feed>
            """.utf8
        )

        let page = try ProjectGutenbergService.decodeSearchPage(data)

        XCTAssertEqual(page.resources.count, 2)
        XCTAssertEqual(page.resources[0].provider, .projectGutenberg)
        XCTAssertEqual(page.resources[0].sourceIdentifier, "1342")
        XCTAssertEqual(page.resources[0].creators, ["Jane Austen"])
        XCTAssertNil(page.resources[0].thumbnailURL)
        XCTAssertEqual(page.resources[1].creators, [])
    }

    func testPublicDomainBookExposesSupportedAcquisitionLinks() throws {
        let data = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
              <entry>
                <title>Pride and Prejudice</title>
                <rights>Public domain in the USA.</rights>
                <link type="application/epub+zip"
                      rel="http://opds-spec.org/acquisition"
                      title="EPUB3 (E-readers)"
                      length="24835612"
                      href="https://www.gutenberg.org/ebooks/1342.epub3.images" />
                <link type="application/x-mobipocket-ebook"
                      rel="http://opds-spec.org/acquisition"
                      title="Kindle"
                      length="540013"
                      href="https://www.gutenberg.org/ebooks/1342.kindle.noimages" />
                <link type="application/pdf"
                      rel="http://opds-spec.org/acquisition"
                      href="https://example.com/untrusted.pdf" />
              </entry>
              <entry>
                <title>Licensed edition</title>
                <rights>Copyrighted.</rights>
                <link type="application/pdf"
                      rel="http://opds-spec.org/acquisition"
                      href="https://www.gutenberg.org/files/licensed.pdf" />
              </entry>
            </feed>
            """.utf8
        )

        let downloads = try ProjectGutenbergService.decodeDownloads(
            data,
            bookID: "1342"
        )

        XCTAssertEqual(downloads.rightsTitle, "美国公版")
        XCTAssertEqual(downloads.options.map(\.formatTitle), ["EPUB3", "Kindle"])
        XCTAssertEqual(downloads.options.first?.byteCount, 24_835_612)
        XCTAssertTrue(
            downloads.options.allSatisfy { $0.url.host == "www.gutenberg.org" }
        )
    }

    func testCopyrightedBookDoesNotExposeDirectDownloads() {
        let data = Data(
            """
            <feed xmlns="http://www.w3.org/2005/Atom">
              <entry>
                <rights>Copyrighted. Read the notice inside this book.</rights>
                <link type="application/epub+zip"
                      rel="http://opds-spec.org/acquisition"
                      href="https://www.gutenberg.org/ebooks/999.epub" />
              </entry>
            </feed>
            """.utf8
        )

        XCTAssertThrowsError(
            try ProjectGutenbergService.decodeDownloads(data, bookID: "999")
        ) { error in
            guard case ProjectGutenbergServiceError.notPublicDomain = error else {
                return XCTFail("Expected notPublicDomain, got \(error)")
            }
        }
    }
}
