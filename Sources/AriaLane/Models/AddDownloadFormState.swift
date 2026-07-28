import Combine
import Foundation

enum AddDownloadSection: String, CaseIterable, Identifiable {
    case destination
    case transfer
    case sources
    case request
    case verification
    case protocols
    case bittorrent
    case raw
    case schedule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .destination: L10n.string("保存位置")
        case .transfer: L10n.string("速度与连接")
        case .sources: L10n.string("镜像来源")
        case .request: L10n.string("请求标头")
        case .verification: L10n.string("认证与校验")
        case .protocols: L10n.string("代理与协议")
        case .bittorrent: "BT / Metalink"
        case .raw: L10n.string("其他参数")
        case .schedule: L10n.string("开始时间")
        }
    }

    var detail: String {
        switch self {
        case .destination: L10n.string("目录与文件名")
        case .transfer: L10n.string("限速、分段、连接")
        case .sources: L10n.string("备用 URI 与多源")
        case .request: "Referer、UA、Header"
        case .verification: L10n.string("Cookie、账号、哈希")
        case .protocols: L10n.string("代理、TLS、FTP、SFTP")
        case .bittorrent: L10n.string("Tracker、加密、偏好")
        case .raw: L10n.string("任意 key=value")
        case .schedule: L10n.string("立即或稍后开始")
        }
    }

    var systemImage: String {
        switch self {
        case .destination: "folder"
        case .transfer: "gauge.with.dots.needle.50percent"
        case .sources: "point.3.filled.connected.trianglepath.dotted"
        case .request: "network"
        case .verification: "checkmark.shield"
        case .protocols: "lock.shield"
        case .bittorrent: "dot.radiowaves.left.and.right"
        case .raw: "terminal"
        case .schedule: "calendar.badge.clock"
        }
    }
}

@MainActor
final class AddDownloadFormState: ObservableObject {
    @Published var input = ""
    @Published var isSubmitting = false
    @Published var selectedSection = AddDownloadSection.transfer

    @Published var downloadDirectory = ""
    @Published var outputFileName = ""

    @Published var maxDownloadLimitKiB = 0
    @Published var maxUploadLimitKiB = 0
    @Published var split = 8
    @Published var maxConnectionPerServer = 8

    @Published var referer = ""
    @Published var userAgent = ""
    @Published var customHeadersText = ""

    @Published var cookie = ""
    @Published var username = ""
    @Published var password = ""
    @Published var checksumAlgorithm = DownloadChecksumAlgorithm.none {
        didSet {
            if checksumAlgorithm == .none {
                checksumDigest = ""
            }
        }
    }
    @Published var checksumDigest = ""
    @Published var additionalURIsText = ""
    @Published var advancedAria2Options = Aria2AdvancedOptions()
    @Published var isScheduled = false
    @Published var scheduledAt = Calendar.current.date(
        byAdding: .hour,
        value: 1,
        to: Date()
    ) ?? Date().addingTimeInterval(3_600)
    @Published var scheduleFrequency = ScheduleFrequency.once

    private(set) var defaultDirectory = ""
    private var defaultDownloadLimitKiB = 0
    private var defaultUploadLimitKiB = 0
    private var defaultSplit = 8
    private var defaultConnections = 8
    private var didPrepareDefaults = false
    private var didLoadScheduledDownload = false

    func prepareDefaults(
        directory: String,
        downloadLimitKiB: Int,
        uploadLimitKiB: Int,
        split: Int,
        connections: Int
    ) {
        guard !didPrepareDefaults else { return }
        didPrepareDefaults = true

        defaultDirectory = directory
        defaultDownloadLimitKiB = max(downloadLimitKiB, 0)
        defaultUploadLimitKiB = max(uploadLimitKiB, 0)
        defaultSplit = min(max(split, 1), 16)
        defaultConnections = min(max(connections, 1), 16)

        downloadDirectory = directory
        maxDownloadLimitKiB = defaultDownloadLimitKiB
        maxUploadLimitKiB = defaultUploadLimitKiB
        self.split = defaultSplit
        maxConnectionPerServer = defaultConnections
    }

    func loadScheduledDownload(_ entry: ScheduledDownload) {
        guard !didLoadScheduledDownload else { return }
        didLoadScheduledDownload = true

        input = entry.urls.joined(separator: "\n")
        downloadDirectory = entry.taskOptions.directory
        outputFileName = entry.taskOptions.outputFileName
        maxDownloadLimitKiB = entry.taskOptions.maxDownloadLimitKiB
        maxUploadLimitKiB = entry.taskOptions.maxUploadLimitKiB
        split = entry.taskOptions.split
        maxConnectionPerServer = entry.taskOptions.maxConnectionPerServer
        referer = entry.taskOptions.referer
        userAgent = entry.taskOptions.userAgent
        customHeadersText = entry.taskOptions.customHeaders.joined(separator: "\n")
        cookie = entry.taskOptions.cookie
        username = entry.taskOptions.username
        password = entry.taskOptions.password
        checksumAlgorithm = entry.taskOptions.checksumAlgorithm
        checksumDigest = entry.taskOptions.checksumDigest
        let advanced = entry.taskOptions.advanced ?? AdvancedDownloadTaskOptions()
        additionalURIsText = advanced.additionalURIs.joined(separator: "\n")
        advancedAria2Options = advanced.aria2
        isScheduled = true
        scheduledAt = max(
            entry.scheduledAt,
            Date().addingTimeInterval(5 * 60)
        )
        scheduleFrequency = entry.frequency
        selectedSection = .transfer
    }

    var taskOptions: DownloadTaskOptions {
        let advanced = AdvancedDownloadTaskOptions(
            additionalURIs: additionalURIsText.components(separatedBy: .newlines),
            aria2: advancedAria2Options
        )
        return DownloadTaskOptions(
            directory: downloadDirectory,
            outputFileName: outputFileName,
            maxDownloadLimitKiB: max(maxDownloadLimitKiB, 0),
            maxUploadLimitKiB: max(maxUploadLimitKiB, 0),
            split: min(max(split, 1), 16),
            maxConnectionPerServer: min(max(maxConnectionPerServer, 1), 16),
            referer: referer,
            userAgent: userAgent,
            customHeaders: customHeadersText.components(separatedBy: .newlines),
            cookie: cookie,
            username: username,
            password: password,
            checksumAlgorithm: checksumAlgorithm,
            checksumDigest: checksumDigest,
            advanced: advanced.isDefault ? nil : advanced
        )
    }

    func hasOverrides(in section: AddDownloadSection) -> Bool {
        switch section {
        case .destination:
            return downloadDirectory.trimmed != defaultDirectory.trimmed
                || !outputFileName.trimmed.isEmpty
        case .transfer:
            return maxDownloadLimitKiB != defaultDownloadLimitKiB
                || maxUploadLimitKiB != defaultUploadLimitKiB
                || split != defaultSplit
                || maxConnectionPerServer != defaultConnections
        case .sources:
            return !additionalURIsText.trimmed.isEmpty
        case .request:
            return !referer.trimmed.isEmpty
                || !userAgent.trimmed.isEmpty
                || !customHeadersText.trimmed.isEmpty
        case .verification:
            return !cookie.trimmed.isEmpty
                || !username.trimmed.isEmpty
                || !password.isEmpty
                || checksumAlgorithm != .none
                || !checksumDigest.trimmed.isEmpty
        case .protocols:
            let options = advancedAria2Options
            return !options.allProxy.trimmed.isEmpty
                || !options.httpProxy.trimmed.isEmpty
                || !options.httpsProxy.trimmed.isEmpty
                || !options.ftpProxy.trimmed.isEmpty
                || !options.noProxy.trimmed.isEmpty
                || !options.proxyUser.trimmed.isEmpty
                || !options.proxyPassword.isEmpty
                || options.checkCertificate != .inherit
                || !options.caCertificate.trimmed.isEmpty
                || !options.clientCertificate.trimmed.isEmpty
                || !options.privateKey.trimmed.isEmpty
                || !options.loadCookies.trimmed.isEmpty
                || !options.saveCookies.trimmed.isEmpty
                || options.ftpPassive != .inherit
                || options.ftpReuseConnection != .inherit
                || options.ftpType != .inherit
                || !options.sshHostKeyDigest.trimmed.isEmpty
                || options.checkIntegrity != .inherit
                || options.dryRun != .inherit
                || options.contentDisposition != .inherit
                || options.conditionalGet != .inherit
                || options.httpAcceptGzip != .inherit
        case .bittorrent:
            let options = advancedAria2Options
            return !options.btTrackers.trimmed.isEmpty
                || !options.btExcludedTrackers.trimmed.isEmpty
                || options.btRequireCrypto != .inherit
                || options.btForceEncryption != .inherit
                || options.btMinimumCryptoLevel != .inherit
                || options.btMetadataOnly != .inherit
                || options.btSaveMetadata != .inherit
                || options.enableDHT6 != .inherit
                || !options.metalinkLocation.trimmed.isEmpty
                || !options.metalinkLanguage.trimmed.isEmpty
                || !options.metalinkOS.trimmed.isEmpty
                || !options.metalinkVersion.trimmed.isEmpty
                || options.metalinkPreferredProtocol != .inherit
        case .raw:
            return !advancedAria2Options.customOptionsText.trimmed.isEmpty
        case .schedule:
            return isScheduled
        }
    }

    var scheduleValidationMessage: String? {
        guard isScheduled else { return nil }
        guard scheduledAt > Date().addingTimeInterval(30) else {
            return L10n.string("计划时间需要晚于当前时间")
        }
        return nil
    }
}
