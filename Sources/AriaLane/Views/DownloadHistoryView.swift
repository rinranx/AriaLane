import AppKit
import SwiftUI

struct DownloadHistoryView: View {
    @EnvironmentObject private var store: DownloadStore
    @EnvironmentObject private var organization: TaskOrganizationStore

    @SceneStorage("historySearchText") private var searchText = ""
    @SceneStorage("historySort") private var sortRaw = DownloadHistorySort.newest.rawValue
    @AppStorage("taskListDisplayMode") private var displayModeRaw = TaskListDisplayMode.card.rawValue
    @StateObject private var viewState = DownloadHistoryViewState()

    private var sort: DownloadHistorySort {
        DownloadHistorySort(rawValue: sortRaw) ?? .newest
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

    private var visibleEntries: [DownloadHistoryEntry] {
        let matching = store.historyEntries.filter { entry in
            guard !searchText.trimmed.isEmpty else { return true }
            if entry.matches(searchText) {
                return true
            }
            guard let entity = entity(for: entry) else { return false }
            return entity.matches(
                searchText,
                tagNames: organization.tags(for: entity).map(\.displayName)
            )
        }
        return sort.results(in: matching, searchText: "")
    }

    private var selectedEntries: [DownloadHistoryEntry] {
        store.historyEntries.filter { viewState.selectedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            historyHeader

            Divider()
                .opacity(0.7)

            historyUtilityBar

            Divider()
                .opacity(0.55)

            if store.historyEntries.isEmpty {
                HistoryEmptyView()
            } else if visibleEntries.isEmpty {
                historySearchEmpty
            } else {
                List(selection: $viewState.selectedIDs) {
                    ForEach(visibleEntries) { entry in
                        DownloadHistoryRow(
                            entry: entry,
                            entityID: entity(for: entry)?.id,
                            isSelected: viewState.selectedIDs.contains(entry.id),
                            displayMode: displayMode,
                            onReveal: { store.reveal(entry) },
                            onRedownload: {
                                Task { await store.redownload(entry) }
                            },
                            onCopySource: { copySource(of: entry) },
                            onRemove: {
                                viewState.removalRequest = .selected([entry.id])
                            }
                        )
                        .laneListSelectionAppearance()
                        .tag(entry.id)
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
        }
        .background(LaneColor.canvas)
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: L10n.string("搜索下载历史")
        )
        .sheet(isPresented: removalBinding) {
            LocalFileDeletionConfirmationView(
                title: removalTitle,
                message: L10n.string("删除后将不再出现在 AriaLane 的下载历史中。"),
                actionTitle: removalActionTitle,
                canDeleteLocalFiles: removalEntries.contains {
                    !$0.localPathsForRemoval.isEmpty
                }
            ) { deleteLocalFiles in
                commitRemoval(deletingLocalFiles: deleteLocalFiles)
            }
        }
        .onChange(of: visibleEntries.map(\.id)) { _, visibleIDs in
            viewState.selectedIDs.formIntersection(Set(visibleIDs))
        }
    }

    private var historyHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("下载历史"))
                    .font(LaneFont.display(27))
                Text(L10n.string("完成与失败记录保存在这台 Mac，不受 aria2 清理影响"))
                    .font(LaneFont.interface(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 22) {
                historyMetric(
                    icon: "checkmark",
                    label: L10n.string("已完成"),
                    value: String(completedCount),
                    color: LaneColor.mint
                )
                historyMetric(
                    icon: "externaldrive",
                    label: L10n.string("累计文件"),
                    value: TransferFormatter.bytes(completedBytes),
                    color: LaneColor.accent
                )
            }
        }
        .padding(.horizontal, LaneMetric.contentPadding)
        .padding(.top, 23)
        .padding(.bottom, 20)
    }

    private var historyUtilityBar: some View {
        HStack(spacing: 10) {
            if selectedEntries.isEmpty {
                Text(L10n.string("\(visibleEntries.count) 条记录"))
                    .font(LaneFont.utility(10, weight: .regular))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    viewState.selectedIDs = Set(visibleEntries.map(\.id))
                } label: {
                    Label(L10n.string("全选"), systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .disabled(visibleEntries.isEmpty)

                TaskListDisplayModePicker(selection: displayModeBinding)

                historySortMenu

                Button {
                    viewState.removalRequest = .all
                } label: {
                    Label(L10n.string("清空历史"), systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(store.historyEntries.isEmpty)
            } else {
                Label(
                    L10n.string("已选择 \(selectedEntries.count) 条"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(LaneFont.interface(11, weight: .semibold))
                .foregroundStyle(LaneColor.accent)

                Button(L10n.string("取消选择")) {
                    viewState.selectedIDs.removeAll()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(role: .destructive) {
                    viewState.removalRequest = .selected(viewState.selectedIDs)
                } label: {
                    Label(L10n.string("移除记录"), systemImage: "trash")
                }
            }
        }
        .font(LaneFont.interface(11))
        .controlSize(.small)
        .padding(.horizontal, LaneMetric.contentPadding)
        .frame(height: 42)
        .background(LaneColor.surface)
    }

    private var historySortMenu: some View {
        Menu {
            Picker(L10n.string("排序方式"), selection: sortBinding) {
                ForEach(DownloadHistorySort.allCases) { option in
                    Label(option.title, systemImage: option.systemImage)
                        .tag(option)
                }
            }
        } label: {
            Label(sort.title, systemImage: sort.systemImage)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var historySearchEmpty: some View {
        VStack(spacing: 13) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.string("没有找到“\(searchText)”"))
                .font(LaneFont.label(15))
            Text(L10n.string("可以尝试文件名、来源地址或保存路径。"))
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

    private var completedCount: Int {
        store.historyEntries.filter { $0.outcome == .completed }.count
    }

    private var completedBytes: Int64 {
        store.historyEntries
            .filter { $0.outcome == .completed }
            .reduce(Int64(0)) { $0 + $1.byteCount }
    }

    private var sortBinding: Binding<DownloadHistorySort> {
        Binding(
            get: { sort },
            set: { sortRaw = $0.rawValue }
        )
    }

    private var removalBinding: Binding<Bool> {
        Binding(
            get: { viewState.removalRequest != nil },
            set: { isPresented in
                if !isPresented {
                    viewState.removalRequest = nil
                }
            }
        )
    }

    private var removalTitle: String {
        switch viewState.removalRequest {
        case .selected(let ids):
            L10n.string("移除 \(ids.count) 条历史记录？")
        case .all:
            L10n.string("清空全部下载历史？")
        case nil:
            L10n.string("移除下载历史？")
        }
    }

    private var removalActionTitle: String {
        switch viewState.removalRequest {
        case .all:
            L10n.string("清空历史")
        case .selected, nil:
            L10n.string("移除记录")
        }
    }

    private func historyMetric(
        icon: String,
        label: String,
        value: String,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(LaneFont.utility(11))
            }
        }
    }

    private func copySource(of entry: DownloadHistoryEntry) {
        guard let sourceURI = entry.sourceURI else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sourceURI, forType: .string)
    }

    private func entity(for entry: DownloadHistoryEntry) -> TaskEntityRecord? {
        organization.entities.first {
            $0.attempts.contains { $0.gid == entry.gid }
        }
    }

    private var removalEntries: [DownloadHistoryEntry] {
        switch viewState.removalRequest {
        case .selected(let ids):
            store.historyEntries.filter { ids.contains($0.id) }
        case .all:
            store.historyEntries
        case nil:
            []
        }
    }

    private func commitRemoval(deletingLocalFiles: Bool) {
        guard let request = viewState.removalRequest else { return }
        viewState.removalRequest = nil

        switch request {
        case .selected(let ids):
            viewState.selectedIDs.subtract(ids)
            Task {
                await store.removeHistory(
                    ids: ids,
                    deletingLocalFiles: deletingLocalFiles
                )
            }
        case .all:
            viewState.selectedIDs.removeAll()
            Task {
                await store.clearHistory(
                    deletingLocalFiles: deletingLocalFiles
                )
            }
        }
    }
}

private enum HistoryRemovalRequest {
    case selected(Set<String>)
    case all
}

@MainActor
private final class DownloadHistoryViewState: ObservableObject {
    @Published var selectedIDs: Set<String> = []
    @Published var removalRequest: HistoryRemovalRequest?
}

private struct DownloadHistoryRow: View {
    let entry: DownloadHistoryEntry
    let entityID: UUID?
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
                    .fill(outcomeColor.opacity(0.1))
                Image(systemName: entry.outcome.systemImage)
                    .font(
                        .system(
                            size: displayMode == .compact ? 10 : 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(outcomeColor)
            }
            .frame(
                width: displayMode == .compact ? 26 : 40,
                height: displayMode == .compact ? 26 : 40
            )

            VStack(alignment: .leading, spacing: displayMode == .compact ? 4 : 7) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(
                            LaneFont.label(
                                displayMode == .compact ? 11.5 : 14
                            )
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(entry.outcome.title)
                        .font(
                            .system(
                                size: displayMode == .compact ? 8 : 9,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(outcomeColor)
                        .padding(
                            .horizontal,
                            displayMode == .compact ? 6 : 7
                        )
                        .padding(
                            .vertical,
                            displayMode == .compact ? 2 : 3
                        )
                        .background(outcomeColor.opacity(0.1), in: Capsule())

                    if let entityID, displayMode == .card {
                        TaskTagBadgeRow(entityID: entityID, limit: 2)
                    }
                }

                if displayMode == .card {
                    Text(detailText)
                        .font(.system(size: 10))
                        .foregroundStyle(
                            entry.outcome == .failed
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
                        entry.recordedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(LaneFont.utility(10, weight: .regular))
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    Text(TransferFormatter.bytes(entry.byteCount))
                        .font(
                            LaneFont.utility(
                                displayMode == .compact ? 9 : 10,
                                weight: .regular
                            )
                        )
                        .foregroundStyle(.tertiary)

                    if entry.outcome == .completed {
                        historyActionButton(
                            title: L10n.string("在 Finder 中显示"),
                            systemImage: "folder",
                            action: onReveal
                        )
                    }
                    if entry.sourceURI != nil {
                        historyActionButton(
                            title: L10n.string("重新下载"),
                            systemImage: "arrow.clockwise",
                            action: onRedownload
                        )
                    }
                    historyActionButton(
                        title: L10n.string("删除历史记录"),
                        systemImage: "trash",
                        color: LaneColor.danger,
                        action: onRemove
                    )

                    Menu {
                        if entry.outcome == .completed {
                            Button(L10n.string("在 Finder 中显示"), action: onReveal)
                        }
                        if entry.sourceURI != nil {
                            Button(L10n.string("重新下载"), action: onRedownload)
                            Button(L10n.string("复制来源地址"), action: onCopySource)
                        }
                        if let entityID {
                            TaskTagCommandMenu(entityIDs: [entityID])
                        }
                        Divider()
                        Button(L10n.string("移除历史记录"), role: .destructive, action: onRemove)
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
                cornerRadius: displayMode == .compact
                    ? LaneMetric.compactRadius
                    : LaneMetric.cornerRadius,
                style: .continuous
            )
                .fill(isSelected ? LaneColor.accent.opacity(0.095) : LaneColor.surface.opacity(0.72))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: displayMode == .compact
                            ? LaneMetric.compactRadius
                            : LaneMetric.cornerRadius,
                        style: .continuous
                    )
                        .stroke(
                            isSelected ? Color.clear : LaneColor.line,
                            lineWidth: 1
                        )
                }
        }
        .contentShape(
            RoundedRectangle(
                cornerRadius: displayMode == .compact
                    ? LaneMetric.compactRadius
                    : LaneMetric.cornerRadius
            )
        )
        .contextMenu {
            if entry.outcome == .completed {
                Button(L10n.string("在 Finder 中显示"), action: onReveal)
            }
            if entry.sourceURI != nil {
                Button(L10n.string("重新下载"), action: onRedownload)
                Button(L10n.string("复制来源地址"), action: onCopySource)
            }
            if let entityID {
                TaskTagCommandMenu(entityIDs: [entityID])
            }
            Divider()
            Button(L10n.string("移除历史记录"), role: .destructive, action: onRemove)
        }
    }

    private var outcomeColor: Color {
        switch entry.outcome {
        case .completed: LaneColor.mint
        case .failed: LaneColor.danger
        }
    }

    private var detailText: String {
        if entry.outcome == .failed, let detail = entry.detail, !detail.isEmpty {
            return detail
        }
        return entry.destinationPath
    }

    private func historyActionButton(
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

private struct HistoryEmptyView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LaneColor.mint.opacity(0.09))
                    .frame(width: 78, height: 78)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 29, weight: .light))
                    .foregroundStyle(LaneColor.mint)
            }

            Text(L10n.string("完成的旅程会留在这里"))
                .font(LaneFont.display(18))

            Text(L10n.string("任务完成或失败后会自动记录，清理 aria2 列表也不会影响历史。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}
