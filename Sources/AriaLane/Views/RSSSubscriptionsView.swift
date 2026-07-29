import AppKit
import SwiftUI

struct RSSSubscriptionsView: View {
    @EnvironmentObject private var store: DownloadStore
    @Binding var searchText: String
    @State private var isShowingNewSubscription = false
    @State private var editingSubscription: RSSSubscription?

    private var visibleSubscriptions: [RSSSubscription] {
        store.rssSubscriptions.filter { $0.matches(searchText) }
    }

    var body: some View {
        GeometryReader { geometry in
            subscriptionsContent
                .sheet(isPresented: $isShowingNewSubscription) {
                    RSSSubscriptionEditorView(
                        availableSize: geometry.size
                    )
                }
                .sheet(item: $editingSubscription) { subscription in
                    RSSSubscriptionEditorView(
                        subscription: subscription,
                        availableSize: geometry.size
                    )
                }
        }
    }

    private var subscriptionsContent: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.7)

            if store.rssSubscriptions.isEmpty {
                emptyState
            } else if visibleSubscriptions.isEmpty {
                searchEmptyState
            } else {
                List {
                    ForEach(visibleSubscriptions) { subscription in
                        RSSSubscriptionRow(
                            subscription: subscription,
                            isRefreshing: store.refreshingRSSSubscriptionIDs.contains(
                                subscription.id
                            ),
                            onSetEnabled: {
                                store.setRSSSubscriptionEnabled(
                                    id: subscription.id,
                                    isEnabled: $0
                                )
                            },
                            onRefresh: {
                                Task {
                                    await store.refreshRSSSubscription(id: subscription.id)
                                }
                            },
                            onDownload: { itemID in
                                Task {
                                    await store.downloadRSSItem(
                                        subscriptionID: subscription.id,
                                        itemID: itemID
                                    )
                                }
                            },
                            onEdit: {
                                editingSubscription = subscription
                            },
                            onRemove: {
                                store.removeRSSSubscription(id: subscription.id)
                            }
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 5,
                                leading: LaneMetric.contentPadding,
                                bottom: 5,
                                trailing: LaneMetric.contentPadding
                            )
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.vertical, 11, for: .scrollContent)
            }
        }
        .background(LaneColor.canvas)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("RSS 订阅"))
                    .font(LaneFont.display(27))
                Text(L10n.string("定时检查 Feed，新附件可自动进入对应服务器的下载队列"))
                    .font(LaneFont.interface(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    Task { await store.refreshAllRSSSubscriptions() }
                } label: {
                    Label(L10n.string("全部刷新"), systemImage: "arrow.clockwise")
                }
                .disabled(
                    store.rssSubscriptions.isEmpty
                        || !store.refreshingRSSSubscriptionIDs.isEmpty
                )

                Button {
                    isShowingNewSubscription = true
                } label: {
                    Label(L10n.string("添加订阅"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, LaneMetric.contentPadding)
        .padding(.top, 23)
        .padding(.bottom, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.string("还没有 RSS 订阅"))
                .font(LaneFont.label(16))
            Text(L10n.string("添加 Feed 后，AriaLane 会按设定频率检查新条目。"))
                .font(LaneFont.interface(11))
                .foregroundStyle(.secondary)
            Button {
                isShowingNewSubscription = true
            } label: {
                Label(L10n.string("添加 RSS 订阅"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 13) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.string("没有找到“\(searchText)”"))
                .font(LaneFont.label(15))
            Button(L10n.string("清除搜索")) {
                searchText = ""
            }
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

private struct RSSSubscriptionRow: View {
    let subscription: RSSSubscription
    let isRefreshing: Bool
    let onSetEnabled: (Bool) -> Void
    let onRefresh: () -> Void
    let onDownload: (String) -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var showsItems = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 14) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(subscription.isEnabled ? LaneColor.accent : .secondary)
                    .frame(width: 40, height: 40)
                    .background(
                        LaneColor.accent.opacity(subscription.isEnabled ? 0.10 : 0.04),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(subscription.displayName)
                        .font(LaneFont.label(14))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(subscription.feedURL)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text(subscription.refreshInterval.title)
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text(subscription.serverDisplayName)
                            .lineLimit(1)
                    }
                    .font(LaneFont.interface(10))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                status

                Toggle(
                    L10n.string("启用"),
                    isOn: Binding(
                        get: { subscription.isEnabled },
                        set: onSetEnabled
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

                Button(action: onRefresh) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help(L10n.string("立即刷新"))

                Menu {
                    Button(L10n.string("编辑订阅…"), action: onEdit)
                    Button(
                        showsItems ? L10n.string("收起最近条目") : L10n.string("查看最近条目")
                    ) {
                        showsItems.toggle()
                    }
                    Divider()
                    Button(L10n.string("移除订阅"), role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            if showsItems {
                Divider()
                recentItems
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: LaneMetric.cornerRadius, style: .continuous)
                .fill(LaneColor.surface.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: LaneMetric.cornerRadius, style: .continuous)
                        .stroke(LaneColor.line, lineWidth: 1)
                }
        }
        .contextMenu {
            Button(L10n.string("立即刷新"), action: onRefresh)
            Button(L10n.string("编辑订阅…"), action: onEdit)
            Divider()
            Button(L10n.string("移除订阅"), role: .destructive, action: onRemove)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let error = subscription.lastError {
            Label(L10n.string("刷新失败"), systemImage: "exclamationmark.triangle.fill")
                .font(LaneFont.interface(10, weight: .medium))
                .foregroundStyle(LaneColor.danger)
                .help(error)
        } else if subscription.autoDownloadNewItems {
            Label(L10n.string("自动下载"), systemImage: "arrow.down.circle")
                .font(LaneFont.interface(10, weight: .medium))
                .foregroundStyle(LaneColor.mint)
        } else {
            Text(L10n.string("\(subscription.items.count) 个条目"))
                .font(LaneFont.interface(10))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var recentItems: some View {
        if subscription.items.isEmpty {
            Text(L10n.string("刷新后会在这里显示最近条目"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 3)
        } else {
            VStack(spacing: 7) {
                ForEach(subscription.items.prefix(5)) { item in
                    HStack(spacing: 9) {
                        Image(
                            systemName: item.canDownload
                                ? "arrow.down.doc"
                                : "doc.text"
                        )
                        .foregroundStyle(
                            item.canDownload
                                ? LaneColor.accent
                                : Color.secondary.opacity(0.62)
                        )
                        .frame(width: 16)

                        Text(item.displayTitle)
                            .font(LaneFont.interface(11, weight: .medium))
                            .lineLimit(1)

                        Spacer()

                        if let date = item.publishedAt {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(LaneFont.utility(9, weight: .regular))
                                .foregroundStyle(.tertiary)
                        }

                        if item.canDownload {
                            Button(L10n.string("下载")) {
                                onDownload(item.id)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}

private enum RSSRefreshUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours
    case days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minutes: L10n.string("分钟")
        case .hours: L10n.string("小时")
        case .days: L10n.string("天")
        }
    }

    var secondsMultiplier: Int {
        switch self {
        case .minutes: 60
        case .hours: 3_600
        case .days: 86_400
        }
    }

    var maximumValue: Int {
        RSSRefreshInterval.maximumSeconds / secondsMultiplier
    }
}

private struct RSSSubscriptionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore

    let subscription: RSSSubscription?
    let availableSize: CGSize

    @State private var title: String
    @State private var feedURL: String
    @State private var refreshInterval: RSSRefreshInterval
    @State private var autoDownloadNewItems: Bool
    @State private var downloadDirectory: String
    @State private var targetProfileID: UUID?
    @State private var usesCustomRefreshInterval: Bool
    @State private var customRefreshValue: Int
    @State private var customRefreshUnit: RSSRefreshUnit
    @State private var isAddingServer = false

    init(
        subscription: RSSSubscription? = nil,
        availableSize: CGSize = CGSize(width: 640, height: 700)
    ) {
        self.subscription = subscription
        self.availableSize = availableSize
        let initialInterval = subscription?.refreshInterval ?? .thirtyMinutes
        let initialCustomUnit: RSSRefreshUnit
        let initialCustomValue: Int
        if initialInterval.seconds.isMultiple(of: 86_400) {
            initialCustomUnit = .days
            initialCustomValue = initialInterval.seconds / 86_400
        } else if initialInterval.seconds.isMultiple(of: 3_600) {
            initialCustomUnit = .hours
            initialCustomValue = initialInterval.seconds / 3_600
        } else {
            initialCustomUnit = .minutes
            initialCustomValue = initialInterval.seconds / 60
        }

        _title = State(initialValue: subscription?.title ?? "")
        _feedURL = State(initialValue: subscription?.feedURL ?? "")
        _refreshInterval = State(initialValue: initialInterval)
        _autoDownloadNewItems = State(
            initialValue: subscription?.autoDownloadNewItems ?? true
        )
        _downloadDirectory = State(
            initialValue: subscription?.taskOptions.directory ?? ""
        )
        _targetProfileID = State(initialValue: subscription?.targetProfileID)
        _usesCustomRefreshInterval = State(
            initialValue: !initialInterval.isPreset
        )
        _customRefreshValue = State(initialValue: initialCustomValue)
        _customRefreshUnit = State(initialValue: initialCustomUnit)
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader

            Divider()
                .opacity(0.62)

            ScrollView {
                VStack(spacing: 14) {
                    subscriptionSourceCard
                    refreshAndDownloadCard
                }
                .padding(usesCompactPresentation ? 14 : 22)
            }
            .scrollIndicators(.hidden)

            Divider()
                .opacity(0.62)

            editorFooter
                .padding(.horizontal, usesCompactPresentation ? 16 : 22)
                .frame(height: usesCompactPresentation ? 60 : 68)
                .background(LaneColor.surface)
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .background(LaneColor.canvas)
        .onAppear {
            if downloadDirectory.trimmed.isEmpty {
                downloadDirectory = preferences.downloadDirectory
            }
            if targetProfileID == nil {
                targetProfileID = preferences.activeServerProfileID
            }
        }
        .sheet(isPresented: $isAddingServer) {
            ServerEditorSheet(saveButtonTitle: L10n.string("添加服务器")) { draft in
                targetProfileID = preferences.addServerProfile(
                    name: draft.name,
                    endpoint: draft.endpoint,
                    secret: draft.secret
                )
            }
            .environmentObject(store)
        }
    }

    private var usesCompactPresentation: Bool {
        sheetSize.width < 620 || sheetSize.height < 650
    }

    private var sheetSize: CGSize {
        LaneAdaptiveSheetSize.rssEditor(in: availableSize)
    }

    private var editorHeader: some View {
        HStack(spacing: usesCompactPresentation ? 11 : 13) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(
                    .system(
                        size: usesCompactPresentation ? 16 : 18,
                        weight: .semibold
                    )
                )
                .foregroundStyle(LaneColor.accent)
                .frame(
                    width: usesCompactPresentation ? 36 : 42,
                    height: usesCompactPresentation ? 36 : 42
                )
                .background(
                    LaneColor.accent.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: usesCompactPresentation ? 10 : 12
                    )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(subscription == nil ? L10n.string("添加 RSS 订阅") : L10n.string("编辑 RSS 订阅"))
                    .font(
                        LaneFont.display(
                            usesCompactPresentation ? 20 : 24
                        )
                    )
                    .lineLimit(1)
                Text(L10n.string("首次同步只记录现有条目；之后发现的新附件才会自动下载"))
                    .font(
                        LaneFont.interface(
                            usesCompactPresentation ? 9.5 : 10.5
                        )
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(L10n.string("关闭"))
        }
        .padding(.horizontal, usesCompactPresentation ? 16 : 22)
        .frame(height: usesCompactPresentation ? 74 : 86)
        .background(LaneColor.surface)
    }

    private var subscriptionSourceCard: some View {
        RSSFormCard(
            title: L10n.string("订阅来源"),
            detail: L10n.string("填写 Feed 地址，也可以设置更易识别的名称"),
            systemImage: "link",
            isCompact: usesCompactPresentation
        ) {
            RSSFormField(L10n.string("订阅名称（可选）")) {
                TextField(L10n.string("例如：项目发布"), text: $title)
                    .textFieldStyle(.plain)
                    .font(LaneFont.interface(12))
            }

            RSSFormField(L10n.string("Feed 地址")) {
                TextField(
                    "https://example.com/feed.xml",
                    text: $feedURL
                )
                .textFieldStyle(.plain)
                .font(LaneFont.utility(11, weight: .regular))
            }
        }
    }

    private var refreshAndDownloadCard: some View {
        RSSFormCard(
            title: L10n.string("刷新与下载"),
            detail: L10n.string("选择检查节奏、目标服务器与附件保存位置"),
            systemImage: "arrow.triangle.2.circlepath",
            isCompact: usesCompactPresentation
        ) {
            if usesCompactPresentation {
                VStack(alignment: .leading, spacing: 12) {
                    refreshFrequencyField
                    serverSelectionField
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    refreshFrequencyField
                    serverSelectionField
                }
            }

            RSSFormField(L10n.string("保存目录")) {
                HStack(spacing: 8) {
                    TextField(L10n.string("下载目录"), text: $downloadDirectory)
                        .textFieldStyle(.plain)
                        .font(LaneFont.utility(11, weight: .regular))

                    Button(L10n.string("选择…"), action: chooseDirectory)
                        .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LaneColor.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        LaneColor.accent.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 9)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("自动下载新条目的附件"))
                        .font(LaneFont.interface(11.5, weight: .semibold))
                    Text(L10n.string("关闭后仍会刷新 Feed，但不会自动创建下载任务"))
                        .font(LaneFont.interface(9.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $autoDownloadNewItems)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(11)
            .background(
                LaneColor.fill1,
                in: RoundedRectangle(cornerRadius: 11)
            )
        }
    }

    private var refreshFrequencyField: some View {
        RSSFormField(L10n.string("检查频率")) {
            RSSRefreshIntervalControl(
                presetSelection: $refreshInterval,
                usesCustomInterval: $usesCustomRefreshInterval,
                customValue: $customRefreshValue,
                customUnit: $customRefreshUnit
            )
        }
    }

    private var serverSelectionField: some View {
        RSSFormField(L10n.string("下载服务器")) {
            RSSServerSelectionMenu(
                selection: $targetProfileID,
                profiles: preferences.serverProfiles,
                onAddServer: {
                    isAddingServer = true
                }
            )
        }
    }

    private var editorFooter: some View {
        HStack(spacing: usesCompactPresentation ? 8 : 12) {
            if let validationMessage {
                Label(
                    validationMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(LaneFont.interface(10.5, weight: .medium))
                .foregroundStyle(LaneColor.danger)
                .lineLimit(1)
            } else {
                Label(L10n.string("订阅信息有效"), systemImage: "checkmark.circle.fill")
                    .font(LaneFont.interface(10.5, weight: .medium))
                    .foregroundStyle(LaneColor.mint)
            }

            Spacer()

            Button(L10n.string("取消")) {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(usesCompactPresentation ? .regular : .large)
            .keyboardShortcut(.cancelAction)

            Button(subscription == nil ? L10n.string("添加并刷新") : L10n.string("保存修改")) {
                save()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(usesCompactPresentation ? .regular : .large)
            .keyboardShortcut(.defaultAction)
            .disabled(validationMessage != nil)
        }
    }

    private var validationMessage: String? {
        let normalized = feedURL.trimmed
        guard !normalized.isEmpty else { return L10n.string("请输入 Feed 地址") }
        let candidate = normalized.contains("://") ? normalized : "https://\(normalized)"
        guard let url = URL(string: candidate),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else {
            return L10n.string("Feed 地址需要使用 HTTP 或 HTTPS")
        }
        if usesCustomRefreshInterval,
           !(1...customRefreshUnit.maximumValue).contains(
               customRefreshValue
           ) {
            return L10n.string("自定义频率需为 1–\(customRefreshUnit.maximumValue) \(customRefreshUnit.title)")
        }
        return nil
    }

    private var selectedRefreshInterval: RSSRefreshInterval {
        guard usesCustomRefreshInterval else {
            return refreshInterval
        }
        let boundedValue = min(
            max(customRefreshValue, 1),
            customRefreshUnit.maximumValue
        )
        return RSSRefreshInterval(
            seconds: boundedValue * customRefreshUnit.secondsMultiplier
        )
    }

    private func save() {
        if let subscription {
            if store.updateRSSSubscription(
                id: subscription.id,
                title: title,
                feedURL: feedURL,
                refreshInterval: selectedRefreshInterval,
                autoDownloadNewItems: autoDownloadNewItems,
                downloadDirectory: downloadDirectory,
                targetProfileID: targetProfileID
            ) {
                dismiss()
            }
        } else if let id = store.addRSSSubscription(
            title: title,
            feedURL: feedURL,
            refreshInterval: selectedRefreshInterval,
            autoDownloadNewItems: autoDownloadNewItems,
            downloadDirectory: downloadDirectory,
            targetProfileID: targetProfileID
        ) {
            dismiss()
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                await store.refreshRSSSubscription(id: id)
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("选择 RSS 下载目录")
        panel.prompt = L10n.string("选择")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: downloadDirectory)

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                downloadDirectory = url.path
            }
        }
    }
}

private struct RSSFormCard<Content: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    let isCompact: Bool
    let content: Content

    init(
        title: String,
        detail: String,
        systemImage: String,
        isCompact: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.isCompact = isCompact
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 12 : 14) {
            HStack(spacing: isCompact ? 9 : 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LaneColor.accent)
                    .frame(
                        width: isCompact ? 30 : 34,
                        height: isCompact ? 30 : 34
                    )
                    .background(
                        LaneColor.accent.opacity(0.09),
                        in: RoundedRectangle(
                            cornerRadius: isCompact ? 8 : 9
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LaneFont.interface(13, weight: .semibold))
                    Text(detail)
                        .font(LaneFont.interface(9.5))
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(isCompact ? 12 : 15)
        .background(
            LaneColor.surface,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LaneColor.line, lineWidth: 1)
        }
    }
}

private struct RSSFormField<Content: View>: View {
    let title: String
    let content: Content

    init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(LaneFont.interface(10.5, weight: .medium))
                .foregroundStyle(.secondary)

            content
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .background(
                    LaneColor.fill1,
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RSSRefreshIntervalControl: View {
    @Binding var presetSelection: RSSRefreshInterval
    @Binding var usesCustomInterval: Bool
    @Binding var customValue: Int
    @Binding var customUnit: RSSRefreshUnit

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(RSSRefreshInterval.allCases) { interval in
                    Button {
                        presetSelection = interval
                        usesCustomInterval = false
                    } label: {
                        if !usesCustomInterval,
                           presetSelection == interval {
                            Label(
                                interval.title,
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(interval.title)
                        }
                    }
                }

                Divider()

                Button {
                    prepareCustomValue()
                    usesCustomInterval = true
                } label: {
                    if usesCustomInterval {
                        Label(L10n.string("自定义…"), systemImage: "checkmark")
                    } else {
                        Label(L10n.string("自定义…"), systemImage: "slider.horizontal.3")
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(
                        usesCustomInterval
                            ? L10n.string("自定义")
                            : presetSelection.title
                    )
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                    if !usesCustomInterval {
                        Spacer(minLength: 8)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(LaneFont.interface(11, weight: .medium))
                .frame(
                    maxWidth: usesCustomInterval ? nil : .infinity,
                    minHeight: 36,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            if usesCustomInterval {
                Spacer(minLength: 2)

                TextField(
                    "30",
                    value: $customValue,
                    format: .number.grouping(.never)
                )
                .textFieldStyle(.plain)
                .font(LaneFont.utility(11, weight: .regular))
                .multilineTextAlignment(.trailing)
                .frame(width: 42)

                Menu {
                    ForEach(RSSRefreshUnit.allCases) { unit in
                        Button {
                            customUnit = unit
                        } label: {
                            if customUnit == unit {
                                Label(unit.title, systemImage: "checkmark")
                            } else {
                                Text(unit.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(customUnit.title)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(LaneFont.interface(10.5, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("检查频率"))
    }

    private func prepareCustomValue() {
        let seconds = presetSelection.seconds
        if seconds.isMultiple(of: 86_400) {
            customUnit = .days
            customValue = seconds / 86_400
        } else if seconds.isMultiple(of: 3_600) {
            customUnit = .hours
            customValue = seconds / 3_600
        } else {
            customUnit = .minutes
            customValue = seconds / 60
        }
    }
}

private struct RSSServerSelectionMenu: View {
    @Binding var selection: UUID?
    let profiles: [Aria2ServerProfile]
    let onAddServer: () -> Void

    var body: some View {
        Menu {
            ForEach(profiles) { profile in
                Button {
                    selection = profile.id
                } label: {
                    if selection == profile.id {
                        Label(
                            profile.displayName,
                            systemImage: "checkmark"
                        )
                    } else {
                        Text(profile.displayName)
                    }
                }
            }

            Divider()

            Button(action: onAddServer) {
                Label(L10n.string("添加服务器…"), systemImage: "plus")
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(LaneFont.interface(11, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(L10n.string("下载服务器"))
        .accessibilityValue(selectedTitle)
    }

    private var selectedTitle: String {
        guard let selection,
              let profile = profiles.first(
                  where: { $0.id == selection }
              ) else {
            return L10n.string("选择服务器")
        }
        return profile.displayName
    }
}
