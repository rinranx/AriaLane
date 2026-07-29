import AppKit
import SwiftUI

struct AddDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DownloadStore
    @StateObject private var form = AddDownloadFormState()
    @State private var isShowingQRCodeScanner = false

    let initialInput: String
    let startsScheduled: Bool
    let availableSize: CGSize

    init(
        initialInput: String = "",
        startsScheduled: Bool = false,
        availableSize: CGSize = CGSize(width: 1_120, height: 720)
    ) {
        self.initialInput = initialInput
        self.startsScheduled = startsScheduled
        self.availableSize = availableSize
    }

    private var parsed: ParsedDownloadInput {
        DownloadInputParser.parse(form.input)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: usesCompactPresentation ? 14 : 12) {
                    header
                    sourceEditor

                    AddDownloadOptionsView(
                        form: form,
                        urlCount: parsed.urls.count,
                        isCompact: usesCompactPresentation,
                        chooseDirectory: chooseDirectory
                    )
                }
                .padding(usesCompactPresentation ? 16 : 20)
            }
            .scrollIndicators(.hidden)

            Divider()
                .opacity(0.62)

            footer
                .padding(.horizontal, usesCompactPresentation ? 16 : 20)
                .frame(height: usesCompactPresentation ? 58 : 62)
                .background(LaneColor.surface)
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .background(LaneColor.canvas)
        .interactiveDismissDisabled(form.isSubmitting)
        .sheet(isPresented: $isShowingQRCodeScanner) {
            QRCodeScannerView(onScan: appendScannedURLs)
        }
        .onAppear {
            form.prepareDefaults(
                directory: store.preferences.downloadDirectory,
                downloadLimitKiB: store.preferences.maxDownloadLimitKiB,
                uploadLimitKiB: store.preferences.maxUploadLimitKiB,
                split: store.preferences.split,
                connections: store.preferences.maxConnectionPerServer
            )
            let initialURLs = DownloadInputParser.parse(initialInput).urls
            if !initialURLs.isEmpty {
                form.input = initialURLs.joined(separator: "\n")
            } else {
                pasteFromClipboard(replacing: true)
            }
            if startsScheduled {
                form.isScheduled = true
                form.selectedSection = .transfer
            }
        }
    }

    private var usesCompactPresentation: Bool {
        sheetSize.width < 820 || sheetSize.height < 650
    }

    private var sheetSize: CGSize {
        LaneAdaptiveSheetSize.downloadComposer(in: availableSize)
    }

    private var header: some View {
        HStack {
            Text(L10n.string("添加下载"))
                .font(
                    LaneFont.display(
                        usesCompactPresentation ? 23 : 27
                    )
                )
            Spacer()
        }
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.string("链接"))
                    .font(.system(size: 11, weight: .semibold))

                Spacer()

                Button {
                    pasteFromClipboard(replacing: false)
                } label: {
                    Label(L10n.string("粘贴"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(LaneColor.accent)
                .labelStyle(
                    AddDownloadActionLabelStyle(
                        isCompact: usesCompactPresentation
                    )
                )
                .help(L10n.string("粘贴链接"))

                Button {
                    isShowingQRCodeScanner = true
                } label: {
                    Label(L10n.string("扫二维码"), systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(LaneColor.accent)
                .labelStyle(
                    AddDownloadActionLabelStyle(
                        isCompact: usesCompactPresentation
                    )
                )
                .help(L10n.string("从图片文件或照片图库识别下载链接"))

                Button {
                    chooseImportFile()
                } label: {
                    Label(L10n.string("导入文件"), systemImage: "doc.badge.plus")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(LaneColor.accent)
                .labelStyle(
                    AddDownloadActionLabelStyle(
                        isCompact: usesCompactPresentation
                    )
                )
                .help(L10n.string("导入 Torrent 或 Metalink 文件"))
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $form.input)
                    .font(LaneFont.utility(12, weight: .regular))
                    .scrollContentBackground(.hidden)
                    .padding(9)

                if form.input.isEmpty {
                    Text(
                        "https://example.com/file.zip\n"
                            + "sftp://host/path/file.zip\n"
                            + "magnet:?xt=urn:btih:…"
                    )
                        .font(LaneFont.utility(12, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: usesCompactPresentation ? 82 : 102)
            .background(
                LaneColor.fill1,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        parsed.rejectedCount > 0
                            ? LaneColor.amber.opacity(0.65)
                            : Color.clear,
                        lineWidth: 1
                    )
            }

            HStack {
                Text(parseSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(
                        parsed.rejectedCount > 0 || validationMessage != nil
                            ? LaneColor.amber
                            : .secondary
                    )

                if !usesCompactPresentation {
                    Spacer()

                    Text(taskSummary)
                        .font(LaneFont.utility(9, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(LaneColor.danger)
                    .lineLimit(1)
            } else if !parsed.urls.isEmpty {
                Label(
                    L10n.string("参数已检查，将创建 \(parsed.urls.count) 个任务"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(LaneColor.mint)
            }

            Spacer()

            Button(L10n.string("取消")) {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(usesCompactPresentation ? .regular : .large)
            .keyboardShortcut(.cancelAction)

            if form.isSubmitting {
                ProgressView()
                    .controlSize(.small)
            }

            Button(addButtonTitle) {
                submit()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(usesCompactPresentation ? .regular : .large)
            .keyboardShortcut(.defaultAction)
            .disabled(
                parsed.urls.isEmpty
                    || validationMessage != nil
                    || form.isSubmitting
            )
        }
    }

    private var validationMessage: String? {
        guard !parsed.urls.isEmpty else { return nil }
        return form.taskOptions.validationMessage(forURLCount: parsed.urls.count)
            ?? form.scheduleValidationMessage
    }

    private var parseSummary: String {
        if form.input.trimmed.isEmpty {
            return L10n.string("链接只会发送给你设置的 aria2")
        }
        if parsed.urls.isEmpty {
            return L10n.string("没有识别到可下载的链接")
        }
        if parsed.rejectedCount > 0 {
            return L10n.string("识别到 \(parsed.urls.count) 个链接，忽略 \(parsed.rejectedCount) 行")
        }
        return L10n.string("识别到 \(parsed.urls.count) 个链接")
    }

    private var taskSummary: String {
        let folder = URL(fileURLWithPath: form.downloadDirectory).lastPathComponent
        let connectionCount = min(form.split, form.maxConnectionPerServer)
        let base = L10n.string("\(folder.isEmpty ? L10n.string("下载目录") : folder) · \(connectionCount) 条并行连接")
        guard form.isScheduled else { return base }
        return "\(base) · \(form.scheduleFrequency.shortTitle) · \(form.scheduledAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var addButtonTitle: String {
        if form.isScheduled {
            return parsed.urls.count > 1
                ? L10n.string("安排 \(parsed.urls.count) 个下载")
                : L10n.string("安排下载")
        }
        return parsed.urls.count > 1
            ? L10n.string("添加 \(parsed.urls.count) 个下载")
            : L10n.string("添加下载")
    }

    private func pasteFromClipboard(replacing: Bool) {
        guard let clipboardInput = DownloadPasteboardReader.validatedInput() else { return }
        let clipboardURLs = DownloadInputParser.parse(clipboardInput).urls

        if replacing, form.input.isEmpty {
            form.input = clipboardURLs.joined(separator: "\n")
        } else if !replacing {
            let prefix = form.input.trimmed.isEmpty ? "" : form.input.trimmed + "\n"
            form.input = prefix + clipboardURLs.joined(separator: "\n")
        }
    }

    private func appendScannedURLs(_ urls: [String]) {
        let existingURLs = Set(parsed.urls)
        let additions = urls.filter { !existingURLs.contains($0) }
        guard !additions.isEmpty else { return }

        let prefix = form.input.trimmed.isEmpty ? "" : form.input.trimmed + "\n"
        form.input = prefix + additions.joined(separator: "\n")
    }

    private func submit() {
        let urls = parsed.urls
        guard !urls.isEmpty, validationMessage == nil else { return }
        form.isSubmitting = true

        Task {
            let didAdd: Bool
            if form.isScheduled {
                didAdd = store.scheduleDownloads(
                    urls,
                    taskOptions: form.taskOptions,
                    at: form.scheduledAt,
                    frequency: form.scheduleFrequency
                )
            } else {
                didAdd = await store.addDownloads(
                    urls,
                    taskOptions: form.taskOptions
                )
            }
            form.isSubmitting = false
            if didAdd {
                dismiss()
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("选择这次任务的保存目录")
        panel.prompt = L10n.string("选择")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: form.downloadDirectory)

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                form.downloadDirectory = url.path
            }
        }
    }

    private func chooseImportFile() {
        DownloadImportPicker.choose { url in
            dismiss()
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                await store.importDownloadFile(at: url)
            }
        }
    }
}

private struct AddDownloadActionLabelStyle: LabelStyle {
    let isCompact: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            if !isCompact {
                configuration.title
            }
        }
    }
}
