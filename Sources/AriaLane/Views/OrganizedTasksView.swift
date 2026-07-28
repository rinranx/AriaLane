import AppKit
import SwiftUI

struct OrganizedTasksView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore
    @EnvironmentObject private var organization: TaskOrganizationStore

    let selection: SidebarSelection
    @Binding var selectedEntityIDs: Set<UUID>
    let onEditSelection: () -> Void

    @SceneStorage("organizedTaskSearchText") private var searchText = ""
    @SceneStorage("organizedTaskSortField")
    private var sortFieldRaw = TaskEntitySortField.addedDate.rawValue
    @SceneStorage("organizedTaskSortDirection")
    private var sortDirectionRaw = TransferSortDirection.descending.rawValue
    @AppStorage("taskListDisplayMode") private var displayModeRaw = TaskListDisplayMode.card.rawValue
    @State private var pendingHistoryRemoval: DownloadHistoryEntry?

    private var scopedEntities: [TaskEntityRecord] {
        organization.entities(for: selection)
    }

    private var visibleEntities: [TaskEntityRecord] {
        TaskEntityQuery.results(
            in: scopedEntities,
            searchText: searchText,
            tags: organization.tags,
            sortField: sortField,
            direction: sortDirection
        )
    }

    private var selectedEntities: [TaskEntityRecord] {
        scopedEntities.filter { selectedEntityIDs.contains($0.id) }
    }

    private var selectedLiveItems: [TransferItem] {
        selectedEntities.compactMap {
            organization.liveTransfer(
                for: $0,
                in: store.transfers,
                profileID: preferences.activeServerProfileID
            )
        }
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
            header

            Divider()
                .opacity(0.7)

            utilityBar

            Divider()
                .opacity(0.55)

            if scopedEntities.isEmpty {
                organizedEmptyView
            } else if visibleEntities.isEmpty {
                searchEmptyView
            } else {
                taskList
            }
        }
        .background(LaneColor.canvas)
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: L10n.string("搜索名称、来源、类型或标签")
        )
        .sheet(isPresented: historyRemovalBinding) {
            if let entry = pendingHistoryRemoval {
                LocalFileDeletionConfirmationView(
                    title: L10n.string("删除这条下载历史？"),
                    message: L10n.string("删除后将不再出现在 AriaLane 的任务记录中。"),
                    actionTitle: L10n.string("删除历史记录"),
                    canDeleteLocalFiles: !entry.localPathsForRemoval.isEmpty
                ) { deleteLocalFiles in
                    pendingHistoryRemoval = nil
                    selectedEntityIDs.removeAll()
                    Task {
                        await store.removeHistory(
                            ids: [entry.id],
                            deletingLocalFiles: deleteLocalFiles
                        )
                    }
                }
            }
        }
        .onChange(of: visibleEntities.map(\.id)) { _, visibleIDs in
            selectedEntityIDs.formIntersection(Set(visibleIDs))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 9) {
                    Image(systemName: selectionSystemImage)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(selectionAccent)

                    Text(selectionTitle)
                        .font(LaneFont.display(27))
                }

                Text(selectionDetail)
                    .font(LaneFont.interface(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 22) {
                headerMetric(
                    label: L10n.string("当前"),
                    value: String(currentCount),
                    color: LaneColor.accent
                )
                headerMetric(
                    label: L10n.string("历史"),
                    value: String(historyCount),
                    color: LaneColor.mint
                )
            }
        }
        .padding(.horizontal, LaneMetric.contentPadding)
        .padding(.top, 23)
        .padding(.bottom, 20)
    }

    private var utilityBar: some View {
        HStack(spacing: 10) {
            if selectedEntities.isEmpty {
                Text(L10n.string("\(visibleEntities.count) 个任务"))
                    .font(LaneFont.utility(10, weight: .regular))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    selectedEntityIDs = Set(visibleEntities.map(\.id))
                } label: {
                    Label(L10n.string("全选"), systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .disabled(visibleEntities.isEmpty)

                TaskListDisplayModePicker(selection: displayModeBinding)

                sortMenu
            } else {
                Label(
                    L10n.string("已选择 \(selectedEntities.count) 个"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(LaneFont.interface(11, weight: .semibold))
                .foregroundStyle(LaneColor.accent)

                Button(L10n.string("取消选择")) {
                    selectedEntityIDs.removeAll()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)

                Spacer()

                TaskTagMenu(entityIDs: selectedEntityIDs)
                    .menuStyle(.borderlessButton)

                Menu {
                    ForEach(
                        [0, 1_024, 5_120, 10_240, 20_480, 51_200],
                        id: \.self
                    ) { limit in
                        Button(TransferFormatter.speedLimit(limit)) {
                            let items = selectedLiveItems
                            Task {
                                await store.setTaskDownloadLimit(limit, for: items)
                            }
                        }
                    }
                } label: {
                    Label(L10n.string("限速"), systemImage: "gauge.with.dots.needle.50percent")
                }
                .disabled(selectedLiveItems.isEmpty)

                Button {
                    let items = selectedLiveItems
                    Task { await store.pause(items) }
                } label: {
                    Label(L10n.string("暂停"), systemImage: "pause.fill")
                }
                .disabled(!selectedLiveItems.contains(where: \.isPausable))

                Button {
                    let items = selectedLiveItems
                    Task { await store.resume(items) }
                } label: {
                    Label(L10n.string("继续"), systemImage: "play.fill")
                }
                .disabled(!selectedLiveItems.contains(where: \.isResumable))

                Button {
                    let items = selectedLiveItems
                    Task { await store.retry(items) }
                } label: {
                    Label(L10n.string("重试"), systemImage: "arrow.clockwise")
                }
                .disabled(!selectedLiveItems.contains(where: \.isRetryable))
            }
        }
        .font(LaneFont.interface(11))
        .controlSize(.small)
        .padding(.horizontal, LaneMetric.contentPadding)
        .frame(height: 42)
        .background(LaneColor.surface)
        .disabled(store.isPerformingAction)
    }

    private var taskList: some View {
        List(selection: $selectedEntityIDs) {
            ForEach(visibleEntities) { entity in
                entityRow(entity)
                    .laneListSelectionAppearance()
                    .tag(entity.id)
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

    @ViewBuilder
    private func entityRow(_ entity: TaskEntityRecord) -> some View {
        if let item = organization.liveTransfer(
            for: entity,
            in: store.transfers,
            profileID: preferences.activeServerProfileID
        ) {
            VStack(alignment: .leading, spacing: 0) {
                TransferRowView(
                    item: item,
                    isSelected: selectedEntityIDs.contains(entity.id),
                    allowsQueueReordering: false,
                    displayMode: displayMode
                )

                if !entity.tagIDs.isEmpty && displayMode == .card {
                    TaskTagBadgeRow(entityID: entity.id, limit: 3)
                        .padding(.leading, 72)
                        .padding(.top, -9)
                        .padding(.bottom, 9)
                }
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    if item.status == .complete {
                        store.reveal(item)
                    }
                }
            )
        } else {
            HistoricalTaskEntityRow(
                entity: entity,
                isSelected: selectedEntityIDs.contains(entity.id),
                displayMode: displayMode,
                onReveal: {
                    if let entry = historyEntry(for: entity) {
                        store.reveal(entry)
                    }
                },
                onRedownload: {
                    guard let entry = historyEntry(for: entity) else { return }
                    Task { await store.redownload(entry) }
                },
                onCopySource: {
                    copySource(of: entity)
                },
                onRemove: {
                    pendingHistoryRemoval = historyEntry(for: entity)
                }
            )
        }
    }

    private var organizedEmptyView: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: selectionSystemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(selectionAccent.opacity(0.8))

            Text(L10n.string("这里还没有匹配任务"))
                .font(LaneFont.label(16))

            Text(
                selectionIsSmartFolder
                    ? L10n.string("规则会持续查询当前任务与下载历史。")
                    : L10n.string("从任务菜单或右侧检查器添加这个标签。")
            )
            .font(LaneFont.interface(11))
            .foregroundStyle(.secondary)

            if selectionIsSmartFolder {
                Button(L10n.string("编辑规则"), action: onEditSelection)
                    .controlSize(.small)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var searchEmptyView: some View {
        VStack(spacing: 13) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.string("没有找到“\(searchText)”"))
                .font(LaneFont.label(15))
            Text(L10n.string("可以尝试名称、来源域名、内容类型、协议或标签。"))
                .font(LaneFont.interface(11))
                .foregroundStyle(.secondary)
            Button(L10n.string("清除搜索")) {
                searchText = ""
            }
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var sortMenu: some View {
        Menu {
            Picker(L10n.string("排序方式"), selection: sortFieldBinding) {
                ForEach(TaskEntitySortField.allCases) { field in
                    Label(field.title, systemImage: field.systemImage)
                        .tag(field)
                }
            }

            Divider()

            Picker(L10n.string("排序方向"), selection: sortDirectionBinding) {
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

    private func historyEntry(for entity: TaskEntityRecord) -> DownloadHistoryEntry? {
        organization.historyEntry(for: entity, in: store.historyEntries)
    }

    private func copySource(of entity: TaskEntityRecord) {
        guard let sourceURI = entity.sourceURI else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sourceURI, forType: .string)
    }

    private func headerMetric(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(LaneFont.utility(12))
            }
        }
    }

    private var currentCount: Int {
        scopedEntities.lazy.filter {
            organization.liveTransfer(
                for: $0,
                in: store.transfers,
                profileID: preferences.activeServerProfileID
            ) != nil
        }.count
    }

    private var historyCount: Int {
        max(scopedEntities.count - currentCount, 0)
    }

    private var selectionTitle: String {
        switch selection {
        case .tag(let id):
            organization.tag(id: id)?.displayName ?? L10n.string("标签")
        case .smartFolder(let id):
            organization.smartFolder(id: id)?.displayName ?? L10n.string("智能文件夹")
        case .filter:
            L10n.string("任务")
        }
    }

    private var selectionDetail: String {
        switch selection {
        case .tag:
            L10n.string("手动归类的任务，包含当前状态与下载历史")
        case .smartFolder:
            L10n.string("规则动态查询同一任务的完整生命周期")
        case .filter:
            ""
        }
    }

    private var selectionSystemImage: String {
        switch selection {
        case .tag: "tag.fill"
        case .smartFolder: "folder.badge.gearshape"
        case .filter: "square.stack.3d.up"
        }
    }

    private var selectionAccent: Color {
        switch selection {
        case .tag(let id):
            organization.tag(id: id)?.color.color ?? LaneColor.accent
        case .smartFolder, .filter:
            LaneColor.accent
        }
    }

    private var selectionIsSmartFolder: Bool {
        if case .smartFolder = selection { return true }
        return false
    }

    private var sortField: TaskEntitySortField {
        TaskEntitySortField(rawValue: sortFieldRaw) ?? .addedDate
    }

    private var sortDirection: TransferSortDirection {
        TransferSortDirection(rawValue: sortDirectionRaw) ?? .descending
    }

    private var sortFieldBinding: Binding<TaskEntitySortField> {
        Binding(
            get: { sortField },
            set: { sortFieldRaw = $0.rawValue }
        )
    }

    private var sortDirectionBinding: Binding<TransferSortDirection> {
        Binding(
            get: { sortDirection },
            set: { sortDirectionRaw = $0.rawValue }
        )
    }

    private var historyRemovalBinding: Binding<Bool> {
        Binding(
            get: { pendingHistoryRemoval != nil },
            set: {
                if !$0 {
                    pendingHistoryRemoval = nil
                }
            }
        )
    }
}

private struct HistoricalTaskEntityRow: View {
    @EnvironmentObject private var organization: TaskOrganizationStore

    let entity: TaskEntityRecord
    let isSelected: Bool
    let displayMode: TaskListDisplayMode
    let onReveal: () -> Void
    let onRedownload: () -> Void
    let onCopySource: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: displayMode == .compact ? 11 : 15) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: displayMode == .compact ? 8 : 11,
                    style: .continuous
                )
                    .fill(statusColor.opacity(0.1))
                Image(systemName: entity.lifecycle.systemImage)
                    .font(
                        .system(
                            size: displayMode == .compact ? 10 : 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(statusColor)
            }
            .frame(
                width: displayMode == .compact ? 26 : 40,
                height: displayMode == .compact ? 26 : 40
            )

            VStack(
                alignment: .leading,
                spacing: displayMode == .compact ? 4 : 7
            ) {
                HStack(spacing: 8) {
                    Text(entity.displayName)
                        .font(
                            LaneFont.label(
                                displayMode == .compact ? 11.5 : 14
                            )
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(entity.lifecycle.title)
                        .font(
                            .system(
                                size: displayMode == .compact ? 8 : 9,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(statusColor)
                        .padding(
                            .horizontal,
                            displayMode == .compact ? 6 : 7
                        )
                        .padding(
                            .vertical,
                            displayMode == .compact ? 2 : 3
                        )
                        .background(statusColor.opacity(0.1), in: Capsule())

                    if displayMode == .card {
                        TaskTagBadgeRow(entityID: entity.id, limit: 2)
                    }
                }

                if displayMode == .card {
                    Text(detailText)
                        .font(.system(size: 10))
                        .foregroundStyle(
                            entity.lifecycle == .failed
                                ? LaneColor.danger
                                : .secondary
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            VStack(
                alignment: .trailing,
                spacing: displayMode == .compact ? 4 : 9
            ) {
                if displayMode == .card {
                    Text(
                        (entity.completedAt ?? entity.addedAt)
                            .formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                    )
                    .font(LaneFont.utility(10, weight: .regular))
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    Text(TransferFormatter.bytes(entity.byteCount))
                        .font(
                            LaneFont.utility(
                                displayMode == .compact ? 9 : 10,
                                weight: .regular
                            )
                        )
                        .foregroundStyle(.tertiary)

                    if entity.lifecycle == .completed {
                        actionButton(
                            title: L10n.string("在 Finder 中显示"),
                            systemImage: "folder",
                            action: onReveal
                        )
                    }
                    if entity.sourceURI != nil {
                        actionButton(
                            title: L10n.string("重新下载"),
                            systemImage: "arrow.clockwise",
                            action: onRedownload
                        )
                    }
                    actionButton(
                        title: L10n.string("删除历史记录"),
                        systemImage: "trash",
                        color: LaneColor.danger,
                        action: onRemove
                    )

                    Menu {
                        rowCommands
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(
                                width: displayMode == .compact ? 23 : 25,
                                height: displayMode == .compact ? 23 : 25
                            )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help(L10n.string("更多操作"))
                }
            }
            .frame(
                minWidth: displayMode == .compact ? 132 : 168,
                alignment: .trailing
            )
        }
        .padding(.horizontal, displayMode == .compact ? 11 : 16)
        .padding(.vertical, displayMode == .compact ? 5 : 14)
        .background {
            RoundedRectangle(
                cornerRadius: rowCornerRadius,
                style: .continuous
            )
                .fill(
                    isSelected
                        ? LaneColor.accent.opacity(0.095)
                        : LaneColor.surface.opacity(0.72)
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: rowCornerRadius,
                        style: .continuous
                    )
                    .stroke(
                        isSelected
                            ? Color.clear
                            : LaneColor.line,
                        lineWidth: 1
                    )
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: rowCornerRadius))
        .contextMenu {
            rowCommands
        }
    }

    @ViewBuilder
    private var rowCommands: some View {
        if entity.lifecycle == .completed {
            Button(L10n.string("在 Finder 中显示"), action: onReveal)
        }
        if entity.sourceURI != nil {
            Button(L10n.string("重新下载"), action: onRedownload)
            Button(L10n.string("复制来源地址"), action: onCopySource)
        }
        TaskTagCommandMenu(entityIDs: [entity.id])
        Divider()
        Button(L10n.string("移除历史记录"), role: .destructive, action: onRemove)
    }

    private var statusColor: Color {
        entity.lifecycle == .failed ? LaneColor.danger : LaneColor.mint
    }

    private var rowCornerRadius: CGFloat {
        displayMode == .compact
            ? LaneMetric.compactRadius
            : LaneMetric.cornerRadius
    }

    private var detailText: String {
        if entity.lifecycle == .failed,
           let detail = entity.detail,
           !detail.isEmpty {
            return detail
        }
        return entity.destinationPath
    }

    private func actionButton(
        title: String,
        systemImage: String,
        color: Color = LaneColor.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size: displayMode == .compact ? 9 : 10,
                        weight: .semibold
                    )
                )
                .foregroundStyle(color)
                .frame(
                    width: displayMode == .compact ? 23 : 25,
                    height: displayMode == .compact ? 23 : 25
                )
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}

struct TaskEntityInspectorView: View {
    @EnvironmentObject private var store: DownloadStore
    @EnvironmentObject private var organization: TaskOrganizationStore

    let entity: TaskEntityRecord

    @State private var isConfirmingRemoval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: entity.contentType.systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(LaneColor.accent)
                        .frame(width: 34, height: 34)
                        .background(
                            LaneColor.accent.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 9)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(entity.displayName)
                            .font(LaneFont.label(15))
                            .lineLimit(3)
                        Text(entity.lifecycle.title)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(lifecycleColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(lifecycleColor.opacity(0.1), in: Capsule())
                    }
                }

                Divider()

                TaskTagsSection(entityID: entity.id)

                Divider()

                VStack(alignment: .leading, spacing: 17) {
                    InfoPair(label: L10n.string("内容类型"), value: entity.contentType.title)
                    InfoPair(label: L10n.string("传输协议"), value: entity.transferProtocol.title)
                    if let domain = entity.sourceDomain {
                        InfoPair(label: L10n.string("来源域名"), value: domain)
                    }
                    InfoPair(
                        label: entity.addedAtIsInferred ? L10n.string("首次观察") : L10n.string("加入日期"),
                        value: entity.addedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    if let completedAt = entity.completedAt {
                        InfoPair(
                            label: L10n.string("完成日期"),
                            value: completedAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                    }
                    InfoPair(
                        label: L10n.string("文件大小"),
                        value: TransferFormatter.bytes(entity.byteCount),
                        isMonospaced: true
                    )
                    InfoPair(label: L10n.string("保存位置"), value: entity.destinationPath)
                    if let source = entity.sourceURI {
                        InfoPair(label: L10n.string("来源"), value: source)
                    }
                }

                VStack(spacing: 9) {
                    if entity.lifecycle == .completed {
                        Button {
                            if let entry = historyEntry {
                                store.reveal(entry)
                            }
                        } label: {
                            Label(L10n.string("在 Finder 中显示"), systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let entry = historyEntry, entry.sourceURI != nil {
                        Button {
                            Task { await store.redownload(entry) }
                        } label: {
                            Label(L10n.string("重新下载"), systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if historyEntry != nil {
                        Button(role: .destructive) {
                            isConfirmingRemoval = true
                        } label: {
                            Label(L10n.string("移除历史记录"), systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(18)
        }
        .background(LaneColor.surface)
        .sheet(isPresented: $isConfirmingRemoval) {
            if let historyEntry {
                LocalFileDeletionConfirmationView(
                    title: L10n.string("删除这条下载历史？"),
                    message: L10n.string("删除后将不再出现在 AriaLane 的任务记录中。"),
                    actionTitle: L10n.string("删除历史记录"),
                    canDeleteLocalFiles:
                        !historyEntry.localPathsForRemoval.isEmpty
                ) { deleteLocalFiles in
                    isConfirmingRemoval = false
                    Task {
                        await store.removeHistory(
                            ids: [historyEntry.id],
                            deletingLocalFiles: deleteLocalFiles
                        )
                    }
                }
            }
        }
    }

    private var historyEntry: DownloadHistoryEntry? {
        organization.historyEntry(for: entity, in: store.historyEntries)
    }

    private var lifecycleColor: Color {
        entity.lifecycle == .failed ? LaneColor.danger : LaneColor.mint
    }
}
