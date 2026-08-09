import Foundation

enum TaskListDisplayMode: String, CaseIterable, Hashable, Identifiable {
    case compact
    case card

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: L10n.string("紧凑")
        case .card: L10n.string("卡片")
        }
    }

    var systemImage: String {
        switch self {
        case .compact: "list.bullet"
        case .card: "rectangle.grid.1x2"
        }
    }
}

enum MenuBarPanelStyle: String, CaseIterable, Hashable, Identifiable {
    case adaptive
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adaptive: L10n.string("自适应面板")
        case .compact: L10n.string("精简面板")
        }
    }

    var systemImage: String {
        switch self {
        case .adaptive: "rectangle.expand.vertical"
        case .compact: "rectangle.compress.vertical"
        }
    }

    var detail: String {
        switch self {
        case .adaptive:
            L10n.string("空闲时收拢；下载时展开图表、任务与批量控制。")
        case .compact:
            L10n.string("只显示连接、速度与常用入口，任务管理回到主窗口。")
        }
    }
}

enum TransferFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case waiting
    case paused
    case completed
    case pending
    case scheduled
    case rss
    case library
    case history

    static let liveCases: [TransferFilter] = [
        .all,
        .active,
        .waiting,
        .paused,
        .completed
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L10n.string("全部")
        case .active: L10n.string("进行中")
        case .waiting: L10n.string("等待中")
        case .paused: L10n.string("已暂停")
        case .completed: L10n.string("已完成")
        case .pending: L10n.string("待发送")
        case .scheduled: L10n.string("计划任务")
        case .rss: L10n.string("RSS 订阅")
        case .library: L10n.string("资源搜索")
        case .history: L10n.string("下载历史")
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .active: "arrow.down.circle.fill"
        case .waiting: "clock"
        case .paused: "pause.circle"
        case .completed: "checkmark.circle"
        case .pending: "tray.and.arrow.up"
        case .scheduled: "calendar.badge.clock"
        case .rss: "dot.radiowaves.left.and.right"
        case .library: "books.vertical"
        case .history: "clock.arrow.circlepath"
        }
    }

    func includes(_ item: TransferItem) -> Bool {
        switch self {
        case .all:
            true
        case .active:
            item.status == .active
        case .waiting:
            item.status == .waiting
        case .paused:
            item.status == .paused || item.status == .error
        case .completed:
            item.status == .complete
        case .pending, .scheduled, .rss, .library, .history:
            false
        }
    }
}

struct ConnectionRetryBackoff: Equatable, Sendable {
    var initialDelay: TimeInterval = 2.5
    var maximumDelay: TimeInterval = 60

    func delay(afterFailure failureCount: Int) -> TimeInterval {
        guard failureCount > 0 else { return 0 }
        let exponent = min(max(failureCount - 1, 0), 10)
        return min(initialDelay * pow(2, Double(exponent)), maximumDelay)
    }
}

enum ConnectionState: Equatable {
    case idle
    case connecting
    case connected(version: String)
    case failed(message: String)

    var title: String {
        switch self {
        case .idle: L10n.string("尚未连接")
        case .connecting: L10n.string("正在连接")
        case .connected: L10n.string("aria2 已连接")
        case .failed: L10n.string("连接中断")
        }
    }

    var detail: String? {
        switch self {
        case .connected(let version):
            "aria2 \(version)"
        case .failed(let message):
            message
        default:
            nil
        }
    }

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

enum SettingsApplyState: Equatable {
    case idle
    case applying
    case applied
    case failed(message: String)
}

enum QueueMoveDirection {
    case top
    case up
    case down
    case bottom
}

enum NotificationPermissionState: Equatable {
    case disabled
    case requesting
    case allowed
    case denied
    case unavailable
    case failed(message: String)
}

struct GlobalStats: Decodable, Equatable, Sendable {
    let downloadSpeed: String
    let uploadSpeed: String
    let numActive: String
    let numWaiting: String
    let numStopped: String
    let numStoppedTotal: String

    var downloadSpeedValue: Int64 { Int64(downloadSpeed) ?? 0 }
    var uploadSpeedValue: Int64 { Int64(uploadSpeed) ?? 0 }
    var activeCount: Int { Int(numActive) ?? 0 }
    var waitingCount: Int { Int(numWaiting) ?? 0 }

    static let zero = GlobalStats(
        downloadSpeed: "0",
        uploadSpeed: "0",
        numActive: "0",
        numWaiting: "0",
        numStopped: "0",
        numStoppedTotal: "0"
    )
}

struct Aria2Version: Decodable, Sendable {
    let version: String
    let enabledFeatures: [String]?
}

struct AppNotice: Identifiable, Equatable {
    enum Kind {
        case success
        case warning
        case error
    }

    let id = UUID()
    let message: String
    let kind: Kind
}
