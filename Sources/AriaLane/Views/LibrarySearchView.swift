import SwiftUI

struct LibrarySearchView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var searchText: String

    let onDownload: (String) -> Void

    @SceneStorage("librarySearchScope")
    private var scopeRaw = LibrarySearchScope.all.storageValue
    @State private var page: LibraryResourceSearchPage?
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedResource: LibraryResource?
    @State private var pendingDownloadURL: String?
    @State private var lastSubmittedQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.7)

            resultBar

            Divider()
                .opacity(0.55)

            content
        }
        .background(LaneColor.canvas)
        .task(id: searchRequestID) {
            await searchAfterDebounce()
        }
        .sheet(item: $selectedResource) { resource in
            LibraryDownloadFormatsView(
                resource: resource,
                service: LibraryCatalogService(
                    customSources: preferences.customLibrarySources
                ),
                onDownload: { pendingDownloadURL = $0 }
            )
        }
        .onChange(of: selectedResource) { _, resource in
            guard resource == nil, let url = pendingDownloadURL else { return }
            pendingDownloadURL = nil
            DispatchQueue.main.async {
                onDownload(url)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("资源搜索"))
                    .font(LaneFont.display(27))
                Text(
                    L10n.string(
                        "搜索内置与自定义 OPDS 来源中的开放资源"
                    )
                )
                .font(LaneFont.interface(12))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Label(
                L10n.string("\(enabledSourceCount) 个已启用来源"),
                systemImage: "books.vertical"
            )
                .font(LaneFont.interface(11, weight: .semibold))
                .foregroundStyle(LaneColor.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    LaneColor.accent.opacity(0.09),
                    in: Capsule(style: .continuous)
                )
        }
        .padding(.horizontal, LaneMetric.contentPadding)
        .padding(.top, 23)
        .padding(.bottom, 20)
    }

    private var resultBar: some View {
        HStack(spacing: 10) {
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string("正在搜索开放资源…"))
                    .foregroundStyle(.secondary)
            } else if let page, !lastSubmittedQuery.isEmpty {
                Text(
                    L10n.string(
                        "显示 \(page.resources.count) 项 · \(scopeTitle)"
                    )
                )
                    .foregroundStyle(.secondary)
            } else {
                Text(
                    L10n.string(
                        "直接下载仅适用于权利状态与来源均可验证的条目"
                    )
                )
                    .foregroundStyle(.secondary)
            }

            if let page, !page.unavailableProviders.isEmpty {
                Label(
                    L10n.string("部分来源不可用"),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(LaneColor.amber)
                .help(page.unavailableProviders.map(\.title).joined(separator: ", "))
            }

            Spacer()

            sourcePicker
            browseSourcesMenu
        }
        .font(LaneFont.interface(11))
        .controlSize(.small)
        .padding(.horizontal, LaneMetric.contentPadding)
        .frame(height: 42)
        .background(LaneColor.surface)
    }

    @ViewBuilder
    private var content: some View {
        if searchText.trimmed.isEmpty {
            introduction
        } else if let errorMessage {
            errorState(errorMessage)
        } else if let page, page.resources.isEmpty, !isSearching {
            noResults
        } else if let page {
            resultsList(page.resources)
        } else {
            loadingState
        }
    }

    private var introduction: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.string("搜索开放图书、文献与公版电子书"))
                .font(LaneFont.label(16))
            Text(L10n.string("在工具栏输入书名、作者或主题即可开始。"))
                .font(LaneFont.interface(11))
                .foregroundStyle(.secondary)
            Text(L10n.string("权利状态不明确的条目只提供馆藏页，不会直接加入下载。"))
                .font(LaneFont.interface(10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Text(
                L10n.string(
                    "Project Gutenberg 的公版标记以美国版权状态为准，请确认所在地法律。"
                )
            )
            .font(LaneFont.interface(10))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            Text(L10n.string("可在设置的“资源来源”中添加多个自定义 OPDS 目录。"))
                .font(LaneFont.interface(10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text(L10n.string("正在搜索开放资源…"))
                .font(LaneFont.interface(11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 13) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.string("没有找到公开可读资源"))
                .font(LaneFont.label(15))
            Text(L10n.string("可以尝试更短的书名、作者姓名或其他关键词。"))
                .font(LaneFont.interface(11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 13) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(LaneColor.amber)
            Text(L10n.string("资源搜索失败"))
                .font(LaneFont.label(15))
            Text(message)
                .font(LaneFont.interface(11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.string("重试")) {
                let currentScope = scope
                Task {
                    await performSearch(searchText.trimmed, scope: currentScope)
                }
            }
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func resultsList(_ resources: [LibraryResource]) -> some View {
        List {
            ForEach(resources) { resource in
                LibraryResourceRow(
                    resource: resource,
                    onShowFormats: { selectedResource = resource },
                    onOpenDetails: { openURL(resource.detailsURL) }
                )
                .listRowInsets(
                    EdgeInsets(
                        top: 6,
                        leading: LaneMetric.contentPadding,
                        bottom: 6,
                        trailing: LaneMetric.contentPadding
                    )
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.vertical, 8, for: .scrollContent)
    }

    @MainActor
    private func searchAfterDebounce() async {
        let query = searchText.trimmed
        guard !query.isEmpty else {
            page = nil
            errorMessage = nil
            isSearching = false
            lastSubmittedQuery = ""
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(450))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        await performSearch(query, scope: scope)
    }

    @MainActor
    private func performSearch(
        _ query: String,
        scope requestedScope: LibrarySearchScope
    ) async {
        let requestedSources = preferences.customLibrarySources
        let service = LibraryCatalogService(customSources: requestedSources)
        isSearching = true
        errorMessage = nil
        lastSubmittedQuery = query

        do {
            let nextPage = try await service.search(
                query: query,
                scope: requestedScope
            )
            guard !Task.isCancelled,
                  searchText.trimmed == query,
                  scope == requestedScope,
                  preferences.customLibrarySources == requestedSources else {
                return
            }
            page = nextPage
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  searchText.trimmed == query,
                  scope == requestedScope,
                  preferences.customLibrarySources == requestedSources else {
                return
            }
            page = nil
            errorMessage = error.localizedDescription
        }

        if searchText.trimmed == query,
           scope == requestedScope,
           preferences.customLibrarySources == requestedSources {
            isSearching = false
        }
    }

    private var scope: LibrarySearchScope {
        let candidate = LibrarySearchScope(storageValue: scopeRaw)
        if case .custom(let id) = candidate,
           !enabledCustomSources.contains(where: { $0.id == id }) {
            return .all
        }
        return candidate
    }

    private var enabledCustomSources: [CustomLibrarySource] {
        preferences.customLibrarySources.filter(\.isEnabled)
    }

    private var enabledSourceCount: Int {
        LibraryResourceProvider.builtInCases.count + enabledCustomSources.count
    }

    private var scopeTitle: String {
        scope.title(customSources: enabledCustomSources)
    }

    private var searchRequestID: String {
        let sourceRevision = preferences.customLibrarySources.map {
            "\($0.id.uuidString):\($0.name):\($0.searchURLTemplate):\($0.isEnabled)"
        }.joined(separator: "\u{1E}")
        return "\(scope.storageValue)\u{1F}\(searchText.trimmed)\u{1F}\(sourceRevision)"
    }

    private var sourcePicker: some View {
        Menu {
            Picker(L10n.string("搜索来源"), selection: $scopeRaw) {
                ForEach(LibrarySearchScope.builtInCases) { option in
                    Label(
                        option.title(customSources: enabledCustomSources),
                        systemImage: option.systemImage
                    )
                    .tag(option.storageValue)
                }

                ForEach(enabledCustomSources) { source in
                    let option = LibrarySearchScope.custom(source.id)
                    Label(source.displayName, systemImage: option.systemImage)
                        .tag(option.storageValue)
                }
            }

            Divider()

            Button {
                openResourceSourceSettings()
            } label: {
                Label(L10n.string("管理自定义来源…"), systemImage: "gearshape")
            }
        } label: {
            Label(scopeTitle, systemImage: scope.systemImage)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var browseSourcesMenu: some View {
        Menu {
            Button("Internet Archive") {
                openURL(URL(string: "https://archive.org/details/texts")!)
            }
            Button("Project Gutenberg") {
                openURL(URL(string: "https://www.gutenberg.org/ebooks/")!)
            }
            Button("Open Library") {
                openURL(URL(string: "https://openlibrary.org/search")!)
            }

            Divider()

            Button {
                openResourceSourceSettings()
            } label: {
                Label(L10n.string("管理自定义来源…"), systemImage: "gearshape")
            }
        } label: {
            Label(L10n.string("浏览来源"), systemImage: "arrow.up.right.square")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func openResourceSourceSettings() {
        SettingsPane.resources.select()
        openSettings()
    }
}

private struct LibraryResourceRow: View {
    let resource: LibraryResource
    let onShowFormats: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            AsyncImage(url: resource.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Image(systemName: "book.closed")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 50, height: 66)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(LaneColor.line, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(resource.title)
                    .font(LaneFont.label(14))
                    .lineLimit(2)

                Text(resource.creatorLine)
                    .font(LaneFont.interface(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Label(resource.provider.title, systemImage: resource.provider.systemImage)
                        .font(LaneFont.interface(9, weight: .semibold))
                        .foregroundStyle(LaneColor.accent)
                    if let year = resource.year {
                        resourceMetadata(year)
                    }
                    if let language = resource.languages.first {
                        resourceMetadata(language.uppercased())
                    }
                    Text(resource.rightsTitle)
                        .font(LaneFont.interface(9, weight: .semibold))
                        .foregroundStyle(LaneColor.mint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            LaneColor.mint.opacity(0.10),
                            in: Capsule(style: .continuous)
                        )
                }
            }

            Spacer(minLength: 14)

            Button(action: onOpenDetails) {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .help(L10n.string("在 \(resource.provider.title) 查看"))

            if resource.canResolveDownloads {
                Button(action: onShowFormats) {
                    Label(L10n.string("选择格式…"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button(action: onOpenDetails) {
                    Label(L10n.string("打开阅读页"), systemImage: "book")
                }
                .controlSize(.small)
            }
        }
        .padding(13)
        .laneSurface(cornerRadius: 12)
    }

    private func resourceMetadata(_ value: String) -> some View {
        Text(value)
            .font(LaneFont.utility(9, weight: .regular))
            .foregroundStyle(.tertiary)
    }
}

private struct LibraryDownloadFormatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let resource: LibraryResource
    let service: LibraryCatalogService
    let onDownload: (String) -> Void

    @State private var downloads: LibraryResourceDownloads?
    @State private var errorMessage: String?
    @State private var reloadID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            Divider()
                .opacity(0.7)

            sheetContent

            Divider()
                .opacity(0.7)

            sheetFooter
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 400, idealHeight: 510)
        .background(LaneColor.canvas)
        .task(id: reloadID) {
            await loadDownloads()
        }
    }

    private var sheetHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(LaneColor.accent)
                .frame(width: 42, height: 42)
                .background(
                    LaneColor.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Label(resource.provider.title, systemImage: resource.provider.systemImage)
                    .font(LaneFont.interface(10, weight: .semibold))
                    .foregroundStyle(LaneColor.accent)
                Text(resource.title)
                    .font(LaneFont.label(16))
                    .lineLimit(2)
                Text(resource.creatorLine)
                    .font(LaneFont.interface(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    @ViewBuilder
    private var sheetContent: some View {
        if let downloads {
            if downloads.options.isEmpty {
                formatEmptyState
            } else {
                List(downloads.options) { option in
                    downloadRow(option)
                        .listRowInsets(
                            EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20)
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.vertical, 7, for: .scrollContent)
            }
        } else if let errorMessage {
            formatErrorState(errorMessage)
        } else {
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text(L10n.string("正在读取可下载格式…"))
                    .font(LaneFont.interface(11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func downloadRow(_ option: LibraryDownloadOption) -> some View {
        HStack(spacing: 13) {
            Text(option.formatTitle)
                .font(LaneFont.utility(10, weight: .semibold))
                .foregroundStyle(LaneColor.accent)
                .frame(width: 48, height: 34)
                .background(
                    LaneColor.accent.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(option.fileName)
                    .font(LaneFont.interface(11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let byteCount = option.byteCount {
                    Text(TransferFormatter.bytes(byteCount))
                        .font(LaneFont.utility(9, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                onDownload(option.url.absoluteString)
                dismiss()
            } label: {
                Label(L10n.string("添加下载"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(11)
        .laneSurface(cornerRadius: 10)
    }

    private var formatEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.questionmark")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.string("没有可用的电子书格式"))
                .font(LaneFont.label(14))
            Text(L10n.string("可以前往馆藏页查看阅读器或其他文件。"))
                .font(LaneFont.interface(11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatErrorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(LaneColor.amber)
            Text(L10n.string("无法读取下载格式"))
                .font(LaneFont.label(14))
            Text(message)
                .font(LaneFont.interface(11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.string("重试")) {
                reloadID = UUID()
            }
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var sheetFooter: some View {
        HStack(spacing: 14) {
            Label(
                downloads?.rightsTitle ?? resource.rightsTitle,
                systemImage: "checkmark.seal"
            )
                .foregroundStyle(LaneColor.mint)

            if let licenseURL = downloads?.licenseURL ?? resource.licenseURL {
                Button(L10n.string("查看权利说明")) {
                    openURL(licenseURL)
                }
                .buttonStyle(.link)
            }

            Spacer()

            Button(L10n.string("馆藏详情")) {
                openURL(resource.detailsURL)
            }
            .buttonStyle(.link)

            Button(L10n.string("完成")) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .font(LaneFont.interface(10))
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    @MainActor
    private func loadDownloads() async {
        downloads = nil
        errorMessage = nil
        do {
            downloads = try await service.downloads(for: resource)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
