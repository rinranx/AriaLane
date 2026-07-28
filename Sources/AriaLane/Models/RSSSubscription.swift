import Foundation

struct RSSRefreshInterval: Codable, CaseIterable, Hashable, Identifiable, Sendable {
    static let minimumSeconds = 60
    static let maximumSeconds = 30 * 86_400

    static let fifteenMinutes = RSSRefreshInterval(seconds: 900)
    static let thirtyMinutes = RSSRefreshInterval(seconds: 1_800)
    static let hourly = RSSRefreshInterval(seconds: 3_600)
    static let sixHours = RSSRefreshInterval(seconds: 21_600)
    static let twelveHours = RSSRefreshInterval(seconds: 43_200)
    static let daily = RSSRefreshInterval(seconds: 86_400)

    static let allCases: [RSSRefreshInterval] = [
        .fifteenMinutes,
        .thirtyMinutes,
        .hourly,
        .sixHours,
        .twelveHours,
        .daily,
    ]

    let seconds: Int

    init(seconds: Int) {
        self.seconds = min(
            max(seconds, Self.minimumSeconds),
            Self.maximumSeconds
        )
    }

    var id: Int { seconds }
    var timeInterval: TimeInterval { TimeInterval(seconds) }
    var isPreset: Bool { Self.allCases.contains(self) }

    var title: String {
        switch self {
        case .fifteenMinutes: return L10n.string("每 15 分钟")
        case .thirtyMinutes: return L10n.string("每 30 分钟")
        case .hourly: return L10n.string("每小时")
        case .sixHours: return L10n.string("每 6 小时")
        case .twelveHours: return L10n.string("每 12 小时")
        case .daily: return L10n.string("每天")
        default:
            if seconds.isMultiple(of: 86_400) {
                return L10n.string("每 \(seconds / 86_400) 天")
            }
            if seconds.isMultiple(of: 3_600) {
                return L10n.string("每 \(seconds / 3_600) 小时")
            }
            return L10n.string("每 \(seconds / 60) 分钟")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(seconds: try container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(seconds)
    }
}

struct RSSFeedItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var link: String?
    var downloadURL: String?
    var publishedAt: Date?

    var displayTitle: String {
        let normalized = title.trimmed
        return normalized.isEmpty ? L10n.string("未命名条目") : normalized
    }

    var canDownload: Bool {
        downloadURL?.trimmed.isEmpty == false
    }
}

struct RSSSubscription: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var feedURL: String
    var isEnabled: Bool
    var autoDownloadNewItems: Bool
    var refreshInterval: RSSRefreshInterval
    var taskOptions: DownloadTaskOptions
    var targetProfileID: UUID?
    var targetProfileName: String?
    let createdAt: Date
    var lastCheckedAt: Date?
    var lastSuccessfulRefreshAt: Date?
    var lastError: String?
    var items: [RSSFeedItem]
    var seenItemIDs: [String]
    var hasCompletedInitialSync: Bool

    init(
        id: UUID = UUID(),
        title: String,
        feedURL: String,
        isEnabled: Bool = true,
        autoDownloadNewItems: Bool = true,
        refreshInterval: RSSRefreshInterval = .thirtyMinutes,
        taskOptions: DownloadTaskOptions,
        targetProfileID: UUID? = nil,
        targetProfileName: String? = nil,
        createdAt: Date = Date(),
        lastCheckedAt: Date? = nil,
        lastSuccessfulRefreshAt: Date? = nil,
        lastError: String? = nil,
        items: [RSSFeedItem] = [],
        seenItemIDs: [String] = [],
        hasCompletedInitialSync: Bool = false
    ) {
        self.id = id
        self.title = title
        self.feedURL = feedURL
        self.isEnabled = isEnabled
        self.autoDownloadNewItems = autoDownloadNewItems
        self.refreshInterval = refreshInterval
        self.taskOptions = taskOptions
        self.targetProfileID = targetProfileID
        self.targetProfileName = targetProfileName
        self.createdAt = createdAt
        self.lastCheckedAt = lastCheckedAt
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.lastError = lastError
        self.items = Array(items.prefix(50))
        self.seenItemIDs = Array(seenItemIDs.prefix(500))
        self.hasCompletedInitialSync = hasCompletedInitialSync
    }

    var displayName: String {
        let normalized = title.trimmed
        if !normalized.isEmpty {
            return normalized
        }
        return URL(string: feedURL)?.host ?? L10n.string("RSS 订阅")
    }

    var serverDisplayName: String {
        let normalized = targetProfileName?.trimmed ?? ""
        return normalized.isEmpty ? L10n.string("当前 aria2 服务器") : normalized
    }

    func isDue(at date: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        guard let lastCheckedAt else { return true }
        return date.timeIntervalSince(lastCheckedAt) >= refreshInterval.timeInterval
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
            [displayName, feedURL, serverDisplayName, lastError ?? ""]
                + items.map(\.displayTitle)
        )
        .joined(separator: "\n")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return terms.allSatisfy(searchableText.contains)
    }
}

struct RSSSubscriptionArchive: Codable, Equatable, Sendable {
    private(set) var entries: [RSSSubscription]
    let maximumCount: Int

    init(entries: [RSSSubscription] = [], maximumCount: Int = 50) {
        self.maximumCount = max(maximumCount, 1)
        self.entries = Array(
            entries
                .sorted { $0.createdAt < $1.createdAt }
                .prefix(self.maximumCount)
        )
    }

    @discardableResult
    mutating func add(_ entry: RSSSubscription) -> Bool {
        guard entries.count < maximumCount,
              !entries.contains(where: {
                  $0.id == entry.id
                      || $0.feedURL.trimmed.caseInsensitiveCompare(entry.feedURL.trimmed)
                      == .orderedSame
              }) else {
            return false
        }
        entries.append(entry)
        entries.sort { $0.createdAt < $1.createdAt }
        return true
    }

    @discardableResult
    mutating func update(_ entry: RSSSubscription) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return false
        }
        guard !entries.contains(where: {
            $0.id != entry.id
                && $0.feedURL.trimmed.caseInsensitiveCompare(entry.feedURL.trimmed)
                == .orderedSame
        }) else {
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

    func entry(id: UUID) -> RSSSubscription? {
        entries.first { $0.id == id }
    }
}
