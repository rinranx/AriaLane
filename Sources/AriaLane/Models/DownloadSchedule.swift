import Foundation

enum ScheduleFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case once
    case hourly
    case daily
    case weekdays
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: L10n.string("仅一次")
        case .hourly: L10n.string("每小时")
        case .daily: L10n.string("每天")
        case .weekdays: L10n.string("工作日")
        case .weekly: L10n.string("每周")
        case .monthly: L10n.string("每月")
        }
    }

    var shortTitle: String {
        switch self {
        case .once: L10n.string("单次")
        case .hourly: L10n.string("每小时")
        case .daily: L10n.string("每天")
        case .weekdays: L10n.string("工作日")
        case .weekly: L10n.string("每周")
        case .monthly: L10n.string("每月")
        }
    }

    func nextDate(
        after referenceDate: Date,
        from scheduledDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard self != .once else { return nil }

        var candidate = scheduledDate
        var iterationCount = 0
        repeat {
            switch self {
            case .once:
                return nil
            case .hourly:
                candidate = calendar.date(byAdding: .hour, value: 1, to: candidate)
                    ?? candidate.addingTimeInterval(3_600)
            case .daily:
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate)
                    ?? candidate.addingTimeInterval(86_400)
            case .weekdays:
                repeat {
                    candidate = calendar.date(byAdding: .day, value: 1, to: candidate)
                        ?? candidate.addingTimeInterval(86_400)
                } while calendar.isDateInWeekend(candidate)
            case .weekly:
                candidate = calendar.date(byAdding: .weekOfYear, value: 1, to: candidate)
                    ?? candidate.addingTimeInterval(7 * 86_400)
            case .monthly:
                candidate = calendar.date(byAdding: .month, value: 1, to: candidate)
                    ?? candidate.addingTimeInterval(30 * 86_400)
            }
            iterationCount += 1
        } while candidate <= referenceDate && iterationCount < 100_000

        return candidate > referenceDate ? candidate : nil
    }
}

struct ScheduledDownload: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var urls: [String]
    var taskOptions: DownloadTaskOptions
    var scheduledAt: Date
    var frequency: ScheduleFrequency
    var createdAt: Date
    var targetProfileID: UUID?
    var targetProfileName: String?
    var submissionGIDs: [String]?

    init(
        id: UUID = UUID(),
        urls: [String],
        taskOptions: DownloadTaskOptions,
        scheduledAt: Date,
        frequency: ScheduleFrequency = .once,
        createdAt: Date = Date(),
        targetProfileID: UUID? = nil,
        targetProfileName: String? = nil,
        submissionGIDs: [String]? = nil
    ) {
        self.id = id
        self.urls = urls
        self.taskOptions = taskOptions
        self.scheduledAt = scheduledAt
        self.frequency = frequency
        self.createdAt = createdAt
        self.targetProfileID = targetProfileID
        self.targetProfileName = targetProfileName
        self.submissionGIDs = submissionGIDs
            ?? DownloadSubmissionIdentifier.makeGIDs(count: urls.count)
    }

    var displayName: String {
        let outputName = taskOptions.outputFileName.trimmed
        if !outputName.isEmpty {
            return outputName
        }
        guard let first = urls.first, let url = URL(string: first) else {
            return urls.count == 1 ? L10n.string("计划下载") : L10n.string("\(urls.count) 个计划下载")
        }
        let candidate = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        if !candidate.isEmpty {
            return urls.count == 1 ? candidate : L10n.string("\(candidate) 等 \(urls.count) 个")
        }
        return urls.count == 1 ? (url.host ?? L10n.string("计划下载")) : L10n.string("\(urls.count) 个计划下载")
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

        let searchableText = (
            [
                displayName,
                taskOptions.directory,
                taskOptions.outputFileName,
                serverDisplayName
            ]
                + urls
        )
        .joined(separator: "\n")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return terms.allSatisfy(searchableText.contains)
    }

    var serverDisplayName: String {
        let normalized = targetProfileName?.trimmed ?? ""
        return normalized.isEmpty ? L10n.string("当前 aria2 服务器") : normalized
    }

    func isForProfile(_ profileID: UUID?) -> Bool {
        targetProfileID == nil || targetProfileID == profileID
    }

    func isOverdue(at date: Date = Date()) -> Bool {
        scheduledAt <= date
    }

    func nextScheduledDate(
        after date: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        frequency.nextDate(after: date, from: scheduledAt, calendar: calendar)
    }

    mutating func prepareSubmissionGIDs() {
        guard let submissionGIDs,
              submissionGIDs.count == urls.count,
              submissionGIDs.allSatisfy(DownloadSubmissionIdentifier.isValidGID) else {
            self.submissionGIDs = DownloadSubmissionIdentifier.makeGIDs(count: urls.count)
            return
        }
    }

    func duplicated(
        at date: Date,
        createdAt: Date = Date()
    ) -> ScheduledDownload {
        ScheduledDownload(
            urls: urls,
            taskOptions: taskOptions,
            scheduledAt: date,
            frequency: frequency,
            createdAt: createdAt,
            targetProfileID: targetProfileID,
            targetProfileName: targetProfileName
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case urls
        case taskOptions
        case scheduledAt
        case frequency
        case createdAt
        case targetProfileID
        case targetProfileName
        case submissionGIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        urls = try container.decode([String].self, forKey: .urls)
        taskOptions = try container.decode(DownloadTaskOptions.self, forKey: .taskOptions)
        scheduledAt = try container.decode(Date.self, forKey: .scheduledAt)
        frequency = try container.decodeIfPresent(
            ScheduleFrequency.self,
            forKey: .frequency
        ) ?? .once
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        targetProfileID = try container.decodeIfPresent(UUID.self, forKey: .targetProfileID)
        targetProfileName = try container.decodeIfPresent(
            String.self,
            forKey: .targetProfileName
        )
        submissionGIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .submissionGIDs
        )
    }
}

struct DownloadScheduleArchive: Codable, Equatable, Sendable {
    private(set) var entries: [ScheduledDownload]
    let maximumCount: Int

    init(entries: [ScheduledDownload] = [], maximumCount: Int = 200) {
        self.maximumCount = max(maximumCount, 1)
        self.entries = Array(
            entries
                .sorted { $0.scheduledAt < $1.scheduledAt }
                .prefix(self.maximumCount)
        )
    }

    @discardableResult
    mutating func add(_ entry: ScheduledDownload) -> Bool {
        guard !entries.contains(where: { $0.id == entry.id }) else { return false }
        entries.append(entry)
        normalize()
        return true
    }

    @discardableResult
    mutating func remove(id: UUID) -> Bool {
        let previousCount = entries.count
        entries.removeAll { $0.id == id }
        return entries.count != previousCount
    }

    func entry(id: UUID) -> ScheduledDownload? {
        entries.first { $0.id == id }
    }

    @discardableResult
    mutating func update(_ entry: ScheduledDownload) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return false
        }
        entries[index] = entry
        normalize()
        return true
    }

    @discardableResult
    mutating func duplicate(id: UUID, scheduledAt: Date) -> ScheduledDownload? {
        guard let source = entry(id: id) else { return nil }
        let copy = source.duplicated(at: scheduledAt)
        guard add(copy) else { return nil }
        return copy
    }

    func due(at date: Date = Date()) -> [ScheduledDownload] {
        entries.filter { $0.scheduledAt <= date }
    }

    private mutating func normalize() {
        entries.sort { $0.scheduledAt < $1.scheduledAt }
        if entries.count > maximumCount {
            entries.removeLast(entries.count - maximumCount)
        }
    }
}

struct NightSpeedSchedule: Equatable, Sendable {
    var isEnabled: Bool
    var startMinute: Int
    var endMinute: Int
    var downloadLimitKiB: Int
    var uploadLimitKiB: Int

    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        let start = normalized(startMinute)
        let end = normalized(endMinute)
        guard start != end else { return false }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        let current = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if start < end {
            return current >= start && current < end
        }
        return current >= start || current < end
    }

    private func normalized(_ minute: Int) -> Int {
        min(max(minute, 0), 1_439)
    }
}
