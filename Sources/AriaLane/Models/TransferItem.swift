import Foundation

enum TransferStatus: String, Codable, Sendable {
    case active
    case waiting
    case paused
    case error
    case complete
    case removed

    var title: String {
        switch self {
        case .active: L10n.string("正在下载")
        case .waiting: L10n.string("等待中")
        case .paused: L10n.string("已暂停")
        case .error: L10n.string("需要处理")
        case .complete: L10n.string("已完成")
        case .removed: L10n.string("已移除")
        }
    }

    var systemImage: String {
        switch self {
        case .active: "arrow.down"
        case .waiting: "clock"
        case .paused: "pause.fill"
        case .error: "exclamationmark"
        case .complete: "checkmark"
        case .removed: "trash"
        }
    }
}

struct TransferURI: Codable, Equatable, Sendable {
    let uri: String
    let status: String?
}

struct TransferFile: Codable, Equatable, Sendable {
    let index: String?
    let path: String
    let length: String?
    let completedLength: String?
    let selected: String?
    let uris: [TransferURI]?

    var byteCount: Int64 { Int64(length ?? "") ?? 0 }
    var completedByteCount: Int64 { Int64(completedLength ?? "") ?? 0 }
    var indexValue: Int { max(Int(index ?? "") ?? 1, 1) }
    var isSelected: Bool { selected != "false" }
    var progress: Double {
        guard byteCount > 0 else { return completedByteCount > 0 ? 1 : 0 }
        return min(max(Double(completedByteCount) / Double(byteCount), 0), 1)
    }
}

struct BitTorrentInfo: Codable, Equatable, Sendable {
    struct Info: Codable, Equatable, Sendable {
        let name: String?
    }

    let info: Info?
}

struct Aria2Peer: Codable, Identifiable, Equatable, Sendable {
    let peerId: String?
    let ip: String
    let port: String
    let bitfield: String?
    let amChoking: String?
    let peerChoking: String?
    let downloadSpeed: String?
    let uploadSpeed: String?
    let seeder: String?

    var id: String {
        let identifier = peerId?.isEmpty == false ? peerId! : "\(ip):\(port)"
        return identifier
    }

    var address: String {
        ip.contains(":") ? "[\(ip)]:\(port)" : "\(ip):\(port)"
    }

    var downloadSpeedValue: Int64 { Int64(downloadSpeed ?? "") ?? 0 }
    var uploadSpeedValue: Int64 { Int64(uploadSpeed ?? "") ?? 0 }
    var isSeeder: Bool { seeder == "true" }
}

struct Aria2ServerEndpoint: Codable, Identifiable, Equatable, Sendable {
    let uri: String
    let currentUri: String?
    let downloadSpeed: String?

    var id: String { currentUri ?? uri }
    var downloadSpeedValue: Int64 { Int64(downloadSpeed ?? "") ?? 0 }

    var displayHost: String {
        let candidate = currentUri?.isEmpty == false ? currentUri! : uri
        return URL(string: candidate)?.host ?? candidate
    }
}

struct Aria2ServerGroup: Codable, Identifiable, Equatable, Sendable {
    let index: String
    let servers: [Aria2ServerEndpoint]

    var id: String { index }
}

struct TransferAdvancedDetails: Equatable, Sendable {
    let item: TransferItem
    let peers: [Aria2Peer]
    let serverGroups: [Aria2ServerGroup]
    let files: [TransferFile]
    let uris: [TransferURI]
    let options: [String: String]

    init(
        item: TransferItem,
        peers: [Aria2Peer],
        serverGroups: [Aria2ServerGroup],
        files: [TransferFile] = [],
        uris: [TransferURI] = [],
        options: [String: String] = [:]
    ) {
        self.item = item
        self.peers = peers
        self.serverGroups = serverGroups
        self.files = files
        self.uris = uris
        self.options = options
    }

    var servers: [Aria2ServerEndpoint] {
        serverGroups.flatMap(\.servers)
    }
}

struct TransferItem: Codable, Identifiable, Equatable, Sendable {
    let gid: String
    let status: TransferStatus
    let totalLength: String?
    let completedLength: String?
    let uploadLength: String?
    let downloadSpeed: String?
    let uploadSpeed: String?
    let dir: String?
    let connections: String?
    let numSeeders: String?
    let seeder: String?
    let pieceLength: String?
    let numPieces: String?
    let bitfield: String?
    let verifiedLength: String?
    let verifyIntegrityPending: String?
    let infoHash: String?
    let errorCode: String?
    let errorMessage: String?
    let files: [TransferFile]?
    let bittorrent: BitTorrentInfo?

    init(
        gid: String,
        status: TransferStatus,
        totalLength: String?,
        completedLength: String?,
        uploadLength: String?,
        downloadSpeed: String?,
        uploadSpeed: String?,
        dir: String?,
        connections: String?,
        numSeeders: String? = nil,
        seeder: String? = nil,
        pieceLength: String? = nil,
        numPieces: String? = nil,
        bitfield: String? = nil,
        verifiedLength: String? = nil,
        verifyIntegrityPending: String? = nil,
        infoHash: String? = nil,
        errorCode: String?,
        errorMessage: String?,
        files: [TransferFile]?,
        bittorrent: BitTorrentInfo?
    ) {
        self.gid = gid
        self.status = status
        self.totalLength = totalLength
        self.completedLength = completedLength
        self.uploadLength = uploadLength
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.dir = dir
        self.connections = connections
        self.numSeeders = numSeeders
        self.seeder = seeder
        self.pieceLength = pieceLength
        self.numPieces = numPieces
        self.bitfield = bitfield
        self.verifiedLength = verifiedLength
        self.verifyIntegrityPending = verifyIntegrityPending
        self.infoHash = infoHash
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.files = files
        self.bittorrent = bittorrent
    }

    var id: String { gid }
    var totalByteCount: Int64 {
        let reported = Int64(totalLength ?? "") ?? 0
        let fileTotal = files?.reduce(Int64(0)) { $0 + $1.byteCount } ?? 0
        return max(reported, fileTotal)
    }

    var completedByteCount: Int64 {
        let reported = Int64(completedLength ?? "") ?? 0
        let fileTotal = files?.reduce(Int64(0)) { $0 + $1.completedByteCount } ?? 0
        return max(reported, fileTotal)
    }

    var downloadSpeedValue: Int64 { Int64(downloadSpeed ?? "") ?? 0 }
    var uploadSpeedValue: Int64 { Int64(uploadSpeed ?? "") ?? 0 }
    var connectionCount: Int { Int(connections ?? "") ?? 0 }
    var seederCount: Int { Int(numSeeders ?? "") ?? 0 }
    var pieceLengthValue: Int64 { Int64(pieceLength ?? "") ?? 0 }
    var pieceCount: Int { max(Int(numPieces ?? "") ?? 0, 0) }
    var verifiedByteCount: Int64 { Int64(verifiedLength ?? "") ?? 0 }
    var isBitTorrent: Bool {
        bittorrent != nil || sourceURI?.lowercased().hasPrefix("magnet:") == true
    }

    var progress: Double {
        guard totalByteCount > 0 else {
            return status == .complete ? 1 : 0
        }
        return min(max(Double(completedByteCount) / Double(totalByteCount), 0), 1)
    }

    var displayName: String {
        if let torrentName = bittorrent?.info?.name?.trimmed, !torrentName.isEmpty {
            return torrentName
        }

        if let path = files?.first?.path.trimmed, !path.isEmpty {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            if !filename.isEmpty {
                return filename.removingPercentEncoding ?? filename
            }
        }

        if let source = sourceURI {
            if source.lowercased().hasPrefix("magnet:"),
               let components = URLComponents(string: source),
               let name = components.queryItems?.first(where: { $0.name == "dn" })?.value,
               !name.isEmpty {
                return name
            }

            if let url = URL(string: source) {
                let filename = url.lastPathComponent
                if !filename.isEmpty {
                    return filename.removingPercentEncoding ?? filename
                }
                if let host = url.host {
                    return host
                }
            }
        }

        return L10n.string("未命名下载")
    }

    var sourceURI: String? {
        files?
            .lazy
            .compactMap(\.uris)
            .flatMap { $0 }
            .first?
            .uri
    }

    var displayPath: String {
        if let path = files?.first?.path, !path.isEmpty {
            return path
        }
        return dir ?? "—"
    }

    var remainingSeconds: TimeInterval? {
        guard downloadSpeedValue > 0, totalByteCount > completedByteCount else {
            return nil
        }
        return TimeInterval(totalByteCount - completedByteCount) / TimeInterval(downloadSpeedValue)
    }

    func pieceProgressBuckets(maximumCount: Int = 72) -> [Double] {
        guard maximumCount > 0, pieceCount > 0, let bitfield, !bitfield.isEmpty else {
            return []
        }

        var states: [Bool] = []
        states.reserveCapacity(min(pieceCount, 1_000_000))
        for character in bitfield.prefix((pieceCount + 3) / 4) {
            guard let nibble = Int(String(character), radix: 16) else { continue }
            for shift in stride(from: 3, through: 0, by: -1) {
                states.append((nibble & (1 << shift)) != 0)
                if states.count == pieceCount || states.count == 1_000_000 {
                    break
                }
            }
            if states.count == pieceCount || states.count == 1_000_000 {
                break
            }
        }
        guard !states.isEmpty else { return [] }

        let bucketCount = min(maximumCount, states.count)
        return (0..<bucketCount).map { bucketIndex in
            let lower = bucketIndex * states.count / bucketCount
            let upper = (bucketIndex + 1) * states.count / bucketCount
            guard upper > lower else { return 0 }
            let completed = states[lower..<upper].reduce(0) { $0 + ($1 ? 1 : 0) }
            return Double(completed) / Double(upper - lower)
        }
    }

    var isPausable: Bool {
        status == .active || status == .waiting
    }

    var isResumable: Bool {
        status == .paused
    }

    var isRetryable: Bool {
        status == .error && sourceURI != nil
    }

    var isQueueMovable: Bool {
        status == .waiting || status == .paused
    }

    var queueDragPayload: String {
        "arialane-gid:\(gid)"
    }

    var userFacingError: String? {
        guard status == .error else { return nil }
        let fallback = errorMessage?.trimmed

        switch errorCode.flatMap(Int.init) {
        case 2: return L10n.string("连接超时")
        case 3, 4: return L10n.string("服务器上找不到这个文件")
        case 5: return L10n.string("下载速度持续低于最低速度限制")
        case 6: return L10n.string("网络连接失败")
        case 8: return L10n.string("服务器不支持断点续传")
        case 9: return L10n.string("磁盘可用空间不足")
        case 11: return L10n.string("同一个文件已经在下载")
        case 12: return L10n.string("同一个 Torrent 已经在下载")
        case 13: return L10n.string("目标文件已经存在")
        case 14: return L10n.string("无法自动重命名目标文件")
        case 15, 16, 17: return L10n.string("无法读写目标文件")
        case 18: return L10n.string("无法创建下载文件夹")
        case 19: return L10n.string("无法解析服务器地址")
        case 20: return L10n.string("Metalink 文件格式无效")
        case 21: return L10n.string("FTP 服务器拒绝了命令")
        case 22: return L10n.string("服务器返回了无效响应")
        case 23: return L10n.string("重定向次数过多")
        case 24: return L10n.string("服务器认证失败")
        case 25, 26: return L10n.string("Torrent 文件损坏或格式无效")
        case 27: return L10n.string("Magnet 链接格式无效")
        case 28: return L10n.string("任务包含 aria2 无法识别的选项")
        case 29: return L10n.string("服务器暂时过载或维护中")
        case 32: return L10n.string("文件校验失败")
        default:
            let normalized = fallback?.lowercased() ?? ""
            if normalized.contains("connection refused")
                || normalized.contains("failed to establish connection") {
                return L10n.string("无法连接到服务器")
            }
            if normalized.contains("timed out") || normalized.contains("timeout") {
                return L10n.string("连接超时")
            }
            return fallback?.isEmpty == false ? fallback : L10n.string("下载失败")
        }
    }

    var sortRank: Int {
        switch status {
        case .active: 0
        case .waiting: 1
        case .paused: 2
        case .error: 3
        case .complete: 4
        case .removed: 5
        }
    }
}
