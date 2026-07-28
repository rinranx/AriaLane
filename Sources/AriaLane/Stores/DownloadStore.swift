import AppKit
import Combine
import Foundation

@MainActor
final class DownloadStore: ObservableObject {
    @Published private(set) var transfers: [TransferItem] = []
    @Published private(set) var globalStats = GlobalStats.zero
    @Published private(set) var speedSamples: [SpeedSample] = []
    @Published private(set) var historyEntries: [DownloadHistoryEntry] = []
    @Published private(set) var scheduledDownloads: [ScheduledDownload] = []
    @Published private(set) var rssSubscriptions: [RSSSubscription] = []
    @Published private(set) var refreshingRSSSubscriptionIDs: Set<UUID> = []
    @Published private(set) var pendingDownloads: [PendingDownload] = []
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var isPerformingAction = false
    @Published private(set) var settingsApplyState: SettingsApplyState = .idle
    @Published private(set) var notificationPermissionState: NotificationPermissionState = .disabled
    @Published private(set) var pendingImport: PendingDownloadImport?
    @Published private(set) var queuedImportCount = 0
    @Published private(set) var isPreventingSystemSleep = false
    @Published private(set) var connectionDiagnosticState: ConnectionDiagnosticState = .idle
    @Published private(set) var eventStreamState: Aria2EventStreamState = .disabled
    @Published private(set) var daemonSessionID: String?
    @Published private(set) var serverRPCMethods: [String] = []
    @Published private(set) var serverRPCNotifications: [String] = []
    @Published var selectedTransferGID: String?
    @Published var notice: AppNotice?

    let preferences: AppPreferences

    private let organizationStore: TaskOrganizationStore
    private let client = Aria2RPCClient()
    private let eventClient = Aria2WebSocketClient()
    private let processManager = Aria2ProcessManager()
    private let notificationService = DownloadNotificationService()
    private let dockProgressController = DockProgressController()
    private let powerAssertionController = DownloadPowerAssertionController()
    private let historyRepository: DownloadHistoryRepository
    private let scheduleRepository: DownloadScheduleRepository
    private let rssSubscriptionRepository: RSSSubscriptionRepository
    private let pendingDownloadRepository: PendingDownloadRepository
    private var pollingTask: Task<Void, Never>?
    private var rssPollingTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var settingsStateTask: Task<Void, Never>?
    private var importContinuationTask: Task<Void, Never>?
    private var eventRefreshTask: Task<Void, Never>?
    private var knownStatuses: [String: TransferStatus] = [:]
    private var hasStatusBaseline = false
    private var queuePositions: [String: Int] = [:]
    private var speedSeries = SpeedSampleSeries()
    private var historyArchive: DownloadHistoryArchive
    private var scheduleArchive: DownloadScheduleArchive
    private var rssSubscriptionArchive: RSSSubscriptionArchive
    private var pendingDownloadArchive: PendingDownloadArchive
    private var executingScheduleIDs: Set<UUID> = []
    private var importQueue: [URL] = []
    private var isPreparingImport = false
    private var appliedSpeedPolicy: SpeedPolicy?
    private var isRefreshing = false
    private var isReconnecting = false
    private var isFlushingPendingDownloads = false
    private var connectionFailureCount = 0
    private var nextReconnectAt: Date?
    private var connectedProfileID: UUID?
    private var connectedEndpoint: URL?
    private var startupMessages: [String] = []
    private let connectionBackoff = ConnectionRetryBackoff()
    private let pendingRetryPolicy = PendingDownloadRetryPolicy()

    init(
        preferences: AppPreferences,
        organizationStore: TaskOrganizationStore,
        historyRepository: DownloadHistoryRepository = DownloadHistoryRepository(),
        scheduleRepository: DownloadScheduleRepository = DownloadScheduleRepository(),
        rssSubscriptionRepository: RSSSubscriptionRepository = RSSSubscriptionRepository(),
        pendingDownloadRepository: PendingDownloadRepository = PendingDownloadRepository()
    ) {
        self.preferences = preferences
        self.organizationStore = organizationStore
        self.historyRepository = historyRepository
        self.scheduleRepository = scheduleRepository
        self.rssSubscriptionRepository = rssSubscriptionRepository
        self.pendingDownloadRepository = pendingDownloadRepository
        var loadingMessages: [String] = []

        let historyResult: ArchiveLoadResult<DownloadHistoryArchive>
        do {
            historyResult = try historyRepository.loadResult()
        } catch {
            historyResult = ArchiveLoadResult(
                value: DownloadHistoryArchive(),
                recovery: nil
            )
            loadingMessages.append(L10n.string("无法读取下载历史：\(error.localizedDescription)"))
        }
        historyArchive = historyResult.value
        historyEntries = historyResult.value.entries
        if historyResult.recovery != nil {
            loadingMessages.append(Self.recoveryMessage(for: L10n.string("下载历史"), historyResult.recovery))
        }

        let scheduleResult: ArchiveLoadResult<DownloadScheduleArchive>
        do {
            scheduleResult = try scheduleRepository.loadResult()
        } catch {
            scheduleResult = ArchiveLoadResult(
                value: DownloadScheduleArchive(),
                recovery: nil
            )
            loadingMessages.append(L10n.string("无法读取计划任务：\(error.localizedDescription)"))
        }
        scheduleArchive = scheduleResult.value
        scheduledDownloads = scheduleResult.value.entries
        if scheduleResult.recovery != nil {
            loadingMessages.append(Self.recoveryMessage(for: L10n.string("计划任务"), scheduleResult.recovery))
        }

        let rssResult: ArchiveLoadResult<RSSSubscriptionArchive>
        do {
            rssResult = try rssSubscriptionRepository.loadResult()
        } catch {
            rssResult = ArchiveLoadResult(
                value: RSSSubscriptionArchive(),
                recovery: nil
            )
            loadingMessages.append(L10n.string("无法读取 RSS 订阅：\(error.localizedDescription)"))
        }
        rssSubscriptionArchive = rssResult.value
        rssSubscriptions = rssResult.value.entries
        if rssResult.recovery != nil {
            loadingMessages.append(Self.recoveryMessage(for: L10n.string("RSS 订阅"), rssResult.recovery))
        }

        let pendingResult: ArchiveLoadResult<PendingDownloadArchive>
        do {
            pendingResult = try pendingDownloadRepository.loadResult()
        } catch {
            pendingResult = ArchiveLoadResult(
                value: PendingDownloadArchive(),
                recovery: nil
            )
            loadingMessages.append(L10n.string("无法读取待发送任务：\(error.localizedDescription)"))
        }
        pendingDownloadArchive = pendingResult.value
        pendingDownloads = pendingResult.value.entries
        if pendingResult.recovery != nil {
            loadingMessages.append(
                Self.recoveryMessage(for: L10n.string("待发送任务"), pendingResult.recovery)
            )
        }
        organizationStore.reconcileHistory(historyEntries)
        if let loadingMessage = organizationStore.loadingMessage {
            loadingMessages.append(loadingMessage)
        }
        startupMessages = loadingMessages
    }

    func start() async {
        guard pollingTask == nil else { return }
        await prepareNotifications(enabled: preferences.notificationsEnabled)
        if !startupMessages.isEmpty {
            postNotice(startupMessages.joined(separator: "；"), kind: .warning)
            startupMessages.removeAll()
        }
        await runDueScheduledDownloads()
        await reconnect()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runDueScheduledDownloads()
                if self.hasActiveConnection {
                    await self.applyNightSpeedPolicyIfNeeded()
                    _ = await self.flushPendingDownloads()
                    await self.refresh()
                } else if self.shouldAttemptAutomaticReconnect() {
                    await self.reconnect(force: false)
                }

                try? await Task.sleep(for: .seconds(1.25))
            }
        }

        rssPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshDueRSSSubscriptions()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    var isConnectedToActiveServer: Bool {
        hasActiveConnection
    }

    func testServerConnection(endpoint: String, secret: String) async throws -> String {
        guard let endpointURL = AppPreferences.normalizedEndpointURL(endpoint) else {
            throw Aria2ClientError.invalidEndpoint
        }
        let probe = Aria2RPCClient()
        await probe.configure(endpoint: endpointURL, secret: secret)
        return try await probe.version().version
    }

    func switchServer(to profileID: UUID) async {
        guard preferences.serverProfiles.contains(where: { $0.id == profileID }) else {
            return
        }
        guard profileID != preferences.activeServerProfileID else {
            if !hasActiveConnection {
                await reconnect()
            }
            return
        }

        preferences.activateServerProfile(id: profileID)
        connectionState = .connecting
        connectedProfileID = nil
        connectedEndpoint = nil
        selectedTransferGID = nil
        transfers = []
        globalStats = .zero
        speedSeries = SpeedSampleSeries()
        speedSamples = []
        queuePositions = [:]
        knownStatuses = [:]
        hasStatusBaseline = false
        daemonSessionID = nil
        serverRPCMethods = []
        serverRPCNotifications = []
        eventStreamState = .disabled
        await eventClient.disconnect()
        dockProgressController.clear()
        refreshPowerAssertion()
        await reconnect()
    }

    func reconnect(force: Bool = true) async {
        guard !isReconnecting else { return }
        if !force, let nextReconnectAt, nextReconnectAt > Date() {
            return
        }

        isReconnecting = true
        defer { isReconnecting = false }
        await eventClient.disconnect()
        eventStreamState = .disabled
        connectionDiagnosticState = .idle
        guard let endpoint = preferences.endpointURL else {
            recordConnectionFailure(message: L10n.string("RPC 地址无效"))
            return
        }
        let profileID = preferences.activeServerProfileID
        let rpcSecret = preferences.rpcSecret
        let shouldAutoStartLocalAria2 = preferences.autoStartLocalAria2

        connectionState = .connecting
        connectedProfileID = nil
        connectedEndpoint = nil
        await client.configure(endpoint: endpoint, secret: rpcSecret)

        do {
            let version = try await client.version()
            await finishConnection(
                version: version,
                profileID: profileID,
                endpoint: endpoint
            )
            return
        } catch {
            guard shouldAutoStartLocalAria2 else {
                recordConnectionFailure(error)
                return
            }
        }

        do {
            let aria2Configuration = try preferences.validatedAria2Configuration()
            try processManager.start(
                endpoint: endpoint,
                secret: rpcSecret,
                configuration: aria2Configuration
            )
        } catch {
            recordConnectionFailure(error)
            return
        }

        var lastError: Error?
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(250))
            do {
                let version = try await client.version()
                await finishConnection(
                    version: version,
                    profileID: profileID,
                    endpoint: endpoint
                )
                return
            } catch {
                lastError = error
            }
        }

        recordConnectionFailure(
            message: lastError?.localizedDescription ?? L10n.string("aria2 没有响应")
        )
    }

    func runConnectionDiagnostics() async {
        guard let endpoint = preferences.endpointURL else {
            connectionDiagnosticState = .failed(message: L10n.string("RPC 地址无效"))
            return
        }

        connectionDiagnosticState = .running
        let diagnosticClient = Aria2RPCClient()
        await diagnosticClient.configure(endpoint: endpoint, secret: preferences.rpcSecret)
        let startedAt = Date()

        do {
            async let versionRequest = diagnosticClient.version()
            async let statsRequest = diagnosticClient.globalStats()
            async let methodsRequest = try? diagnosticClient.rpcMethods()
            async let notificationsRequest = try? diagnosticClient.rpcNotifications()
            async let sessionRequest = try? diagnosticClient.sessionInfo()
            let (version, stats, methods, notifications, sessionInfo) = try await (
                versionRequest,
                statsRequest,
                methodsRequest,
                notificationsRequest,
                sessionRequest
            )
            let elapsed = max(
                Int(Date().timeIntervalSince(startedAt) * 1_000),
                0
            )
            serverRPCMethods = methods ?? []
            serverRPCNotifications = notifications ?? []
            daemonSessionID = sessionInfo?.sessionId
            connectionDiagnosticState = .succeeded(
                ConnectionDiagnosticReport(
                    generatedAt: Date(),
                    profileName: preferences.activeServerProfileName,
                    endpoint: ConnectionDiagnosticReport.sanitizedEndpoint(endpoint),
                    aria2Version: version.version,
                    enabledFeatures: version.enabledFeatures ?? [],
                    elapsedMilliseconds: elapsed,
                    activeCount: stats.activeCount,
                    waitingCount: stats.waitingCount,
                    rpcMethodCount: methods?.count ?? 0,
                    notificationMethods: notifications ?? [],
                    sessionID: sessionInfo?.sessionId
                )
            )
        } catch {
            connectionDiagnosticState = .failed(message: error.localizedDescription)
        }
    }

    func refreshDaemonSessionInfo() async {
        guard hasActiveConnection else {
            postNotice(L10n.string("aria2 尚未连接"), kind: .error)
            return
        }
        do {
            daemonSessionID = try await client.sessionInfo().sessionId
        } catch {
            postNotice(error.localizedDescription, kind: .error)
        }
    }

    func saveDaemonSession() async {
        await perform(successMessage: L10n.string("aria2 会话已保存")) {
            try await client.saveSession()
        }
    }

    func shutdownDaemon(force: Bool) async {
        guard hasActiveConnection else {
            postNotice(L10n.string("aria2 尚未连接"), kind: .error)
            return
        }
        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await client.shutdown(force: force)
            await eventClient.disconnect()
            eventStreamState = .disabled
            connectionState = .idle
            connectedProfileID = nil
            connectedEndpoint = nil
            transfers = []
            globalStats = .zero
            daemonSessionID = nil
            postNotice(force ? L10n.string("已强制关闭 aria2") : L10n.string("已关闭 aria2"), kind: .success)
        } catch {
            postNotice(error.localizedDescription, kind: .error)
        }
    }

    func refresh() async {
        guard hasActiveConnection, !isRefreshing else { return }
        guard connectedProfileID == preferences.activeServerProfileID,
              connectedEndpoint == preferences.endpointURL else {
            connectionState = .idle
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let activeRequest = client.activeTransfers()
            async let waitingRequest = client.waitingTransfers()
            async let stoppedRequest = client.stoppedTransfers()
            async let statsRequest = client.globalStats()
            let (active, waiting, stopped, stats) = try await (
                activeRequest,
                waitingRequest,
                stoppedRequest,
                statsRequest
            )

            var unique: [String: TransferItem] = [:]
            for item in active + waiting + stopped where item.status != .removed {
                unique[item.gid] = item
            }

            queuePositions = Dictionary(
                uniqueKeysWithValues: waiting.enumerated().map { ($0.element.gid, $0.offset) }
            )

            let nextTransfers = unique.values.sorted {
                if $0.sortRank != $1.sortRank {
                    return $0.sortRank < $1.sortRank
                }
                if let firstPosition = queuePositions[$0.gid],
                   let secondPosition = queuePositions[$1.gid],
                   firstPosition != secondPosition {
                    return firstPosition < secondPosition
                }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }

            recordSpeedSample(stats)
            recordHistory(from: nextTransfers)
            organizationStore.reconcile(
                transfers: nextTransfers,
                historyEntries: historyEntries,
                profileID: preferences.activeServerProfileID,
                excludingGIDs: Set(pendingImport?.gids ?? [])
            )
            await handleTransferTransitions(nextTransfers)
            transfers = nextTransfers
            globalStats = stats
            dockProgressController.update(with: nextTransfers)
            refreshPowerAssertion()
            resetConnectionBackoff()
        } catch {
            recordConnectionFailure(error)
            isPreventingSystemSleep = powerAssertionController.update(
                enabled: false,
                transfers: []
            )
        }
    }

    @discardableResult
    func addDownloads(_ urls: [String]) async -> Bool {
        let taskOptions = DownloadTaskOptions.defaults(
            directory: preferences.downloadDirectory,
            split: preferences.split,
            maxConnectionPerServer: preferences.maxConnectionPerServer
        )
        return await addDownloads(urls, taskOptions: taskOptions)
    }

    @discardableResult
    func addDownloads(
        _ urls: [String],
        taskOptions: DownloadTaskOptions
    ) async -> Bool {
        guard !urls.isEmpty else { return false }
        if let validationMessage = taskOptions.validationMessage(forURLCount: urls.count) {
            postNotice(validationMessage, kind: .warning)
            return false
        }

        let requests = urls.map {
            PendingDownload(
                url: $0,
                taskOptions: taskOptions,
                targetProfileID: preferences.activeServerProfileID,
                targetProfileName: preferences.activeServerProfileName
            )
        }
        let previousArchive = pendingDownloadArchive
        var addedIDs: Set<UUID> = []
        for request in requests where pendingDownloadArchive.add(request) {
            addedIDs.insert(request.id)
        }
        guard addedIDs.count == requests.count else {
            pendingDownloadArchive = previousArchive
            postNotice(L10n.string("待发送队列已满，无法保存更多任务"), kind: .error)
            return false
        }
        guard persistPendingDownloads() else {
            pendingDownloadArchive = previousArchive
            pendingDownloads = previousArchive.entries
            return false
        }

        if !hasActiveConnection {
            await reconnect()
        }
        guard hasActiveConnection else {
            postNotice(
                requests.count == 1
                    ? L10n.string("已保存到待发送队列，连接恢复后自动发送")
                    : L10n.string("已保存 \(requests.count) 个待发送任务，连接恢复后自动发送"),
                kind: .success
            )
            return true
        }
        if isFlushingPendingDownloads {
            postNotice(
                L10n.string("任务已保存到待发送队列，将在当前发送完成后继续"),
                kind: .success
            )
            return true
        }

        let result = await flushPendingDownloads(ids: addedIDs, force: true)
        if result.failedCount == 0 {
            postNotice(
                result.submittedCount == 1
                    ? L10n.string("已添加下载")
                    : L10n.string("已添加 \(result.submittedCount) 个下载"),
                kind: .success
            )
        } else if result.submittedCount > 0 {
            postNotice(
                L10n.string("已添加 \(result.submittedCount) 个，另有 \(result.failedCount) 个保留在待发送队列"),
                kind: .warning
            )
        } else {
            postNotice(
                L10n.string("任务已保留在待发送队列，可查看失败原因后重试"),
                kind: .warning
            )
        }
        return true
    }

    @discardableResult
    func scheduleDownloads(
        _ urls: [String],
        taskOptions: DownloadTaskOptions,
        at scheduledAt: Date,
        frequency: ScheduleFrequency = .once
    ) -> Bool {
        guard !urls.isEmpty else { return false }
        if let validationMessage = taskOptions.validationMessage(forURLCount: urls.count) {
            postNotice(validationMessage, kind: .warning)
            return false
        }
        guard scheduledAt > Date().addingTimeInterval(30) else {
            postNotice(L10n.string("计划时间需要晚于当前时间"), kind: .warning)
            return false
        }

        let entry = ScheduledDownload(
            urls: urls,
            taskOptions: taskOptions,
            scheduledAt: scheduledAt,
            frequency: frequency,
            targetProfileID: preferences.activeServerProfileID,
            targetProfileName: preferences.activeServerProfileName
        )
        guard scheduleArchive.add(entry) else { return false }
        guard persistSchedule() else {
            _ = scheduleArchive.remove(id: entry.id)
            scheduledDownloads = scheduleArchive.entries
            return false
        }
        postNotice(
            L10n.string("已安排在 \(Self.scheduleDateFormatter.string(from: scheduledAt)) 开始"),
            kind: .success
        )
        return true
    }

    @discardableResult
    func updateScheduledDownload(
        id: UUID,
        urls: [String],
        taskOptions: DownloadTaskOptions,
        scheduledAt: Date,
        frequency: ScheduleFrequency = .once
    ) -> Bool {
        guard let previous = scheduleArchive.entry(id: id), !urls.isEmpty else {
            return false
        }
        if let validationMessage = taskOptions.validationMessage(forURLCount: urls.count) {
            postNotice(validationMessage, kind: .warning)
            return false
        }
        guard scheduledAt > Date().addingTimeInterval(30) else {
            postNotice(L10n.string("计划时间需要晚于当前时间"), kind: .warning)
            return false
        }

        let updated = ScheduledDownload(
            id: previous.id,
            urls: urls,
            taskOptions: taskOptions,
            scheduledAt: scheduledAt,
            frequency: frequency,
            createdAt: previous.createdAt,
            targetProfileID: previous.targetProfileID,
            targetProfileName: previous.targetProfileName,
            submissionGIDs: previous.urls == urls ? previous.submissionGIDs : nil
        )
        guard scheduleArchive.update(updated), persistSchedule() else {
            _ = scheduleArchive.update(previous)
            scheduledDownloads = scheduleArchive.entries
            return false
        }
        postNotice(L10n.string("已更新「\(updated.displayName)」"), kind: .success)
        return true
    }

    func duplicateScheduledDownload(id: UUID) {
        guard let source = scheduleArchive.entry(id: id) else { return }
        let baseline = max(source.scheduledAt, Date())
        let nextDate = baseline.addingTimeInterval(3_600)
        guard let copy = scheduleArchive.duplicate(id: id, scheduledAt: nextDate) else {
            return
        }
        guard persistSchedule() else {
            _ = scheduleArchive.remove(id: copy.id)
            scheduledDownloads = scheduleArchive.entries
            return
        }
        postNotice(
            L10n.string("已复制任务，并安排在 \(Self.scheduleDateFormatter.string(from: nextDate))"),
            kind: .success
        )
    }

    func startScheduledDownloadNow(id: UUID) async {
        let shouldAdvanceRecurringSchedule =
            scheduleArchive.entry(id: id)?.isOverdue() == true
        guard await moveScheduledDownloadToPending(
            id: id,
            advanceRecurringSchedule: shouldAdvanceRecurringSchedule
        ) else { return }
        if isFlushingPendingDownloads {
            postNotice(L10n.string("计划任务已转入待发送队列"), kind: .success)
            return
        }
        if !hasActiveConnection {
            await reconnect()
        }
        if hasActiveConnection {
            let result = await flushPendingDownloads(
                originScheduleID: id,
                force: true
            )
            if result.failedCount == 0, result.submittedCount > 0 {
                postNotice(L10n.string("计划任务已开始"), kind: .success)
            } else if result.failedCount > 0 {
                postNotice(L10n.string("计划任务已转入待发送队列"), kind: .warning)
            }
        } else {
            postNotice(L10n.string("计划任务已转入待发送队列"), kind: .success)
        }
    }

    func cancelScheduledDownload(id: UUID) {
        guard let entry = scheduleArchive.entry(id: id),
              scheduleArchive.remove(id: id) else {
            return
        }
        guard persistSchedule() else {
            _ = scheduleArchive.add(entry)
            scheduledDownloads = scheduleArchive.entries
            return
        }
        postNotice(L10n.string("已取消计划任务"), kind: .success)
    }

    @discardableResult
    func addRSSSubscription(
        title: String,
        feedURL: String,
        refreshInterval: RSSRefreshInterval,
        autoDownloadNewItems: Bool,
        downloadDirectory: String,
        targetProfileID: UUID?
    ) -> UUID? {
        guard let normalizedURL = Self.normalizedRSSURL(feedURL) else {
            postNotice(L10n.string("请输入有效的 HTTP 或 HTTPS RSS 地址"), kind: .warning)
            return nil
        }
        let targetProfile = preferences.serverProfiles.first {
            $0.id == targetProfileID
        } ?? preferences.activeServerProfile
        let taskOptions = DownloadTaskOptions.defaults(
            directory: downloadDirectory.trimmed.isEmpty
                ? preferences.downloadDirectory
                : downloadDirectory.trimmed,
            split: preferences.split,
            maxConnectionPerServer: preferences.maxConnectionPerServer
        )
        let subscription = RSSSubscription(
            title: title,
            feedURL: normalizedURL.absoluteString,
            autoDownloadNewItems: autoDownloadNewItems,
            refreshInterval: refreshInterval,
            taskOptions: taskOptions,
            targetProfileID: targetProfile?.id,
            targetProfileName: targetProfile?.displayName
        )
        guard rssSubscriptionArchive.add(subscription) else {
            postNotice(L10n.string("这个 RSS 地址已经订阅，或订阅数量已达到上限"), kind: .warning)
            return nil
        }
        guard persistRSSSubscriptions() else {
            _ = rssSubscriptionArchive.remove(id: subscription.id)
            rssSubscriptions = rssSubscriptionArchive.entries
            return nil
        }
        postNotice(L10n.string("已添加 RSS 订阅"), kind: .success)
        return subscription.id
    }

    @discardableResult
    func updateRSSSubscription(
        id: UUID,
        title: String,
        feedURL: String,
        refreshInterval: RSSRefreshInterval,
        autoDownloadNewItems: Bool,
        downloadDirectory: String,
        targetProfileID: UUID?
    ) -> Bool {
        guard let previous = rssSubscriptionArchive.entry(id: id),
              let normalizedURL = Self.normalizedRSSURL(feedURL) else {
            postNotice(L10n.string("请输入有效的 HTTP 或 HTTPS RSS 地址"), kind: .warning)
            return false
        }
        let targetProfile = preferences.serverProfiles.first {
            $0.id == targetProfileID
        } ?? preferences.activeServerProfile
        var updated = previous
        updated.title = title
        updated.feedURL = normalizedURL.absoluteString
        updated.refreshInterval = refreshInterval
        updated.autoDownloadNewItems = autoDownloadNewItems
        updated.taskOptions.directory = downloadDirectory.trimmed.isEmpty
            ? preferences.downloadDirectory
            : downloadDirectory.trimmed
        updated.targetProfileID = targetProfile?.id
        updated.targetProfileName = targetProfile?.displayName
        if updated.feedURL != previous.feedURL {
            updated.lastCheckedAt = nil
            updated.lastSuccessfulRefreshAt = nil
            updated.lastError = nil
            updated.items = []
            updated.seenItemIDs = []
            updated.hasCompletedInitialSync = false
        }

        guard rssSubscriptionArchive.update(updated), persistRSSSubscriptions() else {
            _ = rssSubscriptionArchive.update(previous)
            rssSubscriptions = rssSubscriptionArchive.entries
            postNotice(L10n.string("这个 RSS 地址已经被其他订阅使用"), kind: .warning)
            return false
        }
        postNotice(L10n.string("已更新「\(updated.displayName)」"), kind: .success)
        return true
    }

    func setRSSSubscriptionEnabled(id: UUID, isEnabled: Bool) {
        guard var subscription = rssSubscriptionArchive.entry(id: id) else {
            return
        }
        let previous = subscription
        subscription.isEnabled = isEnabled
        guard rssSubscriptionArchive.update(subscription), persistRSSSubscriptions() else {
            _ = rssSubscriptionArchive.update(previous)
            rssSubscriptions = rssSubscriptionArchive.entries
            return
        }
    }

    func removeRSSSubscription(id: UUID) {
        guard let subscription = rssSubscriptionArchive.entry(id: id),
              rssSubscriptionArchive.remove(id: id) else {
            return
        }
        guard persistRSSSubscriptions() else {
            _ = rssSubscriptionArchive.add(subscription)
            rssSubscriptions = rssSubscriptionArchive.entries
            return
        }
        postNotice(L10n.string("已移除 RSS 订阅"), kind: .success)
    }

    func refreshAllRSSSubscriptions() async {
        let ids = rssSubscriptionArchive.entries.map(\.id)
        guard !ids.isEmpty else { return }
        for id in ids {
            await refreshRSSSubscription(id: id, userInitiated: true)
        }
    }

    func refreshRSSSubscription(
        id: UUID,
        userInitiated: Bool = true
    ) async {
        guard !refreshingRSSSubscriptionIDs.contains(id),
              var subscription = rssSubscriptionArchive.entry(id: id),
              let url = URL(string: subscription.feedURL) else {
            return
        }

        refreshingRSSSubscriptionIDs.insert(id)
        defer { refreshingRSSSubscriptionIDs.remove(id) }

        let checkedAt = Date()
        do {
            let parsedFeed = try await RSSFeedService.fetch(from: url)
            let knownIDs = Set(subscription.seenItemIDs)
            let newItems = parsedFeed.items.filter { !knownIDs.contains($0.id) }
            let shouldAutoDownload = subscription.hasCompletedInitialSync
                && subscription.autoDownloadNewItems
            let downloadURLs = shouldAutoDownload
                ? newItems.compactMap(\.downloadURL)
                : []

            if subscription.title.trimmed.isEmpty,
               !parsedFeed.title.trimmed.isEmpty {
                subscription.title = parsedFeed.title
            }
            subscription.items = Array(parsedFeed.items.prefix(50))
            var uniqueItemIDs: Set<String> = []
            subscription.seenItemIDs = Array(
                (parsedFeed.items.map(\.id) + subscription.seenItemIDs)
                    .filter { uniqueItemIDs.insert($0).inserted }
                    .prefix(500)
            )
            subscription.hasCompletedInitialSync = true
            subscription.lastCheckedAt = checkedAt
            subscription.lastSuccessfulRefreshAt = checkedAt
            subscription.lastError = nil

            guard rssSubscriptionArchive.update(subscription),
                  persistRSSSubscriptions() else {
                return
            }

            let queuedCount = await enqueueRSSDownloads(
                downloadURLs,
                subscription: subscription
            )
            if userInitiated {
                if queuedCount > 0 {
                    postNotice(
                        L10n.string("「\(subscription.displayName)」发现并加入 \(queuedCount) 个新下载"),
                        kind: .success
                    )
                } else {
                    postNotice(L10n.string("「\(subscription.displayName)」已刷新"), kind: .success)
                }
            } else if queuedCount > 0 {
                postNotice(
                    L10n.string("RSS「\(subscription.displayName)」已加入 \(queuedCount) 个新下载"),
                    kind: .success
                )
            }
        } catch {
            subscription.lastCheckedAt = checkedAt
            subscription.lastError = error.localizedDescription
            _ = rssSubscriptionArchive.update(subscription)
            _ = persistRSSSubscriptions()
            if userInitiated {
                postNotice(
                    L10n.string("RSS 刷新失败：\(error.localizedDescription)"),
                    kind: .error
                )
            }
        }
    }

    func downloadRSSItem(subscriptionID: UUID, itemID: String) async {
        guard let subscription = rssSubscriptionArchive.entry(id: subscriptionID),
              let item = subscription.items.first(where: { $0.id == itemID }),
              let url = item.downloadURL else {
            postNotice(L10n.string("这个 RSS 条目没有可下载的附件"), kind: .warning)
            return
        }
        let count = await enqueueRSSDownloads([url], subscription: subscription)
        if count > 0 {
            postNotice(L10n.string("已加入「\(item.displayTitle)」"), kind: .success)
        }
    }

    func retryPendingDownload(id: UUID) async {
        guard var entry = pendingDownloadArchive.entry(id: id) else { return }
        guard !isFlushingPendingDownloads else {
            postNotice(L10n.string("待发送队列正在处理，请稍候"), kind: .warning)
            return
        }
        guard entry.isForProfile(preferences.activeServerProfileID) else {
            postNotice(
                L10n.string("请先切换到「\(entry.serverDisplayName)」，或将任务改发到当前服务器"),
                kind: .warning
            )
            return
        }

        let previousEntry = entry
        entry.prepareForManualRetry()
        _ = pendingDownloadArchive.update(entry)
        guard persistPendingDownloads() else {
            _ = pendingDownloadArchive.update(previousEntry)
            pendingDownloads = pendingDownloadArchive.entries
            return
        }

        if !hasActiveConnection {
            await reconnect()
        }
        guard hasActiveConnection else {
            postNotice(L10n.string("连接尚未恢复，任务会继续保留"), kind: .warning)
            return
        }

        let result = await flushPendingDownloads(ids: [id], force: true)
        if result.submittedCount == 1 {
            postNotice(L10n.string("已发送「\(entry.displayName)」"), kind: .success)
        } else {
            postNotice(L10n.string("发送失败，任务仍保留在待发送队列"), kind: .error)
        }
    }

    func retryAllPendingDownloads() async {
        guard !isFlushingPendingDownloads else {
            postNotice(L10n.string("待发送队列正在处理，请稍候"), kind: .warning)
            return
        }
        let matchingEntries = pendingDownloadArchive.entries.filter {
            $0.isForProfile(preferences.activeServerProfileID)
        }
        guard !matchingEntries.isEmpty else {
            postNotice(L10n.string("当前服务器没有待发送任务"), kind: .warning)
            return
        }

        let previousArchive = pendingDownloadArchive
        for var entry in matchingEntries {
            entry.prepareForManualRetry()
            _ = pendingDownloadArchive.update(entry)
        }
        guard persistPendingDownloads() else {
            pendingDownloadArchive = previousArchive
            pendingDownloads = previousArchive.entries
            return
        }

        if !hasActiveConnection {
            await reconnect()
        }
        guard hasActiveConnection else {
            postNotice(L10n.string("连接尚未恢复，任务会继续保留"), kind: .warning)
            return
        }

        let result = await flushPendingDownloads(
            ids: Set(matchingEntries.map(\.id)),
            force: true
        )
        if result.failedCount == 0 {
            postNotice(L10n.string("已发送 \(result.submittedCount) 个任务"), kind: .success)
        } else if result.submittedCount > 0 {
            postNotice(
                L10n.string("已发送 \(result.submittedCount) 个，另有 \(result.failedCount) 个失败"),
                kind: .warning
            )
        } else {
            postNotice(L10n.string("待发送任务仍未能提交"), kind: .error)
        }
    }

    func cancelPendingDownload(id: UUID) {
        guard let entry = pendingDownloadArchive.entry(id: id),
              pendingDownloadArchive.remove(id: id) else {
            return
        }
        guard persistPendingDownloads() else {
            _ = pendingDownloadArchive.add(entry)
            pendingDownloads = pendingDownloadArchive.entries
            return
        }
        postNotice(L10n.string("已取消待发送任务"), kind: .success)
    }

    func retargetPendingDownloadToActiveServer(id: UUID) async {
        guard var entry = pendingDownloadArchive.entry(id: id) else { return }
        guard !isFlushingPendingDownloads else {
            postNotice(L10n.string("待发送队列正在处理，请稍候"), kind: .warning)
            return
        }
        let previousEntry = entry
        entry.retarget(
            profileID: preferences.activeServerProfileID,
            profileName: preferences.activeServerProfileName
        )
        guard pendingDownloadArchive.update(entry), persistPendingDownloads() else {
            _ = pendingDownloadArchive.update(previousEntry)
            pendingDownloads = pendingDownloadArchive.entries
            return
        }
        await retryPendingDownload(id: id)
    }

    func pause(_ item: TransferItem) async {
        await perform(successMessage: L10n.string("已暂停「\(item.displayName)」")) {
            try await client.pause(gid: item.gid)
        }
    }

    func pause(_ items: [TransferItem]) async {
        let candidates = items.filter(\.isPausable)
        await performGIDMulticall(
            method: "aria2.pause",
            actionName: L10n.string("暂停"),
            emptyMessage: L10n.string("所选任务中没有可暂停的项目"),
            items: candidates
        )
    }

    func forcePause(_ item: TransferItem) async {
        await perform(successMessage: L10n.string("已强制暂停「\(item.displayName)」")) {
            try await client.forcePause(gid: item.gid)
        }
    }

    func forcePause(_ items: [TransferItem]) async {
        let candidates = items.filter(\.isPausable)
        await performGIDMulticall(
            method: "aria2.forcePause",
            actionName: L10n.string("强制暂停"),
            emptyMessage: L10n.string("所选任务中没有可强制暂停的项目"),
            items: candidates
        )
    }

    func resume(_ item: TransferItem) async {
        await perform(successMessage: L10n.string("已继续「\(item.displayName)」")) {
            try await client.resume(gid: item.gid)
        }
    }

    func resume(_ items: [TransferItem]) async {
        let candidates = items.filter(\.isResumable)
        await performGIDMulticall(
            method: "aria2.unpause",
            actionName: L10n.string("继续"),
            emptyMessage: L10n.string("所选任务中没有可继续的项目"),
            items: candidates
        )
    }

    func retry(_ item: TransferItem) async {
        await retry([item])
    }

    func retry(_ items: [TransferItem]) async {
        let candidates = items.filter(\.isRetryable)
        guard !candidates.isEmpty else {
            postNotice(L10n.string("所选任务中没有可重试的项目"), kind: .warning)
            return
        }
        if !hasActiveConnection {
            await reconnect()
        }
        guard hasActiveConnection else {
            let queuedCount = enqueueOfflineRetries(candidates)
            if queuedCount > 0 {
                postNotice(
                    L10n.string("连接尚未恢复，已将 \(queuedCount) 个重试任务保存到待发送队列"),
                    kind: .warning
                )
            } else {
                postNotice(L10n.string("aria2 尚未连接"), kind: .error)
            }
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        var succeeded = 0
        var failures: [String] = []
        for item in candidates {
            do {
                selectedTransferGID = try await retryTransfer(item)
                succeeded += 1
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        await refresh()

        if failures.isEmpty {
            postNotice(
                succeeded == 1
                    ? L10n.string("已重新添加「\(candidates[0].displayName)」")
                    : L10n.string("已重试 \(succeeded) 个任务"),
                kind: .success
            )
        } else if succeeded > 0 {
            postNotice(
                L10n.string("已重试 \(succeeded) 个，另有 \(failures.count) 个失败"),
                kind: .warning
            )
        } else {
            postNotice(failures.first ?? L10n.string("重试失败"), kind: .error)
        }
    }

    func remove(_ item: TransferItem) async {
        await perform(successMessage: L10n.string("已移除「\(item.displayName)」")) {
            try await self.removeFromAria2(item)
        }
    }

    func remove(_ items: [TransferItem]) async {
        await performBatch(
            actionName: L10n.string("移除"),
            emptyMessage: L10n.string("没有选择可移除的任务"),
            items: items
        ) { item in
            try await self.removeFromAria2(item)
        }
    }

    func pauseAll() async {
        await perform(successMessage: L10n.string("已暂停全部下载")) {
            try await client.pauseAll()
        }
    }

    func forcePauseAll() async {
        await perform(successMessage: L10n.string("已强制暂停全部下载")) {
            try await client.forcePauseAll()
        }
    }

    func resumeAll() async {
        await perform(successMessage: L10n.string("已继续全部下载")) {
            try await client.resumeAll()
        }
    }

    func prepareNotifications(enabled: Bool) async {
        notificationPermissionState = enabled ? .requesting : .disabled
        guard enabled else { return }
        notificationPermissionState = await notificationService.prepare(enabled: enabled)
    }

    func sendTestNotification() async {
        guard notificationPermissionState == .allowed else {
            postNotice(L10n.string("请先允许 macOS 通知"), kind: .warning)
            return
        }

        if await notificationService.sendTestNotification() {
            postNotice(L10n.string("测试通知已发送"), kind: .success)
        } else {
            postNotice(L10n.string("系统未接受测试通知"), kind: .error)
        }
    }

    func importDownloadFile(at url: URL) async {
        await importDownloadFiles(at: [url])
    }

    func importDownloadFiles(at urls: [URL]) async {
        let supportedURLs = urls.filter { DownloadImportKind(url: $0) != nil }
        guard !supportedURLs.isEmpty else {
            postNotice(L10n.string("请选择 .torrent、.metalink 或 .meta4 文件"), kind: .warning)
            return
        }

        var knownURLs = Set(importQueue.map(\.standardizedFileURL))
        if let pendingImport {
            knownURLs.insert(pendingImport.sourceURL.standardizedFileURL)
        }
        for url in supportedURLs {
            let normalized = url.standardizedFileURL
            if knownURLs.insert(normalized).inserted {
                importQueue.append(normalized)
            }
        }
        queuedImportCount = importQueue.count
        if supportedURLs.count > 1 {
            postNotice(L10n.string("已加入 \(supportedURLs.count) 个导入文件，将逐个选择"), kind: .success)
        }
        await processQueuedImports()
    }

    private func processQueuedImports() async {
        guard !isPreparingImport, pendingImport == nil else { return }
        isPreparingImport = true
        defer { isPreparingImport = false }

        while pendingImport == nil, !importQueue.isEmpty {
            let url = importQueue.removeFirst()
            queuedImportCount = importQueue.count
            await prepareDownloadImport(at: url)
        }
    }

    private func prepareDownloadImport(at url: URL) async {
        guard let kind = DownloadImportKind(url: url) else { return }
        if !hasActiveConnection {
            await reconnect()
        }
        guard hasActiveConnection else {
            postNotice(L10n.string("aria2 尚未连接，请检查设置"), kind: .error)
            importQueue.removeAll()
            queuedImportCount = 0
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        var stagedGIDs: [String] = []
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 10 * 1_024 * 1_024 else {
                postNotice(L10n.string("导入文件超过 10 MB，RPC 无法安全发送"), kind: .error)
                return
            }

            let options = [
                "dir": preferences.downloadDirectory,
                "pause": "true"
            ]
            switch kind {
            case .torrent:
                stagedGIDs = [try await client.addTorrent(data: data, options: options)]
            case .metalink:
                stagedGIDs = try await client.addMetalink(data: data, options: options)
            }

            var choices: [ImportedFileChoice] = []
            var importTitle = url.deletingPathExtension().lastPathComponent
            for gid in stagedGIDs {
                let status = try await client.status(gid: gid)
                if importTitle.isEmpty || importTitle == url.deletingPathExtension().lastPathComponent {
                    importTitle = status.displayName
                }
                let files = try await client.files(gid: gid)
                choices += files.enumerated().map { offset, file in
                    ImportedFileChoice(
                        gid: gid,
                        index: Int(file.index ?? "") ?? offset + 1,
                        path: file.path,
                        byteCount: file.byteCount,
                        isSelected: file.selected != "false"
                    )
                }
                knownStatuses[gid] = .paused
            }

            guard !choices.isEmpty else {
                organizationStore.registerImported(
                    draft: PendingDownloadImport(
                        sourceURL: url,
                        kind: kind,
                        title: importTitle,
                        gids: stagedGIDs,
                        files: []
                    ),
                    choices: [],
                    profileID: preferences.activeServerProfileID
                )
                for gid in stagedGIDs {
                    try await client.resume(gid: gid)
                    knownStatuses[gid] = .waiting
                }
                await refresh()
                postNotice(L10n.string("已导入 \(kind.title)"), kind: .success)
                return
            }

            pendingImport = PendingDownloadImport(
                sourceURL: url,
                kind: kind,
                title: importTitle,
                gids: stagedGIDs,
                files: choices
            )
            await refresh()
        } catch {
            await removeStagedDownloads(stagedGIDs)
            postNotice(error.localizedDescription, kind: .error)
        }
    }

    @discardableResult
    func commitPendingImport(
        id: UUID,
        choices: [ImportedFileChoice],
        webSeedURIs: [String] = []
    ) async -> Bool {
        guard let draft = pendingImport, draft.id == id else { return false }
        var selectedChoices = choices.filter(\.isSelected)
        guard !selectedChoices.isEmpty else {
            postNotice(L10n.string("至少选择一个文件"), kind: .warning)
            return false
        }

        let normalizedWebSeeds = Self.uniqueURIs(webSeedURIs)
        for uri in normalizedWebSeeds {
            guard let scheme = URLComponents(string: uri)?.scheme?.lowercased(),
                  ["http", "https", "ftp"].contains(scheme) else {
                postNotice(
                    L10n.string("Web Seed 只支持 HTTP、HTTPS 或 FTP"),
                    kind: .warning
                )
                return false
            }
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        var importedDraft = draft
        var replacementGIDs: [String] = []
        do {
            if draft.kind == .torrent, !normalizedWebSeeds.isEmpty {
                let data = try Data(contentsOf: draft.sourceURL)
                guard data.count <= 10 * 1_024 * 1_024 else {
                    postNotice(
                        L10n.string("导入文件超过 10 MB，RPC 无法安全发送"),
                        kind: .error
                    )
                    return false
                }

                let replacementGID = try await client.addTorrent(
                    data: data,
                    webSeedURIs: normalizedWebSeeds,
                    options: [
                        "dir": preferences.downloadDirectory,
                        "pause": "true"
                    ]
                )
                replacementGIDs = [replacementGID]
                selectedChoices = selectedChoices.map {
                    ImportedFileChoice(
                        gid: replacementGID,
                        index: $0.index,
                        path: $0.path,
                        byteCount: $0.byteCount,
                        isSelected: $0.isSelected
                    )
                }
                importedDraft = PendingDownloadImport(
                    id: draft.id,
                    sourceURL: draft.sourceURL,
                    kind: draft.kind,
                    title: draft.title,
                    gids: replacementGIDs,
                    files: choices.map {
                        ImportedFileChoice(
                            gid: replacementGID,
                            index: $0.index,
                            path: $0.path,
                            byteCount: $0.byteCount,
                            isSelected: $0.isSelected
                        )
                    }
                )
            }

            let grouped = Dictionary(grouping: selectedChoices, by: \.gid)
            for (gid, files) in grouped {
                let selectedIndices = files
                    .map(\.index)
                    .sorted()
                    .map(String.init)
                    .joined(separator: ",")
                try await client.updateTaskOptions(
                    gid: gid,
                    options: ["select-file": selectedIndices]
                )
            }

            for gid in importedDraft.gids {
                if grouped[gid] == nil {
                    await removeStagedDownloads([gid])
                } else {
                    try await client.resume(gid: gid)
                    knownStatuses[gid] = .waiting
                }
            }

            organizationStore.registerImported(
                draft: importedDraft,
                choices: selectedChoices,
                profileID: preferences.activeServerProfileID
            )
            if !replacementGIDs.isEmpty {
                await removeStagedDownloads(draft.gids)
            }
            pendingImport = nil
            await refresh()
            postNotice(L10n.string("已开始「\(draft.title)」"), kind: .success)
            continueQueuedImportsAfterSheetCloses()
            return true
        } catch {
            if !replacementGIDs.isEmpty {
                await removeStagedDownloads(replacementGIDs)
            }
            postNotice(error.localizedDescription, kind: .error)
            return false
        }
    }

    func cancelPendingImport(id: UUID? = nil) async {
        guard let draft = pendingImport else { return }
        if let id, draft.id != id { return }
        pendingImport = nil
        await removeStagedDownloads(draft.gids)
        await refresh()
        continueQueuedImportsAfterSheetCloses()
    }

    func moveQueueItem(_ item: TransferItem, direction: QueueMoveDirection) async {
        guard item.isQueueMovable else { return }

        let position: Int
        let how: String
        switch direction {
        case .top:
            position = 0
            how = "POS_SET"
        case .up:
            position = -1
            how = "POS_CUR"
        case .down:
            position = 1
            how = "POS_CUR"
        case .bottom:
            position = 0
            how = "POS_END"
        }

        do {
            _ = try await client.changePosition(
                gid: item.gid,
                position: position,
                relativeTo: how
            )
            await refresh()
        } catch {
            postNotice(error.localizedDescription, kind: .error)
        }
    }

    func moveQueueItem(gid: String, before target: TransferItem) async {
        guard let item = transfers.first(where: { $0.gid == gid }),
              item.isQueueMovable,
              target.isQueueMovable,
              let sourcePosition = queuePositions[gid],
              let targetPosition = queuePositions[target.gid] else {
            return
        }

        let destination = sourcePosition < targetPosition
            ? max(targetPosition - 1, 0)
            : targetPosition
        guard destination != sourcePosition else { return }

        do {
            _ = try await client.changePosition(
                gid: gid,
                position: destination,
                relativeTo: "POS_SET"
            )
            await refresh()
        } catch {
            postNotice(error.localizedDescription, kind: .error)
        }
    }

    var selectedTransfer: TransferItem? {
        guard let selectedTransferGID else { return nil }
        return transfers.first { $0.gid == selectedTransferGID }
    }

    func moveSelectedTransfer(_ direction: QueueMoveDirection) async {
        guard let selectedTransfer else { return }
        await moveQueueItem(selectedTransfer, direction: direction)
    }

    func applyAria2Settings(showNotice: Bool = true) async {
        settingsApplyState = .applying
        if !hasActiveConnection {
            await reconnect()
        }

        guard hasActiveConnection else {
            let message = connectionState.detail ?? L10n.string("aria2 尚未连接")
            settingsApplyState = .failed(message: message)
            if showNotice {
                postNotice(message, kind: .error)
            }
            return
        }

        do {
            let policy = currentSpeedPolicy()
            try await client.updateGlobalOptions(
                try effectiveGlobalOptions(policy: policy)
            )
            appliedSpeedPolicy = policy
            settingsApplyState = .applied
            settingsStateTask?.cancel()
            settingsStateTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                self?.settingsApplyState = .idle
            }
            if showNotice {
                postNotice(L10n.string("aria2 设置已应用"), kind: .success)
            }
            await refresh()
        } catch {
            settingsApplyState = .failed(message: error.localizedDescription)
            if showNotice {
                postNotice(error.localizedDescription, kind: .error)
            }
        }
    }

    func setQuickDownloadLimit(_ kibibytesPerSecond: Int) async {
        preferences.maxOverallDownloadLimitKiB = max(kibibytesPerSecond, 0)
        await applyAria2Settings()
    }

    func taskSpeedLimits(for item: TransferItem) async -> TaskSpeedLimits? {
        if !hasActiveConnection {
            await reconnect()
        }
        guard hasActiveConnection else {
            postNotice(L10n.string("aria2 尚未连接"), kind: .error)
            return nil
        }

        do {
            let options = try await client.taskOptions(gid: item.gid)
            return TaskSpeedLimits(options: options)
        } catch {
            postNotice(error.localizedDescription, kind: .error)
            return nil
        }
    }

    func advancedDetails(for item: TransferItem) async -> TransferAdvancedDetails {
        if !hasActiveConnection {
            await reconnect()
        }
        guard hasActiveConnection else {
            return TransferAdvancedDetails(item: item, peers: [], serverGroups: [])
        }

        async let refreshedItem = try? client.status(gid: item.gid)
        async let peers = item.isBitTorrent
            ? (try? client.peers(gid: item.gid))
            : []
        async let serverGroups = try? client.servers(gid: item.gid)
        async let files = try? client.files(gid: item.gid)
        async let uris = try? client.uris(gid: item.gid)
        async let options = try? client.taskOptions(gid: item.gid)

        let results = await (
            refreshedItem,
            peers,
            serverGroups,
            files,
            uris,
            options
        )
        return TransferAdvancedDetails(
            item: results.0 ?? item,
            peers: results.1 ?? [],
            serverGroups: results.2 ?? [],
            files: results.3 ?? item.files ?? [],
            uris: results.4 ?? [],
            options: results.5 ?? [:]
        )
    }

    @discardableResult
    func setTaskSpeedLimits(_ limits: TaskSpeedLimits, for item: TransferItem) async -> Bool {
        if !hasActiveConnection {
            await reconnect()
        }
        guard hasActiveConnection else {
            postNotice(L10n.string("aria2 尚未连接"), kind: .error)
            return false
        }

        do {
            try await client.updateTaskOptions(
                gid: item.gid,
                options: limits.optionValues
            )
            postNotice(L10n.string("已更新「\(item.displayName)」的限速"), kind: .success)
            await refresh()
            return true
        } catch {
            postNotice(error.localizedDescription, kind: .error)
            return false
        }
    }

    func setTaskDownloadLimit(
        _ kibibytesPerSecond: Int,
        for items: [TransferItem]
    ) async {
        let candidates = items.filter {
            $0.status == .active || $0.status == .waiting || $0.status == .paused
        }
        await performBatch(
            actionName: L10n.string("更新限速"),
            emptyMessage: L10n.string("所选任务中没有可设置限速的当前任务"),
            items: candidates
        ) { item in
            try await self.client.updateTaskOptions(
                gid: item.gid,
                options: [
                    "max-download-limit":
                        Aria2Configuration.speedOption(kibibytesPerSecond)
                ]
            )
        }
    }

    @discardableResult
    func setSelectedFiles(
        _ indices: Set<Int>,
        for item: TransferItem
    ) async -> Bool {
        guard !indices.isEmpty else {
            postNotice(L10n.string("至少选择一个文件"), kind: .warning)
            return false
        }
        let value = indices.sorted().map(String.init).joined(separator: ",")
        return await updateTask(
            item,
            options: ["select-file": value],
            successMessage: L10n.string("已更新「\(item.displayName)」的文件选择")
        )
    }

    @discardableResult
    func addMirror(
        _ uri: String,
        fileIndex: Int,
        to item: TransferItem
    ) async -> Bool {
        let normalized = uri.trimmed
        guard let scheme = URLComponents(string: normalized)?.scheme?.lowercased(),
              ["http", "https", "ftp", "sftp"].contains(scheme) else {
            postNotice(L10n.string("镜像地址只支持 HTTP、HTTPS、FTP 或 SFTP"), kind: .warning)
            return false
        }
        return await changeTaskURIs(
            item,
            fileIndex: fileIndex,
            removing: [],
            adding: [normalized],
            successMessage: L10n.string("已添加备用镜像")
        )
    }

    @discardableResult
    func removeMirror(
        _ uri: String,
        fileIndex: Int,
        from item: TransferItem
    ) async -> Bool {
        await changeTaskURIs(
            item,
            fileIndex: fileIndex,
            removing: [uri],
            adding: [],
            successMessage: L10n.string("已移除备用镜像")
        )
    }

    @discardableResult
    func applyTaskOptionText(
        _ text: String,
        to item: TransferItem
    ) async -> Bool {
        do {
            let options = try Aria2OptionTextParser.parse(text)
            guard !options.isEmpty else {
                postNotice(L10n.string("请输入至少一个 key=value 参数"), kind: .warning)
                return false
            }
            return await updateTask(
                item,
                options: options,
                successMessage: L10n.string("已更新「\(item.displayName)」的高级参数")
            )
        } catch {
            postNotice(error.localizedDescription, kind: .warning)
            return false
        }
    }

    private func updateTask(
        _ item: TransferItem,
        options: [String: String],
        successMessage: String
    ) async -> Bool {
        if !hasActiveConnection {
            await reconnect()
        }
        guard hasActiveConnection else {
            postNotice(L10n.string("aria2 尚未连接"), kind: .error)
            return false
        }
        do {
            try await client.updateTaskOptions(gid: item.gid, options: options)
            postNotice(successMessage, kind: .success)
            await refresh()
            return true
        } catch {
            postNotice(error.localizedDescription, kind: .error)
            return false
        }
    }

    private func changeTaskURIs(
        _ item: TransferItem,
        fileIndex: Int,
        removing: [String],
        adding: [String],
        successMessage: String
    ) async -> Bool {
        if !hasActiveConnection {
            await reconnect()
        }
        guard hasActiveConnection else {
            postNotice(L10n.string("aria2 尚未连接"), kind: .error)
            return false
        }
        do {
            _ = try await client.changeURIs(
                gid: item.gid,
                fileIndex: fileIndex,
                removing: removing,
                adding: adding
            )
            postNotice(successMessage, kind: .success)
            await refresh()
            return true
        } catch {
            postNotice(error.localizedDescription, kind: .error)
            return false
        }
    }

    func clearCompleted() async {
        let completed = transfers.filter { $0.status == .complete || $0.status == .error }
        guard !completed.isEmpty else {
            postNotice(L10n.string("没有可清理的记录"), kind: .warning)
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await client.purgeDownloadResults()
        } catch {
            postNotice(error.localizedDescription, kind: .error)
            return
        }
        for item in completed {
            organizationStore.removeLiveAttempt(
                gid: item.gid,
                profileID: preferences.activeServerProfileID,
                historyGIDs: retainedHistoryGIDs
            )
        }
        await refresh()
        postNotice(L10n.string("已清理 \(completed.count) 条记录"), kind: .success)
    }

    func removeHistory(ids: Set<String>) {
        let removedCount = removeHistoryRecords(ids: ids)
        guard removedCount > 0 else { return }
        postNotice(L10n.string("已移除 \(removedCount) 条下载历史"), kind: .success)
    }

    func removeHistory(
        ids: Set<String>,
        deletingLocalFiles: Bool
    ) async {
        guard deletingLocalFiles else {
            removeHistory(ids: ids)
            return
        }

        let paths = historyArchive.entries
            .filter { ids.contains($0.id) }
            .flatMap(\.localPathsForRemoval)
        let trashResult = await Self.trashLocalFiles(at: paths)
        let removedCount = removeHistoryRecords(ids: ids)
        guard removedCount > 0 else { return }
        postHistoryRemovalNotice(
            removedCount: removedCount,
            trashResult: trashResult
        )
    }

    func clearHistory() {
        let removedCount = clearHistoryRecords()
        guard removedCount > 0 else {
            postNotice(L10n.string("下载历史已经是空的"), kind: .warning)
            return
        }
        postNotice(L10n.string("已清空 \(removedCount) 条下载历史"), kind: .success)
    }

    func clearHistory(deletingLocalFiles: Bool) async {
        guard deletingLocalFiles else {
            clearHistory()
            return
        }

        let paths = historyArchive.entries.flatMap(\.localPathsForRemoval)
        let trashResult = await Self.trashLocalFiles(at: paths)
        let removedCount = clearHistoryRecords()
        guard removedCount > 0 else {
            postNotice(L10n.string("下载历史已经是空的"), kind: .warning)
            return
        }
        postHistoryRemovalNotice(
            removedCount: removedCount,
            trashResult: trashResult
        )
    }

    @discardableResult
    private func removeHistoryRecords(ids: Set<String>) -> Int {
        let removedCount = historyArchive.remove(ids: ids)
        guard removedCount > 0 else { return 0 }
        persistHistory()
        organizationStore.removeHistory(
            gids: ids,
            remainingHistoryGIDs: retainedHistoryGIDs
        )
        return removedCount
    }

    @discardableResult
    private func clearHistoryRecords() -> Int {
        let removedIDs = Set(historyArchive.entries.map(\.gid))
        let removedCount = historyArchive.removeAll()
        guard removedCount > 0 else { return 0 }
        persistHistory()
        organizationStore.removeHistory(
            gids: removedIDs,
            remainingHistoryGIDs: retainedHistoryGIDs
        )
        return removedCount
    }

    private func postHistoryRemovalNotice(
        removedCount: Int,
        trashResult: LocalFileTrashResult
    ) {
        let unresolvedCount = trashResult.failedCount
            + trashResult.skippedDirectoryCount
        if unresolvedCount > 0 {
            postNotice(
                L10n.string("已移除 \(removedCount) 条历史；")
                    + L10n.string("\(trashResult.trashedCount) 个文件已移到废纸篓，")
                    + L10n.string("\(unresolvedCount) 个未删除"),
                kind: .warning
            )
        } else if trashResult.trashedCount > 0 {
            postNotice(
                L10n.string("已移除 \(removedCount) 条历史，")
                    + L10n.string("\(trashResult.trashedCount) 个文件已移到废纸篓"),
                kind: .success
            )
        } else {
            postNotice(
                L10n.string("已移除 \(removedCount) 条历史；本地文件已不存在"),
                kind: .success
            )
        }
    }

    nonisolated private static func trashLocalFiles(
        at paths: [String]
    ) async -> LocalFileTrashResult {
        let uniquePaths = Set(
            paths
                .map(\.trimmed)
                .filter {
                    !$0.isEmpty
                        && $0 != "—"
                        && NSString(string: $0).isAbsolutePath
                }
        )

        return await Task.detached(priority: .utility) {
            var result = LocalFileTrashResult()
            let fileManager = FileManager.default

            for path in uniquePaths.sorted() {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(
                    atPath: path,
                    isDirectory: &isDirectory
                ) else {
                    result.missingCount += 1
                    continue
                }
                guard !isDirectory.boolValue else {
                    result.skippedDirectoryCount += 1
                    continue
                }

                do {
                    try fileManager.trashItem(
                        at: URL(fileURLWithPath: path),
                        resultingItemURL: nil
                    )
                    result.trashedCount += 1
                } catch {
                    result.failedCount += 1
                }
            }

            return result
        }.value
    }

    func redownload(_ entry: DownloadHistoryEntry) async {
        guard let sourceURI = entry.sourceURI?.trimmed, !sourceURI.isEmpty else {
            postNotice(L10n.string("这条历史没有可用于重新下载的来源地址"), kind: .warning)
            return
        }

        let savedDirectory: String
        if entry.destinationPath == "—" || entry.destinationPath.isEmpty {
            savedDirectory = preferences.downloadDirectory
        } else {
            savedDirectory = URL(fileURLWithPath: entry.destinationPath)
                .deletingLastPathComponent()
                .path
        }
        let taskOptions = DownloadTaskOptions.defaults(
            directory: savedDirectory,
            split: preferences.split,
            maxConnectionPerServer: preferences.maxConnectionPerServer
        )
        _ = await addDownloads([sourceURI], taskOptions: taskOptions)
    }

    func reveal(_ item: TransferItem) {
        let url = URL(fileURLWithPath: item.displayPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func reveal(_ entry: DownloadHistoryEntry) {
        guard entry.destinationPath != "—", !entry.destinationPath.isEmpty else {
            postNotice(L10n.string("这条历史没有可显示的文件位置"), kind: .warning)
            return
        }
        let url = URL(fileURLWithPath: entry.destinationPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func refreshPowerAssertion() {
        isPreventingSystemSleep = powerAssertionController.update(
            enabled: preferences.preventSystemSleepDuringDownloads,
            transfers: transfers
        )
    }

    func shutdown() {
        pollingTask?.cancel()
        pollingTask = nil
        rssPollingTask?.cancel()
        rssPollingTask = nil
        noticeTask?.cancel()
        settingsStateTask?.cancel()
        importContinuationTask?.cancel()
        eventRefreshTask?.cancel()
        importQueue.removeAll()
        queuedImportCount = 0
        processManager.stop()
        dockProgressController.clear()
        powerAssertionController.clear()
        isPreventingSystemSleep = false
        eventStreamState = .disabled
        Task {
            await eventClient.disconnect()
        }
    }

    private func handleTransferTransitions(_ nextTransfers: [TransferItem]) async {
        let nextStatuses = Dictionary(
            uniqueKeysWithValues: nextTransfers.map { ($0.gid, $0.status) }
        )

        if hasStatusBaseline {
            for item in nextTransfers {
                guard let previousStatus = knownStatuses[item.gid],
                      previousStatus != item.status else {
                    continue
                }

                switch item.status {
                case .complete:
                    postNotice(L10n.string("下载完成：\(item.displayName)"), kind: .success)
                    if preferences.notificationsEnabled,
                       notificationPermissionState == .allowed {
                        await notificationService.notifyCompletion(for: item)
                    }
                case .error:
                    let detail = item.userFacingError ?? L10n.string("下载失败")
                    postNotice(
                        L10n.string("下载失败：\(item.displayName) · \(detail)"),
                        kind: .error
                    )
                    if preferences.notificationsEnabled,
                       notificationPermissionState == .allowed {
                        await notificationService.notifyFailure(for: item)
                    }
                default:
                    break
                }
            }
        }

        knownStatuses = nextStatuses
        hasStatusBaseline = true
    }

    private func recordSpeedSample(_ stats: GlobalStats) {
        speedSeries.record(
            downloadBytesPerSecond: stats.downloadSpeedValue,
            uploadBytesPerSecond: stats.uploadSpeedValue
        )
        speedSamples = speedSeries.samples
    }

    private func recordHistory(from transfers: [TransferItem]) {
        var didChange = false
        for item in transfers where item.status == .complete || item.status == .error {
            guard !hasStatusBaseline || knownStatuses[item.gid] != item.status else {
                continue
            }
            didChange = historyArchive.record(item) || didChange
        }
        if didChange {
            persistHistory()
        }
    }

    private func persistHistory() {
        historyEntries = historyArchive.entries
        do {
            try historyRepository.save(historyArchive)
        } catch {
            postNotice(L10n.string("无法保存下载历史：\(error.localizedDescription)"), kind: .warning)
        }
    }

    @discardableResult
    private func persistSchedule() -> Bool {
        scheduledDownloads = scheduleArchive.entries
        do {
            try scheduleRepository.save(scheduleArchive)
            return true
        } catch {
            postNotice(L10n.string("无法保存计划任务：\(error.localizedDescription)"), kind: .warning)
            return false
        }
    }

    @discardableResult
    private func persistRSSSubscriptions() -> Bool {
        rssSubscriptions = rssSubscriptionArchive.entries
        do {
            try rssSubscriptionRepository.save(rssSubscriptionArchive)
            return true
        } catch {
            postNotice(L10n.string("无法保存 RSS 订阅：\(error.localizedDescription)"), kind: .warning)
            return false
        }
    }

    @discardableResult
    private func persistPendingDownloads() -> Bool {
        pendingDownloads = pendingDownloadArchive.entries
        do {
            try pendingDownloadRepository.save(pendingDownloadArchive)
            return true
        } catch {
            postNotice(L10n.string("无法保存待发送任务：\(error.localizedDescription)"), kind: .warning)
            return false
        }
    }

    private func refreshDueRSSSubscriptions(at date: Date = Date()) async {
        let dueIDs = rssSubscriptionArchive.entries
            .filter { $0.isDue(at: date) }
            .map(\.id)
        for id in dueIDs where !Task.isCancelled {
            await refreshRSSSubscription(id: id, userInitiated: false)
        }
    }

    private func enqueueRSSDownloads(
        _ urls: [String],
        subscription: RSSSubscription
    ) async -> Int {
        var uniqueURLs: Set<String> = []
        let normalizedURLs = urls
            .map(\.trimmed)
            .filter { !$0.isEmpty && uniqueURLs.insert($0).inserted }
        guard !normalizedURLs.isEmpty else { return 0 }

        let previousArchive = pendingDownloadArchive
        var addedIDs: Set<UUID> = []
        for url in normalizedURLs {
            let request = PendingDownload(
                url: url,
                taskOptions: subscription.taskOptions,
                targetProfileID: subscription.targetProfileID,
                targetProfileName: subscription.targetProfileName
            )
            if pendingDownloadArchive.add(request) {
                addedIDs.insert(request.id)
            }
        }
        guard !addedIDs.isEmpty else { return 0 }
        guard persistPendingDownloads() else {
            pendingDownloadArchive = previousArchive
            pendingDownloads = previousArchive.entries
            return 0
        }

        if subscription.targetProfileID == preferences.activeServerProfileID,
           hasActiveConnection,
           !isFlushingPendingDownloads {
            _ = await flushPendingDownloads(ids: addedIDs, force: true)
        }
        return addedIDs.count
    }

    private func continueQueuedImportsAfterSheetCloses() {
        guard !importQueue.isEmpty else { return }
        importContinuationTask?.cancel()
        importContinuationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.processQueuedImports()
        }
    }

    private func runDueScheduledDownloads(at date: Date = Date()) async {
        let dueEntries = scheduleArchive.due(at: date)
        for entry in dueEntries where !executingScheduleIDs.contains(entry.id) {
            executingScheduleIDs.insert(entry.id)
            let didMove = await moveScheduledDownloadToPending(
                id: entry.id,
                advanceRecurringSchedule: true,
                at: date
            )
            executingScheduleIDs.remove(entry.id)
            if !didMove {
                break
            }
        }

        if hasActiveConnection {
            _ = await flushPendingDownloads()
        }
    }

    private func moveScheduledDownloadToPending(
        id: UUID,
        advanceRecurringSchedule: Bool,
        at date: Date = Date()
    ) async -> Bool {
        guard var entry = scheduleArchive.entry(id: id) else { return false }
        let previousEntry = entry
        entry.prepareSubmissionGIDs()
        if entry != previousEntry {
            _ = scheduleArchive.update(entry)
            guard persistSchedule() else {
                _ = scheduleArchive.update(previousEntry)
                scheduledDownloads = scheduleArchive.entries
                return false
            }
        }

        let gids = entry.submissionGIDs ?? []
        guard gids.count == entry.urls.count else {
            postNotice(L10n.string("计划任务缺少有效的提交标识"), kind: .error)
            return false
        }

        let previousPendingArchive = pendingDownloadArchive
        var needsPendingSave = false
        let occurrenceID = UUID()
        for (index, pair) in zip(entry.urls, gids).enumerated() {
            let request = PendingDownload(
                url: pair.0,
                taskOptions: entry.taskOptions,
                submissionGID: pair.1,
                targetProfileID: entry.targetProfileID,
                targetProfileName: entry.targetProfileName,
                originScheduleID: entry.id,
                originScheduleIndex: index,
                originScheduleOccurrenceID: occurrenceID,
                createdAt: entry.frequency == .once ? entry.createdAt : date
            )
            if pendingDownloadArchive.add(request) {
                needsPendingSave = true
                continue
            }

            let alreadyQueued = pendingDownloadArchive.entries.contains {
                $0.originScheduleOccurrenceID == occurrenceID
                    && $0.originScheduleIndex == index
            }
            guard alreadyQueued else {
                pendingDownloadArchive = previousPendingArchive
                postNotice(L10n.string("待发送队列已满，计划任务暂未移动"), kind: .error)
                return false
            }
        }

        if needsPendingSave, !persistPendingDownloads() {
            pendingDownloadArchive = previousPendingArchive
            pendingDownloads = previousPendingArchive.entries
            return false
        }

        if entry.frequency != .once {
            var nextEntry = entry
            if advanceRecurringSchedule {
                guard let nextDate = entry.nextScheduledDate(after: date) else {
                    postNotice(L10n.string("无法计算重复计划的下一次时间"), kind: .error)
                    return false
                }
                nextEntry.scheduledAt = nextDate
            }
            nextEntry.submissionGIDs = DownloadSubmissionIdentifier.makeGIDs(
                count: nextEntry.urls.count
            )
            guard scheduleArchive.update(nextEntry) else { return false }
            guard persistSchedule() else {
                _ = scheduleArchive.update(entry)
                scheduledDownloads = scheduleArchive.entries
                pendingDownloadArchive = previousPendingArchive
                _ = persistPendingDownloads()
                return false
            }
            return true
        }

        guard scheduleArchive.remove(id: entry.id) else { return false }
        guard persistSchedule() else {
            _ = scheduleArchive.add(entry)
            scheduledDownloads = scheduleArchive.entries
            return false
        }
        return true
    }

    private func flushPendingDownloads(
        ids: Set<UUID>? = nil,
        originScheduleID: UUID? = nil,
        force: Bool = false,
        at date: Date = Date()
    ) async -> PendingFlushResult {
        guard hasActiveConnection,
              !isFlushingPendingDownloads else {
            return PendingFlushResult()
        }

        let candidates = pendingDownloadArchive.entries.filter { entry in
            if let ids, !ids.contains(entry.id) {
                return false
            }
            if let originScheduleID, entry.originScheduleID != originScheduleID {
                return false
            }
            guard entry.isForProfile(preferences.activeServerProfileID) else {
                return false
            }
            return force
                || entry.isEligibleForAutomaticRetry(at: date, policy: pendingRetryPolicy)
        }
        guard !candidates.isEmpty else { return PendingFlushResult() }

        isFlushingPendingDownloads = true
        defer { isFlushingPendingDownloads = false }

        let candidateIDs = Set(candidates.map(\.id))
        var submittedCount = 0
        var didChange = false

        for candidate in candidates {
            do {
                _ = try await client.status(gid: candidate.submissionGID)
                await completePendingSubmission(candidate)
                submittedCount += 1
                didChange = true
                continue
            } catch {
                if isConnectionTransportError(error) {
                    recordConnectionFailure(error)
                    break
                }
            }

            guard hasActiveConnection else { break }
            guard let currentEntry = pendingDownloadArchive.entry(id: candidate.id),
                  currentEntry.isForProfile(preferences.activeServerProfileID) else {
                continue
            }

            let payload = currentEntry.taskOptions.payload
            var options = payload.options
            var headers = payload.headers
            var submissionURIs = Self.uniqueURIs(
                [currentEntry.url] + payload.additionalURIs
            )
            if let replacedGID = currentEntry.replacesGID,
               let previousOptions = try? await client.taskOptions(gid: replacedGID) {
                options = previousOptions.filter {
                    Self.retryOptionKeys.contains($0.key)
                }
                options["dir"] = currentEntry.taskOptions.directory
                headers = previousOptions["header"]?
                    .components(separatedBy: .newlines)
                    .map(\.trimmed)
                    .filter { !$0.isEmpty }
                    ?? headers
                if let previousURIs = try? await client.uris(gid: replacedGID) {
                    let candidates = previousURIs.map(\.uri)
                    if !candidates.isEmpty {
                        submissionURIs = Self.uniqueURIs(candidates)
                    }
                }
            }
            guard hasActiveConnection else { break }
            guard pendingDownloadArchive.entry(id: currentEntry.id) != nil else {
                continue
            }
            options["gid"] = currentEntry.submissionGID
            do {
                let gid = try await client.add(
                    uris: submissionURIs,
                    options: options,
                    headers: headers
                )
                guard pendingDownloadArchive.entry(id: currentEntry.id) != nil else {
                    try? await client.forceRemove(gid: gid)
                    knownStatuses[gid] = nil
                    continue
                }
                knownStatuses[gid] = .waiting
                await completePendingSubmission(currentEntry)
                submittedCount += 1
                didChange = true
            } catch {
                if (try? await client.status(gid: currentEntry.submissionGID)) != nil {
                    guard pendingDownloadArchive.entry(id: currentEntry.id) != nil else {
                        try? await client.forceRemove(gid: currentEntry.submissionGID)
                        knownStatuses[currentEntry.submissionGID] = nil
                        continue
                    }
                    knownStatuses[currentEntry.submissionGID] = .waiting
                    await completePendingSubmission(currentEntry)
                    submittedCount += 1
                    didChange = true
                    continue
                }

                if var failedEntry = pendingDownloadArchive.entry(id: currentEntry.id) {
                    failedEntry.recordFailure(error.localizedDescription, at: date)
                    _ = pendingDownloadArchive.update(failedEntry)
                    didChange = true
                }
                if isConnectionTransportError(error) {
                    recordConnectionFailure(error)
                    break
                }
            }
        }

        if didChange {
            _ = persistPendingDownloads()
        }

        let remainingCount = pendingDownloadArchive.entries.reduce(into: 0) { count, entry in
            if candidateIDs.contains(entry.id) {
                count += 1
            }
        }
        return PendingFlushResult(
            submittedCount: submittedCount,
            failedCount: remainingCount
        )
    }

    private func completePendingSubmission(_ entry: PendingDownload) async {
        organizationStore.registerSubmission(
            entry,
            activeProfileID: preferences.activeServerProfileID
        )
        _ = pendingDownloadArchive.remove(id: entry.id)
        if let replacedGID = entry.replacesGID {
            try? await client.removeResult(gid: replacedGID)
            knownStatuses[replacedGID] = nil
            organizationStore.removeLiveAttempt(
                gid: replacedGID,
                profileID: entry.targetProfileID ?? preferences.activeServerProfileID,
                historyGIDs: retainedHistoryGIDs
            )
        }
    }

    private func enqueueOfflineRetries(_ items: [TransferItem]) -> Int {
        let previousArchive = pendingDownloadArchive
        var queuedCount = 0
        var didAdd = false
        for item in items {
            guard let sourceURI = item.sourceURI else { continue }
            if pendingDownloadArchive.entries.contains(where: {
                $0.replacesGID == item.gid
            }) {
                queuedCount += 1
                continue
            }
            let options = DownloadTaskOptions.defaults(
                directory: item.dir ?? preferences.downloadDirectory,
                maxDownloadLimitKiB: preferences.maxDownloadLimitKiB,
                maxUploadLimitKiB: preferences.maxUploadLimitKiB,
                split: preferences.split,
                maxConnectionPerServer: preferences.maxConnectionPerServer
            )
            let request = PendingDownload(
                url: sourceURI,
                taskOptions: options,
                targetProfileID: preferences.activeServerProfileID,
                targetProfileName: preferences.activeServerProfileName,
                replacesGID: item.gid
            )
            if pendingDownloadArchive.add(request) {
                queuedCount += 1
                didAdd = true
            }
        }

        guard queuedCount > 0 else { return 0 }
        guard didAdd else { return queuedCount }
        guard persistPendingDownloads() else {
            pendingDownloadArchive = previousArchive
            pendingDownloads = previousArchive.entries
            return 0
        }
        return queuedCount
    }

    private func retryTransfer(_ item: TransferItem) async throws -> String {
        guard let sourceURI = item.sourceURI else {
            throw DownloadRetryError.missingSource
        }

        let previousOptions = (try? await client.taskOptions(gid: item.gid)) ?? [:]
        var options = previousOptions.filter {
            Self.retryOptionKeys.contains($0.key)
        }
        options["dir"] = item.dir ?? preferences.downloadDirectory
        let headers = previousOptions["header"]?
            .components(separatedBy: .newlines)
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            ?? []
        let previousURIs = (try? await client.uris(gid: item.gid))?.map(\.uri) ?? []
        let submissionURIs = Self.uniqueURIs(
            previousURIs.isEmpty ? [sourceURI] : previousURIs
        )

        let newGID = try await client.add(
            uris: submissionURIs,
            options: options,
            headers: headers
        )
        organizationStore.registerRetry(
            from: item.gid,
            to: newGID,
            sourceURI: sourceURI,
            profileID: preferences.activeServerProfileID
        )
        knownStatuses[newGID] = .waiting
        try? await client.removeResult(gid: item.gid)
        knownStatuses[item.gid] = nil
        organizationStore.removeLiveAttempt(
            gid: item.gid,
            profileID: preferences.activeServerProfileID,
            historyGIDs: retainedHistoryGIDs
        )
        return newGID
    }

    private func shouldAttemptAutomaticReconnect(at date: Date = Date()) -> Bool {
        guard !isReconnecting else { return false }
        guard let nextReconnectAt else { return true }
        return nextReconnectAt <= date
    }

    private var hasActiveConnection: Bool {
        connectionState.isConnected
            && connectedProfileID == preferences.activeServerProfileID
            && connectedEndpoint == preferences.endpointURL
    }

    private var retainedHistoryGIDs: Set<String> {
        Set(historyArchive.entries.map(\.gid))
    }

    private func recordConnectionFailure(_ error: Error) {
        recordConnectionFailure(message: error.localizedDescription)
    }

    private func recordConnectionFailure(message: String) {
        connectionFailureCount += 1
        nextReconnectAt = Date().addingTimeInterval(
            connectionBackoff.delay(afterFailure: connectionFailureCount)
        )
        connectionState = .failed(message: message)
        connectedProfileID = nil
        connectedEndpoint = nil
        globalStats = .zero
        daemonSessionID = nil
        eventStreamState = .disabled
        Task {
            await eventClient.disconnect()
        }
    }

    private func resetConnectionBackoff() {
        connectionFailureCount = 0
        nextReconnectAt = nil
    }

    private func isConnectionTransportError(_ error: Error) -> Bool {
        if error is URLError {
            return true
        }
        guard let clientError = error as? Aria2ClientError else { return false }
        switch clientError {
        case .invalidEndpoint, .invalidResponse, .httpStatus:
            return true
        case .rpc:
            return false
        }
    }

    private func applyNightSpeedPolicyIfNeeded(at date: Date = Date()) async {
        guard hasActiveConnection else { return }
        let policy = currentSpeedPolicy(at: date)
        guard appliedSpeedPolicy != policy else { return }

        do {
            try await client.updateGlobalOptions([
                "max-overall-download-limit":
                    Aria2Configuration.speedOption(policy.downloadLimitKiB),
                "max-overall-upload-limit":
                    Aria2Configuration.speedOption(policy.uploadLimitKiB)
            ])
            appliedSpeedPolicy = policy
        } catch {
            // A later poll retries without interrupting task refresh.
        }
    }

    private func currentSpeedPolicy(at date: Date = Date()) -> SpeedPolicy {
        let schedule = preferences.nightSpeedSchedule
        let isNight = schedule.isActive(at: date)
        return SpeedPolicy(
            isNight: isNight,
            downloadLimitKiB: isNight
                ? max(schedule.downloadLimitKiB, 0)
                : max(preferences.maxOverallDownloadLimitKiB, 0),
            uploadLimitKiB: isNight
                ? max(schedule.uploadLimitKiB, 0)
                : max(preferences.maxOverallUploadLimitKiB, 0)
        )
    }

    private func effectiveGlobalOptions(
        policy: SpeedPolicy
    ) throws -> [String: String] {
        var options = try preferences.validatedAria2Configuration().globalOptions
        options["max-overall-download-limit"] =
            Aria2Configuration.speedOption(policy.downloadLimitKiB)
        options["max-overall-upload-limit"] =
            Aria2Configuration.speedOption(policy.uploadLimitKiB)
        return options
    }

    private func removeStagedDownloads(_ gids: [String]) async {
        for gid in gids {
            do {
                try await client.forceRemove(gid: gid)
            } catch {
                try? await client.removeResult(gid: gid)
            }
            knownStatuses[gid] = nil
        }
    }

    private func finishConnection(
        version: Aria2Version,
        profileID: UUID?,
        endpoint: URL
    ) async {
        guard profileID == preferences.activeServerProfileID,
              endpoint == preferences.endpointURL else {
            connectionState = .idle
            return
        }
        connectedProfileID = profileID
        connectedEndpoint = endpoint
        connectionState = .connected(version: version.version)
        resetConnectionBackoff()
        let policy = currentSpeedPolicy()
        appliedSpeedPolicy = nil
        if let options = try? effectiveGlobalOptions(policy: policy),
           (try? await client.updateGlobalOptions(options)) != nil {
            appliedSpeedPolicy = policy
        }
        await eventClient.connect(
            endpoint: endpoint,
            secret: preferences.rpcSecret,
            onEvent: { [weak self] event in
                self?.handleAria2Notification(event)
            },
            onStateChange: { [weak self] state in
                self?.eventStreamState = state
            }
        )
        Task { [weak self] in
            await self?.loadDaemonMetadata()
        }
        await refresh()
    }

    private func loadDaemonMetadata() async {
        guard hasActiveConnection else { return }
        async let sessionRequest = try? client.sessionInfo()
        async let methodsRequest = try? client.rpcMethods()
        async let notificationsRequest = try? client.rpcNotifications()
        let (sessionInfo, methods, notifications) = await (
            sessionRequest,
            methodsRequest,
            notificationsRequest
        )
        guard hasActiveConnection else { return }
        daemonSessionID = sessionInfo?.sessionId
        serverRPCMethods = methods ?? []
        serverRPCNotifications = notifications ?? []
    }

    private func handleAria2Notification(_ event: Aria2NotificationEvent) {
        guard hasActiveConnection else { return }
        eventRefreshTask?.cancel()
        eventRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func perform(
        successMessage: String,
        action: () async throws -> Void
    ) async {
        guard hasActiveConnection else {
            postNotice(L10n.string("aria2 尚未连接"), kind: .error)
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await action()
            await refresh()
            postNotice(successMessage, kind: .success)
        } catch {
            postNotice(error.localizedDescription, kind: .error)
        }
    }

    private func performBatch(
        actionName: String,
        emptyMessage: String,
        items: [TransferItem],
        action: (TransferItem) async throws -> Void
    ) async {
        guard !items.isEmpty else {
            postNotice(emptyMessage, kind: .warning)
            return
        }
        guard hasActiveConnection else {
            postNotice(L10n.string("aria2 尚未连接"), kind: .error)
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        var succeeded = 0
        var failed = 0
        for item in items {
            do {
                try await action(item)
                succeeded += 1
            } catch {
                failed += 1
            }
        }

        await refresh()
        if failed == 0 {
            postNotice(L10n.string("已\(actionName) \(succeeded) 个任务"), kind: .success)
        } else if succeeded > 0 {
            postNotice(
                L10n.string("已\(actionName) \(succeeded) 个，另有 \(failed) 个失败"),
                kind: .warning
            )
        } else {
            postNotice(L10n.string("\(actionName)所选任务失败"), kind: .error)
        }
    }

    private func performGIDMulticall(
        method: String,
        actionName: String,
        emptyMessage: String,
        items: [TransferItem]
    ) async {
        guard !items.isEmpty else {
            postNotice(emptyMessage, kind: .warning)
            return
        }
        guard hasActiveConnection else {
            postNotice(L10n.string("aria2 尚未连接"), kind: .error)
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let results = try await client.multicall(
                items.map {
                    Aria2MulticallInvocation(
                        method: method,
                        parameters: [$0.gid]
                    )
                }
            )
            let succeeded = results.filter(\.isSuccess).count
            let failed = max(items.count - succeeded, 0)
            await refresh()

            if failed == 0 {
                postNotice(L10n.string("已\(actionName) \(succeeded) 个任务"), kind: .success)
            } else if succeeded > 0 {
                postNotice(
                    L10n.string("已\(actionName) \(succeeded) 个，另有 \(failed) 个失败"),
                    kind: .warning
                )
            } else {
                let message = results.compactMap(\.errorMessage).first
                    ?? L10n.string("\(actionName)所选任务失败")
                postNotice(message, kind: .error)
            }
        } catch {
            postNotice(error.localizedDescription, kind: .error)
        }
    }

    private func removeFromAria2(_ item: TransferItem) async throws {
        switch item.status {
        case .complete, .error, .removed:
            try await client.removeResult(gid: item.gid)
        case .active, .waiting, .paused:
            do {
                try await client.remove(gid: item.gid)
            } catch {
                try await client.forceRemove(gid: item.gid)
            }
            for _ in 0..<4 {
                do {
                    try await client.removeResult(gid: item.gid)
                    break
                } catch {
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
        }
        organizationStore.removeLiveAttempt(
            gid: item.gid,
            profileID: preferences.activeServerProfileID,
            historyGIDs: retainedHistoryGIDs
        )
    }

    private func postNotice(_ message: String, kind: AppNotice.Kind) {
        let nextNotice = AppNotice(message: message, kind: kind)
        notice = nextNotice
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, self?.notice?.id == nextNotice.id else { return }
            self?.notice = nil
        }
    }

    private static func recoveryMessage(
        for archiveName: String,
        _ recovery: ArchiveRecovery?
    ) -> String {
        switch recovery {
        case .restoredBackup:
            return L10n.string("\(archiveName)文件损坏，已从安全备份恢复")
        case .resetCorruptedFile(let fileURL):
            if let fileURL {
                return L10n.string("\(archiveName)文件损坏，已保留为 \(fileURL.lastPathComponent) 并重新开始")
            }
            return L10n.string("\(archiveName)文件损坏，已使用空存档继续")
        case nil:
            return ""
        }
    }

    private static let retryOptionKeys: Set<String> = [
        "max-download-limit",
        "max-upload-limit",
        "split",
        "max-connection-per-server",
        "out",
        "referer",
        "user-agent",
        "http-user",
        "http-passwd",
        "ftp-user",
        "ftp-passwd",
        "checksum",
        "all-proxy",
        "all-proxy-user",
        "all-proxy-passwd",
        "http-proxy",
        "http-proxy-user",
        "http-proxy-passwd",
        "https-proxy",
        "https-proxy-user",
        "https-proxy-passwd",
        "ftp-proxy",
        "ftp-proxy-user",
        "ftp-proxy-passwd",
        "no-proxy",
        "check-certificate",
        "ca-certificate",
        "certificate",
        "private-key",
        "load-cookies",
        "ftp-pasv",
        "ftp-reuse-connection",
        "ftp-type",
        "ssh-host-key-md",
        "check-integrity",
        "dry-run",
        "content-disposition-default-utf8",
        "conditional-get",
        "http-accept-gzip",
        "bt-tracker",
        "bt-exclude-tracker",
        "bt-require-crypto",
        "bt-force-encryption",
        "bt-min-crypto-level",
        "bt-metadata-only",
        "bt-save-metadata",
        "metalink-location",
        "metalink-language",
        "metalink-os",
        "metalink-version",
        "metalink-preferred-protocol"
    ]

    private static func uniqueURIs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map(\.trimmed)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func normalizedRSSURL(_ value: String) -> URL? {
        var candidate = value.trimmed
        guard !candidate.isEmpty else { return nil }
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }
        guard let url = URL(string: candidate),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    private static let scheduleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct SpeedPolicy: Equatable {
    let isNight: Bool
    let downloadLimitKiB: Int
    let uploadLimitKiB: Int
}

private struct PendingFlushResult: Equatable {
    var submittedCount = 0
    var failedCount = 0
}

private struct LocalFileTrashResult: Sendable {
    var trashedCount = 0
    var missingCount = 0
    var skippedDirectoryCount = 0
    var failedCount = 0
}

private enum DownloadRetryError: LocalizedError {
    case missingSource

    var errorDescription: String? {
        switch self {
        case .missingSource:
            L10n.string("任务没有可用于重试的来源地址")
        }
    }
}
