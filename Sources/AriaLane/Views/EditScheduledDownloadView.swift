import AppKit
import SwiftUI

struct EditScheduledDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DownloadStore
    @StateObject private var form = AddDownloadFormState()

    let entry: ScheduledDownload

    private var parsed: ParsedDownloadInput {
        DownloadInputParser.parse(form.input)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            sourceEditor

            AddDownloadOptionsView(
                form: form,
                urlCount: parsed.urls.count,
                scheduleIsRequired: true,
                chooseDirectory: chooseDirectory
            )

            footer
        }
        .padding(24)
        .frame(width: 920, height: 760)
        .interactiveDismissDisabled(form.isSubmitting)
        .onAppear {
            form.prepareDefaults(
                directory: store.preferences.downloadDirectory,
                downloadLimitKiB: store.preferences.maxDownloadLimitKiB,
                uploadLimitKiB: store.preferences.maxUploadLimitKiB,
                split: store.preferences.split,
                connections: store.preferences.maxConnectionPerServer
            )
            form.loadScheduledDownload(entry)
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LaneColor.accent)
                .frame(width: 38, height: 38)
                .background(
                    LaneColor.accent.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("编辑计划任务"))
                    .font(LaneFont.display(23))
                Text(L10n.string("发送目标：\(entry.serverDisplayName)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.string("下载来源"))
                    .font(.system(size: 11, weight: .semibold))
                Text(L10n.string("每行一个 HTTP、FTP、SFTP 或 magnet 链接"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $form.input)
                    .font(LaneFont.utility(12, weight: .regular))
                    .scrollContentBackground(.hidden)
                    .padding(9)

                if form.input.isEmpty {
                    Text("https://example.com/file.zip")
                        .font(LaneFont.utility(12, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 118)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        parsed.rejectedCount > 0 ? LaneColor.amber.opacity(0.65) : LaneColor.line,
                        lineWidth: 1
                    )
            }

            Text(parseSummary)
                .font(.system(size: 10))
                .foregroundStyle(
                    parsed.rejectedCount > 0 || validationMessage != nil
                        ? LaneColor.amber
                        : .secondary
                )
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(L10n.string("取消")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(LaneColor.danger)
                    .lineLimit(1)
            } else if !parsed.urls.isEmpty {
                Label(L10n.string("修改已通过检查"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(LaneColor.mint)
            }

            Spacer()

            if form.isSubmitting {
                ProgressView()
                    .controlSize(.small)
            }

            Button(L10n.string("保存修改")) {
                submit()
            }
            .buttonStyle(.borderedProminent)
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
            return L10n.string("请输入至少一个下载链接")
        }
        if parsed.urls.isEmpty {
            return L10n.string("没有识别到可下载的链接")
        }
        if parsed.rejectedCount > 0 {
            return L10n.string("识别到 \(parsed.urls.count) 个链接，忽略 \(parsed.rejectedCount) 行")
        }
        return L10n.string("识别到 \(parsed.urls.count) 个链接")
    }

    private func submit() {
        let urls = parsed.urls
        guard !urls.isEmpty, validationMessage == nil else { return }
        form.isSubmitting = true
        let didUpdate = store.updateScheduledDownload(
            id: entry.id,
            urls: urls,
            taskOptions: form.taskOptions,
            scheduledAt: form.scheduledAt,
            frequency: form.scheduleFrequency
        )
        form.isSubmitting = false
        if didUpdate {
            dismiss()
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("选择计划任务的保存目录")
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
}
