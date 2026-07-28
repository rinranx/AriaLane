import Foundation

enum TransferFormatter {
    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func speed(_ value: Int64) -> String {
        "\(bytes(value))/s"
    }

    static func speedLimit(_ kibibytesPerSecond: Int) -> String {
        guard kibibytesPerSecond > 0 else { return L10n.string("不限速") }
        guard kibibytesPerSecond >= 1_024 else {
            return "\(kibibytesPerSecond) KB/s"
        }

        let hundredths = Int(
            (Double(kibibytesPerSecond) / 1_024 * 100).rounded()
        )
        let whole = hundredths / 100
        let remainder = hundredths % 100

        if remainder == 0 {
            return "\(whole) MB/s"
        }
        if remainder.isMultiple(of: 10) {
            return "\(whole).\(remainder / 10) MB/s"
        }
        return String(format: "%d.%02d MB/s", whole, remainder)
    }

    static func percent(_ progress: Double) -> String {
        "\(Int((progress * 100).rounded()))%"
    }

    static func duration(_ interval: TimeInterval?) -> String {
        guard let interval, interval.isFinite, interval >= 0 else {
            return "—"
        }

        let totalMinutes = max(Int(interval / 60), 1)
        if totalMinutes < 60 {
            return L10n.string("约 \(totalMinutes) 分钟")
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours < 24 {
            return minutes == 0 ? L10n.string("约 \(hours) 小时") : L10n.string("约 \(hours) 小时 \(minutes) 分钟")
        }

        let days = hours / 24
        return L10n.string("约 \(days) 天")
    }
}

struct ParsedDownloadInput: Equatable {
    let urls: [String]
    let rejectedCount: Int
}

enum DownloadInputParser {
    private static let supportedSchemes = Set([
        "http",
        "https",
        "ftp",
        "sftp",
        "magnet"
    ])

    static func parse(_ input: String) -> ParsedDownloadInput {
        var urls: [String] = []
        var seen = Set<String>()
        var rejectedCount = 0

        for rawLine in input.components(separatedBy: .newlines) {
            let candidate = rawLine.trimmed
            guard !candidate.isEmpty else { continue }

            let scheme = URLComponents(string: candidate)?.scheme?.lowercased()
            guard let scheme, supportedSchemes.contains(scheme) else {
                rejectedCount += 1
                continue
            }

            if seen.insert(candidate).inserted {
                urls.append(candidate)
            }
        }

        return ParsedDownloadInput(urls: urls, rejectedCount: rejectedCount)
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
