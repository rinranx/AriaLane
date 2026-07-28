import Charts
import SwiftUI

struct FlowHeaderView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var preferences: AppPreferences
    @SceneStorage("isSpeedTrendExpanded") private var isSpeedTrendExpanded = false

    let filter: TransferFilter
    let items: [TransferItem]
    let stats: GlobalStats
    let speedSamples: [SpeedSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(filter.title)
                        .font(LaneFont.display(27))
                    Text(summary)
                        .font(LaneFont.interface(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 22) {
                    speedMetric(
                        icon: "arrow.down",
                        label: downloadLabel,
                        value: TransferFormatter.speed(stats.downloadSpeedValue),
                        color: LaneColor.accent
                    )
                    speedMetric(
                        icon: "arrow.up",
                        label: L10n.string("上传"),
                        value: TransferFormatter.speed(stats.uploadSpeedValue),
                        color: LaneColor.mint
                    )
                }
            }

            ContinuousProgressTrack(
                progress: averageProgress,
                isActive: stats.downloadSpeedValue > 0
            )

            if preferences.showSpeedTrend {
                SpeedTrendView(
                    samples: speedSamples,
                    isExpanded: $isSpeedTrendExpanded
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, LaneMetric.contentPadding)
        .padding(.top, 23)
        .padding(.bottom, 18)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: preferences.showSpeedTrend
        )
    }

    private var summary: String {
        let active = items.filter { $0.status == .active }.count
        if items.isEmpty {
            return L10n.string("把链接拖进来，或按 ⌘N 添加下载")
        }
        if active > 0 {
            return L10n.string("\(active) 个任务正在流动")
        }
        return L10n.string("共 \(items.count) 个任务")
    }

    private var averageProgress: Double {
        guard !items.isEmpty else { return 0 }
        return items.map(\.progress).reduce(0, +) / Double(items.count)
    }

    private var downloadLabel: String {
        let limit = preferences.maxOverallDownloadLimitKiB
        guard limit > 0 else { return L10n.string("下载") }
        return L10n.string("下载 · 限 \(TransferFormatter.speedLimit(limit))")
    }

    private func speedMetric(
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
                    .font(LaneFont.interface(9, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(LaneFont.utility(11))
                    .contentTransition(.numericText())
            }
        }
    }
}

private struct ContinuousProgressTrack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double
    let isActive: Bool

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.075))

                if normalizedProgress > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: isActive
                                    ? [LaneColor.accent, LaneColor.accentSoft, LaneColor.mint]
                                    : [LaneColor.accent, LaneColor.accentSoft],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * normalizedProgress)
                        .shadow(
                            color: isActive ? LaneColor.accent.opacity(0.24) : .clear,
                            radius: 4
                        )
                }
            }
        }
        .frame(height: 7)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.32),
            value: normalizedProgress
        )
        .accessibilityElement()
        .accessibilityLabel(L10n.string("任务总进度"))
        .accessibilityValue(TransferFormatter.percent(normalizedProgress))
    }
}

private struct SpeedTrendView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var selection = SpeedTrendSelection()

    let samples: [SpeedSample]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(
                    reduceMotion ? nil : .easeInOut(duration: 0.2)
                ) {
                    isExpanded.toggle()
                    selection.timestamp = nil
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LaneColor.accent)

                    Text(L10n.string("速度曲线"))
                        .font(LaneFont.interface(9, weight: .medium))

                    Text(L10n.string("最近 3 分钟"))
                        .font(LaneFont.interface(9))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    if let selectedSample, isExpanded {
                        Text(selectedSample.timestamp.formatted(date: .omitted, time: .standard))
                            .font(LaneFont.utility(9, weight: .regular))
                            .foregroundStyle(.secondary)
                        speedReadout(
                            symbol: "↓",
                            value: selectedSample.downloadBytesPerSecond,
                            color: LaneColor.accent
                        )
                        speedReadout(
                            symbol: "↑",
                            value: selectedSample.uploadBytesPerSecond,
                            color: LaneColor.mint
                        )
                    } else {
                        legendLabel(L10n.string("下载"), color: LaneColor.accent)
                        legendLabel(L10n.string("上传"), color: LaneColor.mint, isDashed: true)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? L10n.string("收起速度曲线") : L10n.string("展开速度曲线"))
            .font(LaneFont.interface(9))

            if isExpanded {
                VStack(spacing: 5) {
                    Chart {
                        ForEach(gridLevels, id: \.self) { level in
                            RuleMark(y: .value(L10n.string("参考线"), level))
                                .foregroundStyle(Color.primary.opacity(0.055))
                                .lineStyle(StrokeStyle(lineWidth: 0.5))
                        }

                        ForEach(visibleSamples) { sample in
                            AreaMark(
                                x: .value(L10n.string("时间"), sample.timestamp),
                                yStart: .value(L10n.string("基线"), 0),
                                yEnd: .value(L10n.string("下载"), sample.downloadBytesPerSecond)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        LaneColor.accent.opacity(0.18),
                                        LaneColor.accent.opacity(0.01)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }

                        ForEach(visibleSamples) { sample in
                            LineMark(
                                x: .value(L10n.string("时间"), sample.timestamp),
                                y: .value(L10n.string("下载"), sample.downloadBytesPerSecond)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LaneColor.accent)
                            .lineStyle(
                                StrokeStyle(
                                    lineWidth: 1.8,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                        }

                        ForEach(visibleSamples) { sample in
                            LineMark(
                                x: .value(L10n.string("时间"), sample.timestamp),
                                y: .value(L10n.string("上传"), sample.uploadBytesPerSecond)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LaneColor.mint)
                            .lineStyle(
                                StrokeStyle(
                                    lineWidth: 1.25,
                                    lineCap: .round,
                                    lineJoin: .round,
                                    dash: [4, 3]
                                )
                            )
                        }

                        if let selectedSample {
                            RuleMark(x: .value(L10n.string("所选时间"), selectedSample.timestamp))
                                .foregroundStyle(Color.secondary.opacity(0.3))
                                .lineStyle(StrokeStyle(lineWidth: 0.75, dash: [2, 3]))

                            PointMark(
                                x: .value(L10n.string("时间"), selectedSample.timestamp),
                                y: .value(L10n.string("下载"), selectedSample.downloadBytesPerSecond)
                            )
                            .foregroundStyle(LaneColor.accent)
                            .symbolSize(24)

                            PointMark(
                                x: .value(L10n.string("时间"), selectedSample.timestamp),
                                y: .value(L10n.string("上传"), selectedSample.uploadBytesPerSecond)
                            )
                            .foregroundStyle(LaneColor.mint)
                            .symbolSize(20)
                        } else if let latestSample {
                            PointMark(
                                x: .value(L10n.string("当前时间"), latestSample.timestamp),
                                y: .value(L10n.string("当前下载"), latestSample.downloadBytesPerSecond)
                            )
                            .foregroundStyle(LaneColor.accent)
                            .symbolSize(18)

                            PointMark(
                                x: .value(L10n.string("当前时间"), latestSample.timestamp),
                                y: .value(L10n.string("当前上传"), latestSample.uploadBytesPerSecond)
                            )
                            .foregroundStyle(LaneColor.mint)
                            .symbolSize(14)
                        }
                    }
                    .chartXScale(domain: chartStart...chartEnd)
                    .chartYScale(domain: 0...chartMaximum)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartLegend(.hidden)
                    .chartXSelection(value: $selection.timestamp)
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(Color.primary.opacity(0.016))
                            .clipShape(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                    }
                    .frame(height: 82)
                    .overlay {
                        if visibleSamples.count < 2 {
                            Text(L10n.string("正在收集速度样本…"))
                                .font(LaneFont.interface(9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.24),
                        value: visibleSamples
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.string("最近三分钟下载与上传速度曲线"))
                    .accessibilityValue(
                        L10n.string("下载峰值 \(TransferFormatter.speed(peakDownloadSpeed))，")
                        + L10n.string("上传峰值 \(TransferFormatter.speed(peakUploadSpeed))")
                    )

                    HStack {
                        Text(L10n.string("3 分钟前"))
                        Spacer()
                        peakSummary
                        Spacer()
                        Text(L10n.string("现在"))
                    }
                    .font(LaneFont.interface(8))
                    .foregroundStyle(.tertiary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
                .fill(LaneColor.surface.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
                        .stroke(LaneColor.line, lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
    }

    private var selectedSample: SpeedSample? {
        guard let selectedTimestamp = selection.timestamp else { return nil }
        return visibleSamples.min {
            abs($0.timestamp.timeIntervalSince(selectedTimestamp))
                < abs($1.timestamp.timeIntervalSince(selectedTimestamp))
        }
    }

    private var latestSample: SpeedSample? {
        visibleSamples.last
    }

    private var visibleSamples: [SpeedSample] {
        samples.filter { $0.timestamp >= chartStart && $0.timestamp <= chartEnd }
    }

    private var peakDownloadSpeed: Int64 {
        visibleSamples.map(\.downloadBytesPerSecond).max() ?? 0
    }

    private var peakUploadSpeed: Int64 {
        visibleSamples.map(\.uploadBytesPerSecond).max() ?? 0
    }

    private var chartEnd: Date {
        samples.last?.timestamp ?? Date()
    }

    private var chartStart: Date {
        chartEnd.addingTimeInterval(-180)
    }

    private var chartMaximum: Int64 {
        let maximum = visibleSamples.reduce(Int64(0)) {
            max($0, $1.downloadBytesPerSecond, $1.uploadBytesPerSecond)
        }
        return niceCeiling(for: maximum)
    }

    private var gridLevels: [Int64] {
        Array(
            Set(
                [Int64(1), 2, 3]
                    .map { chartMaximum * $0 / 4 }
                    .filter { $0 > 0 }
            )
        )
        .sorted()
    }

    private var peakSummary: Text {
        Text(L10n.string("峰值 ↓ "))
            .font(LaneFont.interface(8))
        + Text(TransferFormatter.speed(peakDownloadSpeed))
            .font(LaneFont.utility(8, weight: .regular))
        + Text("  ↑ ")
            .font(LaneFont.interface(8))
        + Text(TransferFormatter.speed(peakUploadSpeed))
            .font(LaneFont.utility(8, weight: .regular))
    }

    private func niceCeiling(for value: Int64) -> Int64 {
        guard value > 0 else { return 1 }
        let paddedValue = Double(value) * 1.12
        let magnitude = pow(10, floor(log10(paddedValue)))
        let normalized = paddedValue / magnitude
        let rounded: Double
        if normalized <= 1 {
            rounded = 1
        } else if normalized <= 2 {
            rounded = 2
        } else if normalized <= 5 {
            rounded = 5
        } else {
            rounded = 10
        }
        return max(Int64(rounded * magnitude), 1)
    }

    private func speedReadout(
        symbol: String,
        value: Int64,
        color: Color
    ) -> some View {
        Text("\(symbol) \(TransferFormatter.speed(value))")
            .font(LaneFont.utility(9, weight: .regular))
            .foregroundStyle(color)
    }

    private func legendLabel(
        _ title: String,
        color: Color,
        isDashed: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: isDashed ? 4 : 10, height: 1.5)
                .overlay(alignment: .trailing) {
                    if isDashed {
                        Capsule()
                            .fill(color)
                            .frame(width: 4, height: 1.5)
                            .offset(x: 6)
                    }
                }
                .frame(width: 10, alignment: .leading)
            Text(title)
                .font(LaneFont.interface(8))
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
private final class SpeedTrendSelection: ObservableObject {
    @Published var timestamp: Date?
}
