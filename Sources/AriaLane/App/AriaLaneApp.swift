import AppKit
import SwiftUI

@MainActor
final class ApplicationLifecycleCoordinator {
    private var openMainWindow: (() -> Void)?
    private var resumeAfterSystemWake: (() -> Void)?
    private var shutdown: (() -> Void)?

    func configure(
        openMainWindow: @escaping () -> Void,
        resumeAfterSystemWake: @escaping () -> Void,
        shutdown: @escaping () -> Void
    ) {
        self.openMainWindow = openMainWindow
        self.resumeAfterSystemWake = resumeAfterSystemWake
        self.shutdown = shutdown
    }

    @discardableResult
    func reopenMainWindowIfNeeded(hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows, let openMainWindow else {
            return false
        }
        openMainWindow()
        return true
    }

    func systemDidWake() {
        resumeAfterSystemWake?()
    }

    func applicationWillTerminate() {
        shutdown?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let lifecycleCoordinator = ApplicationLifecycleCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistry.registerBundledFonts()
        NSApp.setActivationPolicy(.regular)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            ApplicationMenuStabilizer.normalize()
        }
    }

    func applicationDidUpdate(_ notification: Notification) {
        ApplicationMenuStabilizer.normalize()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if lifecycleCoordinator.reopenMainWindowIfNeeded(
            hasVisibleWindows: flag
        ) {
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        lifecycleCoordinator.applicationWillTerminate()
    }

    @objc
    private func workspaceDidWake(_ notification: Notification) {
        lifecycleCoordinator.systemDidWake()
    }
}

@MainActor
private enum ApplicationMenuStabilizer {
    static func normalize() {
        guard let applicationMenu = NSApp.mainMenu?.items.first?.submenu else {
            return
        }

        guard let settingsItem = applicationMenu.items.first(where: {
            $0.keyEquivalent == ","
        }) else {
            return
        }

        if settingsItem.image != nil {
            settingsItem.image = nil
        }
        if settingsItem.indentationLevel != 0 {
            settingsItem.indentationLevel = 0
        }
    }
}

extension Notification.Name {
    static let ariaLaneAddDownload = Notification.Name("AriaLane.AddDownload")
    static let ariaLaneImportDownload = Notification.Name("AriaLane.ImportDownload")
    static let ariaLaneSelectTransfer = Notification.Name("AriaLane.SelectTransfer")
}

@main
struct AriaLaneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var preferences: AppPreferences
    @StateObject private var store: DownloadStore
    @StateObject private var organization: TaskOrganizationStore
    @StateObject private var updateService: AppUpdateService

    init() {
        let preferences = AppPreferences()
        let organization = TaskOrganizationStore()
        _preferences = StateObject(wrappedValue: preferences)
        _organization = StateObject(wrappedValue: organization)
        _store = StateObject(
            wrappedValue: DownloadStore(
                preferences: preferences,
                organizationStore: organization
            )
        )
        _updateService = StateObject(wrappedValue: AppUpdateService())
    }

    var body: some Scene {
        WindowGroup("AriaLane", id: "main") {
            ContentView()
                .environmentObject(preferences)
                .environmentObject(store)
                .environmentObject(organization)
                .environmentObject(updateService)
                .environment(\.locale, localizationLocale)
                .id(localizationIdentity)
                .frame(minWidth: 560, minHeight: 620)
                .task {
                    await store.start()
                }
        }
        .defaultSize(width: 1_120, height: 720)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            StableApplicationMenuCommands()
            CommandGroup(replacing: .appInfo) {
                Button(L10n.string("关于 AriaLane")) {
                    AboutPanelPresenter.show()
                }
            }
            AriaLaneCommands(store: store, preferences: preferences)
            CommandGroup(after: .appInfo) {
                Button(L10n.string("检查更新…")) {
                    updateService.checkForUpdates()
                }
                .disabled(!updateService.canCheckForUpdates)
            }
        }

        MenuBarExtra {
            MenuBarMiniView()
                .environmentObject(preferences)
                .environmentObject(store)
                .environmentObject(updateService)
                .environment(\.locale, localizationLocale)
                .id(localizationIdentity)
        } label: {
            MenuBarStatusLabel(
                downloadSpeed: store.globalStats.downloadSpeedValue,
                isConnected: store.connectionState.isConnected
            )
            .background {
                ApplicationLifecycleBridge(
                    appDelegate: appDelegate,
                    store: store
                )
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(preferences)
                .environmentObject(store)
                .environmentObject(updateService)
                .environment(\.locale, localizationLocale)
        }
    }

    private var localizationIdentity: String {
        "\(preferences.appLanguage.rawValue)-\(preferences.appLanguage.resolved.rawValue)"
    }

    private var localizationLocale: Locale {
        Locale(identifier: preferences.appLanguage.resolved.rawValue)
    }
}

private struct ApplicationLifecycleBridge: View {
    @Environment(\.openWindow) private var openWindow

    let appDelegate: AppDelegate
    let store: DownloadStore

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                appDelegate.lifecycleCoordinator.configure(
                    openMainWindow: {
                        openWindow(id: "main")
                    },
                    resumeAfterSystemWake: {
                        Task {
                            await store.resumeAfterSystemWake()
                        }
                    },
                    shutdown: {
                        store.shutdown()
                    }
                )
            }
            .accessibilityHidden(true)
    }
}

private struct StableApplicationMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button(L10n.string("退出 AriaLane")) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

struct AriaLaneCommands: Commands {
    @ObservedObject var store: DownloadStore
    @ObservedObject var preferences: AppPreferences

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.string("添加下载…")) {
                NotificationCenter.default.post(name: .ariaLaneAddDownload, object: nil)
            }
            .keyboardShortcut("n")

            Button(L10n.string("从剪贴板添加…")) {
                NotificationCenter.default.post(
                    name: .ariaLaneAddDownload,
                    object: DownloadPasteboardReader.validatedInput()
                )
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button(L10n.string("导入 Torrent / Metalink…")) {
                NotificationCenter.default.post(name: .ariaLaneImportDownload, object: nil)
            }
            .keyboardShortcut("o")
        }

        CommandMenu(L10n.string("下载")) {
            Button(L10n.string("刷新任务")) {
                Task { await store.refresh() }
            }
            .keyboardShortcut("r")

            Divider()

            Button(L10n.string("暂停全部")) {
                Task { await store.pauseAll() }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button(L10n.string("强制暂停全部")) {
                Task { await store.forcePauseAll() }
            }

            Button(L10n.string("继续全部")) {
                Task { await store.resumeAll() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button(L10n.string("所选任务移到队首")) {
                Task { await store.moveSelectedTransfer(.top) }
            }
            .disabled(store.selectedTransfer?.isQueueMovable != true)

            Button(L10n.string("所选任务上移")) {
                Task { await store.moveSelectedTransfer(.up) }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(store.selectedTransfer?.isQueueMovable != true)

            Button(L10n.string("所选任务下移")) {
                Task { await store.moveSelectedTransfer(.down) }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(store.selectedTransfer?.isQueueMovable != true)

            Button(L10n.string("所选任务移到队尾")) {
                Task { await store.moveSelectedTransfer(.bottom) }
            }
            .disabled(store.selectedTransfer?.isQueueMovable != true)

            if let selectedTransfer = store.selectedTransfer,
               selectedTransfer.isRetryable {
                Button(L10n.string("重试所选任务")) {
                    Task { await store.retry(selectedTransfer) }
                }
            }

            Button(L10n.string("重试全部失败任务")) {
                let failed = store.transfers.filter(\.isRetryable)
                Task { await store.retry(failed) }
            }
            .disabled(!store.transfers.contains(where: \.isRetryable))

            Menu(L10n.string("下载限速")) {
                ForEach([0, 1_024, 5_120, 10_240, 20_480, 51_200], id: \.self) { limit in
                    Button(TransferFormatter.speedLimit(limit)) {
                        Task { await store.setQuickDownloadLimit(limit) }
                    }
                }
            }

            Divider()

            Button(L10n.string("清理已完成记录")) {
                Task { await store.clearCompleted() }
            }
        }
    }
}
