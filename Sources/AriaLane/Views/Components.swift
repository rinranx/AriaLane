import SwiftUI

struct FlowMark: View {
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LaneColor.accent.opacity(0.14))

            HStack(spacing: size * 0.1) {
                Capsule()
                    .fill(LaneColor.accent)
                    .frame(width: size * 0.13, height: size * 0.48)
                Capsule()
                    .fill(LaneColor.mint)
                    .frame(width: size * 0.13, height: size * 0.68)
                Capsule()
                    .fill(LaneColor.accentSoft)
                    .frame(width: size * 0.13, height: size * 0.36)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct TaskListDisplayModePicker: View {
    @Binding var selection: TaskListDisplayMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TaskListDisplayMode.allCases) { mode in
                let isSelected = selection == mode

                Button {
                    selection = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            isSelected ? LaneColor.accent : LaneColor.label2
                        )
                        .frame(width: 27, height: 25)
                        .background(
                            isSelected
                                ? LaneColor.surface
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
                .help(L10n.string("\(mode.title)模式"))
                .accessibilityLabel(L10n.string("\(mode.title)模式"))
                .accessibilityValue(isSelected ? L10n.string("已选择") : L10n.string("未选择"))
            }
        }
        .padding(2)
        .background(
            LaneColor.fill1,
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(LaneColor.line, lineWidth: 1)
        }
    }
}

struct StatusBadge: View {
    let status: TransferStatus
    var isCompact = false

    private var color: Color {
        switch status {
        case .active: LaneColor.accent
        case .waiting: LaneColor.amber
        case .paused: .secondary
        case .error: LaneColor.danger
        case .complete: LaneColor.mint
        case .removed: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.systemImage)
                .font(
                    .system(
                        size: isCompact ? 8 : 9,
                        weight: .bold
                    )
                )
            Text(status.title)
                .font(
                    LaneFont.interface(
                        isCompact ? 8.5 : 10,
                        weight: .semibold
                    )
                )
        }
        .foregroundStyle(color)
        .padding(.horizontal, isCompact ? 6 : 8)
        .padding(.vertical, isCompact ? 2 : 4)
        .background(color.opacity(0.1), in: Capsule())
    }
}

struct NoticeBanner: View {
    let notice: AppNotice

    private var color: Color {
        switch notice.kind {
        case .success: LaneColor.mint
        case .warning: LaneColor.amber
        case .error: LaneColor.danger
        }
    }

    private var icon: String {
        switch notice.kind {
        case .success: "checkmark"
        case .warning: "exclamationmark"
        case .error: "xmark"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color, in: Circle())

            Text(notice.message)
                .font(LaneFont.interface(12, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .laneSurface(cornerRadius: 12)
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
    }
}

struct SegmentedProgressView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double
    let status: TransferStatus
    var height: CGFloat = 5

    private var color: Color {
        switch status {
        case .complete: LaneColor.mint
        case .error: LaneColor.danger
        case .paused: .secondary
        default: LaneColor.accent
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))

                if normalizedProgress > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.72)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * normalizedProgress)
                }
            }
        }
        .frame(height: height)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.28),
            value: normalizedProgress
        )
        .accessibilityElement()
        .accessibilityLabel(L10n.string("下载进度"))
        .accessibilityValue(TransferFormatter.percent(normalizedProgress))
    }

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }
}

struct InfoPair: View {
    let label: String
    let value: String
    var isMonospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(LaneFont.interface(10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(
                    isMonospaced
                        ? LaneFont.utility(11, weight: .regular)
                        : LaneFont.interface(12, weight: .medium)
                )
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

struct LocalFileDeletionConfirmationView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let message: String
    let actionTitle: String
    let canDeleteLocalFiles: Bool
    let onConfirm: (Bool) -> Void

    @State private var deleteLocalFiles = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LaneColor.danger)
                    .frame(width: 38, height: 38)
                    .background(
                        LaneColor.danger.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 11)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(LaneFont.display(19))
                    Text(message)
                        .font(LaneFont.interface(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(L10n.string("关闭"))
            }

            Button {
                guard canDeleteLocalFiles else { return }
                deleteLocalFiles.toggle()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                deleteLocalFiles
                                    ? LaneColor.danger
                                    : LaneColor.surface
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 6,
                                    style: .continuous
                                )
                                .stroke(
                                    deleteLocalFiles
                                        ? LaneColor.danger
                                        : LaneColor.line,
                                    lineWidth: 1
                                )
                            }

                        if deleteLocalFiles {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("同时删除本地文件"))
                            .font(LaneFont.interface(12, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(
                            canDeleteLocalFiles
                                ? L10n.string("对应文件会移到废纸篓，可在废纸篓中恢复。")
                                : L10n.string("没有可定位的本地文件。")
                        )
                        .font(LaneFont.interface(10))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(13)
                .background(
                    deleteLocalFiles
                        ? LaneColor.danger.opacity(0.075)
                        : LaneColor.fill1,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            deleteLocalFiles
                                ? LaneColor.danger.opacity(0.28)
                                : LaneColor.line,
                            lineWidth: 1
                        )
                }
                .contentShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canDeleteLocalFiles)
            .opacity(canDeleteLocalFiles ? 1 : 0.58)
            .accessibilityLabel(L10n.string("同时删除本地文件"))
            .accessibilityValue(deleteLocalFiles ? L10n.string("已勾选") : L10n.string("未勾选"))

            HStack(spacing: 10) {
                Spacer()

                Button(L10n.string("取消")) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

                Button(actionTitle) {
                    onConfirm(deleteLocalFiles)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(LaneColor.danger)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear {
            deleteLocalFiles = false
        }
    }
}
