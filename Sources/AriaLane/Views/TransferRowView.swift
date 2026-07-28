import SwiftUI

struct TransferRowView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore
    @EnvironmentObject private var organization: TaskOrganizationStore

    let item: TransferItem
    let isSelected: Bool
    let allowsQueueReordering: Bool
    let displayMode: TaskListDisplayMode

    var body: some View {
        HStack(spacing: displayMode == .compact ? 11 : 15) {
            if item.isQueueMovable && allowsQueueReordering {
                Image(systemName: "line.3.horizontal")
                    .font(
                        .system(
                            size: displayMode == .compact ? 9 : 10,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.tertiary)
                    .help(L10n.string("拖动调整队列顺序"))
            }

            statusGlyph

            VStack(
                alignment: .leading,
                spacing: displayMode == .compact ? 5 : 9
            ) {
                HStack(spacing: 9) {
                    Text(item.displayName)
                        .font(
                            LaneFont.label(
                                displayMode == .compact ? 11.5 : 14
                            )
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)

                    StatusBadge(
                        status: item.status,
                        isCompact: displayMode == .compact
                    )

                    if let entityID, displayMode == .card {
                        TaskTagBadgeRow(entityID: entityID, limit: 2)
                    }
                }

                SegmentedProgressView(
                    progress: item.progress,
                    status: item.status,
                    height: displayMode == .compact ? 3 : 5
                )

                if displayMode == .card {
                    HStack(spacing: 6) {
                        Text(
                            TransferFormatter.bytes(
                                item.completedByteCount
                            )
                        )
                        .font(LaneFont.utility(10, weight: .regular))
                        Text("/")
                            .font(
                                LaneFont.utility(
                                    10,
                                    weight: .regular
                                )
                            )
                            .foregroundStyle(.quaternary)
                        Text(
                            TransferFormatter.bytes(
                                item.totalByteCount
                            )
                        )
                        .font(LaneFont.utility(10, weight: .regular))

                        if item.status == .active {
                            Text("·")
                                .foregroundStyle(.quaternary)
                            Text(
                                TransferFormatter.duration(
                                    item.remainingSeconds
                                )
                            )
                            .font(
                                LaneFont.utility(
                                    10,
                                    weight: .regular
                                )
                            )
                        } else if item.status == .error,
                                  let error = item.userFacingError {
                            Text("·")
                                .foregroundStyle(.quaternary)
                            Text(error)
                                .font(LaneFont.interface(10))
                                .foregroundStyle(LaneColor.danger)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            VStack(
                alignment: .trailing,
                spacing: displayMode == .compact ? 6 : 12
            ) {
                if displayMode == .card {
                    if item.status == .active {
                        Text(
                            TransferFormatter.speed(
                                item.downloadSpeedValue
                            )
                        )
                        .font(LaneFont.utility(11))
                        .foregroundStyle(LaneColor.accent)
                        .contentTransition(.numericText())
                    } else {
                        Text(TransferFormatter.percent(item.progress))
                            .font(LaneFont.utility(11))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    if item.isPausable {
                        actionButton(
                            title: L10n.string("暂停"),
                            systemImage: "pause.fill"
                        ) {
                            Task { await store.pause(item) }
                        }
                    } else if item.isResumable {
                        actionButton(
                            title: L10n.string("继续"),
                            systemImage: "play.fill"
                        ) {
                            Task { await store.resume(item) }
                        }
                    } else if item.isRetryable {
                        actionButton(
                            title: L10n.string("重新下载"),
                            systemImage: "arrow.clockwise"
                        ) {
                            Task { await store.retry(item) }
                        }
                    } else if item.status == .complete {
                        actionButton(
                            title: L10n.string("在 Finder 中显示"),
                            systemImage: "folder"
                        ) {
                            store.reveal(item)
                        }
                    }

                    Menu {
                        if item.isPausable {
                            Button(L10n.string("暂停")) {
                                Task { await store.pause(item) }
                            }
                        }
                        if item.isResumable {
                            Button(L10n.string("继续")) {
                                Task { await store.resume(item) }
                            }
                        }
                        if item.isRetryable {
                            Button(L10n.string("重新下载")) {
                                Task { await store.retry(item) }
                            }
                        }
                        if item.status == .complete {
                            Button(L10n.string("在 Finder 中显示")) {
                                store.reveal(item)
                            }
                        }
                        if item.isQueueMovable {
                            queueMenu
                        }
                        if let entityID {
                            TaskTagCommandMenu(entityIDs: [entityID])
                        }
                        Divider()
                        Button(L10n.string("移除任务"), role: .destructive) {
                            Task { await store.remove(item) }
                        }
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
                .opacity(isSelected ? 1 : 0.72)
            }
            .frame(
                minWidth: displayMode == .compact ? 54 : 112,
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
                .fill(isSelected ? LaneColor.accent.opacity(0.095) : LaneColor.surface.opacity(0.72))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: rowCornerRadius,
                        style: .continuous
                    )
                        .stroke(
                            isSelected ? Color.clear : LaneColor.line,
                            lineWidth: 1
                        )
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: rowCornerRadius))
        .contextMenu {
            if item.isPausable {
                Button(L10n.string("暂停")) {
                    Task { await store.pause(item) }
                }
                Button(L10n.string("强制暂停")) {
                    Task { await store.forcePause(item) }
                }
            }
            if item.isResumable {
                Button(L10n.string("继续")) {
                    Task { await store.resume(item) }
                }
            }
            if item.isRetryable {
                Button(L10n.string("重新下载")) {
                    Task { await store.retry(item) }
                }
            }
            if item.status == .complete {
                Button(L10n.string("在 Finder 中显示")) {
                    store.reveal(item)
                }
            }
            if item.isQueueMovable {
                queueMenu
            }
            if let entityID {
                TaskTagCommandMenu(entityIDs: [entityID])
            }
            Divider()
            Button(L10n.string("移除任务"), role: .destructive) {
                Task { await store.remove(item) }
            }
        }
        .modifier(
            QueueDragModifier(
                item: item,
                allowsQueueReordering: allowsQueueReordering
            )
        )
        .accessibilityElement(children: .contain)
    }

    private var entityID: UUID? {
        organization.entityID(
            gid: item.gid,
            profileID: preferences.activeServerProfileID
        )
    }

    private var queueMenu: some View {
        Menu(L10n.string("调整队列")) {
            Button(L10n.string("移到队首")) {
                Task { await store.moveQueueItem(item, direction: .top) }
            }
            Button(L10n.string("上移")) {
                Task { await store.moveQueueItem(item, direction: .up) }
            }
            Button(L10n.string("下移")) {
                Task { await store.moveQueueItem(item, direction: .down) }
            }
            Button(L10n.string("移到队尾")) {
                Task { await store.moveQueueItem(item, direction: .bottom) }
            }
        }
    }

    private var statusGlyph: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: displayMode == .compact ? 8 : 11,
                style: .continuous
            )
                .fill(glyphColor.opacity(0.1))
            Image(systemName: item.status.systemImage)
                .font(
                    .system(
                        size: displayMode == .compact ? 10 : 14,
                        weight: .semibold
                    )
                )
                .foregroundStyle(glyphColor)
        }
        .frame(
            width: displayMode == .compact ? 26 : 40,
            height: displayMode == .compact ? 26 : 40
        )
    }

    private var rowCornerRadius: CGFloat {
        displayMode == .compact
            ? LaneMetric.compactRadius
            : LaneMetric.cornerRadius
    }

    private var glyphColor: Color {
        switch item.status {
        case .active: LaneColor.accent
        case .waiting: LaneColor.amber
        case .paused: .secondary
        case .error: LaneColor.danger
        case .complete: LaneColor.mint
        case .removed: .secondary
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
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
                .frame(
                    width: displayMode == .compact ? 23 : 25,
                    height: displayMode == .compact ? 23 : 25
                )
        }
        .buttonStyle(.borderless)
        .help(title)
        .disabled(store.isPerformingAction)
    }
}

private struct QueueDragModifier: ViewModifier {
    @EnvironmentObject private var store: DownloadStore
    let item: TransferItem
    let allowsQueueReordering: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if item.isQueueMovable && allowsQueueReordering {
            content
                .draggable(item.queueDragPayload)
                .dropDestination(for: String.self) { payloads, _ in
                    guard let payload = payloads.first,
                          payload.hasPrefix("arialane-gid:") else {
                        return false
                    }
                    let gid = String(payload.dropFirst("arialane-gid:".count))
                    Task { await store.moveQueueItem(gid: gid, before: item) }
                    return true
                }
        } else {
            content
        }
    }
}
