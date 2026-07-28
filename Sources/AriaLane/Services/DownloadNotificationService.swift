import AppKit
import Foundation
import UserNotifications

@MainActor
final class DownloadNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func prepare(enabled: Bool) async -> NotificationPermissionState {
        guard enabled else { return .disabled }

        let currentSettings = await center.notificationSettings()
        switch currentSettings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .allowed
        case .denied:
            return .denied
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                return granted ? .allowed : .denied
            } catch {
                let notificationError = error as NSError
                if notificationError.domain == "UNErrorDomain",
                   notificationError.code == 1 {
                    return .unavailable
                }
                return .failed(message: error.localizedDescription)
            }
        @unknown default:
            return .failed(message: L10n.string("无法读取通知权限"))
        }
    }

    @discardableResult
    func notifyCompletion(for item: TransferItem) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = L10n.string("下载完成")
        content.body = item.displayName
        content.sound = .default
        content.userInfo = ["gid": item.gid]
        return await add(content: content, identifier: "complete-\(item.gid)")
    }

    @discardableResult
    func notifyFailure(for item: TransferItem) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = L10n.string("下载需要处理")
        content.body = "\(item.displayName)：\(item.userFacingError ?? L10n.string("下载失败"))"
        content.sound = .default
        content.userInfo = ["gid": item.gid]
        return await add(content: content, identifier: "error-\(item.gid)")
    }

    func sendTestNotification() async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = L10n.string("AriaLane 通知已就绪")
        content.body = L10n.string("下载完成或失败时，会在这里提醒你。")
        content.sound = .default
        return await add(content: content, identifier: "notification-test")
    }

    private func add(content: UNNotificationContent, identifier: String) async -> Bool {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let gid = response.notification.request.content.userInfo["gid"] as? String
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows
                .first(where: { $0.title == "AriaLane" })?
                .makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(
                name: .ariaLaneSelectTransfer,
                object: gid
            )
        }
        completionHandler()
    }
}
