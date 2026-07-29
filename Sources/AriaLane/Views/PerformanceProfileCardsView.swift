import SwiftUI

struct PerformanceProfileCardsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore

    @State private var editingProfile: Aria2PerformanceProfile?
    @State private var profilePendingDeletion: Aria2PerformanceProfile?

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(preferences.performanceProfiles) { profile in
                    PerformanceProfileCard(
                        profile: profile,
                        isSelected:
                            preferences.activePerformanceProfileID == profile.id,
                        isDefault:
                            profile.id == Aria2PerformanceProfile.maximumSpeedID,
                        isApplying: store.settingsApplyState == .applying,
                        onSelect: {
                            apply(profile)
                        },
                        onEdit: profile.kind == .custom ? {
                            editingProfile = profile
                        } : nil,
                        onDelete: profile.kind == .custom ? {
                            profilePendingDeletion = profile
                        } : nil
                    )
                }

                AddPerformanceProfileCard {
                    editingProfile = preferences.capturedPerformanceProfile()
                }
            }

            Text(
                L10n.string(
                    "方案只调整速度、并发、分段、缓存与 BT 寻源，不会更改代理、证书或镜像设置。"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .sheet(item: $editingProfile) { profile in
            PerformanceProfileEditorSheet(
                profile: profile,
                isEditing: preferences.customPerformanceProfiles.contains {
                    $0.id == profile.id
                },
                onCancel: {
                    editingProfile = nil
                },
                onSave: { updatedProfile in
                    let saved = preferences.saveCustomPerformanceProfile(
                        updatedProfile
                    )
                    editingProfile = nil
                    apply(saved)
                }
            )
        }
        .alert(
            L10n.string("删除自定义方案？"),
            isPresented: deletionAlertIsPresented,
            presenting: profilePendingDeletion
        ) { profile in
            Button(L10n.string("删除"), role: .destructive) {
                preferences.removeCustomPerformanceProfile(id: profile.id)
                profilePendingDeletion = nil
            }
            Button(L10n.string("取消"), role: .cancel) {
                profilePendingDeletion = nil
            }
        } message: { profile in
            Text(L10n.string("“\(profile.displayName)”将从一键方案中移除。"))
        }
    }

    private var deletionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { profilePendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    profilePendingDeletion = nil
                }
            }
        )
    }

    private func apply(_ profile: Aria2PerformanceProfile) {
        preferences.applyPerformanceProfile(profile)
        Task {
            await store.applyAria2Settings()
        }
    }
}

private struct PerformanceProfileCard: View {
    let profile: Aria2PerformanceProfile
    let isSelected: Bool
    let isDefault: Bool
    let isApplying: Bool
    let onSelect: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: profile.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(
                                isSelected ? LaneColor.accent : LaneColor.label2
                            )
                            .frame(width: 30, height: 30)
                            .background(
                                isSelected
                                    ? LaneColor.accent.opacity(0.12)
                                    : LaneColor.fill1,
                                in: RoundedRectangle(cornerRadius: 9)
                            )

                        Text(profile.displayName)
                            .font(LaneFont.interface(12, weight: .semibold))
                            .foregroundStyle(LaneColor.label1)
                            .lineLimit(1)

                        Spacer(minLength: onEdit == nil ? 0 : 22)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.summary)
                        Text(profile.secondarySummary)
                    }
                    .font(LaneFont.interface(9.5))
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    HStack(spacing: 5) {
                        if isSelected {
                            Label(
                                L10n.string("当前使用"),
                                systemImage: "checkmark.circle.fill"
                            )
                            .foregroundStyle(LaneColor.accent)
                        } else if isDefault {
                            Label(
                                L10n.string("默认"),
                                systemImage: "star.fill"
                            )
                            .foregroundStyle(LaneColor.amber)
                        } else {
                            Text(L10n.string("点击应用"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(LaneFont.interface(9, weight: .medium))
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
                .background(
                    isSelected
                        ? LaneColor.accent.opacity(0.075)
                        : LaneColor.surface,
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected
                                ? LaneColor.accent.opacity(0.46)
                                : LaneColor.line,
                            lineWidth: 1
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isApplying)
            .accessibilityLabel(profile.displayName)
            .accessibilityValue(
                isSelected ? L10n.string("当前使用") : L10n.string("未选择")
            )

            if let onEdit, let onDelete {
                Menu {
                    Button(L10n.string("编辑方案"), action: onEdit)
                    Divider()
                    Button(
                        L10n.string("删除方案"),
                        role: .destructive,
                        action: onDelete
                    )
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(7)
                .help(L10n.string("方案操作"))
            }
        }
    }
}

private struct AddPerformanceProfileCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LaneColor.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        LaneColor.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                VStack(spacing: 3) {
                    Text(L10n.string("新增自定义方案"))
                        .font(LaneFont.interface(11, weight: .semibold))
                    Text(L10n.string("保存为一键方案"))
                        .font(LaneFont.interface(9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 126)
            .background(
                LaneColor.fill1,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LaneColor.accent.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("新增自定义方案"))
    }
}

private struct PerformanceProfileEditorSheet: View {
    @State private var draft: Aria2PerformanceProfile

    let isEditing: Bool
    let onCancel: () -> Void
    let onSave: (Aria2PerformanceProfile) -> Void

    init(
        profile: Aria2PerformanceProfile,
        isEditing: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping (Aria2PerformanceProfile) -> Void
    ) {
        _draft = State(
            initialValue: Aria2PerformanceProfile.custom(
                id: profile.id,
                name: profile.name,
                basedOn: profile
            )
        )
        self.isEditing = isEditing
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LaneColor.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        LaneColor.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        isEditing
                            ? L10n.string("编辑自定义方案")
                            : L10n.string("新增自定义方案")
                    )
                    .font(LaneFont.display(18))

                    Text(L10n.string("保存后可从卡片一键应用这些性能设置"))
                        .font(LaneFont.interface(10))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(18)

            Divider()

            Form {
                Section(L10n.string("方案名称")) {
                    TextField(
                        L10n.string("例如：家庭宽带"),
                        text: $draft.name
                    )
                    .onChange(of: draft.name) { _, newValue in
                        if newValue.count > 30 {
                            draft.name = String(newValue.prefix(30))
                        }
                    }
                }

                Section(L10n.string("速度与并发")) {
                    SpeedLimitField(
                        title: L10n.string("总下载速度"),
                        detail: L10n.string("0 表示不限速"),
                        kibibytesPerSecond:
                            $draft.maxOverallDownloadLimitKiB
                    )
                    SpeedLimitField(
                        title: L10n.string("总上传速度"),
                        detail: L10n.string("0 表示不限速"),
                        kibibytesPerSecond:
                            $draft.maxOverallUploadLimitKiB
                    )
                    SpeedLimitField(
                        title: L10n.string("单任务下载"),
                        detail: L10n.string("新任务默认上限"),
                        kibibytesPerSecond: $draft.maxDownloadLimitKiB
                    )
                    SpeedLimitField(
                        title: L10n.string("单任务上传"),
                        detail: L10n.string("新任务默认上限"),
                        kibibytesPerSecond: $draft.maxUploadLimitKiB
                    )
                    ProfileStepperRow(
                        title: L10n.string("同时下载"),
                        value: $draft.maxConcurrentDownloads,
                        range: 1...20,
                        unit: L10n.string("个任务")
                    )
                }

                Section(L10n.string("分段与缓存")) {
                    ProfileStepperRow(
                        title: L10n.string("单服务器连接"),
                        value: $draft.maxConnectionPerServer,
                        range: 1...16,
                        unit: L10n.string("个连接")
                    )
                    ProfileStepperRow(
                        title: L10n.string("单文件分段"),
                        value: $draft.split,
                        range: 1...16,
                        unit: L10n.string("个分段")
                    )
                    ProfileStepperRow(
                        title: L10n.string("最小分段"),
                        value: $draft.minSplitSizeMiB,
                        range: 1...1_024,
                        unit: "MB"
                    )
                    ProfileStepperRow(
                        title: L10n.string("磁盘缓存"),
                        value: $draft.diskCacheMiB,
                        range: 0...4_096,
                        step: 16,
                        unit: "MB"
                    )
                }

                Section("BitTorrent") {
                    Toggle(L10n.string("启用 DHT"), isOn: $draft.enableDHT)
                    Toggle(
                        L10n.string("启用 IPv6 DHT"),
                        isOn: $draft.enableDHT6
                    )
                    Toggle(
                        L10n.string("启用节点交换（PEX）"),
                        isOn: $draft.enablePeerExchange
                    )
                    Toggle(
                        L10n.string("启用本地节点发现（LPD）"),
                        isOn: $draft.enableLocalPeerDiscovery
                    )
                    ProfileStepperRow(
                        title: L10n.string("每个种子最多"),
                        value: $draft.btMaxPeers,
                        range: 0...500,
                        step: 5,
                        unit: L10n.string("个节点")
                    )
                    SpeedLimitField(
                        title: L10n.string("积极寻找节点阈值"),
                        detail: L10n.string("低于该速度时继续寻找更多节点"),
                        kibibytesPerSecond:
                            $draft.btRequestPeerSpeedLimitKiB
                    )
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button(L10n.string("取消"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(
                    isEditing ? L10n.string("保存更改") : L10n.string("新增方案")
                ) {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmed.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 540, height: 600)
        .background(LaneColor.canvas)
    }
}

private struct ProfileStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let unit: String

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value) \(unit)")
                    .font(LaneFont.utility(10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
