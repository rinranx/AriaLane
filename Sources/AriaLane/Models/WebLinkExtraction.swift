import Foundation

enum WebLinkExtractionScope: String, CaseIterable, Identifiable, Sendable {
    case downloads
    case allSupportedLinks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads:
            L10n.string("下载链接")
        case .allSupportedLinks:
            L10n.string("全部链接")
        }
    }

    var detail: String {
        switch self {
        case .downloads:
            L10n.string("只保留常见文件、下载按钮与 magnet 链接")
        case .allSupportedLinks:
            L10n.string("保留网页中的全部 HTTP、FTP、SFTP 与 magnet 链接")
        }
    }
}

struct ParsedWebPageInput: Equatable, Sendable {
    let urls: [URL]
    let rejectedCount: Int
    let omittedCount: Int
}

enum WebPageInputParser {
    static let maximumPageCount = 20

    static func parse(_ input: String) -> ParsedWebPageInput {
        var urls: [URL] = []
        var seen = Set<String>()
        var rejectedCount = 0
        var omittedCount = 0

        for rawLine in input.components(separatedBy: .newlines) {
            let candidate = rawLine.trimmed
            guard !candidate.isEmpty else { continue }
            guard let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false
            else {
                rejectedCount += 1
                continue
            }

            let normalized = url.absoluteString
            guard seen.insert(normalized).inserted else { continue }
            guard urls.count < maximumPageCount else {
                omittedCount += 1
                continue
            }
            urls.append(url)
        }

        return ParsedWebPageInput(
            urls: urls,
            rejectedCount: rejectedCount,
            omittedCount: omittedCount
        )
    }
}

struct ExtractedWebLink: Identifiable, Equatable, Hashable, Sendable {
    let url: String
    let sourcePageURL: String
    let label: String
    let isExplicitDownload: Bool

    var id: String { url }

    var displayTitle: String {
        if !label.isEmpty {
            return label
        }
        guard let parsedURL = URL(string: url) else { return url }
        if !parsedURL.lastPathComponent.isEmpty {
            return parsedURL.lastPathComponent.removingPercentEncoding
                ?? parsedURL.lastPathComponent
        }
        return parsedURL.host ?? url
    }

    var locationDescription: String {
        guard let parsedURL = URL(string: url) else { return url }
        let host = parsedURL.host ?? parsedURL.scheme ?? ""
        let path = parsedURL.path.isEmpty ? "/" : parsedURL.path
        let querySuffix = parsedURL.query == nil ? "" : "?…"
        return "\(host)\(path)\(querySuffix)"
    }

    var sourceHost: String {
        URL(string: sourcePageURL)?.host ?? sourcePageURL
    }
}

struct WebLinkExtractionFailure: Identifiable, Equatable, Sendable {
    let pageURL: String
    let message: String

    var id: String { pageURL }
}

struct WebLinkExtractionBatch: Equatable, Sendable {
    let requestedPageCount: Int
    let links: [ExtractedWebLink]
    let failures: [WebLinkExtractionFailure]
}
