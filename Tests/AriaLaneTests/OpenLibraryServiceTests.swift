import Foundation
import XCTest
@testable import AriaLane

final class OpenLibraryServiceTests: XCTestCase {
    func testSearchURLRequestsPublicEditionFieldsOnly() throws {
        let url = try XCTUnwrap(
            OpenLibraryService.searchURL(query: "pride and prejudice", limit: 100)
        )
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let items = components.queryItems ?? []

        XCTAssertEqual(components.host, "openlibrary.org")
        XCTAssertTrue(
            items.first { $0.name == "q" }?.value?.contains("ebook_access:public") == true
        )
        XCTAssertTrue(
            items.first { $0.name == "fields" }?.value?.contains("editions.ia") == true
        )
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "50")
    }

    func testDecodesPublicWorksAndAssociatedArchiveEdition() throws {
        let data = Data(
            """
            {
              "numFound": 2,
              "docs": [
                {
                  "key": "/works/OL66554W",
                  "title": "Pride and Prejudice",
                  "author_name": ["Jane Austen"],
                  "first_publish_year": 1813,
                  "cover_i": 14348537,
                  "ebook_access": "public",
                  "language": ["eng", "fre"],
                  "editions": {
                    "docs": [
                      {
                        "ebook_access": "public",
                        "ia": ["public_archive_item"]
                      }
                    ]
                  }
                },
                {
                  "key": "/works/OLPRIVATE",
                  "title": "Private Work",
                  "ebook_access": "borrowable"
                }
              ]
            }
            """.utf8
        )

        let page = try OpenLibraryService.decodeSearchPage(data)

        XCTAssertEqual(page.totalCount, 2)
        XCTAssertEqual(page.resources.count, 1)
        let resource = try XCTUnwrap(page.resources.first)
        XCTAssertEqual(resource.provider, .openLibrary)
        XCTAssertEqual(resource.year, "1813")
        XCTAssertEqual(resource.rightsTitle, "公开阅读")
        XCTAssertEqual(
            resource.detailsURL.absoluteString,
            "https://openlibrary.org/works/OL66554W"
        )
        XCTAssertEqual(
            resource.thumbnailURL?.absoluteString,
            "https://covers.openlibrary.org/b/id/14348537-M.jpg"
        )
        XCTAssertEqual(
            resource.downloadLocator,
            .internetArchive("public_archive_item")
        )
    }

    func testPublicWorkWithoutArchiveEditionStillOpensReadingPage() throws {
        let data = Data(
            """
            {
              "numFound": 1,
              "docs": [
                {
                  "key": "/works/OL1W",
                  "title": "Readable Work",
                  "ebook_access": "public"
                }
              ]
            }
            """.utf8
        )

        let resource = try XCTUnwrap(
            OpenLibraryService.decodeSearchPage(data).resources.first
        )

        XCTAssertFalse(resource.canResolveDownloads)
        XCTAssertEqual(resource.downloadLocator, .unavailable)
    }

    func testAcceptsSnakeCaseCountAndBareWorkKey() throws {
        let data = Data(
            """
            {
              "num_found": 1,
              "docs": [
                {
                  "key": "OL1W",
                  "title": "Readable Work",
                  "ebook_access": "public"
                }
              ]
            }
            """.utf8
        )

        let page = try OpenLibraryService.decodeSearchPage(data)

        XCTAssertEqual(page.totalCount, 1)
        XCTAssertEqual(
            page.resources.first?.detailsURL.absoluteString,
            "https://openlibrary.org/works/OL1W"
        )
    }
}
