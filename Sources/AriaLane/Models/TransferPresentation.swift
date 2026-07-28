import Foundation

struct SpeedSample: Identifiable, Equatable, Sendable {
    let timestamp: Date
    let downloadBytesPerSecond: Int64
    let uploadBytesPerSecond: Int64

    var id: Date { timestamp }
}

struct SpeedSampleSeries: Equatable, Sendable {
    private(set) var samples: [SpeedSample] = []

    let retentionInterval: TimeInterval
    let maximumCount: Int
    let minimumSpacing: TimeInterval

    init(
        retentionInterval: TimeInterval = 180,
        maximumCount: Int = 145,
        minimumSpacing: TimeInterval = 0.7
    ) {
        self.retentionInterval = max(retentionInterval, 1)
        self.maximumCount = max(maximumCount, 2)
        self.minimumSpacing = max(minimumSpacing, 0)
    }

    mutating func record(
        downloadBytesPerSecond: Int64,
        uploadBytesPerSecond: Int64,
        at timestamp: Date = Date()
    ) {
        let sample = SpeedSample(
            timestamp: timestamp,
            downloadBytesPerSecond: max(downloadBytesPerSecond, 0),
            uploadBytesPerSecond: max(uploadBytesPerSecond, 0)
        )

        if let previous = samples.last,
           timestamp.timeIntervalSince(previous.timestamp) < minimumSpacing {
            samples[samples.count - 1] = sample
        } else {
            samples.append(sample)
        }

        let cutoff = timestamp.addingTimeInterval(-retentionInterval)
        samples.removeAll { $0.timestamp < cutoff }
        if samples.count > maximumCount {
            samples.removeFirst(samples.count - maximumCount)
        }
    }
}

enum TransferSortField: String, CaseIterable, Identifiable {
    case queue
    case name
    case size
    case progress
    case speed
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queue: L10n.string("队列")
        case .name: L10n.string("名称")
        case .size: L10n.string("文件大小")
        case .progress: L10n.string("进度")
        case .speed: L10n.string("下载速度")
        case .status: L10n.string("状态")
        }
    }

    var systemImage: String {
        switch self {
        case .queue: "list.number"
        case .name: "textformat"
        case .size: "externaldrive"
        case .progress: "chart.bar.fill"
        case .speed: "gauge.with.dots.needle.50percent"
        case .status: "circle.grid.2x2"
        }
    }

    var preferredDirection: TransferSortDirection {
        switch self {
        case .size, .progress, .speed:
            .descending
        case .queue, .name, .status:
            .ascending
        }
    }
}

enum TransferSortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending: L10n.string("升序")
        case .descending: L10n.string("降序")
        }
    }

    var systemImage: String {
        switch self {
        case .ascending: "arrow.up"
        case .descending: "arrow.down"
        }
    }
}

enum TransferListQuery {
    static func results(
        in items: [TransferItem],
        filter: TransferFilter,
        searchText: String,
        sortField: TransferSortField,
        direction: TransferSortDirection
    ) -> [TransferItem] {
        let terms = normalizedTerms(searchText)
        let filtered = items.filter { item in
            guard filter.includes(item) else { return false }
            guard !terms.isEmpty else { return true }

            let searchableText = [
                item.displayName,
                item.displayPath,
                item.sourceURI ?? "",
                item.status.title,
                item.gid
            ]
            .joined(separator: "\n")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

            return terms.allSatisfy(searchableText.contains)
        }

        return filtered
            .enumerated()
            .sorted { first, second in
                let comparison = compare(
                    first.element,
                    second.element,
                    field: sortField,
                    firstQueueIndex: first.offset,
                    secondQueueIndex: second.offset
                )
                if comparison == .orderedSame {
                    return first.offset < second.offset
                }
                switch direction {
                case .ascending:
                    return comparison == .orderedAscending
                case .descending:
                    return comparison == .orderedDescending
                }
            }
            .map(\.element)
    }

    private static func normalizedTerms(_ searchText: String) -> [String] {
        searchText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map {
                $0.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
            }
    }

    private static func compare(
        _ first: TransferItem,
        _ second: TransferItem,
        field: TransferSortField,
        firstQueueIndex: Int,
        secondQueueIndex: Int
    ) -> ComparisonResult {
        switch field {
        case .queue:
            compare(firstQueueIndex, secondQueueIndex)
        case .name:
            first.displayName.localizedStandardCompare(second.displayName)
        case .size:
            compare(first.totalByteCount, second.totalByteCount)
        case .progress:
            compare(first.progress, second.progress)
        case .speed:
            compare(first.downloadSpeedValue, second.downloadSpeedValue)
        case .status:
            compare(first.sortRank, second.sortRank)
        }
    }

    private static func compare<Value: Comparable>(
        _ first: Value,
        _ second: Value
    ) -> ComparisonResult {
        if first < second { return .orderedAscending }
        if first > second { return .orderedDescending }
        return .orderedSame
    }
}
