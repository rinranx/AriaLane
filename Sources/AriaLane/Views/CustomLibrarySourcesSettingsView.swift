import SwiftUI

struct CustomLibrarySourcesSettingsPane: View {
    @EnvironmentObject private var preferences: AppPreferences
    @State private var editingSource: CustomLibrarySource?
    @State private var sourcePendingDeletion: CustomLibrarySource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                explanationCard
                sourcesCard
            }
            .padding(22)
        }
        .sheet(item: $editingSource) { source in
            CustomLibrarySourceEditorSheet(
                source: source,
                existingSources: preferences.customLibrarySources,
                onSave: { try preferences.saveCustomLibrarySource($0) }
            )
        }
        .alert(
            L10n.string("删除自定义来源？"),
            isPresented: deletionAlertBinding,
            presenting: sourcePendingDeletion
        ) { source in
            Button(L10n.string("取消"), role: .cancel) {}
            Button(L10n.string("删除"), role: .destructive) {
                preferences.removeCustomLibrarySource(id: source.id)
            }
        } message: { source in
            Text(L10n.string("“\(source.displayName)”将从资源搜索中移除。"))
        }
    }

    private var explanationCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "books.vertical.circle.fill")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(LaneColor.accent)
                .frame(width: 42, height: 42)
                .background(
                    LaneColor.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("自定义 OPDS 来源"))
                    .font(LaneFont.label(14))
                Text(
                    L10n.string(
                        "添加支持 OPDS 1.x 的图书目录；已启用来源会出现在资源搜索的来源菜单中。"
                    )
                )
                .font(LaneFont.interface(10.5))
                .foregroundStyle(.secondary)
                Text(
                    L10n.string(
                        "只有明确标注公版或 Creative Commons 的条目才提供直接下载。"
                    )
                )
                .font(LaneFont.interface(10))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .laneSurface(cornerRadius: 13)
    }

    private var sourcesCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("已添加来源"))
                        .font(LaneFont.label(13))
                    Text(L10n.string("可添加多个来源，并分别启用或停用。"))
                        .font(LaneFont.interface(10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    editingSource = CustomLibrarySource(
                        name: "",
                        searchURLTemplate: ""
                    )
                } label: {
                    Label(L10n.string("添加来源"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(16)

            Divider()

            if preferences.customLibrarySources.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(L10n.string("还没有自定义来源"))
                        .font(LaneFont.label(12))
                    Text(L10n.string("添加后可与内置的三个开放来源一起搜索。"))
                        .font(LaneFont.interface(10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 38)
            } else {
                VStack(spacing: 0) {
                    ForEach(preferences.customLibrarySources) { source in
                        sourceRow(source)
                        if source.id != preferences.customLibrarySources.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .laneSurface(cornerRadius: 13)
    }

    private func sourceRow(_ source: CustomLibrarySource) -> some View {
        HStack(spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { source.isEnabled },
                    set: {
                        preferences.setCustomLibrarySourceEnabled(
                            id: source.id,
                            isEnabled: $0
                        )
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.displayName)
                    .font(LaneFont.interface(11.5, weight: .semibold))
                Text(source.searchURLTemplate)
                    .font(LaneFont.utility(9.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Button {
                editingSource = source
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(L10n.string("编辑来源"))

            Button(role: .destructive) {
                sourcePendingDeletion = source
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.string("删除来源"))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 62)
        .opacity(source.isEnabled ? 1 : 0.62)
    }

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { sourcePendingDeletion != nil },
            set: { if !$0 { sourcePendingDeletion = nil } }
        )
    }
}

private struct CustomLibrarySourceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingSources: [CustomLibrarySource]
    let onSave: (CustomLibrarySource) throws -> CustomLibrarySource

    @State private var draft: CustomLibrarySource
    @State private var saveError: String?
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var isTesting = false

    init(
        source: CustomLibrarySource,
        existingSources: [CustomLibrarySource],
        onSave: @escaping (CustomLibrarySource) throws -> CustomLibrarySource
    ) {
        self.existingSources = existingSources
        self.onSave = onSave
        _draft = State(initialValue: source)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editorForm
            Divider()
            footer
        }
        .frame(width: 620, height: 455)
        .background(LaneColor.canvas)
        .onChange(of: draft.name) { _, _ in clearTestResult() }
        .onChange(of: draft.searchURLTemplate) { _, _ in clearTestResult() }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "books.vertical.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LaneColor.accent)
                .frame(width: 40, height: 40)
                .background(
                    LaneColor.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    draft.name.trimmed.isEmpty
                        ? L10n.string("添加自定义来源")
                        : L10n.string("编辑自定义来源")
                )
                .font(LaneFont.display(19))
                Text(L10n.string("配置一个可搜索的 OPDS 1.x 目录"))
                    .font(LaneFont.interface(10.5))
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
            .accessibilityLabel(L10n.string("关闭"))
        }
        .padding(20)
    }

    private var editorForm: some View {
        Form {
            Section(L10n.string("来源信息")) {
                TextField(L10n.string("来源名称"), text: $draft.name)
                TextField(
                    L10n.string("OPDS 搜索地址"),
                    text: $draft.searchURLTemplate,
                    prompt: Text("https://example.org/opds/search?q={query}")
                )
                .font(LaneFont.utility(10.5, weight: .regular))

                Toggle(L10n.string("在资源搜索中启用"), isOn: $draft.isEnabled)
            }

            Section(L10n.string("地址格式")) {
                Text(
                    L10n.string(
                        "用 {query} 表示检索词；也兼容 OPDS OpenSearch 常用的 {searchTerms}。"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(
                    L10n.string("远程地址必须使用 HTTPS；本机 localhost 可使用 HTTP。"),
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section {
                    Label(
                        statusMessage,
                        systemImage: statusIsSuccess
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        statusIsSuccess ? LaneColor.mint : LaneColor.amber
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                Task { await testSource() }
            } label: {
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(L10n.string("测试来源"), systemImage: "network")
                }
            }
            .disabled(validationError != nil || isTesting)

            Spacer()

            Button(L10n.string("取消")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(L10n.string("保存")) {
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(validationError != nil)
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
    }

    private var validationError: String? {
        do {
            let validated = try draft.validated()
            let duplicate = existingSources.contains {
                $0.id != validated.id
                    && $0.searchURLTemplate.caseInsensitiveCompare(
                        validated.searchURLTemplate
                    ) == .orderedSame
            }
            return duplicate ? L10n.string("这个 OPDS 搜索地址已经添加") : nil
        } catch {
            return error.localizedDescription
        }
    }

    private var statusMessage: String? {
        validationError ?? saveError ?? testMessage
    }

    private var statusIsSuccess: Bool {
        validationError == nil
            && saveError == nil
            && testMessage != nil
            && testSucceeded
    }

    private func save() {
        saveError = nil
        do {
            _ = try onSave(draft.validated())
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func clearTestResult() {
        testMessage = nil
        testSucceeded = false
        saveError = nil
    }

    @MainActor
    private func testSource() async {
        isTesting = true
        saveError = nil
        testMessage = nil
        testSucceeded = false
        defer { isTesting = false }

        do {
            let source = try draft.validated()
            let page = try await CustomOPDSService().search(
                source: source,
                query: "test",
                limit: 3
            )
            testSucceeded = true
            testMessage = L10n.string(
                "连接成功，读取到 \(page.resources.count) 项结果"
            )
        } catch {
            testMessage = error.localizedDescription
        }
    }
}
