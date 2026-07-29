import Foundation

enum WebPageLinkExtractorError: LocalizedError {
    case unsupportedResponse
    case httpStatus(Int)
    case responseTooLarge
    case unsupportedContentType(String)
    case unreadablePage

    var errorDescription: String? {
        switch self {
        case .unsupportedResponse:
            L10n.string("网页服务器返回了无法识别的响应")
        case let .httpStatus(status):
            L10n.string("网页服务器返回 HTTP \(status)")
        case .responseTooLarge:
            L10n.string("网页内容超过 5 MB，已停止读取")
        case let .unsupportedContentType(contentType):
            L10n.string("响应不是网页内容：\(contentType)")
        case .unreadablePage:
            L10n.string("无法读取网页文本")
        }
    }
}

enum HTMLDownloadLinkParser {
    private static let supportedSchemes = Set([
        "http",
        "https",
        "ftp",
        "sftp",
        "magnet"
    ])

    private static let downloadableExtensions = Set([
        "3gp", "7z", "aac", "apk", "appx", "avi", "bin", "bz2", "cab",
        "csv", "deb", "dmg", "doc", "docx", "epub", "exe", "flac", "flv",
        "gif", "gz", "gzip", "img", "ipa", "iso", "jar", "jpeg", "jpg",
        "json", "m4a", "m4v", "meta4", "metalink", "mkv", "mobi", "mov",
        "mp3", "mp4", "mpeg", "mpg", "msi", "odp", "ods", "odt", "ogg",
        "opus", "otf", "pdf", "pkg", "png", "ppt", "pptx", "rar", "rpm",
        "rtf", "svg", "tar", "tbz", "tbz2", "tgz", "torrent", "ts", "ttf",
        "txt", "wav", "webm", "webp", "whl", "woff", "woff2", "xls", "xlsx",
        "xml", "xz", "zip", "zst"
    ])

    private static let downloadQueryNames = Set([
        "attachment",
        "dl",
        "download",
        "export",
        "file",
        "filename",
        "response-content-disposition"
    ])

    private static let downloadLabelMarkers = [
        "download",
        "get file",
        "save file",
        "下载",
        "下載",
        "获取文件",
        "取得檔案"
    ]

    private static let baseTagRegex = try! NSRegularExpression(
        pattern: #"<base\b([^>]*)>"#,
        options: [.caseInsensitive]
    )

    private static let linkTagRegex = try! NSRegularExpression(
        pattern: #"<a\b([^>]*)>(.*?)</a\s*>|<area\b([^>]*)/?>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    private static let attributeRegex = try! NSRegularExpression(
        pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#,
        options: []
    )

    private static let markupRegex = try! NSRegularExpression(
        pattern: #"<[^>]+>"#,
        options: [.dotMatchesLineSeparators]
    )

    private static let numericEntityRegex = try! NSRegularExpression(
        pattern: #"&#(x[0-9A-Fa-f]+|[0-9]+);"#,
        options: []
    )

    static func extract(
        from html: String,
        baseURL: URL,
        scope: WebLinkExtractionScope
    ) -> [ExtractedWebLink] {
        let documentBaseURL = resolvedDocumentBaseURL(
            in: html,
            fallback: baseURL
        )
        let sourcePageURL = baseURL.absoluteString
        let source = html as NSString
        let matches = linkTagRegex.matches(
            in: html,
            range: NSRange(location: 0, length: source.length)
        )

        var links: [ExtractedWebLink] = []
        var seen = Set<String>()

        for match in matches.prefix(5_000) {
            let attributeRange = match.range(at: 1).location == NSNotFound
                ? match.range(at: 3)
                : match.range(at: 1)
            guard attributeRange.location != NSNotFound else { continue }

            let attributeText = source.substring(with: attributeRange)
            let attributes = parsedAttributes(in: attributeText)
            guard let rawHref = attributes["href"],
                  let resolvedURL = resolvedURL(
                    rawHref,
                    relativeTo: documentBaseURL
                  )
            else {
                continue
            }

            let isExplicitDownload = attributes.keys.contains("download")
            let body = match.range(at: 2).location == NSNotFound
                ? ""
                : source.substring(with: match.range(at: 2))
            let label = normalizedLabel(
                attributes["aria-label"]
                    ?? attributes["title"]
                    ?? attributes["download"]
                    ?? body
            )

            guard scope == .allSupportedLinks
                    || isLikelyDownload(
                        resolvedURL,
                        label: label,
                        isExplicitDownload: isExplicitDownload
                    )
            else {
                continue
            }

            let normalizedURL = removingFragment(from: resolvedURL)
            let urlString = normalizedURL.absoluteString
            guard seen.insert(urlString).inserted else { continue }

            links.append(
                ExtractedWebLink(
                    url: urlString,
                    sourcePageURL: sourcePageURL,
                    label: label,
                    isExplicitDownload: isExplicitDownload
                )
            )
        }

        return links
    }

    static func isLikelyDownload(
        _ url: URL,
        label: String,
        isExplicitDownload: Bool
    ) -> Bool {
        if isExplicitDownload {
            return true
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if ["ftp", "sftp", "magnet"].contains(scheme) {
            return true
        }

        if downloadableExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }

        let lowercasedLabel = label.lowercased()
        if downloadLabelMarkers.contains(where: lowercasedLabel.contains) {
            return true
        }

        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return false
        }

        for item in components.queryItems ?? [] {
            let name = item.name.lowercased()
            if downloadQueryNames.contains(name) {
                return true
            }
            if let value = item.value,
               downloadableExtensions.contains(
                   URL(fileURLWithPath: value).pathExtension.lowercased()
               ) {
                return true
            }
        }

        let lastPathComponent = url.lastPathComponent.lowercased()
        return ["download", "attachment", "export"].contains(lastPathComponent)
            && components.query != nil
    }

    private static func resolvedDocumentBaseURL(
        in html: String,
        fallback: URL
    ) -> URL {
        let source = html as NSString
        guard let match = baseTagRegex.firstMatch(
            in: html,
            range: NSRange(location: 0, length: source.length)
        ) else {
            return fallback
        }

        let attributes = parsedAttributes(
            in: source.substring(with: match.range(at: 1))
        )
        guard let href = attributes["href"],
              let url = resolvedURL(href, relativeTo: fallback),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
            return fallback
        }
        return url
    }

    private static func parsedAttributes(in text: String) -> [String: String] {
        let source = text as NSString
        let matches = attributeRegex.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        var attributes: [String: String] = [:]

        for match in matches {
            let name = source.substring(with: match.range(at: 1)).lowercased()
            let value = (2...4).compactMap { index -> String? in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return source.substring(with: range)
            }.first ?? ""
            attributes[name] = decodedHTMLEntities(in: value)
        }
        return attributes
    }

    private static func resolvedURL(
        _ rawValue: String,
        relativeTo baseURL: URL
    ) -> URL? {
        let value = decodedHTMLEntities(in: rawValue).trimmed
        guard !value.isEmpty, !value.hasPrefix("#") else { return nil }

        let url: URL?
        if value.hasPrefix("//"), let scheme = baseURL.scheme {
            url = URL(string: "\(scheme):\(value)")
        } else {
            url = URL(string: value, relativeTo: baseURL)?.absoluteURL
        }

        guard let url,
              supportedSchemes.contains(url.scheme?.lowercased() ?? "")
        else {
            return nil
        }
        if ["http", "https", "ftp", "sftp"].contains(
            url.scheme?.lowercased() ?? ""
        ), url.host?.isEmpty != false {
            return nil
        }
        return url
    }

    private static func removingFragment(from url: URL) -> URL {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url
        }
        components.fragment = nil
        return components.url ?? url
    }

    private static func normalizedLabel(_ rawValue: String) -> String {
        let source = rawValue as NSString
        let range = NSRange(location: 0, length: source.length)
        let withoutMarkup = markupRegex.stringByReplacingMatches(
            in: rawValue,
            range: range,
            withTemplate: " "
        )
        let normalized = decodedHTMLEntities(in: withoutMarkup)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(normalized.prefix(160))
    }

    private static func decodedHTMLEntities(in value: String) -> String {
        var result = value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")

        let source = result as NSString
        let matches = numericEntityRegex.matches(
            in: result,
            range: NSRange(location: 0, length: source.length)
        )
        for match in matches.reversed() {
            let rawNumber = source.substring(with: match.range(at: 1))
            let radix = rawNumber.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(rawNumber.dropFirst()) : rawNumber
            guard let value = UInt32(digits, radix: radix),
                  let scalar = UnicodeScalar(value)
            else {
                continue
            }
            result = (result as NSString).replacingCharacters(
                in: match.range,
                with: String(Character(scalar))
            )
        }
        return result
    }
}

enum WebPageLinkExtractor {
    private struct PageOutcome: Sendable {
        let index: Int
        let pageURL: String
        let links: [ExtractedWebLink]
        let errorMessage: String?
    }

    private static let maximumResponseSize = 5 * 1_024 * 1_024
    private static let maximumConcurrentRequests = 4

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

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

        var outcomes: [PageOutcome] = []
        await withTaskGroup(of: PageOutcome.self) { group in
            var nextIndex = 0

            func addTask(at index: Int) {
                let pageURL = pages[index]
                group.addTask {
                    await outcome(
                        for: pageURL,
                        index: index,
                        scope: scope
                    )
                }
            }

            while nextIndex < min(maximumConcurrentRequests, pages.count) {
                addTask(at: nextIndex)
                nextIndex += 1
            }

            while let outcome = await group.next() {
                outcomes.append(outcome)
                if nextIndex < pages.count, !Task.isCancelled {
                    addTask(at: nextIndex)
                    nextIndex += 1
                }
            }
        }

        var links: [ExtractedWebLink] = []
        var seen = Set<String>()
        var failures: [WebLinkExtractionFailure] = []

        for outcome in outcomes.sorted(by: { $0.index < $1.index }) {
            if let errorMessage = outcome.errorMessage {
                failures.append(
                    WebLinkExtractionFailure(
                        pageURL: outcome.pageURL,
                        message: errorMessage
                    )
                )
                continue
            }
            for link in outcome.links where seen.insert(link.url).inserted {
                links.append(link)
            }
        }

        return WebLinkExtractionBatch(
            requestedPageCount: pages.count,
            links: links,
            failures: failures
        )
    }

    private static func outcome(
        for pageURL: URL,
        index: Int,
        scope: WebLinkExtractionScope
    ) async -> PageOutcome {
        do {
            return PageOutcome(
                index: index,
                pageURL: pageURL.absoluteString,
                links: try await links(from: pageURL, scope: scope),
                errorMessage: nil
            )
        } catch is CancellationError {
            return PageOutcome(
                index: index,
                pageURL: pageURL.absoluteString,
                links: [],
                errorMessage: L10n.string("提取已取消")
            )
        } catch let error as URLError {
            return PageOutcome(
                index: index,
                pageURL: pageURL.absoluteString,
                links: [],
                errorMessage: failureMessage(for: error)
            )
        } catch {
            return PageOutcome(
                index: index,
                pageURL: pageURL.absoluteString,
                links: [],
                errorMessage: error.localizedDescription
            )
        }
    }

    private static func links(
        from pageURL: URL,
        scope: WebLinkExtractionScope
    ) async throws -> [ExtractedWebLink] {
        try Task.checkCancellation()

        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 20
        request.setValue(
            "AriaLane/1.0 (+web link extractor)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "text/html, application/xhtml+xml;q=0.9, text/plain;q=0.5",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebPageLinkExtractorError.unsupportedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WebPageLinkExtractorError.httpStatus(
                httpResponse.statusCode
            )
        }
        guard data.count <= maximumResponseSize else {
            throw WebPageLinkExtractorError.responseTooLarge
        }

        if let mimeType = httpResponse.mimeType?.lowercased(),
           ![
               "application/xhtml+xml",
               "text/html",
               "text/plain"
           ].contains(mimeType) {
            throw WebPageLinkExtractorError.unsupportedContentType(mimeType)
        }

        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        else {
            throw WebPageLinkExtractorError.unreadablePage
        }
        let finalURL = httpResponse.url ?? pageURL
        return HTMLDownloadLinkParser.extract(
            from: html,
            baseURL: finalURL,
            scope: scope
        )
    }

    static func failureMessage(for error: URLError) -> String {
        switch error.code {
        case .timedOut:
            L10n.string("读取网页超时")
        case .notConnectedToInternet:
            L10n.string("当前没有可用的网络连接")
        case .cannotFindHost, .dnsLookupFailed:
            L10n.string("找不到网页服务器")
        case .cannotConnectToHost, .networkConnectionLost:
            L10n.string("无法连接到网页服务器")
        default:
            L10n.string("无法读取网页：\(error.localizedDescription)")
        }
    }
}
