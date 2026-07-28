import AppKit
import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginService: ObservableObject {
    enum State: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable
        case failed(String)
    }

    @Published private(set) var state: State = .disabled

    init() {
        refresh()
    }

    var isEnabled: Bool {
        state == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            state = .enabled
        case .notRegistered:
            state = .disabled
        case .requiresApproval:
            state = .requiresApproval
        case .notFound:
            state = .unavailable
        @unknown default:
            state = .unavailable
        }
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
