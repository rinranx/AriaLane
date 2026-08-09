import Foundation
import XCTest
@testable import AriaLane

final class InternetArchiveServiceTests: XCTestCase {
    func testSearchURLScopesResultsToOpenTextResources() throws {
        let url = try XCTUnwrap(
            InternetArchiveService.searchURL(
                query: "pride prejudice",
                limit: 200
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        let query = try XCTUnwrap(items.first { $0.name == "q" }?.value)

        XCTAssertTrue(query.contains("mediatype:texts"))
        XCTAssertTrue(query.contains("licenseurl:(*creativecommons.org*)"))
        XCTAssertTrue(query.contains("\"pride\" AND \"prejudice\""))
        XCTAssertEqual(items.first { $0.name == "rows" }?.value, "50")
        XCTAssertEqual(items.filter { $0.name == "fl[]" }.count, 7)
    }

    func testDecodesSearchDocumentsWithFlexibleMetadataShapes() throws {
        let data = Data(
            """
            {
              "response": {
                "numFound": 2,
                "docs": [
                  {
                    "identifier": "book-one",
                    "title": "Book One",
                    "creator": "Example Author",
                    "year": 1912,
                    "language": ["eng", "fre"],
                    "licenseurl": "https://creativecommons.org/publicdomain/mark/1.0/"
                  },
                  {
                    "identifier": "book-two",
                    "title": "Book Two",
                    "creator": ["First Author", "Second Author"],
                    "date": "1923-01-01T00:00:00Z",
                    "licenseurl": ["https://example.com/custom-license"]
                  }
                ]
              }
            }
            """.utf8
        )

        let page = try InternetArchiveService.decodeSearchPage(data)

        XCTAssertEqual(page.totalCount, 2)
        XCTAssertEqual(page.resources.count, 1)
        XCTAssertEqual(page.resources[0].provider, .internetArchive)
        XCTAssertEqual(page.resources[0].sourceIdentifier, "book-one")
        XCTAssertEqual(page.resources[0].creators, ["Example Author"])
        XCTAssertEqual(page.resources[0].year, "1912")
        XCTAssertEqual(page.resources[0].languages, ["eng", "fre"])
        XCTAssertEqual(page.resources[0].rightsTitle, "公版标记")
    }

    func testDownloadOptionsKeepSupportedPublicFilesOnly() throws {
        let data = Data(
            """
            {
              "files": [
                {
                  "name": "Book File.epub",
                  "source": "derivative",
                  "format": "EPUB",
                  "size": "2048"
                },
                {
                  "name": "Book File.pdf",
                  "source": "original",
                  "format": "Text PDF",
                  "size": "4096"
                },
                {
                  "name": "book_meta.xml",
                  "source": "metadata",
                  "format": "Metadata"
                },
                {
                  "name": "private.mobi",
                  "source": "original",
                  "format": "MOBI",
                  "private": "true"
                }
              ],
              "metadata": {
                "licenseurl": "https://creativecommons.org/licenses/by/4.0/",
                "access-restricted-item": "false"
              }
            }
            """.utf8
        )

        let downloads = try InternetArchiveService.decodeDownloads(
            data,
            identifier: "book-id"
        )

        XCTAssertEqual(downloads.options.map(\.formatTitle), ["EPUB", "PDF"])
        XCTAssertEqual(downloads.options.map(\.byteCount), [2_048, 4_096])
        XCTAssertEqual(
            downloads.options[0].url.absoluteString,
            "https://archive.org/download/book-id/Book%20File.epub"
        )
    }

    func testRestrictedMetadataDisablesDirectDownload() {
        let data = Data(
            """
            {
              "is_dark": true,
              "files": [],
              "metadata": {
                "licenseurl": "https://creativecommons.org/publicdomain/mark/1.0/"
              }
            }
            """.utf8
        )

        XCTAssertThrowsError(
            try InternetArchiveService.decodeDownloads(data, identifier: "restricted")
        ) { error in
            guard case InternetArchiveServiceError.restrictedItem = error else {
                return XCTFail("Expected restrictedItem, got \(error)")
            }
        }
    }

    func testMissingCreativeCommonsLicenseDisablesDirectDownload() {
        let data = Data(
            """
            {
              "files": [],
              "metadata": {
                "licenseurl": "https://example.com/unknown-license"
              }
            }
            """.utf8
        )

        XCTAssertThrowsError(
            try InternetArchiveService.decodeDownloads(data, identifier: "unclear")
        ) { error in
            guard case InternetArchiveServiceError.unverifiedLicense = error else {
                return XCTFail("Expected unverifiedLicense, got \(error)")
            }
        }
    }
}
