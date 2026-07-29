import Foundation

enum FileAllocationMethod: String, CaseIterable, Identifiable, Sendable {
    case trunc
    case prealloc
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trunc: L10n.string("快速（推荐）")
        case .prealloc: L10n.string("预分配")
        case .none: L10n.string("不预分配")
        }
    }

    var detail: String {
        switch self {
        case .trunc: L10n.string("快速创建目标大小的文件，适合 APFS")
        case .prealloc: L10n.string("先占用完整磁盘空间，开始大文件时会等待")
        case .none: L10n.string("立即开始，但下载过程中可能产生更多磁盘碎片")
        }
    }
}

struct Aria2Configuration: Equatable, Sendable {
    var downloadDirectory: String

    var maxOverallDownloadLimitKiB: Int
    var maxOverallUploadLimitKiB: Int
    var maxDownloadLimitKiB: Int
    var maxUploadLimitKiB: Int
    var maxConcurrentDownloads: Int

    var maxConnectionPerServer: Int
    var split: Int
    var minSplitSizeMiB: Int
    var diskCacheMiB: Int
    var connectTimeoutSeconds: Int
    var timeoutSeconds: Int
    var maxTries: Int
    var retryWaitSeconds: Int
    var lowestSpeedLimitKiB: Int

    var fileAllocation: FileAllocationMethod
    var continueDownloads: Bool
    var autoFileRenaming: Bool
    var allowOverwrite: Bool
    var preserveRemoteTime: Bool

    var enableDHT: Bool
    var enablePeerExchange: Bool
    var enableLocalPeerDiscovery: Bool
    var btMaxPeers: Int
    var btRequestPeerSpeedLimitKiB: Int
    var listenPortStart: Int
    var listenPortEnd: Int
    var seedTimeMinutes: Int
    var seedRatio: Double
    var extraGlobalOptions: [String: String] = [:]

    static func recommended(downloadDirectory: String) -> Aria2Configuration {
        Aria2Configuration(
            downloadDirectory: downloadDirectory,
            maxOverallDownloadLimitKiB: 0,
            maxOverallUploadLimitKiB: 0,
            maxDownloadLimitKiB: 0,
            maxUploadLimitKiB: 0,
            maxConcurrentDownloads: Aria2PerformanceProfile.maximumSpeed.maxConcurrentDownloads,
            maxConnectionPerServer:
                Aria2PerformanceProfile.maximumSpeed.maxConnectionPerServer,
            split: Aria2PerformanceProfile.maximumSpeed.split,
            minSplitSizeMiB: Aria2PerformanceProfile.maximumSpeed.minSplitSizeMiB,
            diskCacheMiB: Aria2PerformanceProfile.maximumSpeed.diskCacheMiB,
            connectTimeoutSeconds: 30,
            timeoutSeconds: 60,
            maxTries: 5,
            retryWaitSeconds: 3,
            lowestSpeedLimitKiB: 0,
            fileAllocation: .trunc,
            continueDownloads: true,
            autoFileRenaming: true,
            allowOverwrite: false,
            preserveRemoteTime: false,
            enableDHT: Aria2PerformanceProfile.maximumSpeed.enableDHT,
            enablePeerExchange:
                Aria2PerformanceProfile.maximumSpeed.enablePeerExchange,
            enableLocalPeerDiscovery:
                Aria2PerformanceProfile.maximumSpeed.enableLocalPeerDiscovery,
            btMaxPeers: Aria2PerformanceProfile.maximumSpeed.btMaxPeers,
            btRequestPeerSpeedLimitKiB:
                Aria2PerformanceProfile.maximumSpeed.btRequestPeerSpeedLimitKiB,
            listenPortStart: 6_881,
            listenPortEnd: 6_999,
            seedTimeMinutes: 0,
            seedRatio: 1
        )
    }

    var globalOptions: [String: String] {
        let portStart = Self.clamp(listenPortStart, to: 1_024...65_535)
        let portEnd = max(portStart, Self.clamp(listenPortEnd, to: 1_024...65_535))

        var options = [
            "dir": downloadDirectory,
            "max-overall-download-limit": Self.speedOption(maxOverallDownloadLimitKiB),
            "max-overall-upload-limit": Self.speedOption(maxOverallUploadLimitKiB),
            "max-download-limit": Self.speedOption(maxDownloadLimitKiB),
            "max-upload-limit": Self.speedOption(maxUploadLimitKiB),
            "max-concurrent-downloads": String(max(maxConcurrentDownloads, 1)),
            "max-connection-per-server": String(Self.clamp(maxConnectionPerServer, to: 1...16)),
            "split": String(Self.clamp(split, to: 1...16)),
            "min-split-size": "\(Self.clamp(minSplitSizeMiB, to: 1...1_024))M",
            "disk-cache": "\(Self.clamp(diskCacheMiB, to: 0...4_096))M",
            "connect-timeout": String(Self.clamp(connectTimeoutSeconds, to: 1...600)),
            "timeout": String(Self.clamp(timeoutSeconds, to: 1...600)),
            "max-tries": String(max(maxTries, 0)),
            "retry-wait": String(Self.clamp(retryWaitSeconds, to: 0...600)),
            "lowest-speed-limit": Self.speedOption(lowestSpeedLimitKiB),
            "file-allocation": fileAllocation.rawValue,
            "continue": Self.boolOption(continueDownloads),
            "auto-file-renaming": Self.boolOption(autoFileRenaming),
            "allow-overwrite": Self.boolOption(allowOverwrite),
            "remote-time": Self.boolOption(preserveRemoteTime),
            "enable-dht": Self.boolOption(enableDHT),
            "enable-peer-exchange": Self.boolOption(enablePeerExchange),
            "bt-enable-lpd": Self.boolOption(enableLocalPeerDiscovery),
            "bt-max-peers": String(max(btMaxPeers, 0)),
            "bt-request-peer-speed-limit":
                Self.speedOption(btRequestPeerSpeedLimitKiB),
            "listen-port": portStart == portEnd ? String(portStart) : "\(portStart)-\(portEnd)",
            "seed-time": String(max(seedTimeMinutes, 0)),
            "seed-ratio": String(
                format: "%.1f",
                locale: Locale(identifier: "en_US_POSIX"),
                max(seedRatio, 0)
            )
        ]
        options.merge(extraGlobalOptions) { _, advancedValue in advancedValue }
        return options
    }

    var commandLineArguments: [String] {
        globalOptions
            .sorted { $0.key < $1.key }
            .map { "--\($0.key)=\($0.value)" }
    }

    static func speedOption(_ kibibytesPerSecond: Int) -> String {
        let normalized = max(kibibytesPerSecond, 0)
        return normalized == 0 ? "0" : "\(normalized)K"
    }

    private static func boolOption(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct TaskSpeedLimits: Equatable, Sendable {
    var downloadKiBPerSecond: Int
    var uploadKiBPerSecond: Int

    static let unlimited = TaskSpeedLimits(
        downloadKiBPerSecond: 0,
        uploadKiBPerSecond: 0
    )

    init(downloadKiBPerSecond: Int, uploadKiBPerSecond: Int) {
        self.downloadKiBPerSecond = max(downloadKiBPerSecond, 0)
        self.uploadKiBPerSecond = max(uploadKiBPerSecond, 0)
    }

    init(options: [String: String]) {
        downloadKiBPerSecond = Self.kibibytes(fromByteOption: options["max-download-limit"])
        uploadKiBPerSecond = Self.kibibytes(fromByteOption: options["max-upload-limit"])
    }

    var optionValues: [String: String] {
        [
            "max-download-limit": Aria2Configuration.speedOption(downloadKiBPerSecond),
            "max-upload-limit": Aria2Configuration.speedOption(uploadKiBPerSecond)
        ]
    }

    private static func kibibytes(fromByteOption value: String?) -> Int {
        guard let value, let bytes = Int64(value), bytes > 0 else { return 0 }
        return Int((bytes + 1_023) / 1_024)
    }
}
