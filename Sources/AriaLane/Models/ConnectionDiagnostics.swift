import Foundation

enum ConnectionDiagnosticState: Equatable {
    case idle
    case running
    case succeeded(ConnectionDiagnosticReport)
    case failed(message: String)
}

struct ConnectionDiagnosticReport: Equatable, Sendable {
    let generatedAt: Date
    let profileName: String
    let endpoint: String
    let aria2Version: String
    let enabledFeatures: [String]
    let elapsedMilliseconds: Int
    let activeCount: Int
    let waitingCount: Int
    let rpcMethodCount: Int
    let notificationMethods: [String]
    let sessionID: String?

    init(
        generatedAt: Date,
        profileName: String,
        endpoint: String,
        aria2Version: String,
        enabledFeatures: [String],
        elapsedMilliseconds: Int,
        activeCount: Int,
        waitingCount: Int,
        rpcMethodCount: Int = 0,
        notificationMethods: [String] = [],
        sessionID: String? = nil
    ) {
        self.generatedAt = generatedAt
        self.profileName = profileName
        self.endpoint = endpoint
        self.aria2Version = aria2Version
        self.enabledFeatures = enabledFeatures
        self.elapsedMilliseconds = elapsedMilliseconds
        self.activeCount = activeCount
        self.waitingCount = waitingCount
        self.rpcMethodCount = rpcMethodCount
        self.notificationMethods = notificationMethods
        self.sessionID = sessionID
    }

    static func sanitizedEndpoint(_ url: URL?) -> String {
        guard let url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return L10n.string("无效地址")
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? L10n.string("无效地址")
    }

    var shareableText: String {
        let notReported = L10n.string("未报告")
        let featureText = enabledFeatures.isEmpty
            ? notReported
            : enabledFeatures.sorted().joined(separator: ", ")
        let methods = rpcMethodCount == 0 ? notReported : String(rpcMethodCount)
        let notifications = notificationMethods.isEmpty
            ? notReported
            : notificationMethods.sorted().joined(separator: ", ")

        return [
            L10n.string("AriaLane 连接诊断"),
            L10n.string("时间：\(generatedAt.formatted(date: .numeric, time: .standard))"),
            L10n.string("服务器：\(profileName)"),
            "RPC：\(endpoint)",
            "aria2：\(aria2Version)",
            L10n.string("诊断耗时：\(elapsedMilliseconds) ms"),
            L10n.string("任务：\(activeCount) 个进行中，\(waitingCount) 个等待中"),
            L10n.string("功能：\(featureText)"),
            L10n.string("RPC 方法：\(methods)"),
            L10n.string("WebSocket 通知：\(notifications)"),
            "Session ID：\(sessionID ?? notReported)"
        ].joined(separator: "\n")
    }
}
