import SwiftUI

struct SpeedSettingsPane: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore

    var body: some View {
        Form {
            Section(L10n.string("一键性能方案")) {
                PerformanceProfileCardsView()
            }

            Section(L10n.string("当前流量")) {
                HStack(spacing: 28) {
                    liveMetric(
                        title: L10n.string("下载"),
                        icon: "arrow.down",
                        value: TransferFormatter.speed(store.globalStats.downloadSpeedValue),
                        color: LaneColor.accent
                    )
                    liveMetric(
                        title: L10n.string("上传"),
                        icon: "arrow.up",
                        value: TransferFormatter.speed(store.globalStats.uploadSpeedValue),
                        color: LaneColor.mint
                    )
                    Spacer()
                    Text(L10n.string("\(store.globalStats.activeCount) 个活动任务"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.string("速度曲线")) {
                Toggle(
                    L10n.string("在主窗口显示速度曲线"),
                    isOn: $preferences.showSpeedTrend
                )

                Text(L10n.string("显示最近 3 分钟的下载与上传趋势；关闭后不会影响速度统计。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("全局限速")) {
                SpeedLimitField(
                    title: L10n.string("总下载速度"),
                    detail: L10n.string("所有任务共享；0 表示不限速"),
                    kibibytesPerSecond: $preferences.maxOverallDownloadLimitKiB
                )
                SpeedLimitField(
                    title: L10n.string("总上传速度"),
                    detail: L10n.string("包含 BT 做种流量"),
                    kibibytesPerSecond: $preferences.maxOverallUploadLimitKiB
                )
            }

            Section(L10n.string("新任务默认限速")) {
                SpeedLimitField(
                    title: L10n.string("单任务下载"),
                    detail: L10n.string("新任务默认上限"),
                    kibibytesPerSecond: $preferences.maxDownloadLimitKiB
                )
                SpeedLimitField(
                    title: L10n.string("单任务上传"),
                    detail: L10n.string("新任务默认上限"),
                    kibibytesPerSecond: $preferences.maxUploadLimitKiB
                )
            }

            Section(L10n.string("夜间限速")) {
                Toggle(L10n.string("按时段使用单独限速"), isOn: $preferences.nightLimitEnabled)

                HStack(spacing: 16) {
                    DatePicker(
                        L10n.string("开始"),
                        selection: nightStartBinding,
                        displayedComponents: .hourAndMinute
                    )
                    DatePicker(
                        L10n.string("结束"),
                        selection: nightEndBinding,
                        displayedComponents: .hourAndMinute
                    )
                }
                .disabled(!preferences.nightLimitEnabled)

                SpeedLimitField(
                    title: L10n.string("夜间总下载"),
                    detail: L10n.string("0 表示夜间不限速"),
                    kibibytesPerSecond: $preferences.nightDownloadLimitKiB
                )
                .disabled(!preferences.nightLimitEnabled)

                SpeedLimitField(
                    title: L10n.string("夜间总上传"),
                    detail: L10n.string("包含 BT 做种流量"),
                    kibibytesPerSecond: $preferences.nightUploadLimitKiB
                )
                .disabled(!preferences.nightLimitEnabled)

                Label(
                    nightPolicyIsActive ? L10n.string("当前正在使用夜间限速") : L10n.string("当前使用常规全局限速"),
                    systemImage: nightPolicyIsActive ? "moon.fill" : "sun.max"
                )
                .font(.caption)
                .foregroundStyle(nightPolicyIsActive ? LaneColor.accent : .secondary)
            }

            Section(L10n.string("调度")) {
                Stepper(
                    L10n.string("同时下载 \(preferences.maxConcurrentDownloads) 个任务"),
                    value: $preferences.maxConcurrentDownloads,
                    in: 1...20
                )

                SpeedLimitField(
                    title: L10n.string("最低有效速度"),
                    detail: L10n.string("低于该速度会重试；0 表示关闭"),
                    kibibytesPerSecond: $preferences.lowestSpeedLimitKiB
                )
            }

            SettingsActionFooter()
        }
        .formStyle(.grouped)
    }

    private var nightPolicyIsActive: Bool {
        preferences.nightSpeedSchedule.isActive(at: Date())
    }

    private var nightStartBinding: Binding<Date> {
        timeBinding(
            get: { preferences.nightLimitStartMinute },
            set: { preferences.nightLimitStartMinute = $0 }
        )
    }

    private var nightEndBinding: Binding<Date> {
        timeBinding(
            get: { preferences.nightLimitEndMinute },
            set: { preferences.nightLimitEndMinute = $0 }
        )
    }

    private func timeBinding(
        get: @escaping () -> Int,
        set: @escaping (Int) -> Void
    ) -> Binding<Date> {
        Binding(
            get: {
                let startOfDay = Calendar.current.startOfDay(for: Date())
                return Calendar.current.date(
                    byAdding: .minute,
                    value: min(max(get(), 0), 1_439),
                    to: startOfDay
                ) ?? startOfDay
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                set((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }
        )
    }

    private func liveMetric(
        title: String,
        icon: String,
        value: String,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(LaneFont.utility(11))
            }
        }
    }
}
