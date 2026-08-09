import Foundation

struct Aria2ServerProfile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var endpoint: String
    var autoStartLocalAria2: Bool

    init(
        id: UUID = UUID(),
        name: String,
        endpoint: String,
        autoStartLocalAria2: Bool
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.autoStartLocalAria2 = autoStartLocalAria2
    }

    var displayName: String {
        let normalized = name.trimmed
        guard !normalized.isEmpty else {
            return L10n.string("未命名服务器")
        }

        switch builtInLocalDisplayNameKey {
        case "本机":
            return L10n.string("本机")
        case "本机 aria2":
            return L10n.string("本机 aria2")
        default:
            return normalized
        }
    }

    var builtInLocalDisplayNameKey: String? {
        guard isLocalEndpoint else { return nil }

        if normalizedNameMatches("本机") || normalizedNameMatches("Local") {
            return "本机"
        }
        if normalizedNameMatches("本机 aria2")
            || normalizedNameMatches("Local aria2") {
            return "本机 aria2"
        }
        return nil
    }

    var hostDescription: String {
        var candidate = endpoint.trimmed
        if !candidate.contains("://") {
            candidate = "http://" + candidate
        }
        return URLComponents(string: candidate)?.host ?? endpoint
    }

    var endpointSummary: String {
        var candidate = endpoint.trimmed
        if !candidate.contains("://") {
            candidate = "http://" + candidate
        }
        guard let components = URLComponents(string: candidate),
              let host = components.host else {
            return endpoint
        }

        let normalizedHost = host.lowercased()
        if normalizedHost == "127.0.0.1"
            || normalizedHost == "localhost"
            || normalizedHost == "::1" {
            return ":\(components.port ?? 6_800)"
        }
        if let port = components.port, port != 6_800 {
            return "\(host):\(port)"
        }
        return host
    }

    private var isLocalEndpoint: Bool {
        var candidate = endpoint.trimmed
        if !candidate.contains("://") {
            candidate = "http://" + candidate
        }
        guard let host = URLComponents(string: candidate)?.host?.lowercased() else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func normalizedNameMatches(_ candidate: String) -> Bool {
        name.trimmed.compare(
            candidate,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
    }
}

struct DockProgressSnapshot: Equatable, Sendable {
    let progress: Double
    let liveCount: Int
    let activeCount: Int

    init(transfers: [TransferItem]) {
        let live = transfers.filter {
            switch $0.status {
            case .active, .waiting, .paused:
                true
            case .error, .complete, .removed:
                false
            }
        }
        liveCount = live.count
        activeCount = live.filter { $0.status == .active }.count

        let total = live.reduce(Int64(0)) { $0 + max($1.totalByteCount, 0) }
        let completed = live.reduce(Int64(0)) {
            $0 + min(max($1.completedByteCount, 0), max($1.totalByteCount, 0))
        }
        if total > 0 {
            progress = min(max(Double(completed) / Double(total), 0), 1)
        } else {
            progress = 0
        }
    }
}
