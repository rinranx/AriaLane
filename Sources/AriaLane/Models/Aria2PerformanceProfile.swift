import Foundation

enum Aria2PerformanceProfileKind: String, Codable, Sendable {
    case maximumSpeed
    case compatibility
    case custom
}

struct Aria2PerformanceProfile: Codable, Equatable, Identifiable, Sendable {
    static let maximumSpeedID = UUID(
        uuidString: "7C21815B-4DB4-47C0-A1E7-4B2FA0F68001"
    )!
    static let compatibilityID = UUID(
        uuidString: "7C21815B-4DB4-47C0-A1E7-4B2FA0F68002"
    )!

    var id: UUID
    var kind: Aria2PerformanceProfileKind
    var name: String

    var maxOverallDownloadLimitKiB: Int
    var maxOverallUploadLimitKiB: Int
    var maxDownloadLimitKiB: Int
    var maxUploadLimitKiB: Int
    var maxConcurrentDownloads: Int

    var maxConnectionPerServer: Int
    var split: Int
    var minSplitSizeMiB: Int
    var diskCacheMiB: Int

    var enableDHT: Bool
    var enablePeerExchange: Bool
    var enableLocalPeerDiscovery: Bool
    var enableDHT6: Bool
    var btMaxPeers: Int
    var btRequestPeerSpeedLimitKiB: Int

    static let maximumSpeed = Aria2PerformanceProfile(
        id: maximumSpeedID,
        kind: .maximumSpeed,
        name: "",
        maxOverallDownloadLimitKiB: 0,
        maxOverallUploadLimitKiB: 0,
        maxDownloadLimitKiB: 0,
        maxUploadLimitKiB: 0,
        maxConcurrentDownloads: 8,
        maxConnectionPerServer: 16,
        split: 16,
        minSplitSizeMiB: 4,
        diskCacheMiB: 128,
        enableDHT: true,
        enablePeerExchange: true,
        enableLocalPeerDiscovery: true,
        enableDHT6: true,
        btMaxPeers: 128,
        btRequestPeerSpeedLimitKiB: 5_120
    )

    static let compatibility = Aria2PerformanceProfile(
        id: compatibilityID,
        kind: .compatibility,
        name: "",
        maxOverallDownloadLimitKiB: 0,
        maxOverallUploadLimitKiB: 0,
        maxDownloadLimitKiB: 0,
        maxUploadLimitKiB: 0,
        maxConcurrentDownloads: 3,
        maxConnectionPerServer: 4,
        split: 4,
        minSplitSizeMiB: 10,
        diskCacheMiB: 32,
        enableDHT: true,
        enablePeerExchange: true,
        enableLocalPeerDiscovery: false,
        enableDHT6: false,
        btMaxPeers: 55,
        btRequestPeerSpeedLimitKiB: 50
    )

    static var builtIn: [Aria2PerformanceProfile] {
        [.maximumSpeed, .compatibility]
    }

    static func custom(
        id: UUID = UUID(),
        name: String,
        basedOn profile: Aria2PerformanceProfile
    ) -> Aria2PerformanceProfile {
        var custom = profile
        custom.id = id
        custom.kind = .custom
        custom.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom
    }

    var displayName: String {
        switch kind {
        case .maximumSpeed:
            L10n.string("极速模式")
        case .compatibility:
            L10n.string("兼容模式")
        case .custom:
            name
        }
    }

    var systemImage: String {
        switch kind {
        case .maximumSpeed:
            "bolt.fill"
        case .compatibility:
            "shield.lefthalf.filled"
        case .custom:
            "slider.horizontal.3"
        }
    }

    var summary: String {
        L10n.string(
            "\(maxConcurrentDownloads) 个任务 · \(maxConnectionPerServer) 个连接"
        )
    }

    var secondarySummary: String {
        L10n.string("\(diskCacheMiB) MB 缓存 · BT \(btMaxPeers) 节点")
    }

    func hasSameSettings(as other: Aria2PerformanceProfile) -> Bool {
        maxOverallDownloadLimitKiB == other.maxOverallDownloadLimitKiB
            && maxOverallUploadLimitKiB == other.maxOverallUploadLimitKiB
            && maxDownloadLimitKiB == other.maxDownloadLimitKiB
            && maxUploadLimitKiB == other.maxUploadLimitKiB
            && maxConcurrentDownloads == other.maxConcurrentDownloads
            && maxConnectionPerServer == other.maxConnectionPerServer
            && split == other.split
            && minSplitSizeMiB == other.minSplitSizeMiB
            && diskCacheMiB == other.diskCacheMiB
            && enableDHT == other.enableDHT
            && enablePeerExchange == other.enablePeerExchange
            && enableLocalPeerDiscovery == other.enableLocalPeerDiscovery
            && enableDHT6 == other.enableDHT6
            && btMaxPeers == other.btMaxPeers
            && btRequestPeerSpeedLimitKiB == other.btRequestPeerSpeedLimitKiB
    }
}
