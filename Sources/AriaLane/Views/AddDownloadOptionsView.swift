import Foundation
import SwiftUI

struct AddDownloadOptionsView: View {
    @ObservedObject var form: AddDownloadFormState
    let urlCount: Int
    let scheduleIsRequired: Bool
    let isCompact: Bool
    let availableHeight: CGFloat
    let chooseDirectory: () -> Void

    @State private var isAdvancedExpanded = true
    @State private var isShowingDestinationEditor = false
    @State private var isShowingScheduleEditor = false

    private let advancedSections: [AddDownloadSection] = [
        .transfer,
        .sources,
        .request,
        .verification,
        .protocols,
        .bittorrent,
        .raw,
    ]

    init(
        form: AddDownloadFormState,
        urlCount: Int,
        scheduleIsRequired: Bool = false,
        isCompact: Bool = false,
        availableHeight: CGFloat = 720,
        chooseDirectory: @escaping () -> Void
    ) {
        self.form = form
        self.urlCount = urlCount
        self.scheduleIsRequired = scheduleIsRequired
        self.isCompact = isCompact
        self.availableHeight = availableHeight
        self.chooseDirectory = chooseDirectory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 14 : 18) {
            essentialOptions
            advancedOptions
        }
        .onAppear {
            if !advancedSections.contains(form.selectedSection) {
                form.selectedSection = .transfer
            }
        }
    }

    private var essentialOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("保存与开始"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if isCompact {
                VStack(spacing: 10) {
                    destinationCard
                    scheduleCard
                }
            } else {
                HStack(spacing: 12) {
                    destinationCard
                    scheduleCard
                }
            }
        }
    }

    private var destinationCard: some View {
        EssentialOptionCard(
            systemImage: "folder",
            title: L10n.string("保存位置"),
            value: displayDirectory,
            isModified: form.hasOverrides(in: .destination)
        ) {
            isShowingDestinationEditor = true
        }
        .frame(maxWidth: .infinity)
        .popover(
            isPresented: $isShowingDestinationEditor,
            arrowEdge: .bottom
        ) {
            destinationEditor
                .padding(isCompact ? 15 : 18)
                .frame(width: isCompact ? 390 : 440)
        }
    }

    @ViewBuilder
    private var scheduleCard: some View {
        if isCompact {
            scheduleCardContent
                .frame(maxWidth: .infinity)
        } else {
            scheduleCardContent
                .frame(width: 250)
        }
    }

    private var scheduleCardContent: some View {
        EssentialOptionCard(
            systemImage: form.isScheduled ? "calendar.badge.clock" : "clock",
            title: L10n.string("开始时间"),
            value: scheduleSummary,
            isModified: form.hasOverrides(in: .schedule)
        ) {
            isShowingScheduleEditor = true
        }
        .popover(
            isPresented: $isShowingScheduleEditor,
            arrowEdge: .bottom
        ) {
            scheduleEditor
                .padding(isCompact ? 15 : 18)
                .frame(width: isCompact ? 390 : 430)
        }
    }

    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isAdvancedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isAdvancedExpanded ? 0 : -90))

                    Text(L10n.string("高级选项"))
                        .font(.system(size: 14, weight: .semibold))

                    Text(
                        isCompact
                            ? L10n.string("选择类别后调整参数")
                            : L10n.string("在左侧选择类别，右侧调整参数")
                    )
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isAdvancedExpanded {
                Group {
                    if isCompact {
                        VStack(spacing: 0) {
                            compactSectionRail
                                .padding(10)

                            Divider()

                            sectionEditor
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .frame(
                                    maxWidth: .infinity,
                                    maxHeight: .infinity,
                                    alignment: .topLeading
                                )
                        }
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            sectionRail
                                .frame(width: 236)
                                .padding(14)

                            Divider()

                            sectionEditor
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .frame(
                                    maxWidth: .infinity,
                                    maxHeight: .infinity,
                                    alignment: .topLeading
                                )
                        }
                    }
                }
                .frame(height: advancedPanelHeight)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(LaneColor.line, lineWidth: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var compactSectionRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(advancedSections) { section in
                    let isSelected = selectedAdvancedSection == section

                    Button {
                        form.selectedSection = section
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 11.5, weight: .semibold))

                            Text(section.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)

                            if form.hasOverrides(in: section) {
                                Circle()
                                    .fill(LaneColor.mint)
                                    .frame(width: 5, height: 5)
                                    .accessibilityLabel(L10n.string("已修改"))
                            }
                        }
                        .foregroundStyle(
                            isSelected ? LaneColor.accent : Color.secondary
                        )
                        .padding(.horizontal, 11)
                        .frame(minWidth: 104, minHeight: 42)
                        .background(
                            isSelected
                                ? LaneColor.accent.opacity(0.10)
                                : Color.clear,
                            in: RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                        )
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var advancedPanelHeight: CGFloat {
        let minimumHeight: CGFloat = isCompact ? 374 : 318
        guard !isCompact else { return minimumHeight }

        return minimumHeight + max(0, availableHeight - 720)
    }

    private var sectionRail: some View {
        ScrollView {
            VStack(spacing: 5) {
                ForEach(advancedSections) { section in
                    railButton(for: section)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func railButton(for section: AddDownloadSection) -> some View {
        let isSelected = selectedAdvancedSection == section

        return Button {
            form.selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? LaneColor.accent : .secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        isSelected
                            ? LaneColor.accent.opacity(0.10)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(section.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if form.hasOverrides(in: section) {
                            Circle()
                                .fill(LaneColor.mint)
                                .frame(width: 6, height: 6)
                                .accessibilityLabel(L10n.string("已修改"))
                        }
                    }

                    Text(sectionSummary(for: section))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LaneColor.accent.opacity(0.10))
                }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(LaneColor.accent)
                        .frame(width: 3, height: 42)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var sectionEditor: some View {
        switch selectedAdvancedSection {
        case .transfer:
            transferEditor
        case .request:
            requestEditor
        case .verification:
            verificationEditor
        case .sources:
            DownloadSourcesOptionsView(form: form, primaryURLCount: urlCount)
        case .protocols:
            DownloadProtocolOptionsView(form: form)
        case .bittorrent:
            DownloadBitTorrentOptionsView(form: form)
        case .raw:
            DownloadRawOptionsView(form: form)
        case .destination, .schedule:
            transferEditor
        }
    }

    private var transferEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            OptionSectionHeader(
                title: L10n.string("速度与连接"),
                detail: L10n.string("0 KB/s 表示不限速。"),
                systemImage: "gauge.with.dots.needle.50percent"
            )

            HStack(alignment: .top, spacing: 16) {
                OptionInput(L10n.string("下载上限")) {
                    SpeedValueField(value: $form.maxDownloadLimitKiB)
                }

                OptionInput(L10n.string("上传上限")) {
                    SpeedValueField(value: $form.maxUploadLimitKiB)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                OptionInput(L10n.string("分段数")) {
                    TextField("10", value: $form.split, format: .number)
                        .textFieldStyle(.plain)
                        .font(LaneFont.utility(12, weight: .regular))
                }

                OptionInput(L10n.string("单服务器连接")) {
                    TextField(
                        "8",
                        value: $form.maxConnectionPerServer,
                        format: .number
                    )
                    .textFieldStyle(.plain)
                    .font(LaneFont.utility(12, weight: .regular))
                }
            }

            Text(
                L10n.string("单个服务器最多并行 ")
                    + L10n.string("\(min(form.split, form.maxConnectionPerServer)) 条连接；")
                    + L10n.string("只有修改过的项目会作为本任务的覆盖设置发送。")
            )
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .lineLimit(2)

            Spacer(minLength: 0)
        }
    }

    private var requestEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            OptionSectionHeader(
                title: L10n.string("请求标头"),
                detail: L10n.string("只覆盖本次任务发送的 HTTP 请求信息。"),
                systemImage: "network"
            )

            HStack(alignment: .top, spacing: 16) {
                OptionInput("Referer") {
                    TextField("https://example.com/", text: $form.referer)
                        .textFieldStyle(.plain)
                        .font(LaneFont.utility(11, weight: .regular))
                }

                OptionInput("User-Agent") {
                    TextField(L10n.string("沿用 aria2 默认值"), text: $form.userAgent)
                        .textFieldStyle(.plain)
                        .font(LaneFont.utility(11, weight: .regular))
                }
            }

            OptionTextEditor(
                title: L10n.string("自定义 Header · 每行一个 Name: Value"),
                placeholder: "Authorization: Bearer …",
                text: $form.customHeadersText
            )

            Text(L10n.string("全部留空时沿用 aria2 当前请求设置。"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)
        }
    }

    private var verificationEditor: some View {
        VStack(alignment: .leading, spacing: 13) {
            OptionSectionHeader(
                title: L10n.string("认证与校验"),
                detail: L10n.string("填写访问凭据，并为下载内容选择校验算法。"),
                systemImage: "checkmark.shield"
            )

            HStack(alignment: .top, spacing: 16) {
                OptionInput(L10n.string("用户名")) {
                    TextField(L10n.string("HTTP / FTP 用户名"), text: $form.username)
                        .textFieldStyle(.plain)
                }

                OptionInput(L10n.string("密码")) {
                    SecureField(L10n.string("密码"), text: $form.password)
                        .textFieldStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                OptionInput(L10n.string("校验算法")) {
                    OptionSelectionMenu(
                        selection: $form.checksumAlgorithm,
                        values: DownloadChecksumAlgorithm.allCases,
                        accessibilityLabel: L10n.string("校验算法")
                    ) { $0.title }
                }

                OptionInput("Cookie") {
                    SecureField("session=…; token=…", text: $form.cookie)
                        .textFieldStyle(.plain)
                }
            }

            OptionInput(L10n.string("校验值")) {
                TextField(checksumPlaceholder, text: $form.checksumDigest)
                    .textFieldStyle(.plain)
                    .font(LaneFont.utility(10, weight: .regular))
                    .disabled(form.checksumAlgorithm == .none)
            }

            Text(verificationDetail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
    }

    private var destinationEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            OptionSectionHeader(
                title: L10n.string("保存位置"),
                detail: L10n.string("只覆盖这次添加的任务，不改变默认下载目录。"),
                systemImage: "folder"
            )

            OptionInput(L10n.string("保存目录")) {
                HStack(spacing: 8) {
                    TextField(L10n.string("下载目录"), text: $form.downloadDirectory)
                        .textFieldStyle(.plain)
                        .font(LaneFont.utility(11, weight: .regular))

                    Button(L10n.string("选择…"), action: chooseDirectory)
                        .buttonStyle(.plain)
                        .foregroundStyle(LaneColor.accent)
                }
            }

            OptionInput(L10n.string("文件名（可选）")) {
                TextField(
                    L10n.string("留空则使用服务器提供的名称"),
                    text: $form.outputFileName
                )
                .textFieldStyle(.plain)
                .font(LaneFont.utility(11, weight: .regular))
            }

            Text(destinationDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            OptionSectionHeader(
                title: L10n.string("开始时间"),
                detail: L10n.string("立即发送，或在指定时间自动创建下载任务。"),
                systemImage: "calendar.badge.clock"
            )

            Toggle(L10n.string("定时开始下载"), isOn: $form.isScheduled)
                .toggleStyle(.switch)
                .disabled(scheduleIsRequired)

            OptionInput(L10n.string("计划时间")) {
                OptionDateTimePicker(
                    selection: $form.scheduledAt,
                    isEnabled: form.isScheduled
                )
            }

            OptionInput(L10n.string("重复频率")) {
                OptionSelectionMenu(
                    selection: $form.scheduleFrequency,
                    values: ScheduleFrequency.allCases,
                    accessibilityLabel: L10n.string("重复频率")
                ) { $0.title }
                .disabled(!form.isScheduled)
            }

            Text(scheduleDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private var selectedAdvancedSection: AddDownloadSection {
        advancedSections.contains(form.selectedSection)
            ? form.selectedSection
            : .transfer
    }

    private var displayDirectory: String {
        let path = form.downloadDirectory.trimmed
        guard !path.isEmpty else { return L10n.string("选择保存目录") }
        return NSString(string: path).abbreviatingWithTildeInPath
    }

    private var scheduleSummary: String {
        guard form.isScheduled else { return L10n.string("立即开始") }
        return "\(form.scheduleFrequency.shortTitle) · "
            + form.scheduledAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func sectionSummary(for section: AddDownloadSection) -> String {
        switch section {
        case .transfer:
            let speedSummary: String
            if form.maxDownloadLimitKiB == 0, form.maxUploadLimitKiB == 0 {
                speedSummary = L10n.string("不限速")
            } else {
                let download = form.maxDownloadLimitKiB == 0
                    ? "∞"
                    : String(form.maxDownloadLimitKiB)
                let upload = form.maxUploadLimitKiB == 0
                    ? "∞"
                    : String(form.maxUploadLimitKiB)
                speedSummary = "↓\(download) · ↑\(upload) KB/s"
            }
            return L10n.string("\(speedSummary) · \(form.split) 分段 · ")
                + L10n.string("\(form.maxConnectionPerServer) 连接")

        case .request:
            return form.hasOverrides(in: .request)
                ? L10n.string("已自定义 · Referer · UA · Header")
                : L10n.string("默认 · Referer · UA · Header")

        case .verification:
            let checksum = form.checksumAlgorithm == .none
                ? L10n.string("不校验")
                : form.checksumAlgorithm.title
            return "\(checksum) · \(hasAuthentication ? L10n.string("认证已填写") : L10n.string("无认证"))"

        case .sources:
            let count = form.taskOptions.advanced?.normalizedAdditionalURIs.count ?? 0
            return count == 0 ? L10n.string("未添加备用 URI") : L10n.string("\(count) 个备用 URI")

        case .protocols:
            return form.hasOverrides(in: .protocols)
                ? L10n.string("已覆盖代理、TLS 或协议参数")
                : section.detail

        case .bittorrent:
            return form.hasOverrides(in: .bittorrent)
                ? L10n.string("已覆盖 BT 或 Metalink 参数")
                : section.detail

        case .raw:
            let count = form.advancedAria2Options.customOptionsText
                .components(separatedBy: .newlines)
                .filter { !$0.trimmed.isEmpty && !$0.trimmed.hasPrefix("#") }
                .count
            return count == 0 ? section.detail : L10n.string("\(count) 条自定义参数")

        case .destination:
            return displayDirectory

        case .schedule:
            return scheduleSummary
        }
    }

    private var hasAuthentication: Bool {
        !form.cookie.trimmed.isEmpty
            || !form.username.trimmed.isEmpty
            || !form.password.isEmpty
    }

    private var destinationDetail: String {
        if urlCount > 1 {
            return L10n.string("一次添加多个链接时，请留空文件名；每个任务会使用自己的名称。")
        }
        return L10n.string("文件名只填写名称，不需要包含保存路径。")
    }

    private var scheduleDetail: String {
        guard form.isScheduled else {
            return L10n.string("点击“添加下载”后立即加入 aria2 队列。")
        }
        if form.scheduleFrequency == .once {
            return L10n.string("退出 AriaLane 后计划仍会保存；下次启动或服务器恢复连接时会补执行。")
        }
        return L10n.string("每次执行后会自动计算下一次时间；离线期间只补执行一次。")
    }

    private var checksumPlaceholder: String {
        guard let length = form.checksumAlgorithm.expectedHexLength else {
            return L10n.string("选择算法后输入校验值")
        }
        return L10n.string("\(length) 位十六进制 \(form.checksumAlgorithm.title)")
    }

    private var verificationDetail: String {
        if urlCount > 1 {
            return L10n.string("校验值和自定义文件名仅支持单链接任务。")
        }
        if form.isScheduled {
            return L10n.string("认证数据会保存在仅当前用户可读的本机文件中；aria2 仍可能写入会话文件。")
        }
        return L10n.string("敏感字段只保留在当前窗口；aria2 仍可能将其写入会话文件。")
    }
}

private struct EssentialOptionCard: View {
    let systemImage: String
    let title: String
    let value: String
    let isModified: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    if isModified {
                        Circle()
                            .fill(LaneColor.mint)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel(L10n.string("已修改"))
                    }
                }

                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button(L10n.string("更改"), action: action)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LaneColor.accent)
                .accessibilityLabel(L10n.string("更改\(title)"))
        }
        .padding(.horizontal, 15)
        .frame(height: 64)
        .background(
            LaneColor.fill1,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

struct OptionSectionHeader: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LaneColor.accent)
                .frame(width: 40, height: 40)
                .background(
                    LaneColor.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LaneFont.label(17))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct OptionInput<Content: View>: View {
    let title: String
    let content: Content

    init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

            content
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 39, alignment: .leading)
                .background(
                    LaneColor.fill1,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OptionTextEditor: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(LaneFont.utility(10.5, weight: .regular))
                    .scrollContentBackground(.hidden)
                    .padding(7)

                if text.isEmpty {
                    Text(placeholder)
                        .font(LaneFont.utility(10.5, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 66)
            .background(
                LaneColor.fill1,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
    }
}

private struct SpeedValueField: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 8) {
            TextField("0", value: $value, format: .number)
                .textFieldStyle(.plain)
                .font(LaneFont.utility(12, weight: .regular))

            Spacer(minLength: 6)

            Text("KB/s")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

struct OptionSelectionMenu<Value: Identifiable & Equatable>: View {
    @Binding var selection: Value
    let values: [Value]
    let accessibilityLabel: String
    let title: (Value) -> String

    var body: some View {
        Menu {
            ForEach(values) { value in
                Button {
                    selection = value
                } label: {
                    if selection == value {
                        Label(title(value), systemImage: "checkmark")
                    } else {
                        Text(title(value))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title(selection))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct OptionDateTimePicker: View {
    @Binding var selection: Date
    let isEnabled: Bool

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                Text(
                    selection.formatted(
                        date: .numeric,
                        time: .shortened
                    )
                )
                .foregroundStyle(.primary)
                .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(!isEnabled)
        .accessibilityLabel(L10n.string("计划时间"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Label(L10n.string("计划时间"), systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .foregroundStyle(LaneColor.accent)

                DatePicker(
                    L10n.string("计划时间"),
                    selection: $selection,
                    in: Date().addingTimeInterval(60)...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.graphical)

                HStack {
                    Spacer()

                    Button(L10n.string("完成")) {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(16)
            .frame(width: 310)
        }
    }
}
