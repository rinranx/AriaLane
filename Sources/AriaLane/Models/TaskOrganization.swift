import Foundation

enum TaskContentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case installer
    case video
    case audio
    case document
    case image
    case archive
    case diskImage
    case code
    case other
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .installer: L10n.string("安装包")
        case .video: L10n.string("视频")
        case .audio: L10n.string("音频")
        case .document: L10n.string("文档")
        case .image: L10n.string("图片")
        case .archive: L10n.string("压缩包")
        case .diskImage: L10n.string("磁盘映像")
        case .code: L10n.string("代码")
        case .other: L10n.string("其他")
        case .unknown: L10n.string("未知")
        }
    }

    var systemImage: String {
        switch self {
        case .installer: "shippingbox"
        case .video: "film"
        case .audio: "waveform"
        case .document: "doc.text"
        case .image: "photo"
        case .archive: "archivebox"
        case .diskImage: "opticaldisc"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .other: "doc"
        case .unknown: "questionmark.square.dashed"
        }
    }

    static func classify(path: String) -> TaskContentType {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard !ext.isEmpty else { return .unknown }

        if installerExtensions.contains(ext) { return .installer }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if documentExtensions.contains(ext) { return .document }
        if imageExtensions.contains(ext) { return .image }
        if archiveExtensions.contains(ext) { return .archive }
        if diskImageExtensions.contains(ext) { return .diskImage }
        if codeExtensions.contains(ext) { return .code }
        return .other
    }

    static func classify(files: [TransferFile]?) -> TaskContentType {
        guard let files else { return .unknown }
        let selected = files.filter { $0.selected != "false" }
        let candidates = selected.isEmpty ? files : selected
        guard let primary = candidates.max(by: { first, second in
            if first.byteCount == second.byteCount {
                return first.path.count < second.path.count
            }
            return first.byteCount < second.byteCount
        }) else {
            return .unknown
        }
        return classify(path: primary.path)
    }

    private static let installerExtensions: Set<String> = [
        "app", "dmg", "ipa", "mpkg", "pkg", "xip"
    ]
    private static let videoExtensions: Set<String> = [
        "3gp", "avi", "flv", "m2ts", "m4v", "mkv", "mov", "mp4", "mpeg",
        "mpg", "mts", "ts", "webm", "wmv"
    ]
    private static let audioExtensions: Set<String> = [
        "aac", "aiff", "alac", "ape", "flac", "m4a", "mp3", "ogg", "opus",
        "wav", "wma"
    ]
    private static let documentExtensions: Set<String> = [
        "csv", "doc", "docx", "epub", "key", "md", "mobi", "numbers", "ods",
        "odt", "pages", "pdf", "ppt", "pptx", "rtf", "tex", "txt", "xls",
        "xlsx"
    ]
    private static let imageExtensions: Set<String> = [
        "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png",
        "psd", "raw", "svg", "tif", "tiff", "webp"
    ]
    private static let archiveExtensions: Set<String> = [
        "7z", "bz2", "cab", "gz", "lz", "rar", "tar", "tbz", "tgz", "xz",
        "zip", "zst"
    ]
    private static let diskImageExtensions: Set<String> = [
        "img", "iso", "sparsebundle", "sparseimage"
    ]
    private static let codeExtensions: Set<String> = [
        "c", "cc", "cpp", "css", "go", "h", "hpp", "html", "java", "js",
        "json", "jsx", "kt", "m", "mm", "php", "plist", "py", "rb", "rs",
        "sh", "sql", "swift", "toml", "ts", "tsx", "xml", "yaml", "yml"
    ]
}

enum TaskTransferProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case http
    case ftp
    case sftp
    case magnet
    case torrent
    case metalink
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .http: "HTTP"
        case .ftp: "FTP"
        case .sftp: "SFTP"
        case .magnet: "Magnet"
        case .torrent: "Torrent"
        case .metalink: "Metalink"
        case .unknown: L10n.string("未知")
        }
    }

    var systemImage: String {
        switch self {
        case .http: "network"
        case .ftp: "server.rack"
        case .sftp: "lock.shield"
        case .magnet: "magnet"
        case .torrent: "point.3.connected.trianglepath.dotted"
        case .metalink: "link.badge.plus"
        case .unknown: "questionmark.circle"
        }
    }

    static func infer(fromURI uri: String?) -> TaskTransferProtocol {
        guard let uri = uri?.trimmed, !uri.isEmpty else { return .unknown }
        if uri.lowercased().hasPrefix("magnet:") {
            return .magnet
        }
        switch URLComponents(string: uri)?.scheme?.lowercased() {
        case "http", "https": return .http
        case "ftp", "ftps": return .ftp
        case "sftp": return .sftp
        default: return .unknown
        }
    }

    static func infer(from item: TransferItem) -> TaskTransferProtocol {
        let uriProtocol = infer(fromURI: item.sourceURI)
        if uriProtocol == .magnet {
            return .magnet
        }
        if item.bittorrent != nil {
            return .torrent
        }
        return uriProtocol
    }
}

enum TaskLifecycle: String, Codable, CaseIterable, Identifiable, Sendable {
    case downloading
    case waiting
    case paused
    case seeding
    case completed
    case failed
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloading: L10n.string("下载中")
        case .waiting: L10n.string("等待中")
        case .paused: L10n.string("已暂停")
        case .seeding: L10n.string("做种中")
        case .completed: L10n.string("已完成")
        case .failed: L10n.string("失败")
        case .unknown: L10n.string("未知")
        }
    }

    var systemImage: String {
        switch self {
        case .downloading: "arrow.down.circle"
        case .waiting: "clock"
        case .paused: "pause.circle"
        case .seeding: "arrow.up.circle"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .unknown: "questionmark.circle"
        }
    }

    var isTerminal: Bool {
        self == .completed || self == .failed
    }

    static func infer(from item: TransferItem) -> TaskLifecycle {
        switch item.status {
        case .active:
            if item.isBitTorrent, item.seeder == "true" {
                return .seeding
            }
            return .downloading
        case .waiting: return .waiting
        case .paused: return .paused
        case .error: return .failed
        case .complete: return .completed
        case .removed: return .unknown
        }
    }

    static func infer(from outcome: DownloadHistoryOutcome) -> TaskLifecycle {
        switch outcome {
        case .completed: .completed
        case .failed: .failed
        }
    }
}

enum TaskTagColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue
    case indigo
    case purple
    case mint
    case green
    case orange
    case red
    case gray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: L10n.string("蓝色")
        case .indigo: L10n.string("靛蓝")
        case .purple: L10n.string("紫色")
        case .mint: L10n.string("薄荷")
        case .green: L10n.string("绿色")
        case .orange: L10n.string("橙色")
        case .red: L10n.string("红色")
        case .gray: L10n.string("灰色")
        }
    }
}

struct TaskTag: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var color: TaskTagColor
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        color: TaskTagColor = .blue,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
    }

    var displayName: String {
        let normalized = name.trimmed
        return normalized.isEmpty ? L10n.string("未命名标签") : normalized
    }
}

struct TaskAttemptKey: Codable, Hashable, Sendable {
    var serverProfileID: UUID?
    var gid: String
}

struct TaskEntityRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var attempts: Set<TaskAttemptKey>
    var primaryAttempt: TaskAttemptKey?
    var name: String
    var sourceURI: String?
    var sourceDomain: String?
    var destinationPath: String
    var byteCount: Int64
    var contentType: TaskContentType
    var transferProtocol: TaskTransferProtocol
    var lifecycle: TaskLifecycle
    var addedAt: Date
    var addedAtIsInferred: Bool
    var completedAt: Date?
    var tagIDs: Set<UUID>
    var detail: String?
    var hasHistory: Bool

    init(
        id: UUID = UUID(),
        attempts: Set<TaskAttemptKey>,
        primaryAttempt: TaskAttemptKey?,
        name: String,
        sourceURI: String?,
        destinationPath: String,
        byteCount: Int64,
        contentType: TaskContentType,
        transferProtocol: TaskTransferProtocol,
        lifecycle: TaskLifecycle,
        addedAt: Date,
        addedAtIsInferred: Bool,
        completedAt: Date? = nil,
        tagIDs: Set<UUID> = [],
        detail: String? = nil,
        hasHistory: Bool = false
    ) {
        self.id = id
        self.attempts = attempts
        self.primaryAttempt = primaryAttempt
        self.name = name
        self.sourceURI = sourceURI
        self.sourceDomain = TaskDomain.normalizedHost(from: sourceURI)
        self.destinationPath = destinationPath
        self.byteCount = max(byteCount, 0)
        self.contentType = contentType
        self.transferProtocol = transferProtocol
        self.lifecycle = lifecycle
        self.addedAt = addedAt
        self.addedAtIsInferred = addedAtIsInferred
        self.completedAt = completedAt
        self.tagIDs = tagIDs
        self.detail = detail
        self.hasHistory = hasHistory
    }

    var displayName: String {
        let normalized = name.trimmed
        return normalized.isEmpty ? L10n.string("未命名下载") : normalized
    }

    func matches(_ searchText: String, tagNames: [String] = []) -> Bool {
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

        let searchable = (
            [
                displayName,
                sourceURI ?? "",
                sourceDomain ?? "",
                destinationPath,
                contentType.title,
                transferProtocol.title,
                lifecycle.title,
                detail ?? ""
            ]
            + attempts.map(\.gid)
            + tagNames
        )
        .joined(separator: "\n")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        return terms.allSatisfy(searchable.contains)
    }
}

enum SmartFolderMatchMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case any

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L10n.string("符合全部条件")
        case .any: L10n.string("符合任一条件")
        }
    }
}

enum SmartRuleField: String, Codable, CaseIterable, Identifiable, Sendable {
    case tag
    case contentType
    case transferProtocol
    case sourceDomain
    case addedDate
    case completedDate
    case lifecycle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tag: L10n.string("标签")
        case .contentType: L10n.string("内容类型")
        case .transferProtocol: L10n.string("传输协议")
        case .sourceDomain: L10n.string("来源域名")
        case .addedDate: L10n.string("加入日期")
        case .completedDate: L10n.string("完成日期")
        case .lifecycle: L10n.string("任务状态")
        }
    }

    var systemImage: String {
        switch self {
        case .tag: "tag"
        case .contentType: "doc.on.doc"
        case .transferProtocol: "arrow.left.arrow.right"
        case .sourceDomain: "globe"
        case .addedDate: "calendar.badge.plus"
        case .completedDate: "calendar.badge.checkmark"
        case .lifecycle: "circle.grid.2x2"
        }
    }

    var allowedOperators: [SmartRuleOperator] {
        switch self {
        case .tag, .contentType, .transferProtocol, .lifecycle:
            [.isAnyOf, .isNotAnyOf]
        case .sourceDomain:
            [.equals, .includesSubdomains, .notEquals]
        case .addedDate, .completedDate:
            [.withinLastDays, .before, .after, .between]
        }
    }
}

enum SmartRuleOperator: String, Codable, CaseIterable, Identifiable, Sendable {
    case isAnyOf
    case isNotAnyOf
    case equals
    case includesSubdomains
    case notEquals
    case withinLastDays
    case before
    case after
    case between

    var id: String { rawValue }

    var title: String {
        switch self {
        case .isAnyOf: L10n.string("是其中任一")
        case .isNotAnyOf: L10n.string("不是其中任一")
        case .equals: L10n.string("等于")
        case .includesSubdomains: L10n.string("包含子域名")
        case .notEquals: L10n.string("不等于")
        case .withinLastDays: L10n.string("最近若干天")
        case .before: L10n.string("早于")
        case .after: L10n.string("晚于")
        case .between: L10n.string("介于")
        }
    }
}

struct SmartFolderRule: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var field: SmartRuleField
    var comparison: SmartRuleOperator
    var selectedValues: Set<String>
    var textValue: String
    var dayCount: Int
    var startDate: Date
    var endDate: Date

    init(
        id: UUID = UUID(),
        field: SmartRuleField,
        comparison: SmartRuleOperator? = nil,
        selectedValues: Set<String> = [],
        textValue: String = "",
        dayCount: Int = 7,
        startDate: Date = Date(),
        endDate: Date = Date()
    ) {
        self.id = id
        self.field = field
        self.comparison = comparison ?? field.allowedOperators[0]
        self.selectedValues = selectedValues
        self.textValue = textValue
        self.dayCount = max(dayCount, 1)
        self.startDate = startDate
        self.endDate = endDate
    }

    var isConfigured: Bool {
        switch field {
        case .tag, .contentType, .transferProtocol, .lifecycle:
            !selectedValues.isEmpty
        case .sourceDomain:
            !TaskDomain.normalizedRule(textValue).isEmpty
        case .addedDate, .completedDate:
            comparison != .withinLastDays || dayCount > 0
        }
    }

    mutating func reset(for nextField: SmartRuleField) {
        field = nextField
        comparison = nextField.allowedOperators[0]
        selectedValues.removeAll()
        textValue = ""
        dayCount = 7
        startDate = Date()
        endDate = Date()
    }

    func matches(
        _ entity: TaskEntityRecord,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Bool {
        switch field {
        case .tag:
            let values = Set(entity.tagIDs.map(\.uuidString))
            return compareSet(values)
        case .contentType:
            return compareSet([entity.contentType.rawValue])
        case .transferProtocol:
            return compareSet([entity.transferProtocol.rawValue])
        case .lifecycle:
            return compareSet([entity.lifecycle.rawValue])
        case .sourceDomain:
            return compareDomain(entity.sourceDomain)
        case .addedDate:
            return compareDate(entity.addedAt, calendar: calendar, now: now)
        case .completedDate:
            return compareDate(entity.completedAt, calendar: calendar, now: now)
        }
    }

    private func compareSet(_ entityValues: Set<String>) -> Bool {
        let intersects = !entityValues.isDisjoint(with: selectedValues)
        switch comparison {
        case .isNotAnyOf:
            return !intersects
        default:
            return intersects
        }
    }

    private func compareDomain(_ domain: String?) -> Bool {
        let rule = TaskDomain.normalizedRule(textValue)
        let domain = domain?.lowercased() ?? ""
        guard !rule.isEmpty else { return false }

        switch comparison {
        case .includesSubdomains:
            return domain == rule || domain.hasSuffix(".\(rule)")
        case .notEquals:
            return domain != rule
        default:
            return domain == rule
        }
    }

    private func compareDate(
        _ date: Date?,
        calendar: Calendar,
        now: Date
    ) -> Bool {
        guard let date else { return false }
        switch comparison {
        case .withinLastDays:
            let today = calendar.startOfDay(for: now)
            let firstDay = calendar.date(
                byAdding: .day,
                value: -(max(dayCount, 1) - 1),
                to: today
            ) ?? today
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            return date >= firstDay && date < tomorrow
        case .before:
            return date < calendar.startOfDay(for: startDate)
        case .after:
            return date >= calendar.startOfDay(for: startDate)
        case .between:
            let lower = min(startDate, endDate)
            let upper = max(startDate, endDate)
            let firstDay = calendar.startOfDay(for: lower)
            let finalDay = calendar.startOfDay(for: upper)
            let endExclusive =
                calendar.date(byAdding: .day, value: 1, to: finalDay) ?? finalDay
            return date >= firstDay && date < endExclusive
        default:
            return false
        }
    }
}

struct SmartFolder: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var matchMode: SmartFolderMatchMode
    var rules: [SmartFolderRule]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        matchMode: SmartFolderMatchMode = .all,
        rules: [SmartFolderRule],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.matchMode = matchMode
        self.rules = rules
        self.createdAt = createdAt
    }

    var displayName: String {
        let normalized = name.trimmed
        return normalized.isEmpty ? L10n.string("未命名智能文件夹") : normalized
    }

    func matches(
        _ entity: TaskEntityRecord,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Bool {
        let configuredRules = rules.filter(\.isConfigured)
        guard !configuredRules.isEmpty else { return false }
        switch matchMode {
        case .all:
            return configuredRules.allSatisfy {
                $0.matches(entity, calendar: calendar, now: now)
            }
        case .any:
            return configuredRules.contains {
                $0.matches(entity, calendar: calendar, now: now)
            }
        }
    }
}

struct TaskOrganizationArchive: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var tags: [TaskTag]
    var smartFolders: [SmartFolder]
    var entities: [TaskEntityRecord]

    init(
        schemaVersion: Int = 1,
        tags: [TaskTag] = [],
        smartFolders: [SmartFolder] = [],
        entities: [TaskEntityRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.tags = tags
        self.smartFolders = smartFolders
        self.entities = entities
    }
}

enum SidebarSelection: Hashable, Sendable {
    case filter(TransferFilter)
    case tag(UUID)
    case smartFolder(UUID)

    init(storageValue: String) {
        let parts = storageValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            self = .filter(TransferFilter(rawValue: storageValue) ?? .all)
            return
        }
        switch parts[0] {
        case "filter":
            self = .filter(TransferFilter(rawValue: parts[1]) ?? .all)
        case "tag":
            self = UUID(uuidString: parts[1]).map(Self.tag) ?? .filter(.all)
        case "smart":
            self = UUID(uuidString: parts[1]).map(Self.smartFolder) ?? .filter(.all)
        default:
            self = .filter(.all)
        }
    }

    var storageValue: String {
        switch self {
        case .filter(let filter): "filter:\(filter.rawValue)"
        case .tag(let id): "tag:\(id.uuidString)"
        case .smartFolder(let id): "smart:\(id.uuidString)"
        }
    }

    var fixedFilter: TransferFilter? {
        guard case .filter(let filter) = self else { return nil }
        return filter
    }
}

enum TaskEntitySortField: String, CaseIterable, Identifiable {
    case addedDate
    case completedDate
    case name
    case size
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addedDate: L10n.string("加入日期")
        case .completedDate: L10n.string("完成日期")
        case .name: L10n.string("名称")
        case .size: L10n.string("文件大小")
        case .status: L10n.string("状态")
        }
    }

    var systemImage: String {
        switch self {
        case .addedDate: "calendar.badge.plus"
        case .completedDate: "calendar.badge.checkmark"
        case .name: "textformat"
        case .size: "externaldrive"
        case .status: "circle.grid.2x2"
        }
    }
}

enum TaskEntityQuery {
    static func results(
        in entities: [TaskEntityRecord],
        searchText: String,
        tags: [TaskTag],
        sortField: TaskEntitySortField,
        direction: TransferSortDirection
    ) -> [TaskEntityRecord] {
        let tagNames = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.displayName) })
        let matching = entities.filter { entity in
            entity.matches(
                searchText,
                tagNames: entity.tagIDs.compactMap { tagNames[$0] }
            )
        }
        return matching.sorted { first, second in
            let comparison: ComparisonResult
            switch sortField {
            case .addedDate:
                comparison = compare(first.addedAt, second.addedAt)
            case .completedDate:
                comparison = compare(
                    first.completedAt ?? .distantPast,
                    second.completedAt ?? .distantPast
                )
            case .name:
                comparison = first.displayName.localizedStandardCompare(second.displayName)
            case .size:
                comparison = compare(first.byteCount, second.byteCount)
            case .status:
                comparison = first.lifecycle.title.localizedStandardCompare(
                    second.lifecycle.title
                )
            }
            if comparison == .orderedSame {
                return first.displayName.localizedStandardCompare(second.displayName)
                    == .orderedAscending
            }
            switch direction {
            case .ascending: return comparison == .orderedAscending
            case .descending: return comparison == .orderedDescending
            }
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

enum TaskDomain {
    static func normalizedHost(from sourceURI: String?) -> String? {
        guard let sourceURI,
              let host = URLComponents(string: sourceURI)?.host?.lowercased() else {
            return nil
        }
        return host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    static func normalizedRule(_ input: String) -> String {
        let normalized = input.trimmed.lowercased()
        guard !normalized.isEmpty else { return "" }
        let candidate = normalized.contains("://") ? normalized : "https://\(normalized)"
        if let host = URLComponents(string: candidate)?.host {
            return host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        return normalized
            .split(separator: "/")
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            ?? ""
    }
}
