import SwiftUI

struct TransferListView: View {
    @EnvironmentObject private var store: DownloadStore

    let filter: TransferFilter
    @Binding var selectedGIDs: Set<String>
    let onAdd: () -> Void

    @SceneStorage("transferSearchText") private var searchText = ""
    @SceneStorage("transferSortField") private var sortFieldRaw = TransferSortField.queue.rawValue
    @SceneStorage("transferSortDirection")
    private var sortDirectionRaw = TransferSortDirection.ascending.rawValue
    @SceneStorage("isConfirmingBatchRemoval") private var isConfirmingRemoval = false
    @AppStorage("taskListDisplayMode") private var displayModeRaw = TaskListDisplayMode.card.rawValue

    private var sortField: TransferSortField {
        TransferSortField(rawValue: sortFieldRaw) ?? .queue
    }

    private var sortDirection: TransferSortDirection {
        TransferSortDirection(rawValue: sortDirectionRaw) ?? .ascending
    }

    private var filteredItems: [TransferItem] {
        store.transfers.filter(filter.includes)
    }

    private var visibleItems: [TransferItem] {
        TransferListQuery.results(
            in: store.transfers,
            filter: filter,
            searchText: searchText,
            sortField: sortField,
            direction: sortDirection
        )
    }

    private var selectedItems: [TransferItem] {
        store.transfers.filter { selectedGIDs.contains($0.gid) }
    }

    private var displayMode: TaskListDisplayMode {
        TaskListDisplayMode(rawValue: displayModeRaw) ?? .card
    }

    private var displayModeBinding: Binding<TaskListDisplayMode> {
        Binding(
            get: { displayMode },
            set: { displayModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            FlowHeaderView(
                filter: filter,
                items: filteredItems,
                stats: store.globalStats,
                speedSamples: store.speedSamples
            )

            Divider()
                .opacity(0.7)

            TransferListUtilityBar(
                items: visibleItems,
                selectedItems: selectedItems,
                selectedGIDs: $selectedGIDs,
                sortField: sortFieldBinding,
                sortDirection: sortDirectionBinding,
                displayMode: displayModeBinding,
                isPerformingAction: store.isPerformingAction,
                onPause: {
                    let items = selectedItems
                    Task { await store.pause(items) }
                },
                onForcePause: {
                    let items = selectedItems
                    Task { await store.forcePause(items) }
                },
                onResume: {
                    let items = selectedItems
                    Task { await store.resume(items) }
                },
                onRetry: {
                    let items = selectedItems
                    Task { await store.retry(items) }
                },
                onRemove: {
                    isConfirmingRemoval = true
                }
            )

            Divider()
                .opacity(0.55)

            if filteredItems.isEmpty {
                EmptyTransferView(
                    filter: filter,
                    connectionState: store.connectionState,
                    onAdd: onAdd
                )
            } else if visibleItems.isEmpty {
                SearchEmptyTransferView(searchText: searchText) {
                    searchText = ""
                }
            } else {
                List(selection: $selectedGIDs) {
                    ForEach(visibleItems) { item in
                        TransferRowView(
                            item: item,
                            isSelected: selectedGIDs.contains(item.gid),
                            allowsQueueReordering: allowsQueueReordering,
                            displayMode: displayMode
                        )
                        .laneListSelectionAppearance()
                        .tag(item.gid)
                        .listRowInsets(
                            EdgeInsets(
                                top: displayMode == .compact ? 2 : 5,
                                leading: LaneMetric.contentPadding,
                                bottom: displayMode == .compact ? 2 : 5,
                                trailing: LaneMetric.contentPadding
                            )
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                if item.status == .complete {
                                    store.reveal(item)
                                }
                            }
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(
                    .vertical,
                    displayMode == .compact ? 5 : 11,
                    for: .scrollContent
                )
                .animation(.easeInOut(duration: 0.16), value: displayMode)
            }
        }
        .background(LaneColor.canvas)
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: L10n.string("搜索名称、地址或路径")
        )
        .confirmationDialog(
            L10n.string("移除 \(selectedItems.count) 个任务？"),
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button(L10n.string("移除任务"), role: .destructive) {
                let items = selectedItems
                selectedGIDs.removeAll()
                Task { await store.remove(items) }
            }
            Button(L10n.string("取消"), role: .cancel) {}
        } message: {
            Text(L10n.string("任务会从 aria2 列表移除，已经下载的文件不会被删除。"))
        }
        .onChange(of: visibleItems.map(\.gid)) { _, visibleGIDs in
            selectedGIDs.formIntersection(Set(visibleGIDs))
        }
        .dropDestination(for: String.self) { values, _ in
            let parsed = DownloadInputParser.parse(values.joined(separator: "\n"))
            guard !parsed.urls.isEmpty else { return false }
            Task {
                await store.addDownloads(parsed.urls)
            }
            return true
        }
        .dropDestination(for: URL.self) { urls, _ in
            let importURLs = urls.filter { $0.isFileURL && DownloadImportKind(url: $0) != nil }
            let parsed = DownloadInputParser.parse(
                urls
                    .filter { !$0.isFileURL }
                    .map(\.absoluteString)
                    .joined(separator: "\n")
            )
            guard !importURLs.isEmpty || !parsed.urls.isEmpty else { return false }
            Task {
                if !importURLs.isEmpty {
                    await store.importDownloadFiles(at: importURLs)
                }
                if !parsed.urls.isEmpty {
                    await store.addDownloads(parsed.urls)
                }
            }
            return true
        }
    }

    private var sortFieldBinding: Binding<TransferSortField> {
        Binding(
            get: { sortField },
            set: { field in
                sortFieldRaw = field.rawValue
                sortDirectionRaw = field.preferredDirection.rawValue
            }
        )
    }

    private var allowsQueueReordering: Bool {
        sortField == .queue
            && sortDirection == .ascending
            && searchText.trimmed.isEmpty
    }

    private var sortDirectionBinding: Binding<TransferSortDirection> {
        Binding(
            get: { sortDirection },
            set: { sortDirectionRaw = $0.rawValue }
        )
    }
}

private struct TransferListUtilityBar: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var organization: TaskOrganizationStore

    let items: [TransferItem]
    let selectedItems: [TransferItem]
    @Binding var selectedGIDs: Set<String>
    @Binding var sortField: TransferSortField
    @Binding var sortDirection: TransferSortDirection
    @Binding var displayMode: TaskListDisplayMode
    let isPerformingAction: Bool
    let onPause: () -> Void
    let onForcePause: () -> Void
    let onResume: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if selectedItems.isEmpty {
                HStack(spacing: 3) {
                    Text(String(items.count))
                        .font(LaneFont.utility(10, weight: .regular))
                    Text(L10n.string("项"))
                        .font(LaneFont.interface(10))
                }
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    selectedGIDs = Set(items.map(\.gid))
                } label: {
                    Label(L10n.string("全选"), systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .disabled(items.isEmpty)

                TaskListDisplayModePicker(selection: $displayMode)

                sortMenu
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(L10n.string("已选择"))
                    Text(String(selectedItems.count))
                        .font(LaneFont.utility(10, weight: .medium))
                    Text(L10n.string("项"))
                }
                .font(LaneFont.interface(11, weight: .semibold))
                .foregroundStyle(LaneColor.accent)

                Button(L10n.string("取消选择")) {
                    selectedGIDs.removeAll()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)

                Spacer()

                TaskTagMenu(entityIDs: selectedEntityIDs)
                    .menuStyle(.borderlessButton)

                Menu {
                    Button(action: onPause) {
                        Label(L10n.string("暂停"), systemImage: "pause.fill")
                    }
                    Button(action: onForcePause) {
                        Label(
                            L10n.string("强制暂停"),
                            systemImage: "exclamationmark.pause.fill"
                        )
                    }
                } label: {
                    Label(L10n.string("暂停"), systemImage: "pause.fill")
                }
                .menuStyle(.borderlessButton)
                .disabled(!selectedItems.contains(where: \.isPausable))

                Button(action: onResume) {
                    Label(L10n.string("继续"), systemImage: "play.fill")
                }
                .disabled(!selectedItems.contains(where: \.isResumable))

                Button(action: onRetry) {
                    Label(L10n.string("重试"), systemImage: "arrow.clockwise")
                }
                .disabled(!selectedItems.contains(where: \.isRetryable))

                Button(role: .destructive, action: onRemove) {
                    Label(L10n.string("移除"), systemImage: "trash")
                }
            }
        }
        .font(LaneFont.interface(11))
        .controlSize(.small)
        .padding(.horizontal, LaneMetric.contentPadding)
        .frame(height: 42)
        .background(LaneColor.surface)
        .disabled(isPerformingAction)
    }

    private var selectedEntityIDs: Set<UUID> {
        organization.entityIDs(
            gids: Set(selectedItems.map(\.gid)),
            profileID: preferences.activeServerProfileID
        )
    }

    private var sortMenu: some View {
        Menu {
            Picker(L10n.string("排序方式"), selection: $sortField) {
                ForEach(TransferSortField.allCases) { field in
                    Label(field.title, systemImage: field.systemImage)
                        .tag(field)
                }
            }

            Divider()

            Picker(L10n.string("排序方向"), selection: $sortDirection) {
                ForEach(TransferSortDirection.allCases) { direction in
                    Label(direction.title, systemImage: direction.systemImage)
                        .tag(direction)
                }
            }
        } label: {
            Label(
                L10n.string("按\(sortField.title)"),
                systemImage: sortDirection.systemImage
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct EmptyTransferView: View {
    let filter: TransferFilter
    let connectionState: ConnectionState
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LaneColor.accent.opacity(0.08))
                    .frame(width: 86, height: 86)

                FlowMark(size: 48)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(LaneFont.display(19))
                Text(detail)
                    .font(LaneFont.interface(12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            if filter == .all {
                Button(L10n.string("添加第一个下载"), action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var title: String {
        if case .failed = connectionState {
            return L10n.string("还没有连上 aria2")
        }
        switch filter {
        case .all: return L10n.string("让第一个任务进入轨道")
        case .active: return L10n.string("当前没有进行中的下载")
        case .waiting: return L10n.string("等待队列是空的")
        case .paused: return L10n.string("没有暂停的任务")
        case .completed: return L10n.string("还没有完成记录")
        case .pending: return L10n.string("没有等待发送的任务")
        case .scheduled: return L10n.string("还没有计划任务")
        case .rss: return L10n.string("还没有 RSS 订阅")
        case .history: return L10n.string("还没有下载历史")
        }
    }

    private var detail: String {
        if case .failed(let message) = connectionState {
            return L10n.string("\(message)\n点击侧边栏底部的连接状态重试。")
        }
        if filter == .all {
            return L10n.string("粘贴 HTTP、FTP 或 magnet 链接，也可以直接把链接拖到这里。")
        }
        return L10n.string("切换到“全部”可以查看其他任务。")
    }
}

private struct SearchEmptyTransferView: View {
    let searchText: String
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.tertiary)

            Text(L10n.string("没有找到“\(searchText)”"))
                .font(LaneFont.label(15))

            Text(L10n.string("可以尝试任务名称、来源地址或保存路径。"))
                .font(LaneFont.interface(11))
                .foregroundStyle(.secondary)

            Button(L10n.string("清除搜索"), action: onClear)
                .controlSize(.small)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}
