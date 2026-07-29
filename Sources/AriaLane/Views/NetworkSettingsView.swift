import SwiftUI

struct NetworkSettingsPane: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Form {
            Section(L10n.string("HTTP / FTP 分段")) {
                NetworkIntegerRow(
                    title: L10n.string("每台服务器最多"),
                    unit: L10n.string("个连接"),
                    value: $preferences.maxConnectionPerServer,
                    range: 1...16
                )
                NetworkIntegerRow(
                    title: L10n.string("每个任务最多"),
                    unit: L10n.string("个分段"),
                    value: $preferences.split,
                    range: 1...16
                )
                NetworkIntegerRow(
                    title: L10n.string("最小分段大小"),
                    unit: "MB",
                    value: $preferences.minSplitSizeMiB,
                    range: 1...1_024
                )
                NetworkIntegerRow(
                    title: L10n.string("磁盘缓存"),
                    unit: "MB",
                    value: $preferences.diskCacheMiB,
                    range: 0...4_096,
                    step: 16
                )
            }

            Section(L10n.string("超时与重试")) {
                NetworkIntegerRow(
                    title: L10n.string("连接超时"),
                    unit: L10n.string("秒"),
                    value: $preferences.connectTimeoutSeconds,
                    range: 1...600
                )
                NetworkIntegerRow(
                    title: L10n.string("传输超时"),
                    unit: L10n.string("秒"),
                    value: $preferences.timeoutSeconds,
                    range: 1...600
                )
                NetworkIntegerRow(
                    title: L10n.string("最多重试"),
                    unit: L10n.string("次"),
                    value: $preferences.maxTries,
                    range: 0...100
                )
                NetworkIntegerRow(
                    title: L10n.string("重试间隔"),
                    unit: L10n.string("秒"),
                    value: $preferences.retryWaitSeconds,
                    range: 0...600
                )
            }

            Section("BitTorrent") {
                Toggle(L10n.string("启用 DHT"), isOn: $preferences.enableDHT)
                Toggle(L10n.string("启用节点交换（PEX）"), isOn: $preferences.enablePeerExchange)
                Toggle(L10n.string("启用本地节点发现（LPD）"), isOn: $preferences.enableLocalPeerDiscovery)

                NetworkIntegerRow(
                    title: L10n.string("每个种子最多"),
                    unit: L10n.string("个节点"),
                    value: $preferences.btMaxPeers,
                    range: 0...500,
                    step: 5
                )
                NetworkIntegerRow(
                    title: L10n.string("积极寻找节点阈值"),
                    detail: L10n.string("低于该速度时继续寻找更多节点"),
                    unit: "KB/s",
                    value: $preferences.btRequestPeerSpeedLimitKiB,
                    range: 0...1_048_576,
                    step: 50
                )

                HStack(spacing: 12) {
                    Text(L10n.string("监听端口"))
                    Spacer()
                    NetworkIntegerInput(
                        value: $preferences.listenPortStart,
                        range: 1_024...65_535,
                        accessibilityLabel: L10n.string("监听端口起始值"),
                        width: 108
                    )
                    Text("—")
                        .foregroundStyle(.tertiary)
                    NetworkIntegerInput(
                        value: $preferences.listenPortEnd,
                        range: 1_024...65_535,
                        accessibilityLabel: L10n.string("监听端口结束值"),
                        width: 108
                    )
                }

                NetworkIntegerRow(
                    title: L10n.string("最长做种时间"),
                    detail: L10n.string("0 表示完成后不做种"),
                    unit: L10n.string("分钟"),
                    value: $preferences.seedTimeMinutes,
                    range: 0...10_080,
                    step: 10
                )

                HStack(spacing: 12) {
                    Text(L10n.string("分享率达到"))
                    Spacer()
                    NetworkDecimalInput(
                        value: $preferences.seedRatio,
                        range: 0...100,
                        accessibilityLabel: L10n.string("停止做种分享率")
                    )
                    Text(L10n.string("后停止"))
                        .foregroundStyle(.secondary)
                }

                Text(L10n.string("时间或分享率任一达到即停止；分享率为 0 时不设比例上限。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsActionFooter()
        }
        .formStyle(.grouped)
    }
}

private struct NetworkIntegerRow: View {
    let title: String
    var detail: String?
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack(alignment: detail == nil ? .center : .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            NetworkIntegerInput(
                value: $value,
                range: range,
                step: step,
                unit: unit,
                accessibilityLabel: title
            )
        }
    }
}

private struct NetworkIntegerInput: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var unit = ""
    let accessibilityLabel: String
    var width: CGFloat = 156

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        unit: String = "",
        accessibilityLabel: String,
        width: CGFloat = 156
    ) {
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.accessibilityLabel = accessibilityLabel
        self.width = width
        _draft = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 7) {
            TextField("", text: $draft)
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(LaneFont.utility(11, weight: .medium))
            .multilineTextAlignment(.trailing)
            .focused($isFocused)
            .accessibilityLabel(accessibilityLabel)
            .onSubmit {
                normalizeDraft()
            }
            .onMoveCommand { direction in
                switch direction {
                case .up:
                    adjust(by: step)
                case .down:
                    adjust(by: -step)
                default:
                    break
                }
            }

            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 11)
        .frame(width: width, height: 34)
        .background(
            LaneColor.fill1,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isFocused
                        ? LaneColor.accent.opacity(0.58)
                        : Color.clear,
                    lineWidth: 1
                )
        }
        .contentShape(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .onTapGesture {
            isFocused = true
        }
        .onChange(of: draft) { _, candidate in
            updateValue(from: candidate)
        }
        .onChange(of: value) { _, newValue in
            guard !isFocused else { return }
            draft = String(newValue)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                normalizeDraft()
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func updateValue(from candidate: String) {
        let filtered = candidate.filter(\.isNumber)
        if filtered != candidate {
            draft = filtered
            return
        }

        guard let parsed = Int(filtered) else { return }
        value = clamped(parsed)
    }

    private func normalizeDraft() {
        if let parsed = Int(draft) {
            value = clamped(parsed)
        }
        draft = String(value)
    }

    private func adjust(by amount: Int) {
        normalizeDraft()
        value = clamped(value + amount)
        draft = String(value)
    }

    private func clamped(_ candidate: Int) -> Int {
        min(max(candidate, range.lowerBound), range.upperBound)
    }
}

private struct NetworkDecimalInput: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accessibilityLabel: String

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        accessibilityLabel: String
    ) {
        _value = value
        self.range = range
        self.accessibilityLabel = accessibilityLabel
        _draft = State(initialValue: Self.formatted(value.wrappedValue))
    }

    var body: some View {
        TextField("", text: $draft)
        .labelsHidden()
        .textFieldStyle(.plain)
        .font(LaneFont.utility(11, weight: .medium))
        .multilineTextAlignment(.trailing)
        .focused($isFocused)
        .padding(.horizontal, 11)
        .frame(width: 108, height: 34)
        .background(
            LaneColor.fill1,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isFocused
                        ? LaneColor.accent.opacity(0.58)
                        : Color.clear,
                    lineWidth: 1
                )
        }
        .contentShape(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .onTapGesture {
            isFocused = true
        }
        .onSubmit {
            normalizeDraft()
        }
        .onChange(of: draft) { _, candidate in
            updateValue(from: candidate)
        }
        .onChange(of: value) { _, newValue in
            guard !isFocused else { return }
            draft = Self.formatted(newValue)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                normalizeDraft()
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func updateValue(from candidate: String) {
        let filtered = decimalCharacters(from: candidate)
        if filtered != candidate {
            draft = filtered
            return
        }

        guard let parsed = Double(filtered) else { return }
        value = clamped(parsed)
    }

    private func normalizeDraft() {
        if let parsed = Double(draft) {
            value = clamped(parsed)
        }
        draft = Self.formatted(value)
    }

    private func decimalCharacters(from candidate: String) -> String {
        let normalized = candidate.replacingOccurrences(of: ",", with: ".")
        var hasDecimalPoint = false
        return normalized.filter { character in
            if character.isNumber {
                return true
            }
            if character == ".", !hasDecimalPoint {
                hasDecimalPoint = true
                return true
            }
            return false
        }
    }

    private func clamped(_ candidate: Double) -> Double {
        min(max(candidate, range.lowerBound), range.upperBound)
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(
            .number
                .grouping(.never)
                .precision(.fractionLength(1))
        )
    }
}
