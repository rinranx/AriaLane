import SwiftUI

struct PendingDownloadsView: View {
    @EnvironmentObject private var store: DownloadStore
    @Binding var searchText: String

    private var visibleEntries: [PendingDownload] {
        store.pendingDownloads.filter { $0.matches(searchText) }
    }

    private var failedCount: Int {
        store.pendingDownloads.filter(\.hasFailed).count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.7)

            utilityBar

            Divider()
                .opacity(0.55)

            if store.pendingDownloads.isEmpty {
                emptyState
            } else if visibleEntries.isEmpty {
                searchEmptyState
            } else {
                List {
                    ForEach(visibleEntries) { entry in
                        PendingDownloadRow(
                            entry: entry,
                            isForCurrentProfile: entry.isForProfile(
                                store.preferences.activeServerProfileID
                            ),
                            onRetry: {
                                Task { await store.retryPendingDownload(id: entry.id) }
                            },
                            onRetarget: {
                                Task {
                                    await store.retargetPendingDownloadToActiveServer(
                                        id: entry.id
                                    )
                                }
                            },
                            onCancel: {
                                store.cancelPendingDownload(id: entry.id)
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
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("待发送"))
                    .font(LaneFont.display(27))
                Text(L10n.string("断线时安全保存，连接恢复后自动发送到原服务器"))
                    .font(LaneFont.interface(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 18) {
                headerMetric(
                    value: store.pendingDownloads.count,
                    label: L10n.string("等待"),
                    color: LaneColor.accent
                )
                if failedCount > 0 {
                    headerMetric(
                        value: failedCount,
                        label: L10n.string("需处理"),
                        color: LaneColor.danger
                    )
                }
            }
        }
        .padding(.horizontal, LaneMetric.contentPadding)
        .padding(.top, 23)
        .padding(.bottom, 20)
    }

    private var utilityBar: some View {
        HStack(spacing: 10) {
            Text(L10n.string("当前服务器：\(store.preferences.activeServerProfileName)"))
                .font(LaneFont.utility(10, weight: .regular))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer()

            Button {
                Task { await store.reconnect() }
            } label: {
                Label(L10n.string("重新连接"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.connectionState == .connecting)

            Button {
                Task { await store.retryAllPendingDownloads() }
            } label: {
                Label(L10n.string("全部重试"), systemImage: "paperplane")
            }
            .buttonStyle(.borderless)
            .disabled(store.pendingDownloads.isEmpty)
        }
        .font(LaneFont.interface(11))
        .controlSize(.small)
        .padding(.horizontal, LaneMetric.contentPadding)
        .frame(height: 42)
        .background(LaneColor.surface)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.string("没有待发送任务"))
                .font(LaneFont.label(16))
            Text(L10n.string("连接中断时添加的链接会保存在这里，并在恢复后自动发送。"))
                .font(LaneFont.interface(11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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

    private func headerMetric(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(value))
                    .font(LaneFont.utility(12))
                Text(label)
                    .font(LaneFont.interface(9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct PendingDownloadRow: View {
    let entry: PendingDownload
    let isForCurrentProfile: Bool
    let onRetry: () -> Void
    let onRetarget: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(statusColor.opacity(0.1))
                Image(systemName: entry.hasFailed ? "exclamationmark" : "paperplane")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(entry.displayName)
                        .font(LaneFont.label(14))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(statusTitle)
                        .font(LaneFont.interface(9, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.1), in: Capsule())
                }

                Text(detailText)
                    .font(LaneFont.interface(10))
                    .foregroundStyle(entry.hasFailed ? LaneColor.danger : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text(entry.serverDisplayName)
                    .font(LaneFont.interface(10))
                    .foregroundStyle(isForCurrentProfile ? .secondary : LaneColor.amber)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(LaneFont.utility(9, weight: .regular))
                        .foregroundStyle(.tertiary)

                    Button(L10n.string("重试"), action: onRetry)
                        .controlSize(.small)
                        .disabled(!isForCurrentProfile)

                    Menu {
                        Button(L10n.string("立即重试"), action: onRetry)
                            .disabled(!isForCurrentProfile)
                        if !isForCurrentProfile {
                            Button(L10n.string("改发到当前服务器"), action: onRetarget)
                        }
                        Divider()
                        Button(L10n.string("取消待发送任务"), role: .destructive, action: onCancel)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help(L10n.string("更多操作"))
                }
            }
            .frame(minWidth: 190, alignment: .trailing)
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
            Button(L10n.string("立即重试"), action: onRetry)
                .disabled(!isForCurrentProfile)
            if !isForCurrentProfile {
                Button(L10n.string("改发到当前服务器"), action: onRetarget)
            }
            Divider()
            Button(L10n.string("取消待发送任务"), role: .destructive, action: onCancel)
        }
    }

    private var statusColor: Color {
        if !isForCurrentProfile {
            return LaneColor.amber
        }
        return entry.hasFailed ? LaneColor.danger : LaneColor.accent
    }

    private var statusTitle: String {
        if !isForCurrentProfile {
            return L10n.string("等待原服务器")
        }
        return entry.hasFailed ? L10n.string("发送失败") : L10n.string("等待连接")
    }

    private var detailText: String {
        if let lastError = entry.lastError, !lastError.trimmed.isEmpty {
            return lastError
        }
        return entry.url
    }
}
