import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TransferInspectorView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore
    @EnvironmentObject private var organization: TaskOrganizationStore
    @StateObject private var advancedDetails = TransferAdvancedDetailsModel()
    @StateObject private var taskSettings = TaskInspectorSettingsModel()
    @State private var selectedTab = InspectorTab.general
    @State private var isTaskSettingsExpanded = true
    @State private var isHTTPFTPExpanded = false
    @State private var isAdvancedOptionsExpanded = false
    @State private var isTaskControlsExpanded = false

    let item: TransferItem
    let onClose: () -> Void

    private let presentation: Presentation

    init(item: TransferItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        presentation = Presentation(item: item)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    progressSummary
                    metricsGrid
                    locationAndSource

                    if let errorMessage = item.userFacingError, !errorMessage.isEmpty {
                        errorPanel(errorMessage)
                    }

                    inspectorTabBar

                    tabContent
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }

            Divider()
            actionBar
        }
        .background(
            LaneColor.surface,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(LaneColor.line, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .padding(9)
        .background(LaneColor.canvas)
        .task(id: item.gid) {
            await taskSettings.load(item: item, store: store)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            NativeTransferFileIcon(path: presentation.path)

            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.title)
                    .font(LaneFont.label(15))
                    .foregroundStyle(LaneColor.label1)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                StatusBadge(status: item.status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TaskInspectorCloseButton(action: onClose)
        }
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(presentation.progress)
                .font(LaneFont.display(29))
                .foregroundStyle(LaneColor.label1)

            SegmentedProgressView(
                progress: presentation.progressValue,
                status: item.status,
                height: 5
            )
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 58), spacing: 10),
                count: 3
            ),
            alignment: .leading,
            spacing: 16
        ) {
            TransferInspectorMetric(
                label: L10n.string("下载速度"),
                value: presentation.downloadSpeed
            )
            TransferInspectorMetric(
                label: L10n.string("已下载"),
                value: presentation.downloaded
            )
            TransferInspectorMetric(
                label: L10n.string("剩余时间"),
                value: presentation.remainingTime
            )
            TransferInspectorMetric(
                label: L10n.string("文件大小"),
                value: presentation.fileSize
            )
            TransferInspectorMetric(
                label: L10n.string("上传速度"),
                value: presentation.uploadSpeed
            )
            TransferInspectorMetric(
                label: L10n.string("连接数"),
                value: presentation.connectionCount
            )
        }
        .padding(.vertical, 2)
    }

    private var inspectorTabBar: some View {
        HStack(spacing: 2) {
            ForEach(InspectorTab.allCases) { tab in
                let isSelected = selectedTab == tab

                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(
                            LaneFont.interface(
                                10.5,
                                weight: isSelected ? .semibold : .regular
                            )
                        )
                        .foregroundStyle(
                            isSelected ? LaneColor.accent : LaneColor.label2
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? LaneColor.surface : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .overlay(alignment: .bottom) {
                            if isSelected {
                                Capsule()
                                    .fill(LaneColor.accent)
                                    .frame(height: 2)
                                    .padding(.horizontal, 15)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .animation(.easeInOut(duration: 0.15), value: selectedTab)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("任务详情"))
    }

    private var locationAndSource: some View {
        VStack(alignment: .leading, spacing: 11) {
            TransferInspectorInfoBlock(
                label: L10n.string("保存路径"),
                value: presentation.path,
                systemImage: "folder"
            )

            TransferInspectorInfoBlock(
                label: L10n.string("来源"),
                value: presentation.source,
                systemImage: "link"
            )

            if let taskEntity {
                inspectorMetadataRow(
                    label: taskEntity.addedAtIsInferred
                        ? L10n.string("首次观察")
                        : L10n.string("加入日期"),
                    value: taskEntity.addedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
            }

            inspectorMetadataRow(
                label: L10n.string("任务 ID"),
                value: presentation.gid,
                isMonospaced: true
            )
        }
    }

    private func inspectorMetadataRow(
        label: String,
        value: String,
        isMonospaced: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(LaneFont.interface(10))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value)
                .font(
                    isMonospaced
                        ? LaneFont.utility(9, weight: .regular)
                        : LaneFont.interface(10)
                )
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalTab
        case .connection:
            connectionTab
        case .advanced:
            advancedTab
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 3) {
            TransferInspectorDisclosureCard(
                title: L10n.string("任务设置"),
                isExpanded: $isTaskSettingsExpanded
            ) {
                taskSettingsContent
            }

            TransferInspectorDisclosureCard(
                title: L10n.string("HTTP / FTP 选项"),
                isExpanded: $isHTTPFTPExpanded
            ) {
                httpFTPContent
            }

            TransferInspectorDisclosureCard(
                title: L10n.string("高级选项"),
                isExpanded: $isAdvancedOptionsExpanded
            ) {
                advancedOptionsContent
            }
        }
    }

    private var taskSettingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            taskSettingRow(
                label: L10n.string("下载线程"),
                value: taskSettings.downloadThreads
            )
            taskSettingRow(
                label: L10n.string("最小分片大小"),
                value: taskSettings.minimumSplitSize
            )
            taskSettingRow(
                label: L10n.string("优先级"),
                value: taskSettings.priority,
                isMonospaced: false
            )

            if hasAdditionalTaskControls {
                Divider()

                Button {
                    isTaskControlsExpanded.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(LaneColor.accent)
                        Text(L10n.string("标签、限速与队列"))
                            .font(LaneFont.interface(10, weight: .medium))
                        Spacer()
                        Image(systemName: isTaskControlsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isTaskControlsExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        if let entityID {
                            TaskTagsSection(entityID: entityID)
                        }

                        if item.status == .active
                            || item.status == .waiting
                            || item.status == .paused {
                            TaskSpeedLimitView(item: item)
                        }

                        if item.isQueueMovable {
                            queueControls
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var httpFTPContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let source = presentation.httpFTPSource {
                Text(L10n.string("当前来源"))
                    .font(LaneFont.interface(9))
                    .foregroundStyle(.secondary)
                Text(source)
                    .font(LaneFont.utility(9, weight: .regular))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(source)
            } else {
                Text(L10n.string("aria2 当前没有报告 HTTP / FTP 来源。"))
                    .font(LaneFont.interface(10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                selectedTab = .advanced
            } label: {
                inspectorNavigationLabel(
                    L10n.string("管理来源与镜像"),
                    systemImage: "link.badge.plus"
                )
            }
            .buttonStyle(
                LaneCompactActionButtonStyle(
                    tone: .accent,
                    surface: .tinted,
                    minimumHeight: 28
                )
            )
        }
    }

    private var advancedOptionsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("文件选择、镜像和 aria2 运行参数会在高级页按需读取。"))
                .font(LaneFont.interface(10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                selectedTab = .advanced
            } label: {
                inspectorNavigationLabel(
                    L10n.string("打开高级选项"),
                    systemImage: "slider.horizontal.3"
                )
            }
            .buttonStyle(
                LaneCompactActionButtonStyle(
                    tone: .accent,
                    surface: .tinted,
                    minimumHeight: 28
                )
            )
        }
    }

    private var connectionTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.string("连接概览"), systemImage: "network")
                .font(LaneFont.interface(12, weight: .semibold))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 90), spacing: 10),
                    GridItem(.flexible(minimum: 90), spacing: 10),
                ],
                alignment: .leading,
                spacing: 13
            ) {
                TransferInspectorConnectionMetric(
                    label: L10n.string("当前状态"),
                    value: item.status.title,
                    systemImage: item.status.systemImage,
                    tint: statusTint
                )
                TransferInspectorConnectionMetric(
                    label: L10n.string("活动连接"),
                    value: presentation.connectionCount,
                    systemImage: "point.3.connected.trianglepath.dotted",
                    tint: LaneColor.accent
                )
                TransferInspectorConnectionMetric(
                    label: L10n.string("下载速度"),
                    value: presentation.downloadSpeed,
                    systemImage: "arrow.down",
                    tint: LaneColor.accent
                )
                TransferInspectorConnectionMetric(
                    label: L10n.string("上传速度"),
                    value: presentation.uploadSpeed,
                    systemImage: "arrow.up",
                    tint: LaneColor.mint
                )
            }

            if presentation.isBitTorrent {
                HStack {
                    Label(L10n.string("做种者"), systemImage: "person.2")
                        .font(LaneFont.interface(10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(presentation.seederCount)
                        .font(LaneFont.utility(10))
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .transferInspectorCard()
    }

    private var advancedTab: some View {
        TransferAdvancedDetailsView(model: advancedDetails, item: item)
            .padding(12)
            .transferInspectorCard()
    }

    private var queueControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("队列优先级"), systemImage: "arrow.up.arrow.down")
                .font(LaneFont.interface(12, weight: .semibold))

            HStack(spacing: 7) {
                queueButton(L10n.string("队首"), icon: "arrow.up.to.line", direction: .top)
                queueButton(L10n.string("上移"), icon: "arrow.up", direction: .up)
                queueButton(L10n.string("下移"), icon: "arrow.down", direction: .down)
                queueButton(L10n.string("队尾"), icon: "arrow.down.to.line", direction: .bottom)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 7) {
            Button {
                store.reveal(item)
            } label: {
                Label(L10n.string("在 Finder 中显示"), systemImage: "folder")
                    .font(LaneFont.interface(10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .buttonStyle(.bordered)

            primaryAction

            Button(role: .destructive) {
                Task { await store.remove(item) }
            } label: {
                Label(L10n.string("删除"), systemImage: "trash")
                    .font(LaneFont.interface(10, weight: .medium))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .help(L10n.string("只移除任务记录，不删除已经下载的文件"))
            .accessibilityLabel(L10n.string("移除任务"))
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.regularMaterial)
        .disabled(store.isPerformingAction)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if item.isPausable {
            Button {
                Task { await store.pause(item) }
            } label: {
                Label(L10n.string("暂停"), systemImage: "pause.fill")
                    .font(LaneFont.interface(10, weight: .medium))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .contextMenu {
                Button {
                    Task { await store.forcePause(item) }
                } label: {
                    Label(L10n.string("强制暂停"), systemImage: "exclamationmark.pause.fill")
                }
            }
            .help(L10n.string("右键可强制暂停"))
        } else if item.isResumable {
            Button {
                Task { await store.resume(item) }
            } label: {
                Label(L10n.string("继续"), systemImage: "play.fill")
                    .font(LaneFont.interface(10, weight: .medium))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
        } else if item.isRetryable {
            Button {
                Task { await store.retry(item) }
            } label: {
                Label(L10n.string("重试"), systemImage: "arrow.clockwise")
                    .font(LaneFont.interface(10, weight: .medium))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
        } else {
            Button(action: {}) {
                Label(item.status.title, systemImage: item.status.systemImage)
                    .font(LaneFont.interface(10, weight: .medium))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .disabled(true)
        }
    }

    private var entityID: UUID? {
        organization.entityID(
            gid: item.gid,
            profileID: preferences.activeServerProfileID
        )
    }

    private var taskEntity: TaskEntityRecord? {
        entityID.flatMap { organization.entity(id: $0) }
    }

    private var hasAdditionalTaskControls: Bool {
        entityID != nil
            || item.status == .active
            || item.status == .waiting
            || item.status == .paused
            || item.isQueueMovable
    }

    private var statusTint: Color {
        switch item.status {
        case .active: LaneColor.accent
        case .waiting: LaneColor.amber
        case .paused: LaneColor.label2
        case .error: LaneColor.danger
        case .complete: LaneColor.mint
        case .removed: LaneColor.label2
        }
    }

    private func errorPanel(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(LaneColor.danger)
            Text(message)
                .font(LaneFont.interface(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LaneColor.danger.opacity(0.08),
            in: RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
        )
    }

    private func queueButton(
        _ title: String,
        icon: String,
        direction: QueueMoveDirection
    ) -> some View {
        Button {
            Task { await store.moveQueueItem(item, direction: direction) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
                    .font(LaneFont.interface(9))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func inspectorNavigationLabel(
        _ title: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))

            Text(title)
                .foregroundStyle(LaneColor.label1)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(LaneColor.accent.opacity(0.72))
        }
    }

    private func taskSettingRow(
        label: String,
        value: String,
        isMonospaced: Bool = true
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(LaneFont.interface(10))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value)
                .font(
                    isMonospaced
                        ? LaneFont.utility(10, weight: .regular)
                        : LaneFont.interface(10, weight: .medium)
                )
                .foregroundStyle(LaneColor.label1)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private extension TransferInspectorView {
    enum InspectorTab: String, CaseIterable, Identifiable {
        case general
        case connection
        case advanced

        var id: Self { self }

        var title: String {
            switch self {
            case .general: L10n.string("常规")
            case .connection: L10n.string("连接")
            case .advanced: L10n.string("高级")
            }
        }
    }

    struct Presentation {
        let title: String
        let progressValue: Double
        let progress: String
        let downloadSpeed: String
        let downloaded: String
        let remainingTime: String
        let fileSize: String
        let uploadSpeed: String
        let connectionCount: String
        let path: String
        let source: String
        let gid: String
        let isBitTorrent: Bool
        let seederCount: String
        let httpFTPSource: String?

        init(item: TransferItem) {
            let totalByteCount = item.totalByteCount
            let completedByteCount = item.completedByteCount
            let downloadSpeedValue = item.downloadSpeedValue
            let displayPath = item.displayPath.trimmed
            let sourceURI = item.sourceURI?.trimmed

            title = item.displayName
            if totalByteCount > 0 {
                progressValue = min(
                    max(Double(completedByteCount) / Double(totalByteCount), 0),
                    1
                )
            } else {
                progressValue = item.status == .complete ? 1 : 0
            }
            progress = TransferFormatter.percent(progressValue)
            downloadSpeed = TransferFormatter.speed(downloadSpeedValue)
            downloaded = TransferFormatter.bytes(completedByteCount)
            if downloadSpeedValue > 0, totalByteCount > completedByteCount {
                let seconds = TimeInterval(totalByteCount - completedByteCount)
                    / TimeInterval(downloadSpeedValue)
                remainingTime = TransferFormatter.duration(seconds)
            } else {
                remainingTime = TransferFormatter.duration(nil)
            }
            fileSize = totalByteCount > 0
                ? TransferFormatter.bytes(totalByteCount)
                : "—"
            uploadSpeed = TransferFormatter.speed(item.uploadSpeedValue)
            connectionCount = String(item.connectionCount)
            path = displayPath.isEmpty ? "—" : displayPath
            source = sourceURI.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
            gid = item.gid
            isBitTorrent = item.bittorrent != nil
                || source.lowercased().hasPrefix("magnet:")
            seederCount = String(item.seederCount)
            if let sourceURI,
               let scheme = URL(string: sourceURI)?.scheme?.lowercased(),
               ["http", "https", "ftp", "ftps"].contains(scheme) {
                httpFTPSource = sourceURI
            } else {
                httpFTPSource = nil
            }
        }
    }
}

@MainActor
private final class TaskInspectorSettingsModel: ObservableObject {
    @Published private(set) var downloadThreads = "—"
    @Published private(set) var minimumSplitSize = "—"
    @Published private(set) var priority = L10n.string("普通")

    private var loadedGID: String?

    func load(item: TransferItem, store: DownloadStore) async {
        guard loadedGID != item.gid else { return }
        loadedGID = item.gid
        downloadThreads = "—"
        minimumSplitSize = "—"
        priority = L10n.string("普通")

        guard let options = await store.taskOptions(for: item) else {
            loadedGID = nil
            return
        }

        if let split = options["split"]?.trimmed, !split.isEmpty {
            downloadThreads = split
        }
        minimumSplitSize = Self.formattedSize(options["min-split-size"])
    }

    private static func formattedSize(_ rawValue: String?) -> String {
        guard let rawValue = rawValue?.trimmed, !rawValue.isEmpty else {
            return "—"
        }

        let uppercased = rawValue.uppercased()
        let suffix = uppercased.last
        let multipliers: [Character: Double] = [
            "K": 1_024,
            "M": 1_048_576,
            "G": 1_073_741_824,
            "T": 1_099_511_627_776,
        ]

        let byteCount: Double?
        if let suffix, let multiplier = multipliers[suffix] {
            byteCount = Double(uppercased.dropLast()).map { $0 * multiplier }
        } else {
            byteCount = Double(uppercased)
        }

        guard let byteCount, byteCount.isFinite, byteCount >= 0 else {
            return rawValue
        }

        return String(
            format: "%.2f MB",
            locale: Locale(identifier: "en_US_POSIX"),
            byteCount / 1_048_576
        )
    }
}

private struct TransferInspectorDisclosureCard<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool

    private let content: Content

    init(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(LaneFont.interface(11, weight: .semibold))
                        .foregroundStyle(LaneColor.label1)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                isExpanded ? L10n.string("已展开") : L10n.string("已收起")
            )

            if isExpanded {
                content
                    .padding(.top, 11)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LaneColor.fill1,
            in: RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
                .stroke(LaneColor.line, lineWidth: 1)
        }
    }
}

private struct NativeTransferFileIcon: View {
    let path: String

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "doc.fill")
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .frame(width: 52, height: 58)
        .accessibilityHidden(true)
        .task(id: path) {
            let pathExtension = URL(fileURLWithPath: path).pathExtension
            let contentType = UTType(filenameExtension: pathExtension) ?? .data
            let workspaceIcon = NSWorkspace.shared.icon(for: contentType)
            let resolvedIcon = (workspaceIcon.copy() as? NSImage) ?? workspaceIcon
            resolvedIcon.size = NSSize(width: 52, height: 52)
            icon = resolvedIcon
        }
    }
}

private struct TransferInspectorMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(LaneFont.interface(9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Text(value)
                .font(LaneFont.interface(12, weight: .medium))
                .foregroundStyle(LaneColor.label1)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TransferInspectorConnectionMetric: View {
    let label: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(LaneFont.interface(8.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(value)
                    .font(LaneFont.interface(10.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TransferInspectorInfoBlock: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(LaneFont.interface(9.5))
                .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(LaneFont.utility(9, weight: .regular))
                    .foregroundStyle(LaneColor.label1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(value)

                Spacer(minLength: 4)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .medium))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(value == "—")
                .help(L10n.string("复制"))
                .accessibilityLabel(L10n.string("复制"))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(LaneColor.fill1, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(LaneColor.line, lineWidth: 1)
            }
        }
    }
}

private extension View {
    func transferInspectorCard() -> some View {
        background(
            LaneColor.fill1,
            in: RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
                .stroke(LaneColor.line, lineWidth: 1)
        }
    }
}

struct TaskInspectorCloseButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? LaneColor.label1 : LaneColor.label2)
        .background(
            LaneColor.fill1,
            in: Circle()
        )
        .overlay {
            Circle()
                .stroke(LaneColor.line, lineWidth: 1)
        }
        .onHover { isHovering = $0 }
        .help(L10n.string("关闭任务详情"))
        .accessibilityLabel(L10n.string("关闭任务详情"))
        .accessibilityHint(L10n.string("关闭右侧的任务详情面板"))
    }
}
