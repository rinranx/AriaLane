import Foundation
import WebKit

@MainActor
enum RenderedWebPageLinkExtractor {
    static func extract(
        from pages: [URL],
        scope: WebLinkExtractionScope
    ) async -> WebLinkExtractionBatch {
        let pages = Array(pages.prefix(WebPageInputParser.maximumPageCount))
        guard !pages.isEmpty else {
            return WebLinkExtractionBatch(
                requestedPageCount: 0,
                links: [],
                failures: []
            )
        }

        let loader = RenderedPageLoader()
        var links: [ExtractedWebLink] = []
        var seen = Set<String>()
        var failures: [WebLinkExtractionFailure] = []

        for pageURL in pages {
            if Task.isCancelled {
                break
            }

            do {
                let pageLinks = try await loader.links(
                    from: pageURL,
                    scope: scope
                )
                for link in pageLinks where seen.insert(link.url).inserted {
                    links.append(link)
                }
            } catch is CancellationError {
                break
            } catch let error as URLError {
                failures.append(
                    WebLinkExtractionFailure(
                        pageURL: pageURL.absoluteString,
                        message: WebPageLinkExtractor.failureMessage(for: error)
                    )
                )
            } catch {
                failures.append(
                    WebLinkExtractionFailure(
                        pageURL: pageURL.absoluteString,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return WebLinkExtractionBatch(
            requestedPageCount: pages.count,
            links: links,
            failures: failures
        )
    }
}

@MainActor
private final class RenderedPageLoader: NSObject, WKNavigationDelegate {
    private struct PendingNavigation {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let webView: WKWebView
    private var pendingNavigation: PendingNavigation?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = "AriaLane/1.0 (+rendered web link extractor)"
    }

    func links(
        from pageURL: URL,
        scope: WebLinkExtractionScope
    ) async throws -> [ExtractedWebLink] {
        try Task.checkCancellation()
        try await navigate(to: pageURL)
        try await Task.sleep(for: .milliseconds(900))
        try Task.checkCancellation()

        let script = """
        (() => {
          const nodes = Array.from(
            document.querySelectorAll('a[href], area[href]')
          ).slice(0, 5000);
          return {
            baseURI: document.baseURI || location.href,
            markup: nodes.map((node) => node.outerHTML).join('\\n')
          };
        })()
        """
        let value = try await webView.evaluateJavaScript(script)
        guard let payload = value as? [String: Any],
              let markup = payload["markup"] as? String
        else {
            throw WebPageLinkExtractorError.unreadablePage
        }

        let finalURL = (payload["baseURI"] as? String)
            .flatMap(URL.init(string:))
            ?? webView.url
            ?? pageURL
        return HTMLDownloadLinkParser.extract(
            from: markup,
            baseURL: finalURL,
            scope: scope
        )
    }

    private func navigate(to pageURL: URL) async throws {
        if pendingNavigation != nil {
            completeNavigation(with: .failure(CancellationError()))
        }

        let navigationID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingNavigation = PendingNavigation(
                    id: navigationID,
                    continuation: continuation
                )

                timeoutTask?.cancel()
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(25))
                    guard !Task.isCancelled else { return }
                    self?.completeNavigation(
                        id: navigationID,
                        with: .failure(URLError(.timedOut))
                    )
                }

                var request = URLRequest(url: pageURL)
                request.timeoutInterval = 20
                webView.load(request)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.completeNavigation(
                    id: navigationID,
                    with: .failure(CancellationError())
                )
            }
        }
    }

    private func completeNavigation(
        id: UUID? = nil,
        with result: Result<Void, Error>
    ) {
        guard let pendingNavigation,
              id == nil || id == pendingNavigation.id
        else {
            return
        }

        self.pendingNavigation = nil
        timeoutTask?.cancel()
        timeoutTask = nil

        switch result {
        case .success:
            pendingNavigation.continuation.resume()
        case let .failure(error):
            webView.stopLoading()
            pendingNavigation.continuation.resume(throwing: error)
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        completeNavigation(with: .success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        completeNavigation(with: .failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        completeNavigation(with: .failure(error))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard navigationResponse.isForMainFrame,
              let response = navigationResponse.response as? HTTPURLResponse,
              !(200..<400).contains(response.statusCode)
        else {
            decisionHandler(.allow)
            return
        }

        decisionHandler(.cancel)
        completeNavigation(
            with: .failure(
                WebPageLinkExtractorError.httpStatus(response.statusCode)
            )
        )
    }
}
