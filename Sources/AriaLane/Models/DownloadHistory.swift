import Foundation

enum DownloadHistoryOutcome: String, Codable, Sendable {
    case completed
    case failed

    var title: String {
        switch self {
        case .completed: L10n.string("已完成")
        case .failed: L10n.string("失败")
        }
    }

    var systemImage: String {
        switch self {
        case .completed: "checkmark"
        case .failed: "exclamationmark"
        }
    }
}

struct DownloadHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    let gid: String
    var name: String
    var sourceURI: String?
    var destinationPath: String
    var localFilePaths: [String]? = nil
    var byteCount: Int64
    var outcome: DownloadHistoryOutcome
    var recordedAt: Date
    var detail: String?

    var id: String { gid }

    init?(item: TransferItem, recordedAt: Date = Date()) {
        let outcome: DownloadHistoryOutcome
        switch item.status {
        case .complete:
            outcome = .completed
        case .error:
            outcome = .failed
        case .active, .waiting, .paused, .removed:
            return nil
        }

        self.gid = item.gid
        self.name = item.displayName
        self.sourceURI = item.sourceURI
        self.destinationPath = item.displayPath
        self.localFilePaths = item.files?
            .filter { $0.selected != "false" }
            .map(\.path)
            .map(\.trimmed)
            .filter { !$0.isEmpty }
        self.byteCount = item.totalByteCount
        self.outcome = outcome
        self.recordedAt = recordedAt
        self.detail = item.userFacingError
    }

    func matches(_ searchText: String) -> Bool {
        let terms = searchText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map {
                $0.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
            }
        guard !terms.isEmpty else { return true }

        let searchableText = [
            name,
            sourceURI ?? "",
            destinationPath,
            outcome.title,
            detail ?? "",
            gid
        ]
        .joined(separator: "\n")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        return terms.allSatisfy(searchableText.contains)
    }

    var localPathsForRemoval: [String] {
        let recordedPaths = localFilePaths?
            .map(\.trimmed)
            .filter { !$0.isEmpty } ?? []
        if !recordedPaths.isEmpty {
            return Array(Set(recordedPaths)).sorted()
        }

        let fallback = destinationPath.trimmed
        guard !fallback.isEmpty, fallback != "—" else { return [] }
        return [fallback]
    }
}

struct DownloadHistoryArchive: Codable, Equatable, Sendable {
    private(set) var entries: [DownloadHistoryEntry]
    private(set) var excludedGIDs: Set<String>
    let maximumCount: Int

    init(
        entries: [DownloadHistoryEntry] = [],
        excludedGIDs: Set<String> = [],
        maximumCount: Int = 500
    ) {
        self.maximumCount = max(maximumCount, 1)
        self.excludedGIDs = excludedGIDs
        self.entries = Array(
            entries
                .sorted { $0.recordedAt > $1.recordedAt }
                .prefix(self.maximumCount)
        )
    }

    @discardableResult
    mutating func record(_ item: TransferItem, at date: Date = Date()) -> Bool {
        guard !excludedGIDs.contains(item.gid) else { return false }
        guard var nextEntry = DownloadHistoryEntry(item: item, recordedAt: date) else {
            return false
        }

        if let index = entries.firstIndex(where: { $0.gid == item.gid }) {
            let previousEntry = entries[index]
            if previousEntry.outcome == nextEntry.outcome {
                nextEntry.recordedAt = previousEntry.recordedAt
            }
            guard previousEntry != nextEntry else { return false }
            entries[index] = nextEntry
        } else {
            entries.append(nextEntry)
        }

        normalize()
        return true
    }

    @discardableResult
    mutating func remove(ids: Set<String>) -> Int {
        guard !ids.isEmpty else { return 0 }
        let removedIDs = Set(entries.lazy.map(\.id).filter(ids.contains))
        let previousCount = entries.count
        entries.removeAll { ids.contains($0.id) }
        excludedGIDs.formUnion(removedIDs)
        return previousCount - entries.count
    }

    @discardableResult
    mutating func removeAll() -> Int {
        let previousCount = entries.count
        excludedGIDs.formUnion(entries.map(\.id))
        entries.removeAll()
        return previousCount
    }

    private mutating func normalize() {
        entries.sort { $0.recordedAt > $1.recordedAt }
        if entries.count > maximumCount {
            entries.removeLast(entries.count - maximumCount)
        }
    }
}

enum DownloadHistorySort: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case name
    case size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: L10n.string("最近完成")
        case .oldest: L10n.string("最早完成")
        case .name: L10n.string("名称")
        case .size: L10n.string("文件大小")
        }
    }

    var systemImage: String {
        switch self {
        case .newest: "clock.arrow.circlepath"
        case .oldest: "clock"
        case .name: "textformat"
        case .size: "externaldrive"
        }
    }

    func results(
        in entries: [DownloadHistoryEntry],
        searchText: String
    ) -> [DownloadHistoryEntry] {
        entries
            .filter { $0.matches(searchText) }
            .sorted { first, second in
                switch self {
                case .newest:
                    first.recordedAt > second.recordedAt
                case .oldest:
                    first.recordedAt < second.recordedAt
                case .name:
                    first.name.localizedStandardCompare(second.name) == .orderedAscending
                case .size:
                    first.byteCount == second.byteCount
                        ? first.recordedAt > second.recordedAt
                        : first.byteCount > second.byteCount
                }
            }
    }
}
