import SwiftUI

struct TransferInspectorView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore
    @EnvironmentObject private var organization: TaskOrganizationStore
    @StateObject private var advancedDetails = TransferAdvancedDetailsModel()
    let item: TransferItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 11) {
                        FlowMark(size: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayName)
                                .font(LaneFont.label(15))
                                .lineLimit(3)
                            StatusBadge(status: item.status)
                        }
                    }

                    HStack(alignment: .lastTextBaseline) {
                        Text(TransferFormatter.percent(item.progress))
                            .font(LaneFont.display(31))
                        Spacer()
                        if item.status == .active {
                            Text(TransferFormatter.speed(item.downloadSpeedValue))
                                .font(LaneFont.utility(11))
                                .foregroundStyle(LaneColor.accent)
                        }
                    }

                    SegmentedProgressView(
                        progress: item.progress,
                        status: item.status,
                        height: 6
                    )
                }

                Divider()

                if let entityID {
                    TaskTagsSection(entityID: entityID)
                    Divider()
                }

                VStack(alignment: .leading, spacing: 17) {
                    InfoPair(
                        label: L10n.string("已下载"),
                        value: "\(TransferFormatter.bytes(item.completedByteCount)) / \(TransferFormatter.bytes(item.totalByteCount))",
                        isMonospaced: true
                    )
                    InfoPair(
                        label: L10n.string("剩余时间"),
                        value: TransferFormatter.duration(item.remainingSeconds)
                    )
                    InfoPair(label: L10n.string("保存位置"), value: item.displayPath)
                    if let source = item.sourceURI {
                        InfoPair(label: L10n.string("来源"), value: source)
                    }
                    InfoPair(label: "GID", value: item.gid, isMonospaced: true)
                }

                if let errorMessage = item.userFacingError, !errorMessage.isEmpty {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(LaneColor.danger)
                        Text(errorMessage)
                            .font(LaneFont.interface(11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LaneColor.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                if item.status == .active || item.status == .waiting || item.status == .paused {
                    TaskSpeedLimitView(item: item)
                }

                TransferAdvancedDetailsView(model: advancedDetails, item: item)

                if item.isQueueMovable {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("队列优先级"))
                            .font(LaneFont.interface(12, weight: .semibold))

                        HStack(spacing: 7) {
                            queueButton(L10n.string("队首"), icon: "arrow.up.to.line", direction: .top)
                            queueButton(L10n.string("上移"), icon: "arrow.up", direction: .up)
                            queueButton(L10n.string("下移"), icon: "arrow.down", direction: .down)
                            queueButton(L10n.string("队尾"), icon: "arrow.down.to.line", direction: .bottom)
                        }
                    }
                }

                VStack(spacing: 9) {
                    if item.isPausable {
                        HStack(spacing: 8) {
                            Button {
                                Task { await store.pause(item) }
                            } label: {
                                Label(L10n.string("暂停下载"), systemImage: "pause.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                Task { await store.forcePause(item) }
                            } label: {
                                Image(systemName: "exclamationmark.pause.fill")
                                    .frame(width: 22)
                            }
                            .buttonStyle(.bordered)
                            .help(L10n.string("立即中断连接并强制暂停"))
                        }
                    } else if item.isResumable {
                        Button {
                            Task { await store.resume(item) }
                        } label: {
                            Label(L10n.string("继续下载"), systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else if item.isRetryable {
                        Button {
                            Task { await store.retry(item) }
                        } label: {
                            Label(L10n.string("重新下载"), systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        store.reveal(item)
                    } label: {
                        Label(L10n.string("在 Finder 中显示"), systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        Task { await store.remove(item) }
                    } label: {
                        Label(L10n.string("移除任务"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.string("只移除任务记录，不删除已经下载的文件"))
                }
                .disabled(store.isPerformingAction)
            }
            .padding(18)
        }
        .background(LaneColor.surface)
    }

    private var entityID: UUID? {
        organization.entityID(
            gid: item.gid,
            profileID: preferences.activeServerProfileID
        )
    }

    private func queueButton(
        _ title: String,
        icon: String,
        direction: QueueMoveDirection
    ) -> some View {
        Button {
            Task { await store.moveQueueItem(item, direction: direction) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
                    .font(LaneFont.interface(9))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
