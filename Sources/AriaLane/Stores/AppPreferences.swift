import Combine
import Foundation

enum KeychainCredential: Equatable {
    case rpcSecret
    case proxyPassword

    var title: String {
        switch self {
        case .rpcSecret:
            return L10n.string("RPC 密钥")
        case .proxyPassword:
            return L10n.string("代理密码")
        }
    }
}

struct KeychainPersistenceIssue: Identifiable, Equatable {
    let id = UUID()
    let credential: KeychainCredential
    let account: String
    let title: String
    let message: String
}

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let endpoint = "rpcEndpoint"
        static let serverProfiles = "aria2ServerProfiles"
        static let activeServerProfileID = "activeAria2ServerProfileID"
        static let downloadDirectory = "downloadDirectory"
        static let autoStartLocalAria2 = "autoStartLocalAria2"
        static let notificationsEnabled = "notificationsEnabled"
        static let preventSystemSleepDuringDownloads = "preventSystemSleepDuringDownloads"
        static let showSpeedTrend = "showSpeedTrend"
        static let menuBarPanelStyle = "menuBarPanelStyle"
        static let appLanguage = AppLanguage.preferenceKey

        static let maxOverallDownloadLimitKiB = "maxOverallDownloadLimitKiB"
        static let maxOverallUploadLimitKiB = "maxOverallUploadLimitKiB"
        static let maxDownloadLimitKiB = "maxDownloadLimitKiB"
        static let maxUploadLimitKiB = "maxUploadLimitKiB"
        static let maxConcurrentDownloads = "maxConcurrentDownloads"
        static let nightLimitEnabled = "nightLimitEnabled"
        static let nightLimitStartMinute = "nightLimitStartMinute"
        static let nightLimitEndMinute = "nightLimitEndMinute"
        static let nightDownloadLimitKiB = "nightDownloadLimitKiB"
        static let nightUploadLimitKiB = "nightUploadLimitKiB"

        static let maxConnectionPerServer = "maxConnectionPerServer"
        static let split = "split"
        static let minSplitSizeMiB = "minSplitSizeMiB"
        static let diskCacheMiB = "diskCacheMiB"
        static let connectTimeoutSeconds = "connectTimeoutSeconds"
        static let timeoutSeconds = "timeoutSeconds"
        static let maxTries = "maxTries"
        static let retryWaitSeconds = "retryWaitSeconds"
        static let lowestSpeedLimitKiB = "lowestSpeedLimitKiB"

        static let fileAllocation = "fileAllocation"
        static let continueDownloads = "continueDownloads"
        static let autoFileRenaming = "autoFileRenaming"
        static let allowOverwrite = "allowOverwrite"
        static let preserveRemoteTime = "preserveRemoteTime"

        static let enableDHT = "enableDHT"
        static let enablePeerExchange = "enablePeerExchange"
        static let enableLocalPeerDiscovery = "enableLocalPeerDiscovery"
        static let btMaxPeers = "btMaxPeers"
        static let btRequestPeerSpeedLimitKiB = "btRequestPeerSpeedLimitKiB"
        static let listenPortStart = "listenPortStart"
        static let listenPortEnd = "listenPortEnd"
        static let seedTimeMinutes = "seedTimeMinutes"
        static let seedRatio = "seedRatio"
        static let advancedConfiguration = "aria2AdvancedConfiguration"
        static let customPerformanceProfiles = "aria2CustomPerformanceProfiles"
        static let customLibrarySources = "customLibrarySources"
        static let selectedPerformanceProfileID = "selectedPerformanceProfileID"
        static let didMigrateMetalinkLocaleAutofill =
            "didMigrateMetalinkLocaleAutofill"
    }

    static let defaultEndpoint = "http://127.0.0.1:6800/jsonrpc"
    static let defaultDownloadDirectory =
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
        ?? NSHomeDirectory() + "/Downloads"

    @Published var endpoint: String {
        didSet {
            defaults.set(endpoint, forKey: Key.endpoint)
            updateActiveServerProfile {
                $0.endpoint = endpoint
            }
        }
    }

    @Published var downloadDirectory: String {
        didSet { defaults.set(downloadDirectory, forKey: Key.downloadDirectory) }
    }

    @Published var autoStartLocalAria2: Bool {
        didSet {
            defaults.set(autoStartLocalAria2, forKey: Key.autoStartLocalAria2)
            updateActiveServerProfile {
                $0.autoStartLocalAria2 = autoStartLocalAria2
            }
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    @Published var preventSystemSleepDuringDownloads: Bool {
        didSet {
            defaults.set(
                preventSystemSleepDuringDownloads,
                forKey: Key.preventSystemSleepDuringDownloads
            )
        }
    }

    @Published var showSpeedTrend: Bool {
        didSet { defaults.set(showSpeedTrend, forKey: Key.showSpeedTrend) }
    }

    @Published var menuBarPanelStyle: MenuBarPanelStyle {
        didSet { defaults.set(menuBarPanelStyle.rawValue, forKey: Key.menuBarPanelStyle) }
    }

    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: Key.appLanguage)
        }
    }

    @Published var maxOverallDownloadLimitKiB: Int {
        didSet { defaults.set(maxOverallDownloadLimitKiB, forKey: Key.maxOverallDownloadLimitKiB) }
    }

    @Published var maxOverallUploadLimitKiB: Int {
        didSet { defaults.set(maxOverallUploadLimitKiB, forKey: Key.maxOverallUploadLimitKiB) }
    }

    @Published var maxDownloadLimitKiB: Int {
        didSet { defaults.set(maxDownloadLimitKiB, forKey: Key.maxDownloadLimitKiB) }
    }

    @Published var maxUploadLimitKiB: Int {
        didSet { defaults.set(maxUploadLimitKiB, forKey: Key.maxUploadLimitKiB) }
    }

    @Published var maxConcurrentDownloads: Int {
        didSet { defaults.set(maxConcurrentDownloads, forKey: Key.maxConcurrentDownloads) }
    }

    @Published var nightLimitEnabled: Bool {
        didSet { defaults.set(nightLimitEnabled, forKey: Key.nightLimitEnabled) }
    }

    @Published var nightLimitStartMinute: Int {
        didSet {
            defaults.set(
                min(max(nightLimitStartMinute, 0), 1_439),
                forKey: Key.nightLimitStartMinute
            )
        }
    }

    @Published var nightLimitEndMinute: Int {
        didSet {
            defaults.set(
                min(max(nightLimitEndMinute, 0), 1_439),
                forKey: Key.nightLimitEndMinute
            )
        }
    }

    @Published var nightDownloadLimitKiB: Int {
        didSet {
            defaults.set(max(nightDownloadLimitKiB, 0), forKey: Key.nightDownloadLimitKiB)
        }
    }

    @Published var nightUploadLimitKiB: Int {
        didSet {
            defaults.set(max(nightUploadLimitKiB, 0), forKey: Key.nightUploadLimitKiB)
        }
    }

    @Published var maxConnectionPerServer: Int {
        didSet { defaults.set(maxConnectionPerServer, forKey: Key.maxConnectionPerServer) }
    }

    @Published var split: Int {
        didSet { defaults.set(split, forKey: Key.split) }
    }

    @Published var minSplitSizeMiB: Int {
        didSet { defaults.set(minSplitSizeMiB, forKey: Key.minSplitSizeMiB) }
    }

    @Published var diskCacheMiB: Int {
        didSet { defaults.set(diskCacheMiB, forKey: Key.diskCacheMiB) }
    }

    @Published var connectTimeoutSeconds: Int {
        didSet { defaults.set(connectTimeoutSeconds, forKey: Key.connectTimeoutSeconds) }
    }

    @Published var timeoutSeconds: Int {
        didSet { defaults.set(timeoutSeconds, forKey: Key.timeoutSeconds) }
    }

    @Published var maxTries: Int {
        didSet { defaults.set(maxTries, forKey: Key.maxTries) }
    }

    @Published var retryWaitSeconds: Int {
        didSet { defaults.set(retryWaitSeconds, forKey: Key.retryWaitSeconds) }
    }

    @Published var lowestSpeedLimitKiB: Int {
        didSet { defaults.set(lowestSpeedLimitKiB, forKey: Key.lowestSpeedLimitKiB) }
    }

    @Published var fileAllocation: FileAllocationMethod {
        didSet { defaults.set(fileAllocation.rawValue, forKey: Key.fileAllocation) }
    }

    @Published var continueDownloads: Bool {
        didSet { defaults.set(continueDownloads, forKey: Key.continueDownloads) }
    }

    @Published var autoFileRenaming: Bool {
        didSet { defaults.set(autoFileRenaming, forKey: Key.autoFileRenaming) }
    }

    @Published var allowOverwrite: Bool {
        didSet { defaults.set(allowOverwrite, forKey: Key.allowOverwrite) }
    }

    @Published var preserveRemoteTime: Bool {
        didSet { defaults.set(preserveRemoteTime, forKey: Key.preserveRemoteTime) }
    }

    @Published var enableDHT: Bool {
        didSet { defaults.set(enableDHT, forKey: Key.enableDHT) }
    }

    @Published var enablePeerExchange: Bool {
        didSet { defaults.set(enablePeerExchange, forKey: Key.enablePeerExchange) }
    }

    @Published var enableLocalPeerDiscovery: Bool {
        didSet { defaults.set(enableLocalPeerDiscovery, forKey: Key.enableLocalPeerDiscovery) }
    }

    @Published var btMaxPeers: Int {
        didSet { defaults.set(btMaxPeers, forKey: Key.btMaxPeers) }
    }

    @Published var btRequestPeerSpeedLimitKiB: Int {
        didSet {
            defaults.set(
                btRequestPeerSpeedLimitKiB,
                forKey: Key.btRequestPeerSpeedLimitKiB
            )
        }
    }

    @Published var listenPortStart: Int {
        didSet { defaults.set(listenPortStart, forKey: Key.listenPortStart) }
    }

    @Published var listenPortEnd: Int {
        didSet { defaults.set(listenPortEnd, forKey: Key.listenPortEnd) }
    }

    @Published var seedTimeMinutes: Int {
        didSet { defaults.set(seedTimeMinutes, forKey: Key.seedTimeMinutes) }
    }

    @Published var seedRatio: Double {
        didSet { defaults.set(seedRatio, forKey: Key.seedRatio) }
    }

    @Published var advancedConfiguration: Aria2AdvancedOptions {
        didSet {
            if let data = try? JSONEncoder().encode(advancedConfiguration) {
                defaults.set(data, forKey: Key.advancedConfiguration)
            }
        }
    }

    @Published var proxyPassword: String {
        didSet {
            persistCredential(
                proxyPassword,
                account: "aria2-proxy-password",
                credential: .proxyPassword
            )
        }
    }

    @Published private(set) var serverProfiles: [Aria2ServerProfile] = []
    @Published private(set) var activeServerProfileID: UUID?
    @Published private(set) var keychainPersistenceIssue: KeychainPersistenceIssue?
    @Published private(set) var customPerformanceProfiles: [Aria2PerformanceProfile] = [] {
        didSet { persistPerformanceProfiles() }
    }
    @Published private(set) var customLibrarySources: [CustomLibrarySource] = [] {
        didSet { persistCustomLibrarySources() }
    }
    @Published private(set) var selectedPerformanceProfileID: UUID? {
        didSet {
            defaults.set(
                selectedPerformanceProfileID?.uuidString,
                forKey: Key.selectedPerformanceProfileID
            )
        }
    }

    @Published var rpcSecret: String {
        didSet {
            let account = activeServerProfileID.map(Self.profileSecretAccount)
                ?? "aria2-rpc-secret"
            persistCredential(
                rpcSecret,
                account: account,
                credential: .rpcSecret
            )
        }
    }

    private let defaults: UserDefaults
    private let keychain: KeychainClient

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainClient = .live
    ) {
        self.defaults = defaults
        self.keychain = keychain
        let recommended = Aria2Configuration.recommended(
            downloadDirectory: Self.defaultDownloadDirectory
        )

        defaults.register(defaults: [
            Key.endpoint: Self.defaultEndpoint,
            Key.downloadDirectory: Self.defaultDownloadDirectory,
            Key.autoStartLocalAria2: true,
            Key.notificationsEnabled: true,
            Key.preventSystemSleepDuringDownloads: true,
            Key.showSpeedTrend: true,
            Key.menuBarPanelStyle: MenuBarPanelStyle.adaptive.rawValue,
            Key.appLanguage: AppLanguage.system.rawValue,
            Key.maxOverallDownloadLimitKiB: recommended.maxOverallDownloadLimitKiB,
            Key.maxOverallUploadLimitKiB: recommended.maxOverallUploadLimitKiB,
            Key.maxDownloadLimitKiB: recommended.maxDownloadLimitKiB,
            Key.maxUploadLimitKiB: recommended.maxUploadLimitKiB,
            Key.maxConcurrentDownloads: recommended.maxConcurrentDownloads,
            Key.nightLimitEnabled: false,
            Key.nightLimitStartMinute: 23 * 60,
            Key.nightLimitEndMinute: 7 * 60,
            Key.nightDownloadLimitKiB: 2_048,
            Key.nightUploadLimitKiB: 256,
            Key.maxConnectionPerServer: recommended.maxConnectionPerServer,
            Key.split: recommended.split,
            Key.minSplitSizeMiB: recommended.minSplitSizeMiB,
            Key.diskCacheMiB: recommended.diskCacheMiB,
            Key.connectTimeoutSeconds: recommended.connectTimeoutSeconds,
            Key.timeoutSeconds: recommended.timeoutSeconds,
            Key.maxTries: recommended.maxTries,
            Key.retryWaitSeconds: recommended.retryWaitSeconds,
            Key.lowestSpeedLimitKiB: recommended.lowestSpeedLimitKiB,
            Key.fileAllocation: recommended.fileAllocation.rawValue,
            Key.continueDownloads: recommended.continueDownloads,
            Key.autoFileRenaming: recommended.autoFileRenaming,
            Key.allowOverwrite: recommended.allowOverwrite,
            Key.preserveRemoteTime: recommended.preserveRemoteTime,
            Key.enableDHT: recommended.enableDHT,
            Key.enablePeerExchange: recommended.enablePeerExchange,
            Key.enableLocalPeerDiscovery: recommended.enableLocalPeerDiscovery,
            Key.btMaxPeers: recommended.btMaxPeers,
            Key.btRequestPeerSpeedLimitKiB:
                recommended.btRequestPeerSpeedLimitKiB,
            Key.listenPortStart: recommended.listenPortStart,
            Key.listenPortEnd: recommended.listenPortEnd,
            Key.seedTimeMinutes: recommended.seedTimeMinutes,
            Key.seedRatio: recommended.seedRatio,
            Key.selectedPerformanceProfileID:
                Aria2PerformanceProfile.maximumSpeedID.uuidString
        ])

        endpoint = defaults.string(forKey: Key.endpoint) ?? Self.defaultEndpoint
        downloadDirectory =
            defaults.string(forKey: Key.downloadDirectory) ?? Self.defaultDownloadDirectory
        autoStartLocalAria2 = defaults.bool(forKey: Key.autoStartLocalAria2)
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        preventSystemSleepDuringDownloads =
            defaults.bool(forKey: Key.preventSystemSleepDuringDownloads)
        showSpeedTrend = defaults.bool(forKey: Key.showSpeedTrend)
        menuBarPanelStyle =
            MenuBarPanelStyle(rawValue: defaults.string(forKey: Key.menuBarPanelStyle) ?? "")
            ?? .adaptive
        let storedAppLanguage =
            AppLanguage(rawValue: defaults.string(forKey: Key.appLanguage) ?? "")
            ?? .system
        appLanguage = storedAppLanguage

        maxOverallDownloadLimitKiB = defaults.integer(forKey: Key.maxOverallDownloadLimitKiB)
        maxOverallUploadLimitKiB = defaults.integer(forKey: Key.maxOverallUploadLimitKiB)
        maxDownloadLimitKiB = defaults.integer(forKey: Key.maxDownloadLimitKiB)
        maxUploadLimitKiB = defaults.integer(forKey: Key.maxUploadLimitKiB)
        maxConcurrentDownloads = max(defaults.integer(forKey: Key.maxConcurrentDownloads), 1)
        nightLimitEnabled = defaults.bool(forKey: Key.nightLimitEnabled)
        nightLimitStartMinute = min(
            max(defaults.integer(forKey: Key.nightLimitStartMinute), 0),
            1_439
        )
        nightLimitEndMinute = min(
            max(defaults.integer(forKey: Key.nightLimitEndMinute), 0),
            1_439
        )
        nightDownloadLimitKiB = max(
            defaults.integer(forKey: Key.nightDownloadLimitKiB),
            0
        )
        nightUploadLimitKiB = max(
            defaults.integer(forKey: Key.nightUploadLimitKiB),
            0
        )

        maxConnectionPerServer = defaults.integer(forKey: Key.maxConnectionPerServer)
        split = defaults.integer(forKey: Key.split)
        minSplitSizeMiB = defaults.integer(forKey: Key.minSplitSizeMiB)
        diskCacheMiB = defaults.integer(forKey: Key.diskCacheMiB)
        connectTimeoutSeconds = defaults.integer(forKey: Key.connectTimeoutSeconds)
        timeoutSeconds = defaults.integer(forKey: Key.timeoutSeconds)
        maxTries = defaults.integer(forKey: Key.maxTries)
        retryWaitSeconds = defaults.integer(forKey: Key.retryWaitSeconds)
        lowestSpeedLimitKiB = defaults.integer(forKey: Key.lowestSpeedLimitKiB)

        fileAllocation =
            FileAllocationMethod(rawValue: defaults.string(forKey: Key.fileAllocation) ?? "")
            ?? .trunc
        continueDownloads = defaults.bool(forKey: Key.continueDownloads)
        autoFileRenaming = defaults.bool(forKey: Key.autoFileRenaming)
        allowOverwrite = defaults.bool(forKey: Key.allowOverwrite)
        preserveRemoteTime = defaults.bool(forKey: Key.preserveRemoteTime)

        enableDHT = defaults.bool(forKey: Key.enableDHT)
        enablePeerExchange = defaults.bool(forKey: Key.enablePeerExchange)
        enableLocalPeerDiscovery = defaults.bool(forKey: Key.enableLocalPeerDiscovery)
        btMaxPeers = defaults.integer(forKey: Key.btMaxPeers)
        btRequestPeerSpeedLimitKiB = max(
            defaults.integer(forKey: Key.btRequestPeerSpeedLimitKiB),
            0
        )
        listenPortStart = defaults.integer(forKey: Key.listenPortStart)
        listenPortEnd = defaults.integer(forKey: Key.listenPortEnd)
        seedTimeMinutes = defaults.integer(forKey: Key.seedTimeMinutes)
        seedRatio = defaults.double(forKey: Key.seedRatio)

        var storedAdvancedConfiguration = defaults.data(
            forKey: Key.advancedConfiguration
        ).flatMap {
            try? JSONDecoder().decode(Aria2AdvancedOptions.self, from: $0)
        } ?? Aria2AdvancedOptions.defaultGlobalConfiguration
        let removedLegacyMetalinkAutofill =
            !defaults.bool(forKey: Key.didMigrateMetalinkLocaleAutofill)
            && Self.removeLegacyMetalinkLocaleAutofill(
                from: &storedAdvancedConfiguration
            )
        let legacyProxyPassword = storedAdvancedConfiguration.proxyPassword
        storedAdvancedConfiguration.proxyPassword = ""
        if removedLegacyMetalinkAutofill,
           let migratedData = try? JSONEncoder().encode(
               storedAdvancedConfiguration
           )
        {
            defaults.set(migratedData, forKey: Key.advancedConfiguration)
        }
        defaults.set(true, forKey: Key.didMigrateMetalinkLocaleAutofill)
        advancedConfiguration = storedAdvancedConfiguration
        customPerformanceProfiles = defaults.data(
            forKey: Key.customPerformanceProfiles
        ).flatMap {
            try? JSONDecoder().decode([Aria2PerformanceProfile].self, from: $0)
        }?.filter {
            $0.kind == .custom && !$0.name.trimmed.isEmpty
        } ?? []
        customLibrarySources = defaults.data(
            forKey: Key.customLibrarySources
        ).flatMap {
            try? JSONDecoder().decode([CustomLibrarySource].self, from: $0)
        }?.compactMap {
            try? $0.validated()
        } ?? []
        selectedPerformanceProfileID = defaults.string(
            forKey: Key.selectedPerformanceProfileID
        ).flatMap(UUID.init(uuidString:))
        let storedProxyPassword = keychain.read(
            service: KeychainStore.service,
            account: "aria2-proxy-password"
        )
        proxyPassword = storedProxyPassword ?? legacyProxyPassword

        rpcSecret =
            keychain.read(service: KeychainStore.service, account: "aria2-rpc-secret") ?? ""
        configureServerProfiles(legacySecret: rpcSecret)

        if storedProxyPassword == nil, !legacyProxyPassword.isEmpty {
            persistCredential(
                legacyProxyPassword,
                account: "aria2-proxy-password",
                credential: .proxyPassword
            )
        }
    }

    var endpointURL: URL? {
        Self.normalizedEndpointURL(endpoint)
    }

    nonisolated static func normalizedEndpointURL(_ endpoint: String) -> URL? {
        var candidate = endpoint.trimmed
        guard !candidate.isEmpty else { return nil }
        if !candidate.contains("://") {
            candidate = "http://" + candidate
        }

        guard var components = URLComponents(string: candidate) else {
            return nil
        }
        guard let scheme = components.scheme?.lowercased(),
              ["http", "https", "ws", "wss"].contains(scheme) else {
            return nil
        }
        components.scheme = ["https", "wss"].contains(scheme) ? "https" : "http"
        if components.path.isEmpty || components.path == "/" {
            components.path = "/jsonrpc"
        }
        return components.url
    }

    var webSocketEndpointURL: URL? {
        endpointURL.flatMap(Aria2WebSocketClient.webSocketURL(from:))
    }

    var activeServerProfile: Aria2ServerProfile? {
        guard let activeServerProfileID else { return nil }
        return serverProfiles.first { $0.id == activeServerProfileID }
    }

    var activeServerProfileName: String {
        activeServerProfile?.displayName ?? L10n.string("aria2 服务器")
    }

    func saveActiveServerProfile() {
        guard let activeServerProfileID,
              let index = serverProfiles.firstIndex(where: { $0.id == activeServerProfileID }) else {
            return
        }

        serverProfiles[index].endpoint = endpoint
        serverProfiles[index].autoStartLocalAria2 = autoStartLocalAria2
        persistCredential(
            rpcSecret,
            account: Self.profileSecretAccount(activeServerProfileID),
            credential: .rpcSecret
        )
        persistServerProfiles()
    }

    func renameActiveServerProfile(_ name: String) {
        guard let activeServerProfileID,
              let index = serverProfiles.firstIndex(where: { $0.id == activeServerProfileID }) else {
            return
        }
        serverProfiles[index].name = name
        persistServerProfiles()
    }

    @discardableResult
    func addServerProfile() -> UUID {
        saveActiveServerProfile()
        let profile = Aria2ServerProfile(
            name: L10n.string("服务器 \(serverProfiles.count + 1)"),
            endpoint: endpoint,
            autoStartLocalAria2: false
        )
        serverProfiles.append(profile)
        activeServerProfileID = profile.id
        endpoint = profile.endpoint
        autoStartLocalAria2 = profile.autoStartLocalAria2
        rpcSecret = ""
        persistServerProfiles()
        return profile.id
    }

    @discardableResult
    func addServerProfile(
        name: String,
        endpoint: String,
        secret: String
    ) -> UUID {
        saveActiveServerProfile()
        let profile = Aria2ServerProfile(
            name: name.trimmed,
            endpoint: endpoint.trimmed,
            autoStartLocalAria2: false
        )
        serverProfiles.append(profile)
        persistCredential(
            secret,
            account: Self.profileSecretAccount(profile.id),
            credential: .rpcSecret
        )
        persistServerProfiles()
        return profile.id
    }

    func activateServerProfile(id: UUID) {
        guard id != activeServerProfileID,
              let profile = serverProfiles.first(where: { $0.id == id }) else {
            return
        }
        saveActiveServerProfile()
        activeServerProfileID = id
        endpoint = profile.endpoint
        autoStartLocalAria2 = profile.autoStartLocalAria2
        rpcSecret = keychain.read(
            service: KeychainStore.service,
            account: Self.profileSecretAccount(id)
        ) ?? ""
        persistServerProfiles()
    }

    func removeServerProfile(id: UUID) {
        guard serverProfiles.count > 1,
              let index = serverProfiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        if id != activeServerProfileID {
            saveActiveServerProfile()
        }
        serverProfiles.remove(at: index)
        persistCredential(
            "",
            account: Self.profileSecretAccount(id),
            credential: .rpcSecret
        )

        if id == activeServerProfileID, let replacement = serverProfiles.first {
            activeServerProfileID = replacement.id
            endpoint = replacement.endpoint
            autoStartLocalAria2 = replacement.autoStartLocalAria2
            rpcSecret = keychain.read(
                service: KeychainStore.service,
                account: Self.profileSecretAccount(replacement.id)
            ) ?? ""
        }
        persistServerProfiles()
    }

    var aria2Configuration: Aria2Configuration {
        makeAria2Configuration(
            extraGlobalOptions: (
                try? advancedConfiguration.optionValues(
                    proxyPassword: proxyPassword
                )
            ) ?? [:]
        )
    }

    func validatedAria2Configuration() throws -> Aria2Configuration {
        makeAria2Configuration(
            extraGlobalOptions: try advancedConfiguration.optionValues(
                proxyPassword: proxyPassword
            )
        )
    }

    private func makeAria2Configuration(
        extraGlobalOptions: [String: String]
    ) -> Aria2Configuration {
        Aria2Configuration(
            downloadDirectory: downloadDirectory,
            maxOverallDownloadLimitKiB: maxOverallDownloadLimitKiB,
            maxOverallUploadLimitKiB: maxOverallUploadLimitKiB,
            maxDownloadLimitKiB: maxDownloadLimitKiB,
            maxUploadLimitKiB: maxUploadLimitKiB,
            maxConcurrentDownloads: maxConcurrentDownloads,
            maxConnectionPerServer: maxConnectionPerServer,
            split: split,
            minSplitSizeMiB: minSplitSizeMiB,
            diskCacheMiB: diskCacheMiB,
            connectTimeoutSeconds: connectTimeoutSeconds,
            timeoutSeconds: timeoutSeconds,
            maxTries: maxTries,
            retryWaitSeconds: retryWaitSeconds,
            lowestSpeedLimitKiB: lowestSpeedLimitKiB,
            fileAllocation: fileAllocation,
            continueDownloads: continueDownloads,
            autoFileRenaming: autoFileRenaming,
            allowOverwrite: allowOverwrite,
            preserveRemoteTime: preserveRemoteTime,
            enableDHT: enableDHT,
            enablePeerExchange: enablePeerExchange,
            enableLocalPeerDiscovery: enableLocalPeerDiscovery,
            btMaxPeers: btMaxPeers,
            btRequestPeerSpeedLimitKiB: btRequestPeerSpeedLimitKiB,
            listenPortStart: listenPortStart,
            listenPortEnd: listenPortEnd,
            seedTimeMinutes: seedTimeMinutes,
            seedRatio: seedRatio,
            extraGlobalOptions: extraGlobalOptions
        )
    }

    var nightSpeedSchedule: NightSpeedSchedule {
        NightSpeedSchedule(
            isEnabled: nightLimitEnabled,
            startMinute: nightLimitStartMinute,
            endMinute: nightLimitEndMinute,
            downloadLimitKiB: nightDownloadLimitKiB,
            uploadLimitKiB: nightUploadLimitKiB
        )
    }

    var performanceProfiles: [Aria2PerformanceProfile] {
        Aria2PerformanceProfile.builtIn + customPerformanceProfiles
    }

    var activePerformanceProfileID: UUID? {
        guard let selectedPerformanceProfileID,
              let selected = performanceProfiles.first(
                where: { $0.id == selectedPerformanceProfileID }
              ),
              selected.hasSameSettings(as: capturedPerformanceProfile())
        else {
            return nil
        }
        return selectedPerformanceProfileID
    }

    func capturedPerformanceProfile(
        id: UUID = UUID(),
        name: String = ""
    ) -> Aria2PerformanceProfile {
        Aria2PerformanceProfile(
            id: id,
            kind: .custom,
            name: name,
            maxOverallDownloadLimitKiB: maxOverallDownloadLimitKiB,
            maxOverallUploadLimitKiB: maxOverallUploadLimitKiB,
            maxDownloadLimitKiB: maxDownloadLimitKiB,
            maxUploadLimitKiB: maxUploadLimitKiB,
            maxConcurrentDownloads: maxConcurrentDownloads,
            maxConnectionPerServer: maxConnectionPerServer,
            split: split,
            minSplitSizeMiB: minSplitSizeMiB,
            diskCacheMiB: diskCacheMiB,
            enableDHT: enableDHT,
            enablePeerExchange: enablePeerExchange,
            enableLocalPeerDiscovery: enableLocalPeerDiscovery,
            enableDHT6: advancedConfiguration.enableDHT6 == .enabled,
            btMaxPeers: btMaxPeers,
            btRequestPeerSpeedLimitKiB: btRequestPeerSpeedLimitKiB
        )
    }

    func applyPerformanceProfile(_ profile: Aria2PerformanceProfile) {
        maxOverallDownloadLimitKiB = max(profile.maxOverallDownloadLimitKiB, 0)
        maxOverallUploadLimitKiB = max(profile.maxOverallUploadLimitKiB, 0)
        maxDownloadLimitKiB = max(profile.maxDownloadLimitKiB, 0)
        maxUploadLimitKiB = max(profile.maxUploadLimitKiB, 0)
        maxConcurrentDownloads = min(max(profile.maxConcurrentDownloads, 1), 20)
        maxConnectionPerServer = min(max(profile.maxConnectionPerServer, 1), 16)
        split = min(max(profile.split, 1), 16)
        minSplitSizeMiB = min(max(profile.minSplitSizeMiB, 1), 1_024)
        diskCacheMiB = min(max(profile.diskCacheMiB, 0), 4_096)
        enableDHT = profile.enableDHT
        enablePeerExchange = profile.enablePeerExchange
        enableLocalPeerDiscovery = profile.enableLocalPeerDiscovery
        btMaxPeers = min(max(profile.btMaxPeers, 0), 500)
        btRequestPeerSpeedLimitKiB = max(
            profile.btRequestPeerSpeedLimitKiB,
            0
        )

        var updatedAdvancedConfiguration = advancedConfiguration
        updatedAdvancedConfiguration.enableDHT6 =
            profile.enableDHT6 ? .enabled : .disabled
        advancedConfiguration = updatedAdvancedConfiguration
        selectedPerformanceProfileID = profile.id
    }

    @discardableResult
    func saveCustomPerformanceProfile(
        _ profile: Aria2PerformanceProfile
    ) -> Aria2PerformanceProfile {
        let trimmedName = profile.name.trimmed
        let resolvedID = [
            Aria2PerformanceProfile.maximumSpeedID,
            Aria2PerformanceProfile.compatibilityID
        ].contains(profile.id) ? UUID() : profile.id
        var saved = Aria2PerformanceProfile.custom(
            id: resolvedID,
            name: trimmedName.isEmpty
                ? L10n.string("自定义方案")
                : trimmedName,
            basedOn: profile
        )
        saved.kind = .custom

        if let index = customPerformanceProfiles.firstIndex(
            where: { $0.id == saved.id }
        ) {
            customPerformanceProfiles[index] = saved
        } else {
            customPerformanceProfiles.append(saved)
        }
        return saved
    }

    func removeCustomPerformanceProfile(id: UUID) {
        guard customPerformanceProfiles.contains(where: { $0.id == id }) else {
            return
        }
        customPerformanceProfiles.removeAll { $0.id == id }
        if selectedPerformanceProfileID == id {
            selectedPerformanceProfileID = nil
        }
    }

    @discardableResult
    func saveCustomLibrarySource(
        _ source: CustomLibrarySource
    ) throws -> CustomLibrarySource {
        let saved = try source.validated()
        if let index = customLibrarySources.firstIndex(
            where: { $0.id == saved.id }
        ) {
            customLibrarySources[index] = saved
        } else {
            customLibrarySources.append(saved)
        }
        return saved
    }

    func setCustomLibrarySourceEnabled(id: UUID, isEnabled: Bool) {
        guard let index = customLibrarySources.firstIndex(
            where: { $0.id == id }
        ) else {
            return
        }
        customLibrarySources[index].isEnabled = isEnabled
    }

    func removeCustomLibrarySource(id: UUID) {
        customLibrarySources.removeAll { $0.id == id }
    }

    func restoreRecommendedAria2Settings() {
        let recommended = Aria2Configuration.recommended(downloadDirectory: downloadDirectory)
        maxOverallDownloadLimitKiB = recommended.maxOverallDownloadLimitKiB
        maxOverallUploadLimitKiB = recommended.maxOverallUploadLimitKiB
        maxDownloadLimitKiB = recommended.maxDownloadLimitKiB
        maxUploadLimitKiB = recommended.maxUploadLimitKiB
        maxConcurrentDownloads = recommended.maxConcurrentDownloads
        maxConnectionPerServer = recommended.maxConnectionPerServer
        split = recommended.split
        minSplitSizeMiB = recommended.minSplitSizeMiB
        diskCacheMiB = recommended.diskCacheMiB
        connectTimeoutSeconds = recommended.connectTimeoutSeconds
        timeoutSeconds = recommended.timeoutSeconds
        maxTries = recommended.maxTries
        retryWaitSeconds = recommended.retryWaitSeconds
        lowestSpeedLimitKiB = recommended.lowestSpeedLimitKiB
        fileAllocation = recommended.fileAllocation
        continueDownloads = recommended.continueDownloads
        autoFileRenaming = recommended.autoFileRenaming
        allowOverwrite = recommended.allowOverwrite
        preserveRemoteTime = recommended.preserveRemoteTime
        enableDHT = recommended.enableDHT
        enablePeerExchange = recommended.enablePeerExchange
        enableLocalPeerDiscovery = recommended.enableLocalPeerDiscovery
        btMaxPeers = recommended.btMaxPeers
        btRequestPeerSpeedLimitKiB = recommended.btRequestPeerSpeedLimitKiB
        listenPortStart = recommended.listenPortStart
        listenPortEnd = recommended.listenPortEnd
        seedTimeMinutes = recommended.seedTimeMinutes
        seedRatio = recommended.seedRatio
        advancedConfiguration = .defaultGlobalConfiguration
        proxyPassword = ""
        selectedPerformanceProfileID = Aria2PerformanceProfile.maximumSpeedID
    }

    func dismissKeychainPersistenceIssue() {
        keychainPersistenceIssue = nil
    }

    private static func removeLegacyMetalinkLocaleAutofill(
        from configuration: inout Aria2AdvancedOptions
    ) -> Bool {
        let region = configuration.metalinkLocation.trimmed.lowercased()
        let language = configuration.metalinkLanguage.trimmed.lowercased()
        let isKnownAutofill =
            (region == "cn" && language == "zh-cn")
            || (region == "us" && language == "en-us")

        guard isKnownAutofill else {
            return false
        }

        configuration.metalinkLocation = ""
        configuration.metalinkLanguage = ""
        return true
    }

    private func persistCredential(
        _ value: String,
        account: String,
        credential: KeychainCredential
    ) {
        do {
            try keychain.save(
                value,
                service: KeychainStore.service,
                account: account
            )
            if keychainPersistenceIssue?.account == account {
                keychainPersistenceIssue = nil
            }
        } catch {
            keychainPersistenceIssue = KeychainPersistenceIssue(
                credential: credential,
                account: account,
                title: L10n.string("无法保存到 macOS 钥匙串"),
                message: L10n.string(
                    "\(credential.title)的更改未能保存到 macOS 钥匙串。当前会话仍会使用此值，但重新启动后可能无法恢复。请确认登录钥匙串已解锁后重试。系统信息：\(error.localizedDescription)"
                )
            )
        }
    }

    private func configureServerProfiles(legacySecret: String) {
        let decoder = JSONDecoder()
        let decodedProfiles = defaults.data(forKey: Key.serverProfiles)
            .flatMap { try? decoder.decode([Aria2ServerProfile].self, from: $0) }
            .flatMap { $0.isEmpty ? nil : $0 }

        if let decodedProfiles {
            serverProfiles = decodedProfiles
        } else {
            serverProfiles = [
                Aria2ServerProfile(
                    name: endpoint.contains("127.0.0.1") || endpoint.contains("localhost")
                        ? L10n.string("本机 aria2")
                        : L10n.string("aria2 服务器"),
                    endpoint: endpoint,
                    autoStartLocalAria2: autoStartLocalAria2
                )
            ]
        }

        let storedID = defaults.string(forKey: Key.activeServerProfileID)
            .flatMap(UUID.init(uuidString:))
        let selectedID = storedID.flatMap { candidate in
            serverProfiles.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? serverProfiles[0].id
        activeServerProfileID = selectedID

        guard let profile = serverProfiles.first(where: { $0.id == selectedID }) else {
            return
        }
        endpoint = profile.endpoint
        autoStartLocalAria2 = profile.autoStartLocalAria2

        let profileAccount = Self.profileSecretAccount(selectedID)
        if let storedSecret = keychain.read(
            service: KeychainStore.service,
            account: profileAccount
        ) {
            rpcSecret = storedSecret
        } else {
            rpcSecret = legacySecret
            persistCredential(
                legacySecret,
                account: profileAccount,
                credential: .rpcSecret
            )
        }
        persistServerProfiles()
    }

    private func persistServerProfiles() {
        if let data = try? JSONEncoder().encode(serverProfiles) {
            defaults.set(data, forKey: Key.serverProfiles)
        }
        defaults.set(activeServerProfileID?.uuidString, forKey: Key.activeServerProfileID)
    }

    private func persistPerformanceProfiles() {
        if let data = try? JSONEncoder().encode(customPerformanceProfiles) {
            defaults.set(data, forKey: Key.customPerformanceProfiles)
        }
    }

    private func persistCustomLibrarySources() {
        if let data = try? JSONEncoder().encode(customLibrarySources) {
            defaults.set(data, forKey: Key.customLibrarySources)
        }
    }

    private func updateActiveServerProfile(
        _ update: (inout Aria2ServerProfile) -> Void
    ) {
        guard let activeServerProfileID,
              let index = serverProfiles.firstIndex(where: { $0.id == activeServerProfileID }) else {
            return
        }
        update(&serverProfiles[index])
        persistServerProfiles()
    }

    private static func profileSecretAccount(_ id: UUID) -> String {
        "aria2-rpc-secret-\(id.uuidString.lowercased())"
    }
}
