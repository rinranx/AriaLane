import Foundation

struct Aria2SessionInfo: Codable, Equatable, Sendable {
    let sessionId: String
}

struct Aria2MulticallInvocation: Equatable, Sendable {
    let method: String
    let parameters: [String]

    init(method: String, parameters: [String] = []) {
        self.method = method
        self.parameters = parameters
    }
}

struct Aria2MulticallResult: Equatable, Sendable {
    let isSuccess: Bool
    let errorCode: Int?
    let errorMessage: String?

    static let success = Aria2MulticallResult(
        isSuccess: true,
        errorCode: nil,
        errorMessage: nil
    )

    static func failure(code: Int?, message: String?) -> Aria2MulticallResult {
        Aria2MulticallResult(
            isSuccess: false,
            errorCode: code,
            errorMessage: message
        )
    }
}

enum Aria2NotificationMethod: String, Codable, CaseIterable, Sendable {
    case downloadStart = "aria2.onDownloadStart"
    case downloadPause = "aria2.onDownloadPause"
    case downloadStop = "aria2.onDownloadStop"
    case downloadComplete = "aria2.onDownloadComplete"
    case downloadError = "aria2.onDownloadError"
    case btDownloadComplete = "aria2.onBtDownloadComplete"
}

struct Aria2NotificationEvent: Equatable, Sendable {
    let method: Aria2NotificationMethod
    let gid: String
}

enum Aria2EventStreamState: Equatable, Sendable {
    case disabled
    case connecting
    case connected
    case disconnected(message: String)

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var title: String {
        switch self {
        case .disabled:
            return L10n.string("未启用")
        case .connecting:
            return L10n.string("正在连接")
        case .connected:
            return L10n.string("实时事件已连接")
        case .disconnected:
            return L10n.string("实时事件不可用")
        }
    }
}
