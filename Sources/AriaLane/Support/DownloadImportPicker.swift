import AppKit
import UniformTypeIdentifiers

@MainActor
enum DownloadImportPicker {
    static func choose(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = L10n.string("选择 Torrent 或 Metalink")
        panel.prompt = L10n.string("导入")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = DownloadImportKind.supportedExtensions
            .compactMap { UTType(filenameExtension: $0) }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }
}
