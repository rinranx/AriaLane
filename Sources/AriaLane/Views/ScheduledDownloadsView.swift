import SwiftUI

struct ScheduledDownloadsView: View {
    @Environment(\.laneWindowContentSize) private var windowContentSize
    @EnvironmentObject private var store: DownloadStore
    @SceneStorage("scheduleSearchText") private var searchText = ""
    @State private var editingEntry: ScheduledDownload?
    @State private var isShowingNewSchedule = false

    private var visibleEntries: [ScheduledDownload] {
        store.scheduledDownloads.filter { $0.matches(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.7)

            if store.scheduledDownloads.isEmpty {
                emptyState
            } else if visibleEntries.isEmpty {
                searchEmptyState
            } else {
                List {
                    ForEach(visibleEntries) { entry in
                        ScheduledDownloadRow(
                            entry: entry,
                            onStartNow: {
                                Task { await store.startScheduledDownloadNow(id: entry.id) }
                            },
                            onEdit: {
                                editingEntry = entry
                            },
                            onDuplicate: {
                                store.duplicateScheduledDownload(id: entry.id)
                            },
                            onCancel: {
                                store.cancelScheduledDownload(id: entry.id)
                            }
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 5,
                                leading: LaneMetric.contentPadding,
                                bottom: 5,
                                trailing: LaneMetric.contentPadding
                            )
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.vertical, 11, for: .scrollContent)
            }
        }
        .background(LaneColor.canvas)
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: L10n.string("搜索计划任务")
        )
        .sheet(item: $editingEntry) { entry in
            EditScheduledDownloadView(entry: entry)
        }
        .sheet(isPresented: $isShowingNewSchedule) {
            AddDownloadView(
                startsScheduled: true,
                availableSize: windowContentSize
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("计划任务"))
                    .font(LaneFont.display(27))
                Text(L10n.string("到达设定时间后安全转入待发送队列，并提交到原 aria2 服务器"))
                    .font(LaneFont.interface(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Label(
                    L10n.string("\(store.scheduledDownloads.count) 个待执行"),
                    systemImage: "calendar.badge.clock"
                )
                .font(LaneFont.utility(11, weight: .medium))
                .foregroundStyle(LaneColor.accent)

                Button {
                    isShowingNewSchedule = true
                } label: {
                    Label(L10n.string("新增计划"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, LaneMetric.contentPadding)
        .padding(.top, 23)
        .padding(.bottom, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.string("还没有计划任务"))
                .font(LaneFont.label(16))
            Text(L10n.string("添加下载时打开“开始时间”，即可安排稍后自动开始。"))
                .font(LaneFont.interface(11))
                .foregroundStyle(.secondary)
            Button {
                isShowingNewSchedule = true
            } label: {
                Label(L10n.string("新增计划任务"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 13) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.string("没有找到“\(searchText)”"))
                .font(LaneFont.label(15))
            Button(L10n.string("清除搜索")) {
                searchText = ""
            }
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

private struct ScheduledDownloadRow: View {
    let entry: ScheduledDownload
    let onStartNow: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LaneColor.accent)
                .frame(width: 40, height: 40)
                .background(
                    LaneColor.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(entry.displayName)
                    .font(LaneFont.label(14))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(entry.taskOptions.directory)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(entry.serverDisplayName)
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Label(entry.frequency.shortTitle, systemImage: "repeat")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(
                            entry.frequency == .once
                                ? Color.secondary.opacity(0.62)
                                : LaneColor.accent
                        )
                }
                .font(LaneFont.interface(10))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text(scheduleTitle)
                    .font(LaneFont.utility(11, weight: .medium))
                    .foregroundStyle(entry.isOverdue() ? LaneColor.amber : .primary)

                HStack(spacing: 7) {
                    Text(entry.urls.count == 1 ? L10n.string("1 个链接") : L10n.string("\(entry.urls.count) 个链接"))
                        .font(LaneFont.interface(9))
                        .foregroundStyle(.tertiary)
                    Button(L10n.string("立即开始"), action: onStartNow)
                        .controlSize(.small)
                    Button(L10n.string("编辑"), action: onEdit)
                        .controlSize(.small)

                    Menu {
                        Button(L10n.string("复制计划任务"), action: onDuplicate)
                        Divider()
                        Button(L10n.string("取消计划任务"), role: .destructive, action: onCancel)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help(L10n.string("更多操作"))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: LaneMetric.cornerRadius, style: .continuous)
                .fill(LaneColor.surface.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: LaneMetric.cornerRadius, style: .continuous)
                        .stroke(LaneColor.line, lineWidth: 1)
                }
        }
        .contextMenu {
            Button(L10n.string("立即开始"), action: onStartNow)
            Button(L10n.string("编辑…"), action: onEdit)
            Button(L10n.string("复制计划任务"), action: onDuplicate)
            Divider()
            Button(L10n.string("取消计划任务"), role: .destructive, action: onCancel)
        }
    }

    private var scheduleTitle: String {
        if entry.isOverdue() {
            return L10n.string("已到时间，等待处理")
        }
        let date = entry.scheduledAt.formatted(date: .abbreviated, time: .shortened)
        return entry.frequency == .once ? date : "\(date) · \(entry.frequency.title)"
    }
}
