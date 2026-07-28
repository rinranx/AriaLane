import AppKit
import Foundation

struct IncomingDownloadRequest: Equatable, Sendable {
    let urls: [String]

    static func parse(_ url: URL) -> IncomingDownloadRequest? {
        guard url.scheme?.lowercased() == "arialane",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let route = components.host?.lowercased()
            ?? components.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
        guard route == "add" else { return nil }

        let input = components.queryItems?
            .filter { ["url", "urls", "text"].contains($0.name.lowercased()) }
            .compactMap(\.value)
            .joined(separator: "\n")
            ?? ""
        let parsed = DownloadInputParser.parse(input)
        guard !parsed.urls.isEmpty else { return nil }
        return IncomingDownloadRequest(urls: parsed.urls)
    }
}

enum DownloadPasteboardReader {
    static func validatedInput(from pasteboard: NSPasteboard = .general) -> String? {
        let candidates = [
            pasteboard.string(forType: .string),
            pasteboard.string(forType: .URL)
        ]
        for candidate in candidates {
            guard let candidate else { continue }
            let parsed = DownloadInputParser.parse(candidate)
            if !parsed.urls.isEmpty {
                return parsed.urls.joined(separator: "\n")
            }
        }
        return nil
    }
}
