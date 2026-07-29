import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case speed
    case network
    case advanced
    case connection
    case about

    static let preferenceKey = "settingsSelectedPane"

    var id: String { rawValue }

    func select(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }

    var title: String {
        switch self {
        case .general: L10n.string("通用")
        case .speed: L10n.string("速度")
        case .network: L10n.string("网络")
        case .advanced: L10n.string("高级")
        case .connection: L10n.string("连接")
        case .about: L10n.string("关于")
        }
    }

    var detail: String {
        switch self {
        case .general: L10n.string("应用行为与文件")
        case .speed: L10n.string("限速、趋势与调度")
        case .network: L10n.string("分段、重试与 BT")
        case .advanced: L10n.string("代理、TLS 与协议细节")
        case .connection: L10n.string("服务器与连接诊断")
        case .about: L10n.string("版本与版权信息")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .speed: "gauge.with.dots.needle.67percent"
        case .network: "network"
        case .advanced: "slider.horizontal.3"
        case .connection: "point.3.connected.trianglepath.dotted"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @AppStorage(SettingsPane.preferenceKey) private var selectedPane = "general"

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 218)

            Divider()
                .opacity(0.65)

            VStack(spacing: 0) {
                settingsHeader

                Divider()
                    .opacity(0.65)

                selectedPaneContent
                    .scrollContentBackground(.hidden)
                    .background(LaneColor.canvas)
            }
        }
        .frame(width: 860, height: 620)
        .background(LaneColor.canvas)
        .background {
            WindowFrameAutosaveConfigurator(
                autosaveName: "AriaLane.SettingsWindow"
            )
            .frame(width: 0, height: 0)
        }
        .tint(LaneColor.accent)
        .keychainPersistenceAlert(preferences: preferences)
    }

    private var activePane: SettingsPane {
        SettingsPane(rawValue: selectedPane) ?? .general
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                FlowMark(size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AriaLane")
                        .font(LaneFont.display(17))
                    Text(L10n.string("设置"))
                        .font(LaneFont.interface(10))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 6) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        selectedPane = pane.rawValue
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: pane.systemImage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(
                                    activePane == pane
                                        ? LaneColor.accent
                                        : .secondary
                                )
                                .frame(width: 28, height: 28)
                                .background(
                                    activePane == pane
                                        ? LaneColor.accent.opacity(0.10)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pane.title)
                                    .font(
                                        LaneFont.interface(
                                            12,
                                            weight: .semibold
                                        )
                                    )
                                Text(pane.detail)
                                    .font(LaneFont.interface(9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 52)
                        .background(
                            activePane == pane
                                ? LaneColor.accent.opacity(0.085)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                        .contentShape(
                            RoundedRectangle(cornerRadius: 11)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            if activePane == .about {
                Label("Copyright © 2026 rinran", systemImage: "c.circle")
                    .font(LaneFont.interface(10))
                    .foregroundStyle(.secondary)
            } else {
                Label(L10n.string("修改会自动保存"), systemImage: "checkmark.circle")
                    .font(LaneFont.interface(10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(LaneColor.fill1)
    }

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: activePane.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LaneColor.accent)
                .frame(width: 38, height: 38)
                .background(
                    LaneColor.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(activePane.title)
                    .font(LaneFont.display(21))
                Text(activePane.detail)
                    .font(LaneFont.interface(11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .frame(height: 78)
        .background(LaneColor.surface)
    }

    @ViewBuilder
    private var selectedPaneContent: some View {
        switch activePane {
        case .general:
            GeneralSettingsPane()
        case .speed:
            SpeedSettingsPane()
        case .network:
            NetworkSettingsPane()
        case .advanced:
            AdvancedAria2SettingsPane()
        case .connection:
            ConnectionSettingsPane()
        case .about:
            AboutSettingsPane()
        }
    }
}

private struct AboutSettingsPane: View {
    private let author = "rinran"
    private let email = "a@rinran.me"
    private let xHandle = "@rinran223"

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 28)

            VStack(spacing: 13) {
                FlowMark(size: 72)
                    .shadow(color: LaneColor.accent.opacity(0.12), radius: 18, y: 8)

                VStack(spacing: 5) {
                    Text("AriaLane")
                        .font(LaneFont.display(28))

                    Text(L10n.string("轻盈、清晰的 aria2 下载管理器"))
                        .font(LaneFont.interface(11))
                        .foregroundStyle(.secondary)
                }

                Text(versionTitle)
                    .font(LaneFont.utility(10, weight: .medium))
                    .foregroundStyle(LaneColor.accent)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(
                        LaneColor.accent.opacity(0.09),
                        in: Capsule()
                    )
            }

            VStack(spacing: 0) {
                aboutRow(title: L10n.string("作者"), value: author)

                Divider()
                    .padding(.horizontal, 16)

                HStack(spacing: 16) {
                    Text(L10n.string("联系邮箱"))
                        .font(LaneFont.interface(11, weight: .medium))
                        .foregroundStyle(LaneColor.label2)

                    Spacer()

                    Link(email, destination: mailURL)
                        .font(LaneFont.utility(10, weight: .medium))
                        .foregroundStyle(LaneColor.accent)
                }
                .padding(.horizontal, 16)
                .frame(height: 46)

                Divider()
                    .padding(.horizontal, 16)

                HStack(spacing: 16) {
                    XLogo(size: 12)
                        .foregroundStyle(LaneColor.label2)
                        .accessibilityLabel("X")

                    Spacer()

                    Link(xHandle, destination: xURL)
                        .font(LaneFont.utility(10, weight: .medium))
                        .foregroundStyle(LaneColor.accent)
                }
                .padding(.horizontal, 16)
                .frame(height: 46)

                Divider()
                    .padding(.horizontal, 16)

                aboutRow(
                    title: L10n.string("版权"),
                    value: "Copyright © 2026 rinran (a@rinran.me)"
                )

                Divider()
                    .padding(.horizontal, 16)

                aboutRow(title: L10n.string("开源许可"), value: "GPL-3.0-only")
            }
            .frame(maxWidth: 430)
            .background(
                LaneColor.surface,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(LaneColor.line, lineWidth: 1)
            }

            Text(L10n.string("感谢使用 AriaLane"))
                .font(LaneFont.interface(10))
                .foregroundStyle(.secondary)

            Spacer(minLength: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .background(LaneColor.canvas)
    }

    private var versionTitle: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? L10n.string("开发版")
        return L10n.string("版本 \(version)")
    }

    private var mailURL: URL {
        URL(string: "mailto:\(email)")!
    }

    private var xURL: URL {
        URL(string: "https://x.com/rinran223")!
    }

    private func aboutRow(title: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(LaneFont.interface(11, weight: .medium))
                .foregroundStyle(LaneColor.label2)

            Spacer()

            Text(value)
                .font(LaneFont.interface(11, weight: .medium))
                .foregroundStyle(LaneColor.label1)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore
    @EnvironmentObject private var updateService: AppUpdateService
    @StateObject private var launchAtLogin = LaunchAtLoginService()

    var body: some View {
        Form {
            Section(L10n.string("语言")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("应用语言"))
                        Text(preferences.appLanguage.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker(L10n.string("应用语言"), selection: $preferences.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title)
                                .tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            Section(L10n.string("菜单栏面板")) {
                HStack(spacing: 12) {
                    ForEach(MenuBarPanelStyle.allCases) { style in
                        panelStyleChoice(style)
                    }
                }
            }

            Section(L10n.string("下载位置")) {
                HStack(spacing: 10) {
                    TextField(L10n.string("文件夹"), text: $preferences.downloadDirectory)
                        .font(LaneFont.utility(11, weight: .regular))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(
                            LaneColor.fill1,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    Button(L10n.string("选择…")) {
                        chooseDirectory()
                    }
                    .controlSize(.large)
                }

                Text(L10n.string("只影响新任务；已经添加的任务不会移动。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("磁盘与文件")) {
                HStack {
                    Text(L10n.string("文件分配"))
                    Spacer()
                    SettingsSelectionMenu(
                        selection: $preferences.fileAllocation,
                        options: FileAllocationMethod.allCases,
                        value: \.self,
                        title: \.title,
                        accessibilityLabel: L10n.string("文件分配")
                    )
                }

                Text(preferences.fileAllocation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(L10n.string("继续未完成的下载"), isOn: $preferences.continueDownloads)
                Toggle(L10n.string("文件重名时自动改名"), isOn: $preferences.autoFileRenaming)
                Toggle(L10n.string("保留服务器文件时间"), isOn: $preferences.preserveRemoteTime)
                Toggle(L10n.string("允许覆盖已有文件"), isOn: $preferences.allowOverwrite)
            }

            Section(L10n.string("本机 aria2")) {
                Toggle(
                    L10n.string("连接失败时自动启动本机 aria2"),
                    isOn: $preferences.autoStartLocalAria2
                )

                Text(L10n.string("自动启动需要通过 Homebrew 安装 aria2；会话记录每 30 秒保存一次。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("启动")) {
                Toggle(
                    L10n.string("登录 Mac 后自动启动 AriaLane"),
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )

                launchAtLoginStatus
            }

            Section(L10n.string("电源")) {
                Toggle(
                    L10n.string("下载时防止 Mac 自动休眠"),
                    isOn: $preferences.preventSystemSleepDuringDownloads
                )

                if store.isPreventingSystemSleep {
                    Label(L10n.string("有任务正在下载，Mac 将保持唤醒"), systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(LaneColor.mint)
                } else {
                    Text(L10n.string("仅阻止系统自动休眠，不影响显示器按系统设置关闭。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.string("软件更新")) {
                if updateService.isConfigured {
                    Toggle(
                        L10n.string("自动检查更新"),
                        isOn: Binding(
                            get: { updateService.automaticallyChecksForUpdates },
                            set: { updateService.automaticallyChecksForUpdates = $0 }
                        )
                    )
                    Toggle(
                        L10n.string("自动下载可用更新"),
                        isOn: Binding(
                            get: { updateService.automaticallyDownloadsUpdates },
                            set: { updateService.automaticallyDownloadsUpdates = $0 }
                        )
                    )

                    HStack {
                        Text(L10n.string("更新包会验证 Developer ID 与 Ed25519 签名。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.string("检查更新…")) {
                            updateService.checkForUpdates()
                        }
                        .disabled(!updateService.canCheckForUpdates)
                    }
                } else {
                    Label(
                        L10n.string("当前开发构建未配置更新源"),
                        systemImage: "shippingbox"
                    )
                    .foregroundStyle(.secondary)
                    Text(L10n.string("正式发布时注入 Sparkle Feed URL 与公钥后自动启用。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.string("通知")) {
                Toggle(
                    L10n.string("下载完成或失败时显示 macOS 通知"),
                    isOn: $preferences.notificationsEnabled
                )
                notificationPermissionLabel
            }

            SettingsActionFooter()
        }
        .formStyle(.grouped)
        .onChange(of: preferences.notificationsEnabled) { _, isEnabled in
            Task { await store.prepareNotifications(enabled: isEnabled) }
        }
        .onChange(of: preferences.preventSystemSleepDuringDownloads) { _, _ in
            store.refreshPowerAssertion()
        }
        .onAppear {
            launchAtLogin.refresh()
        }
    }

    private func panelStyleChoice(_ style: MenuBarPanelStyle) -> some View {
        let isSelected = preferences.menuBarPanelStyle == style

        return Button {
            preferences.menuBarPanelStyle = style
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: style.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        isSelected ? LaneColor.accent : LaneColor.label2
                    )
                    .frame(width: 32, height: 32)
                    .background(
                        isSelected
                            ? LaneColor.accent.opacity(0.11)
                            : LaneColor.fill1,
                        in: RoundedRectangle(cornerRadius: 9)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(style.title)
                        .font(LaneFont.interface(12, weight: .semibold))
                        .foregroundStyle(LaneColor.label1)
                    Text(style.detail)
                        .font(LaneFont.interface(9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        isSelected ? LaneColor.accent : LaneColor.label2.opacity(0.7)
                    )
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(
                isSelected
                    ? LaneColor.accent.opacity(0.075)
                    : LaneColor.surface,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected
                            ? LaneColor.accent.opacity(0.42)
                            : LaneColor.line,
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.title)，\(style.detail)")
        .accessibilityValue(isSelected ? L10n.string("已选择") : L10n.string("未选择"))
    }

    @ViewBuilder
    private var launchAtLoginStatus: some View {
        switch launchAtLogin.state {
        case .enabled:
            Label(L10n.string("已加入系统登录项"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(LaneColor.mint)
        case .disabled:
            Text(L10n.string("关闭主窗口后仍可通过菜单栏查看；退出应用后不会在后台运行。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .requiresApproval:
            HStack {
                Label(L10n.string("需要在系统设置中允许"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(LaneColor.amber)
                Spacer()
                Button(L10n.string("打开登录项设置")) {
                    launchAtLogin.openSystemSettings()
                }
            }
        case .unavailable:
            Text(L10n.string("当前构建无法注册登录项；打包成正式 .app 后可用。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(LaneColor.danger)
        }
    }

    @ViewBuilder
    private var notificationPermissionLabel: some View {
        switch store.notificationPermissionState {
        case .disabled:
            Text(L10n.string("通知已在 AriaLane 中关闭"))
                .foregroundStyle(.secondary)
        case .requesting:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string("正在请求系统权限…"))
            }
        case .allowed:
            HStack {
                Label(L10n.string("macOS 通知已允许"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(LaneColor.mint)
                Spacer()
                Button(L10n.string("发送测试通知")) {
                    Task { await store.sendTestNotification() }
                }
            }
        case .denied:
            HStack {
                Label(L10n.string("通知被系统关闭"), systemImage: "bell.slash.fill")
                    .foregroundStyle(LaneColor.amber)
                Spacer()
                Button(L10n.string("打开系统设置")) {
                    openNotificationSettings()
                }
            }
        case .unavailable:
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    L10n.string("当前构建未获系统通知资格"),
                    systemImage: "signature"
                )
                .foregroundStyle(LaneColor.amber)
                Text(L10n.string("使用 Apple Development 或 Developer ID 签名后即可启用；应用内完成与失败提示仍然有效。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(L10n.string("无法启用系统通知"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(LaneColor.danger)
                .help(message)
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("选择下载文件夹")
        panel.prompt = L10n.string("选择")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: preferences.downloadDirectory)

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                preferences.downloadDirectory = url.path
            }
        }
    }
}

private struct ConnectionSettingsPane: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore
    @State private var isShowingShutdownConfirmation = false
    @State private var forceShutdown = false

    var body: some View {
        Form {
            Section(L10n.string("服务器配置")) {
                HStack(spacing: 8) {
                    Text(L10n.string("当前服务器"))

                    Spacer()

                    SettingsSelectionMenu(
                        selection: activeProfileBinding,
                        options: preferences.serverProfiles,
                        value: \.id,
                        title: \.displayName,
                        accessibilityLabel: L10n.string("当前服务器")
                    )

                    Button {
                        _ = preferences.addServerProfile()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help(L10n.string("添加服务器配置"))

                    Button(role: .destructive) {
                        guard let id = preferences.activeServerProfileID else { return }
                        preferences.removeServerProfile(id: id)
                        Task { await store.reconnect() }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(preferences.serverProfiles.count <= 1)
                    .help(L10n.string("删除当前服务器配置"))
                }

                TextField(L10n.string("配置名称"), text: activeProfileNameBinding)
            }

            Section(L10n.string("当前服务器")) {
                TextField(L10n.string("RPC 地址"), text: $preferences.endpoint)
                    .font(LaneFont.utility(11, weight: .regular))

                SecureField(L10n.string("RPC 密钥（可选）"), text: $preferences.rpcSecret)

                Text(
                    L10n.string("支持 HTTP(S) 与 WS(S) 地址；WebSocket 用于接收实时事件。")
                        + " "
                        + L10n.string("密钥写入后会立即回读校验，并保存在 macOS 钥匙串。")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("连接状态")) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.connectionState.title)
                            .font(.system(size: 12, weight: .medium))
                        if let detail = store.connectionState.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if case .connecting = store.connectionState {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                HStack(spacing: 10) {
                    Image(
                        systemName: store.eventStreamState.isConnected
                            ? "bolt.horizontal.circle.fill"
                            : "bolt.horizontal.circle"
                    )
                    .foregroundStyle(
                        store.eventStreamState.isConnected
                            ? LaneColor.mint
                            : Color.secondary
                    )
                    .frame(width: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.eventStreamState.title)
                            .font(.system(size: 12, weight: .medium))
                        Text(eventStreamDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if store.eventStreamState == .connecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section(L10n.string("连接诊断")) {
                HStack {
                    diagnosticSummary

                    Spacer()

                    if case .running = store.connectionDiagnosticState {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if case .succeeded(let report) = store.connectionDiagnosticState {
                        Button(L10n.string("复制结果")) {
                            copyDiagnosticReport(report)
                        }
                    }

                    Button(L10n.string("运行诊断")) {
                        Task { await store.runConnectionDiagnostics() }
                    }
                    .disabled(store.connectionDiagnosticState == .running)
                }

                Text(
                    L10n.string("诊断只读取版本、状态、RPC 能力和 Session ID；")
                        + L10n.string("复制结果不会包含 RPC 密钥或 URL 查询参数。")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("aria2 会话与进程")) {
                LabeledContent("Session ID") {
                    Text(store.daemonSessionID ?? L10n.string("尚未读取"))
                        .font(LaneFont.utility(10.5, weight: .regular))
                        .foregroundStyle(
                            store.daemonSessionID == nil
                                ? Color.secondary
                                : Color.primary
                        )
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 10) {
                    Button(L10n.string("刷新信息")) {
                        Task { await store.refreshDaemonSessionInfo() }
                    }
                    Button(L10n.string("保存会话")) {
                        Task { await store.saveDaemonSession() }
                    }
                    Button(L10n.string("清理结果记录")) {
                        Task { await store.clearCompleted() }
                    }

                    Spacer()

                    Menu(L10n.string("关闭 aria2")) {
                        Button(L10n.string("正常关闭")) {
                            forceShutdown = false
                            isShowingShutdownConfirmation = true
                        }
                        Button(L10n.string("强制关闭"), role: .destructive) {
                            forceShutdown = true
                            isShowingShutdownConfirmation = true
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .disabled(
                    !isConnected
                        || store.isPerformingAction
                )

                Text(
                    L10n.string("“保存会话”调用 aria2.saveSession；关闭操作作用于当前连接的 aria2 进程。")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text(L10n.string("更换 RPC 地址或密钥后需要重新连接。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.string("应用并重新连接")) {
                        preferences.saveActiveServerProfile()
                        Task { await store.reconnect() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.connectionState == .connecting)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            forceShutdown ? L10n.string("强制关闭 aria2？") : L10n.string("关闭 aria2？"),
            isPresented: $isShowingShutdownConfirmation
        ) {
            Button(
                forceShutdown ? L10n.string("强制关闭") : L10n.string("关闭"),
                role: .destructive
            ) {
                Task { await store.shutdownDaemon(force: forceShutdown) }
            }
            Button(L10n.string("取消"), role: .cancel) {}
        } message: {
            Text(
                forceShutdown
                    ? L10n.string("aria2 会立即退出，尚未保存的会话数据可能丢失。")
                    : L10n.string("aria2 会在安全退出后断开当前服务器。")
            )
        }
    }

    private var activeProfileBinding: Binding<UUID> {
        Binding(
            get: {
                preferences.activeServerProfileID
                    ?? preferences.serverProfiles.first?.id
                    ?? UUID()
            },
            set: { id in
                preferences.activateServerProfile(id: id)
                Task { await store.reconnect() }
            }
        )
    }

    private var activeProfileNameBinding: Binding<String> {
        Binding(
            get: { preferences.activeServerProfile?.name ?? "" },
            set: { preferences.renameActiveServerProfile($0) }
        )
    }

    private var connectionColor: Color {
        switch store.connectionState {
        case .idle: .secondary
        case .connecting: LaneColor.amber
        case .connected: LaneColor.mint
        case .failed: LaneColor.danger
        }
    }

    private var isConnected: Bool {
        if case .connected = store.connectionState {
            return true
        }
        return false
    }

    private var eventStreamDetail: String {
        switch store.eventStreamState {
        case .disabled:
            return L10n.string("连接 aria2 后会自动启用")
        case .connecting:
            return L10n.string("正在订阅下载状态通知")
        case .connected:
            return L10n.string("\(store.serverRPCNotifications.count) 种通知 · 状态变化会即时刷新")
        case .disconnected(let message):
            return L10n.string("\(message)；列表仍会定时刷新")
        }
    }

    @ViewBuilder
    private var diagnosticSummary: some View {
        switch store.connectionDiagnosticState {
        case .idle:
            Text(L10n.string("检查地址、认证、响应耗时与 aria2 功能"))
                .foregroundStyle(.secondary)
        case .running:
            Text(L10n.string("正在连接并读取状态…"))
                .foregroundStyle(.secondary)
        case .succeeded(let report):
            VStack(alignment: .leading, spacing: 2) {
                Label(
                    "aria2 \(report.aria2Version) · \(report.elapsedMilliseconds) ms",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(LaneColor.mint)
                Text(L10n.string("\(report.activeCount) 个进行中 · \(report.waitingCount) 个等待中"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    L10n.string("\(report.rpcMethodCount) 个 RPC 方法 · ")
                        + L10n.string("\(report.notificationMethods.count) 种通知")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(LaneColor.danger)
                .lineLimit(2)
        }
    }

    private func copyDiagnosticReport(_ report: ConnectionDiagnosticReport) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.shareableText, forType: .string)
    }
}

private struct SettingsSelectionMenu<Option, Selection: Equatable>: View {
    @Binding var selection: Selection
    let options: [Option]
    let value: KeyPath<Option, Selection>
    let title: KeyPath<Option, String>
    let accessibilityLabel: String

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option[keyPath: value]
                } label: {
                    if selection == option[keyPath: value] {
                        Label(
                            option[keyPath: title],
                            systemImage: "checkmark"
                        )
                    } else {
                        Text(option[keyPath: title])
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(selectedTitle)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(LaneFont.interface(11, weight: .medium))
            .foregroundStyle(LaneColor.label1)
            .padding(.horizontal, 12)
            .frame(minWidth: 150, minHeight: 34, alignment: .trailing)
            .background(
                LaneColor.fill1,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(LaneColor.line, lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selectedTitle)
    }

    private var selectedTitle: String {
        options.first {
            $0[keyPath: value] == selection
        }?[keyPath: title] ?? L10n.string("未选择")
    }
}

struct SettingsActionFooter: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore

    var body: some View {
        Section {
            HStack(spacing: 10) {
                stateLabel
                Spacer()

                Button(L10n.string("恢复推荐值")) {
                    preferences.restoreRecommendedAria2Settings()
                    Task { await store.applyAria2Settings() }
                }
                .disabled(store.settingsApplyState == .applying)

                Button(L10n.string("应用到 aria2")) {
                    Task { await store.applyAria2Settings() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.settingsApplyState == .applying)
            }
        }
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch store.settingsApplyState {
        case .idle:
            Text(L10n.string("修改会自动保存，点“应用”立即生效"))
                .foregroundStyle(.secondary)
        case .applying:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string("正在应用…"))
            }
        case .applied:
            Label(L10n.string("已应用"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(LaneColor.mint)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(LaneColor.danger)
                .lineLimit(1)
        }
    }
}

struct SpeedLimitField: View {
    let title: String
    let detail: String
    @Binding var kibibytesPerSecond: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if kibibytesPerSecond > 0 {
                Button(L10n.string("不限速")) {
                    kibibytesPerSecond = 0
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }

            SpeedLimitNumberInput(
                value: megabytesBinding,
                accessibilityLabel: title
            )
        }
    }

    private var megabytesBinding: Binding<Double> {
        Binding(
            get: { Double(kibibytesPerSecond) / 1_024 },
            set: {
                kibibytesPerSecond = max(Int(($0 * 1_024).rounded()), 0)
            }
        )
    }
}

private struct SpeedLimitNumberInput: View {
    @Binding var value: Double
    let accessibilityLabel: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            TextField(
                "",
                value: nonnegativeValue,
                format: .number.precision(.fractionLength(0...2))
            )
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(LaneFont.utility(11, weight: .medium))
            .multilineTextAlignment(.trailing)
            .focused($isFocused)
            .accessibilityLabel(accessibilityLabel)

            Text("MB/s")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 11)
        .frame(width: 156, height: 34)
        .background(
            LaneColor.fill1,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isFocused
                        ? LaneColor.accent.opacity(0.58)
                        : Color.clear,
                    lineWidth: 1
                )
        }
        .contentShape(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .onTapGesture {
            isFocused = true
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var nonnegativeValue: Binding<Double> {
        Binding(
            get: { value },
            set: { value = max($0, 0) }
        )
    }
}
