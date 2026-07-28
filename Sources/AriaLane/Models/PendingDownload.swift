import Foundation

enum DownloadSubmissionIdentifier {
    static func makeGID() -> String {
        String(
            UUID()
                .uuidString
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
                .prefix(16)
        )
    }

    static func makeGIDs(count: Int) -> [String] {
        guard count > 0 else { return [] }
        return (0..<count).map { _ in makeGID() }
    }

    static func isValidGID(_ value: String) -> Bool {
        value.count == 16
            && value.unicodeScalars.allSatisfy(
                CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains
            )
    }
}

struct PendingDownloadRetryPolicy: Equatable, Sendable {
    var initialDelay: TimeInterval = 5
    var maximumDelay: TimeInterval = 300

    func delay(afterAttempt attemptCount: Int) -> TimeInterval {
        guard attemptCount > 0 else { return 0 }
        let exponent = min(max(attemptCount - 1, 0), 10)
        return min(initialDelay * pow(2, Double(exponent)), maximumDelay)
    }
}

struct PendingDownload: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var url: String
    var taskOptions: DownloadTaskOptions
    let submissionGID: String
    var targetProfileID: UUID?
    var targetProfileName: String?
    var originScheduleID: UUID?
    var originScheduleIndex: Int?
    var originScheduleOccurrenceID: UUID?
    var replacesGID: String?
    let createdAt: Date
    var lastAttemptAt: Date?
    var attemptCount: Int
    var lastError: String?

    init(
        id: UUID = UUID(),
        url: String,
        taskOptions: DownloadTaskOptions,
        submissionGID: String = DownloadSubmissionIdentifier.makeGID(),
        targetProfileID: UUID? = nil,
        targetProfileName: String? = nil,
        originScheduleID: UUID? = nil,
        originScheduleIndex: Int? = nil,
        originScheduleOccurrenceID: UUID? = nil,
        replacesGID: String? = nil,
        createdAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        attemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.url = url
        self.taskOptions = taskOptions
        self.submissionGID = submissionGID
        self.targetProfileID = targetProfileID
        self.targetProfileName = targetProfileName
        self.originScheduleID = originScheduleID
        self.originScheduleIndex = originScheduleIndex
        self.originScheduleOccurrenceID = originScheduleOccurrenceID
        self.replacesGID = replacesGID
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
        self.attemptCount = max(attemptCount, 0)
        self.lastError = lastError
    }

    var displayName: String {
        let outputName = taskOptions.outputFileName.trimmed
        if !outputName.isEmpty {
            return outputName
        }
        guard let parsedURL = URL(string: url) else {
            return L10n.string("待发送下载")
        }
        if parsedURL.scheme?.lowercased() == "magnet",
           let name = URLComponents(string: url)?
            .queryItems?
            .first(where: { $0.name == "dn" })?
            .value,
           !name.isEmpty {
            return name
        }
        let candidate =
            parsedURL.lastPathComponent.removingPercentEncoding
            ?? parsedURL.lastPathComponent
        return candidate.isEmpty ? (parsedURL.host ?? L10n.string("待发送下载")) : candidate
    }

    var hasFailed: Bool {
        lastError?.trimmed.isEmpty == false
    }

    var serverDisplayName: String {
        let normalized = targetProfileName?.trimmed ?? ""
        return normalized.isEmpty ? L10n.string("当前 aria2 服务器") : normalized
    }

    func isForProfile(_ profileID: UUID?) -> Bool {
        targetProfileID == nil || targetProfileID == profileID
    }

    func isEligibleForAutomaticRetry(
        at date: Date = Date(),
        policy: PendingDownloadRetryPolicy = PendingDownloadRetryPolicy()
    ) -> Bool {
        guard let lastAttemptAt else { return true }
        return date.timeIntervalSince(lastAttemptAt)
            >= policy.delay(afterAttempt: attemptCount)
    }

    mutating func recordFailure(_ message: String, at date: Date = Date()) {
        attemptCount += 1
        lastAttemptAt = date
        lastError = message
    }

    mutating func prepareForManualRetry() {
        lastAttemptAt = nil
        lastError = nil
    }

    mutating func retarget(profileID: UUID?, profileName: String?) {
        targetProfileID = profileID
        targetProfileName = profileName
        prepareForManualRetry()
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
            displayName,
            url,
            taskOptions.directory,
            serverDisplayName,
            lastError ?? ""
        ]
        .joined(separator: "\n")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return terms.allSatisfy(searchableText.contains)
    }
}

struct PendingDownloadArchive: Codable, Equatable, Sendable {
    private(set) var entries: [PendingDownload]
    let maximumCount: Int

    init(entries: [PendingDownload] = [], maximumCount: Int = 500) {
        self.maximumCount = max(maximumCount, 1)
        self.entries = Array(
            entries
                .sorted { $0.createdAt < $1.createdAt }
                .prefix(self.maximumCount)
        )
    }

    @discardableResult
    mutating func add(_ entry: PendingDownload) -> Bool {
        guard !entries.contains(where: {
            if $0.id == entry.id || $0.submissionGID == entry.submissionGID {
                return true
            }
            if let replacedGID = entry.replacesGID,
               $0.replacesGID == replacedGID {
                return true
            }
            guard let scheduleID = entry.originScheduleID,
                  let scheduleIndex = entry.originScheduleIndex else {
                return false
            }
            if let occurrenceID = entry.originScheduleOccurrenceID {
                return $0.originScheduleOccurrenceID == occurrenceID
                    && $0.originScheduleIndex == scheduleIndex
            }
            return $0.originScheduleID == scheduleID
                && $0.originScheduleIndex == scheduleIndex
        }) else {
            return false
        }
        guard entries.count < maximumCount else { return false }
        entries.append(entry)
        entries.sort { $0.createdAt < $1.createdAt }
        return true
    }

    @discardableResult
    mutating func add(contentsOf newEntries: [PendingDownload]) -> Int {
        newEntries.reduce(into: 0) { addedCount, entry in
            if add(entry) {
                addedCount += 1
            }
        }
    }

    @discardableResult
    mutating func update(_ entry: PendingDownload) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return false
        }
        entries[index] = entry
        return true
    }

    @discardableResult
    mutating func remove(id: UUID) -> Bool {
        let previousCount = entries.count
        entries.removeAll { $0.id == id }
        return entries.count != previousCount
    }

    @discardableResult
    mutating func remove(ids: Set<UUID>) -> Int {
        let previousCount = entries.count
        entries.removeAll { ids.contains($0.id) }
        return previousCount - entries.count
    }

    func entry(id: UUID) -> PendingDownload? {
        entries.first { $0.id == id }
    }
}
