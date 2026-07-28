import AppKit
import Charts
import SwiftUI

struct MenuBarStatusLabel: View {
    let downloadSpeed: Int64
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 3) {
            MenuBarLaneMark(isConnected: isConnected)

            if downloadSpeed > 0 {
                Text(TransferFormatter.speed(downloadSpeed))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityTitle)
    }

    private var accessibilityTitle: String {
        guard isConnected else { return L10n.string("AriaLane 未连接") }
        guard downloadSpeed > 0 else { return L10n.string("AriaLane 已连接") }
        return L10n.string("AriaLane 下载速度 \(TransferFormatter.speed(downloadSpeed))")
    }
}

private struct MenuBarLaneMark: View {
    let isConnected: Bool

    var body: some View {
        Image(nsImage: isConnected ? Self.connectedImage : Self.disconnectedImage)
            .renderingMode(.template)
            .frame(width: 15, height: 15)
            .accessibilityHidden(true)
    }

    private static let connectedImage = makeImage(isConnected: true)
    private static let disconnectedImage = makeImage(isConnected: false)

    private static func makeImage(isConnected: Bool) -> NSImage {
        let size = NSSize(width: 15, height: 15)
        let image = NSImage(size: size, flipped: false) { bounds in
            let barWidth: CGFloat = 2.5
            let spacing: CGFloat = 1.5
            let barHeights: [CGFloat] = [8.5, 12, 6.5]
            let contentWidth = barWidth * 3 + spacing * 2
            let startX = bounds.midX - contentWidth / 2
            let barColor = NSColor.black.withAlphaComponent(isConnected ? 1 : 0.48)

            barColor.setFill()
            for (index, height) in barHeights.enumerated() {
                let barRect = NSRect(
                    x: startX + CGFloat(index) * (barWidth + spacing),
                    y: bounds.midY - height / 2,
                    width: barWidth,
                    height: height
                )
                NSBezierPath(
                    roundedRect: barRect,
                    xRadius: barWidth / 2,
                    yRadius: barWidth / 2
                )
                .fill()
            }

            if !isConnected {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: bounds.minX + 2.5, y: bounds.maxY - 2.5))
                slash.line(to: NSPoint(x: bounds.maxX - 2.5, y: bounds.minY + 2.5))
                slash.lineWidth = 1.25
                slash.lineCapStyle = .round
                NSColor.black.withAlphaComponent(0.82).setStroke()
                slash.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarMiniView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore

    private let quickLimits = [0, 1_024, 5_120, 10_240, 20_480]

    var body: some View {
        selectedPanel
            .padding(panelPadding)
            .frame(width: panelWidth)
            .background {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    LaneColor.mint.opacity(0.035)
                }
            }
            .tint(LaneColor.accent)
    }

    @ViewBuilder
    private var selectedPanel: some View {
        switch preferences.menuBarPanelStyle {
        case .adaptive:
            adaptivePanel
        case .compact:
            compactPanel
        }
    }

    private var adaptivePanel: some View {
        VStack(spacing: 12) {
            identityHeader(compact: false)

            Divider()
                .opacity(0.65)

            adaptiveContent
        }
    }

    private var compactPanel: some View {
        VStack(spacing: 10) {
            identityHeader(compact: true)

            MenuBarSpeedSummary(
                downloadSpeed: store.globalStats.downloadSpeedValue,
                uploadSpeed: store.globalStats.uploadSpeedValue
            )

            compactPrimaryAction

            HStack(spacing: 8) {
                speedLimitMenu(filled: false)
                openMainWindowLink
            }
            .controlSize(.small)
        }
    }

    private func identityHeader(compact: Bool) -> some View {
        HStack(spacing: compact ? 9 : 10) {
            FlowMark(size: compact ? 24 : 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("AriaLane")
                    .font(LaneFont.label(compact ? 12 : 13))

                HStack(spacing: 5) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 6, height: 6)
                    Text("\(preferences.activeServerProfileName) · \(connectionShortTitle)")
                        .font(.system(size: compact ? 8.5 : 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                Task {
                    if store.connectionState.isConnected {
                        await store.refresh()
                    } else {
                        await store.reconnect()
                    }
                }
            } label: {
                Image(
                    systemName: store.connectionState.isConnected
                        ? "arrow.clockwise"
                        : "bolt.horizontal.circle"
                )
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(isConnecting)
            .help(store.connectionState.isConnected ? L10n.string("刷新任务") : L10n.string("重新连接 aria2"))
        }
    }

    @ViewBuilder
    private var adaptiveContent: some View {
        if case .failed(let message) = store.connectionState {
            VStack(spacing: 12) {
                connectionFailureSection(message: message)

                Divider()
                    .opacity(0.65)

                openMainWindowLink
            }
        } else if !store.connectionState.isConnected {
            VStack(spacing: 12) {
                connectionPendingSection

                Divider()
                    .opacity(0.65)

                openMainWindowLink
            }
        } else if currentTransfers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.string("传输状态"))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)

                MenuBarSpeedLine(
                    downloadSpeed: store.globalStats.downloadSpeedValue,
                    uploadSpeed: store.globalStats.uploadSpeedValue
                )

                readyState

                adaptiveIdleControls
            }
        } else {
            VStack(spacing: 12) {
                if preferences.showSpeedTrend {
                    MiniSpeedPulse(
                        samples: Array(store.speedSamples.suffix(50)),
                        downloadSpeed: store.globalStats.downloadSpeedValue,
                        uploadSpeed: store.globalStats.uploadSpeedValue
                    )
                } else {
                    MenuBarSpeedSummary(
                        downloadSpeed: store.globalStats.downloadSpeedValue,
                        uploadSpeed: store.globalStats.uploadSpeedValue
                    )
                }

                Divider()
                    .opacity(0.65)

                activeTaskSection

                Divider()
                    .opacity(0.65)

                adaptiveActiveControls
            }
        }
    }

    private var activeTaskSection: some View {
        VStack(spacing: 5) {
            HStack {
                Text(L10n.string("当前任务"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if remainingTaskCount > 0 {
                    Button(L10n.string("还有 \(remainingTaskCount) 个")) {
                        showMainWindow()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundStyle(LaneColor.accent)
                }
            }
            .padding(.bottom, 2)

            ForEach(currentTransfers) { item in
                MenuBarTransferRow(
                    item: item,
                    onOpen: { showMainWindow(selecting: item.gid) },
                    onPrimaryAction: { performPrimaryAction(for: item) }
                )
            }
        }
    }

    private var readyState: some View {
        HStack(spacing: 13) {
            MenuBarIdleGlyph()

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("已连接，等待任务"))
                    .font(LaneFont.label(11))
                Text(L10n.string("空闲时不显示多余图表"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
                .fill(LaneColor.mint.opacity(0.075))
        }
    }

    private func connectionFailureSection(message: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(LaneColor.danger)

            VStack(spacing: 3) {
                Text(L10n.string("无法连接 aria2"))
                    .font(LaneFont.label(12))
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            reconnectButton
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var connectionPendingSection: some View {
        VStack(spacing: 9) {
            if isConnecting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
            }

            Text(isConnecting ? L10n.string("正在连接 aria2…") : L10n.string("尚未连接 aria2"))
                .font(LaneFont.label(11))

            if !isConnecting {
                reconnectButton
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var adaptiveIdleControls: some View {
        VStack(spacing: 8) {
            addDownloadButton

            HStack(spacing: 8) {
                speedLimitMenu(filled: true)
                openMainWindowLink
            }
        }
        .controlSize(.small)
    }

    private var adaptiveActiveControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                bulkControlButton
                speedLimitMenu(filled: true)
            }

            addDownloadButton
            openMainWindowLink
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var compactPrimaryAction: some View {
        if store.connectionState.isConnected {
            addDownloadButton
                .controlSize(.small)
        } else if isConnecting {
            Button {} label: {
                Label(L10n.string("正在连接…"), systemImage: "hourglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MenuBarPrimaryButtonStyle())
            .controlSize(.small)
            .disabled(true)
            .opacity(0.5)
        } else {
            reconnectButton
                .controlSize(.small)
        }
    }

    private var bulkControlButton: some View {
        Button {
            Task {
                if hasPausableTransfers {
                    await store.pauseAll()
                } else {
                    await store.resumeAll()
                }
            }
        } label: {
            Label(
                hasPausableTransfers ? L10n.string("暂停全部") : L10n.string("继续全部"),
                systemImage: hasPausableTransfers ? "pause.fill" : "play.fill"
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
        }
        .buttonStyle(.plain)
        .disabled(!hasBulkAction || store.isPerformingAction)
    }

    private func speedLimitMenu(filled: Bool) -> some View {
        Menu {
            ForEach(quickLimits, id: \.self) { limit in
                Button {
                    Task { await store.setQuickDownloadLimit(limit) }
                } label: {
                    if preferences.maxOverallDownloadLimitKiB == limit {
                        Label(
                            TransferFormatter.speedLimit(limit),
                            systemImage: "checkmark"
                        )
                    } else {
                        Text(TransferFormatter.speedLimit(limit))
                    }
                }
            }
        } label: {
            Label(
                compactLimitTitle,
                systemImage: "clock"
            )
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.primary)
            .frame(
                maxWidth: .infinity,
                alignment: filled ? .center : .leading
            )
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(filled ? 0.05 : 0))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .disabled(store.settingsApplyState == .applying)
    }

    private var addDownloadButton: some View {
        Button {
            showMainWindow(andPost: .ariaLaneAddDownload)
        } label: {
            Label(L10n.string("添加下载"), systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MenuBarPrimaryButtonStyle())
    }

    private var reconnectButton: some View {
        Button {
            Task { await store.reconnect() }
        } label: {
            Label(L10n.string("重新连接"), systemImage: "bolt.horizontal.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MenuBarPrimaryButtonStyle())
        .disabled(isConnecting)
    }

    private var openMainWindowLink: some View {
        Button {
            showMainWindow()
        } label: {
            HStack(spacing: 5) {
                Text(L10n.string("打开主窗口"))
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(LaneColor.accent)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(.plain)
    }

    private var panelWidth: CGFloat {
        preferences.menuBarPanelStyle == .adaptive ? 340 : 300
    }

    private var panelPadding: CGFloat {
        preferences.menuBarPanelStyle == .adaptive ? 14 : 12
    }

    private var currentTransfers: [TransferItem] {
        Array(
            store.transfers
                .filter {
                    switch $0.status {
                    case .active, .waiting, .paused, .error:
                        true
                    case .complete, .removed:
                        false
                    }
                }
                .prefix(4)
        )
    }

    private var remainingTaskCount: Int {
        let total = store.transfers.filter {
            $0.status != .complete && $0.status != .removed
        }.count
        return max(total - currentTransfers.count, 0)
    }

    private var hasPausableTransfers: Bool {
        store.transfers.contains(where: \.isPausable)
    }

    private var hasBulkAction: Bool {
        store.transfers.contains {
            $0.isPausable || $0.isResumable
        }
    }

    private var compactLimitTitle: String {
        let limit = preferences.maxOverallDownloadLimitKiB
        return limit == 0 ? L10n.string("不限速") : TransferFormatter.speedLimit(limit)
    }

    private var connectionShortTitle: String {
        switch store.connectionState {
        case .idle: L10n.string("尚未连接")
        case .connecting: L10n.string("正在连接")
        case .connected: L10n.string("已连接")
        case .failed: L10n.string("连接中断")
        }
    }

    private var isConnecting: Bool {
        if case .connecting = store.connectionState {
            return true
        }
        return false
    }

    private var connectionColor: Color {
        switch store.connectionState {
        case .idle: .secondary
        case .connecting: LaneColor.amber
        case .connected: LaneColor.mint
        case .failed: LaneColor.danger
        }
    }

    private func performPrimaryAction(for item: TransferItem) {
        Task {
            if item.isPausable {
                await store.pause(item)
            } else if item.isResumable {
                await store.resume(item)
            } else if item.isRetryable {
                await store.retry(item)
            }
        }
    }

    private func showMainWindow(
        selecting gid: String? = nil,
        andPost notification: Notification.Name? = nil
    ) {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)

        guard gid != nil || notification != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if let gid {
                NotificationCenter.default.post(
                    name: .ariaLaneSelectTransfer,
                    object: gid
                )
            }
            if let notification {
                NotificationCenter.default.post(name: notification, object: nil)
            }
        }
    }
}

private struct MenuBarPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LaneColor.accent.opacity(
                            configuration.isPressed ? 0.82 : 1
                        )
                    )
            }
    }
}

private struct MenuBarTransferRow: View {
    let item: TransferItem
    let onOpen: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Text(shortTitle)
                            .font(LaneFont.label(11))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        Text(trailingDetail)
                            .font(LaneFont.utility(9, weight: .regular))
                            .foregroundStyle(detailColor)
                    }

                    SegmentedProgressView(
                        progress: item.progress,
                        status: item.status,
                        height: 4
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.isPausable || item.isResumable || item.isRetryable {
                Button(action: onPrimaryAction) {
                    Image(systemName: primaryActionImage)
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help(primaryActionTitle)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.74))
                .overlay {
                    RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
                        .stroke(LaneColor.line, lineWidth: 1)
                }
        }
    }

    private var shortTitle: String {
        guard item.displayName.count > 30 else { return item.displayName }
        return String(item.displayName.prefix(27)) + "…"
    }

    private var trailingDetail: String {
        if item.status == .active {
            return TransferFormatter.speed(item.downloadSpeedValue)
        }
        if item.status == .error {
            return L10n.string("需要处理")
        }
        return item.status.title
    }

    private var detailColor: Color {
        switch item.status {
        case .active: LaneColor.accent
        case .waiting: LaneColor.amber
        case .error: LaneColor.danger
        case .paused, .complete, .removed: .secondary
        }
    }

    private var primaryActionImage: String {
        if item.isPausable { return "pause.fill" }
        if item.isResumable { return "play.fill" }
        return "arrow.clockwise"
    }

    private var primaryActionTitle: String {
        if item.isPausable { return L10n.string("暂停") }
        if item.isResumable { return L10n.string("继续") }
        return L10n.string("重新下载")
    }
}

private struct MenuBarIdleGlyph: View {
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            Capsule()
                .frame(width: 4, height: 20)
            Capsule()
                .frame(width: 4, height: 30)
            Capsule()
                .frame(width: 4, height: 15)
        }
        .foregroundStyle(.secondary)
        .frame(width: 24, height: 32)
        .accessibilityHidden(true)
    }
}

private struct MenuBarSpeedLine: View {
    let downloadSpeed: Int64
    let uploadSpeed: Int64

    var body: some View {
        HStack {
            speedValue(
                icon: "arrow.down",
                label: L10n.string("下载"),
                value: downloadSpeed,
                color: LaneColor.accent
            )

            Spacer()

            speedValue(
                icon: "arrow.up",
                label: L10n.string("上传"),
                value: uploadSpeed,
                color: LaneColor.mint
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("当前传输速度"))
        .accessibilityValue(
            L10n.string("下载 \(TransferFormatter.speed(downloadSpeed))，上传 \(TransferFormatter.speed(uploadSpeed))")
        )
    }

    private func speedValue(
        icon: String,
        label: String,
        value: Int64,
        color: Color
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            Text(TransferFormatter.speed(value))
                .font(LaneFont.utility(10))
                .contentTransition(.numericText())
        }
    }
}

private struct MenuBarSpeedSummary: View {
    let downloadSpeed: Int64
    let uploadSpeed: Int64

    var body: some View {
        HStack {
            speedValue(
                icon: "arrow.down",
                label: L10n.string("下载"),
                value: downloadSpeed,
                color: LaneColor.accent
            )

            Spacer()

            speedValue(
                icon: "arrow.up",
                label: L10n.string("上传"),
                value: uploadSpeed,
                color: LaneColor.mint
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
                .fill(LaneColor.mint.opacity(0.055))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("当前传输速度"))
        .accessibilityValue(
            L10n.string("下载 \(TransferFormatter.speed(downloadSpeed))，上传 \(TransferFormatter.speed(uploadSpeed))")
        )
    }

    private func speedValue(
        icon: String,
        label: String,
        value: Int64,
        color: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            Text(TransferFormatter.speed(value))
                .font(LaneFont.utility(10))
                .contentTransition(.numericText())
        }
    }
}

private struct MiniSpeedPulse: View {
    let samples: [SpeedSample]
    let downloadSpeed: Int64
    let uploadSpeed: Int64

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                speedValue(
                    icon: "arrow.down",
                    label: L10n.string("下载"),
                    value: downloadSpeed,
                    color: LaneColor.accent
                )

                Spacer()

                speedValue(
                    icon: "arrow.up",
                    label: L10n.string("上传"),
                    value: uploadSpeed,
                    color: LaneColor.mint
                )
            }

            Chart {
                RuleMark(y: .value(L10n.string("基线"), 0))
                    .foregroundStyle(Color.primary.opacity(0.07))

                ForEach(samples) { sample in
                    AreaMark(
                        x: .value(L10n.string("时间"), sample.timestamp),
                        yStart: .value(L10n.string("基线"), 0),
                        yEnd: .value(L10n.string("下载"), sample.downloadBytesPerSecond)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                LaneColor.accent.opacity(0.18),
                                LaneColor.accent.opacity(0.01)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                ForEach(samples) { sample in
                    LineMark(
                        x: .value(L10n.string("时间"), sample.timestamp),
                        y: .value(L10n.string("下载"), sample.downloadBytesPerSecond)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LaneColor.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }

                ForEach(samples) { sample in
                    LineMark(
                        x: .value(L10n.string("时间"), sample.timestamp),
                        y: .value(L10n.string("上传"), sample.uploadBytesPerSecond)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LaneColor.mint)
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 1.1,
                            lineCap: .round,
                            dash: [3, 3]
                        )
                    )
                }
            }
            .chartXScale(domain: chartStart...chartEnd)
            .chartYScale(domain: 0...chartMaximum)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 34)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.74))
                .overlay {
                    RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
                        .stroke(LaneColor.line, lineWidth: 1)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("当前传输速度"))
        .accessibilityValue(
            L10n.string("下载 \(TransferFormatter.speed(downloadSpeed))，上传 \(TransferFormatter.speed(uploadSpeed))")
        )
    }

    private func speedValue(
        icon: String,
        label: String,
        value: Int64,
        color: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            Text(TransferFormatter.speed(value))
                .font(LaneFont.utility(10))
                .contentTransition(.numericText())
        }
    }

    private var chartEnd: Date {
        samples.last?.timestamp ?? Date()
    }

    private var chartStart: Date {
        chartEnd.addingTimeInterval(-65)
    }

    private var chartMaximum: Int64 {
        let maximum = samples.reduce(Int64(0)) {
            max($0, $1.downloadBytesPerSecond, $1.uploadBytesPerSecond)
        }
        return max(Int64(Double(maximum) * 1.12), 1)
    }
}
