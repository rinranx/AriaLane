import SwiftUI

@MainActor
final class ImportSelectionModel: ObservableObject {
    @Published var files: [ImportedFileChoice]
    @Published var searchQuery = ""
    @Published var webSeedURIsText = ""
    @Published var isSubmitting = false

    let draft: PendingDownloadImport

    init(draft: PendingDownloadImport) {
        self.draft = draft
        files = draft.files
    }

    var filteredIndices: [Int] {
        let query = searchQuery.trimmed
        guard !query.isEmpty else { return Array(files.indices) }
        return files.indices.filter {
            files[$0].path.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedFiles: [ImportedFileChoice] {
        files.filter(\.isSelected)
    }

    var selectedByteCount: Int64 {
        selectedFiles.reduce(Int64(0)) { $0 + $1.byteCount }
    }

    var webSeedURIs: [String] {
        var seen = Set<String>()
        return webSeedURIsText
            .components(separatedBy: .newlines)
            .map(\.trimmed)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var webSeedValidationMessage: String? {
        for uri in webSeedURIs {
            guard let scheme = URLComponents(string: uri)?.scheme?.lowercased(),
                  ["http", "https", "ftp"].contains(scheme) else {
                return L10n.string("Web Seed 只支持 HTTP、HTTPS 或 FTP")
            }
        }
        return nil
    }

    func selectAllVisible(_ isSelected: Bool) {
        for index in filteredIndices {
            files[index].isSelected = isSelected
        }
    }
}

struct ImportSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DownloadStore
    @StateObject private var model: ImportSelectionModel

    init(draft: PendingDownloadImport) {
        _model = StateObject(wrappedValue: ImportSelectionModel(draft: draft))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 12) {
                selectionToolbar
                if model.draft.kind == .torrent {
                    webSeedEditor
                }
                fileList
            }
            .padding(18)

            Divider()

            footer
        }
        .frame(width: 680, height: 520)
        .interactiveDismissDisabled(model.isSubmitting)
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: model.draft.kind.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LaneColor.accent)
                .frame(width: 42, height: 42)
                .background(LaneColor.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 3) {
                Text(model.draft.title)
                    .font(LaneFont.display(20))
                    .lineLimit(1)
                Text(importSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(L10n.string("\(model.selectedFiles.count) / \(model.files.count) 个文件"))
                    .font(.system(size: 11, weight: .medium))
                Text(TransferFormatter.bytes(model.selectedByteCount))
                    .font(LaneFont.utility(10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var importSubtitle: String {
        let base = L10n.string("选择要下载的文件 · \(model.draft.kind.title)")
        guard store.queuedImportCount > 0 else { return base }
        return L10n.string("\(base) · 另有 \(store.queuedImportCount) 个待导入")
    }

    private var selectionToolbar: some View {
        HStack(spacing: 10) {
            TextField(L10n.string("搜索文件"), text: $model.searchQuery)
                .textFieldStyle(.roundedBorder)

            Button(L10n.string("全选")) {
                model.selectAllVisible(true)
            }
            Button(L10n.string("全不选")) {
                model.selectAllVisible(false)
            }
        }
    }

    private var webSeedEditor: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 7) {
                TextEditor(text: $model.webSeedURIsText)
                    .font(LaneFont.utility(10, weight: .regular))
                    .frame(height: 58)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(LaneColor.line, lineWidth: 1)
                    }

                if let message = model.webSeedValidationMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(LaneColor.danger)
                } else {
                    Text(L10n.string("每行一个 HTTP(S) 或 FTP 地址，作为 Torrent Web Seed。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 7)
        } label: {
            HStack {
                Label(L10n.string("Web Seed（可选）"), systemImage: "globe")
                Spacer()
                if !model.webSeedURIs.isEmpty {
                    Text(L10n.string("\(model.webSeedURIs.count) 个"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11, weight: .semibold))
        }
    }

    private var fileList: some View {
        List {
            ForEach(model.filteredIndices, id: \.self) { index in
                Toggle(isOn: $model.files[index].isSelected) {
                    HStack(spacing: 11) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        Text(model.files[index].displayPath)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text(TransferFormatter.bytes(model.files[index].byteCount))
                            .font(LaneFont.utility(10))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.vertical, 3)
            }
        }
        .listStyle(.inset)
        .overlay {
            if model.filteredIndices.isEmpty {
                ContentUnavailableView.search(text: model.searchQuery)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(L10n.string("取消")) {
                cancel()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Text(L10n.string("保存到 \(store.preferences.downloadDirectory)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 300, alignment: .trailing)

            if model.isSubmitting {
                ProgressView()
                    .controlSize(.small)
            }

            Button(L10n.string("开始下载")) {
                commit()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(
                model.selectedFiles.isEmpty
                    || model.webSeedValidationMessage != nil
                    || model.isSubmitting
            )
        }
        .padding(18)
    }

    private func commit() {
        model.isSubmitting = true
        Task {
            let didCommit = await store.commitPendingImport(
                id: model.draft.id,
                choices: model.files,
                webSeedURIs: model.webSeedURIs
            )
            model.isSubmitting = false
            if didCommit {
                dismiss()
            }
        }
    }

    private func cancel() {
        model.isSubmitting = true
        Task {
            await store.cancelPendingImport(id: model.draft.id)
            model.isSubmitting = false
            dismiss()
        }
    }
}
