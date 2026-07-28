import Foundation

struct DownloadPowerPolicy {
    static func shouldPreventSystemSleep(
        enabled: Bool,
        transfers: [TransferItem]
    ) -> Bool {
        guard enabled else { return false }
        return transfers.contains { item in
            guard item.status == .active, item.seeder != "true" else { return false }
            return item.totalByteCount == 0
                || item.completedByteCount < item.totalByteCount
                || item.verifyIntegrityPending == "true"
        }
    }
}

@MainActor
final class DownloadPowerAssertionController {
    private var activity: NSObjectProtocol?

    var isActive: Bool {
        activity != nil
    }

    @discardableResult
    func update(enabled: Bool, transfers: [TransferItem]) -> Bool {
        let shouldBeActive = DownloadPowerPolicy.shouldPreventSystemSleep(
            enabled: enabled,
            transfers: transfers
        )

        if shouldBeActive, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled],
                reason: L10n.string("AriaLane 正在下载文件")
            )
        } else if !shouldBeActive {
            clear()
        }
        return isActive
    }

    func clear() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}
