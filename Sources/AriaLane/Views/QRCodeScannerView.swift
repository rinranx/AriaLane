import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct QRCodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingImageFile = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isProcessingImage = false
    @State private var feedback: QRCodeScannerFeedback?

    let onScan: ([String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            imageSourcePanel
            feedbackRow
        }
        .padding(22)
        .frame(width: 520, height: 350)
        .fileImporter(
            isPresented: $isChoosingImageFile,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: handleFileSelection
        )
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            scanPhoto(photo)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LaneColor.accent)
                .frame(width: 38, height: 38)
                .background(LaneColor.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("从图片识别二维码"))
                    .font(LaneFont.display(20))
                Text(L10n.string("选择本地图片文件，或从系统照片图库读取"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help(L10n.string("关闭"))
        }
    }

    private var imageSourcePanel: some View {
        VStack(spacing: 14) {
            if isProcessingImage {
                ProgressView()
                    .controlSize(.regular)
                Text(L10n.string("正在识别图片中的二维码…"))
                    .font(.system(size: 12, weight: .medium))
            } else {
                Image(systemName: "photo.badge.magnifyingglass")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(LaneColor.accent)

                VStack(spacing: 4) {
                    Text(L10n.string("选择一张包含二维码的图片"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.string("支持常见图片格式，也可同时识别一张图片中的多个二维码"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    isChoosingImageFile = true
                } label: {
                    Label(L10n.string("选择图片文件"), systemImage: "folder")
                }
                .buttonStyle(QRCodeSourceButtonStyle())
                .disabled(isProcessingImage)

                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images,
                    preferredItemEncoding: .automatic
                ) {
                    Label(L10n.string("照片图库"), systemImage: "photo.on.rectangle")
                }
                .buttonStyle(QRCodeSourceButtonStyle(isProminent: true))
                .disabled(isProcessingImage)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(
            LaneColor.accent.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LaneColor.line, lineWidth: 1)
        }
    }

    private var feedbackRow: some View {
        HStack(spacing: 7) {
            if let feedback {
                Image(systemName: feedback.systemImage)
                    .foregroundStyle(feedback.color)
                Text(feedback.message)
                    .foregroundStyle(feedback.color)
            } else {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                Text(L10n.string("图片只在本机通过 Vision 识别，不会上传"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            scanImageFile(at: url)
        case let .failure(error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            showImageFailure(L10n.string("无法打开所选图片"))
        }
    }

    private func scanImageFile(at url: URL) {
        beginImageProcessing()
        let isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()

        Task {
            defer {
                if isAccessingSecurityScopedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: url, options: .mappedIfSafe)
                }.value
                try await decodeImageData(data)
            } catch {
                showImageFailure(L10n.string("无法读取或识别所选图片"))
            }
        }
    }

    private func scanPhoto(_ photo: PhotosPickerItem) {
        beginImageProcessing()

        Task {
            defer { selectedPhoto = nil }

            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else {
                    showImageFailure(L10n.string("无法读取所选照片"))
                    return
                }
                try await decodeImageData(data)
            } catch {
                showImageFailure(L10n.string("无法读取或识别所选照片"))
            }
        }
    }

    private func decodeImageData(_ data: Data) async throws {
        let payloads = try await Task.detached(priority: .userInitiated) {
            try QRCodeImageDecoder.payloads(in: data)
        }.value
        handlePayloads(payloads)
    }

    private func beginImageProcessing() {
        feedback = nil
        isProcessingImage = true
    }

    private func handlePayloads(_ payloads: [String]) {
        isProcessingImage = false

        guard !payloads.isEmpty else {
            feedback = .warning(L10n.string("图片中没有检测到二维码，请换一张重试"))
            return
        }

        let urls = QRCodeDownloadPayloadParser.downloadURLs(from: payloads)
        guard !urls.isEmpty else {
            feedback = .warning(L10n.string("二维码中没有 HTTP、FTP 或 magnet 下载链接"))
            return
        }

        onScan(urls)
        dismiss()
    }

    private func showImageFailure(_ message: String) {
        isProcessingImage = false
        feedback = .error(message)
    }
}

private struct QRCodeSourceButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .padding(.horizontal, 16)
            .frame(minWidth: 142, minHeight: 38)
            .background(
                isProminent ? LaneColor.accent : LaneColor.fill1,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if !isProminent {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(LaneColor.line.opacity(0.75), lineWidth: 1)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(
                .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private enum QRCodeScannerFeedback {
    case warning(String)
    case error(String)

    var message: String {
        switch self {
        case let .warning(message), let .error(message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .warning:
            LaneColor.amber
        case .error:
            LaneColor.danger
        }
    }
}
