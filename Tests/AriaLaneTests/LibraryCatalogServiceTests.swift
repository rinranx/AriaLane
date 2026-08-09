import Foundation
import XCTest
@testable import AriaLane

final class LibraryCatalogServiceTests: XCTestCase {
    override func tearDown() {
        CatalogURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testAllScopeCombinesBuiltInAndCustomCatalogs() async throws {
        let customSource = CustomLibrarySource(
            name: "Custom Catalog",
            searchURLTemplate: "https://catalog.example/opds/search?q={query}"
        )
        CatalogURLProtocolStub.handler = { request in
            switch (request.url?.host, request.url?.path) {
            case ("archive.org", "/advancedsearch.php"):
                return Self.response(
                    for: request,
                    contentType: "application/json",
                    body: """
                    {
                      "response": {
                        "numFound": 1,
                        "docs": [{
                          "identifier": "archive-book",
                          "title": "Archive Book",
                          "licenseurl": "https://creativecommons.org/licenses/by/4.0/"
                        }]
                      }
                    }
                    """
                )
            case ("www.gutenberg.org", "/ebooks/search.opds/"),
                 ("www.gutenberg.org", "/ebooks/search.opds"):
                return Self.response(
                    for: request,
                    contentType: "application/atom+xml",
                    body: """
                    <feed xmlns="http://www.w3.org/2005/Atom">
                      <entry>
                        <id>https://www.gutenberg.org/ebooks/1.opds</id>
                        <title>Gutenberg Book</title>
                        <content type="text">Public Author</content>
                        <link rel="subsection" href="/ebooks/1.opds" />
                      </entry>
                    </feed>
                    """
                )
            case ("openlibrary.org", "/search.json"):
                return Self.response(
                    for: request,
                    contentType: "application/json",
                    body: """
                    {
                      "numFound": 1,
                      "docs": [{
                        "key": "/works/OL1W",
                        "title": "Open Library Book",
                        "ebook_access": "public"
                      }]
                    }
                    """
                )
            case ("catalog.example", "/opds/search"):
                return Self.response(
                    for: request,
                    contentType: "application/atom+xml",
                    body: """
                    <feed xmlns="http://www.w3.org/2005/Atom">
                      <entry>
                        <id>urn:custom:1</id>
                        <title>Custom Book</title>
                        <rights>Creative Commons CC BY 4.0</rights>
                        <link rel="alternate" href="/books/1" />
                        <link rel="http://opds-spec.org/acquisition"
                              href="https://catalog.example/files/1.epub"
                              type="application/epub+zip" />
                      </entry>
                    </feed>
                    """
                )
            default:
                return Self.response(
                    for: request,
                    statusCode: 404,
                    contentType: "text/plain",
                    body: "Not Found"
                )
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let page = try await LibraryCatalogService(
            session: session,
            customSources: [customSource]
        ).search(
            query: "book",
            scope: .all
        )

        XCTAssertEqual(page.resources.count, 4)
        XCTAssertEqual(page.totalCount, 4)
        XCTAssertTrue(page.unavailableProviders.isEmpty)
        XCTAssertEqual(
            Set(page.resources.map(\.provider)),
            Set(LibraryResourceProvider.builtInCases + [.custom(customSource)])
        )
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        contentType: String,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
        return (response, Data(body.utf8))
    }
}

private final class CatalogURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            XCTFail("CatalogURLProtocolStub handler is missing")
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
