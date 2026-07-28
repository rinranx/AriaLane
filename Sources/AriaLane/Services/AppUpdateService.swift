import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdateService: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    let isConfigured: Bool
    let updaterController: SPUStandardUpdaterController

    private var cancellables: Set<AnyCancellable> = []

    init(bundle: Bundle = .main) {
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        isConfigured = feedURL?.trimmed.isEmpty == false
            && publicKey?.trimmed.isEmpty == false

        updaterController = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        guard isConfigured else { return }
        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
    }

    var automaticallyChecksForUpdates: Bool {
        get { isConfigured && updaterController.updater.automaticallyChecksForUpdates }
        set {
            guard isConfigured else { return }
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { isConfigured && updaterController.updater.automaticallyDownloadsUpdates }
        set {
            guard isConfigured else { return }
            updaterController.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        updaterController.checkForUpdates(nil)
    }
}
