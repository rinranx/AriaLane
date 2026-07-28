import SwiftUI

struct TagEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let tag: TaskTag?
    let onSave: (String, TaskTagColor) -> Bool

    @State private var name: String
    @State private var color: TaskTagColor
    @State private var showsValidationError = false

    init(
        tag: TaskTag?,
        onSave: @escaping (String, TaskTagColor) -> Bool
    ) {
        self.tag = tag
        self.onSave = onSave
        _name = State(initialValue: tag?.name ?? "")
        _color = State(initialValue: tag?.color ?? .blue)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(color.color)
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 3) {
                    Text(tag == nil ? L10n.string("新建标签") : L10n.string("编辑标签"))
                        .font(LaneFont.label(17))
                    Text(L10n.string("标签可以手动分配给任意下载任务"))
                        .font(LaneFont.interface(11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                TextField(L10n.string("名称"), text: $name, prompt: Text(L10n.string("例如：工作")))

                Picker(L10n.string("颜色"), selection: $color) {
                    ForEach(TaskTagColor.allCases) { option in
                        HStack {
                            Circle()
                                .fill(option.color)
                                .frame(width: 8, height: 8)
                            Text(option.title)
                        }
                        .tag(option)
                    }
                }

                if showsValidationError {
                    Text(L10n.string("名称不能为空，且不能和现有标签重复。"))
                        .font(LaneFont.interface(10))
                        .foregroundStyle(LaneColor.danger)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(L10n.string("取消")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(tag == nil ? L10n.string("创建") : L10n.string("保存")) {
                    if onSave(name.trimmed, color) {
                        dismiss()
                    } else {
                        showsValidationError = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmed.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 390, height: 285)
    }
}

struct SmartFolderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organization: TaskOrganizationStore

    let folder: SmartFolder?
    let onSave: (String, SmartFolderMatchMode, [SmartFolderRule]) -> Bool

    @State private var name: String
    @State private var matchMode: SmartFolderMatchMode
    @State private var rules: [SmartFolderRule]
    @State private var showsValidationError = false

    init(
        folder: SmartFolder?,
        onSave: @escaping (
            String,
            SmartFolderMatchMode,
            [SmartFolderRule]
        ) -> Bool
    ) {
        self.folder = folder
        self.onSave = onSave
        _name = State(initialValue: folder?.name ?? "")
        _matchMode = State(initialValue: folder?.matchMode ?? .all)
        _rules = State(
            initialValue: folder?.rules
                ?? [SmartFolderRule(field: .contentType)]
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    definitionSection
                    rulesSection
                }
                .padding(22)
            }

            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 500, idealHeight: 590)
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(LaneColor.accent)
                .frame(width: 42, height: 42)
                .background(
                    LaneColor.accent.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(folder == nil ? L10n.string("新建智能文件夹") : L10n.string("编辑智能文件夹"))
                    .font(LaneFont.label(18))
                Text(L10n.string("规则动态查询同一任务从下载到历史的完整生命周期"))
                    .font(LaneFont.interface(11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(previewCount))
                    .font(LaneFont.display(23))
                    .foregroundStyle(LaneColor.accent)
                Text(L10n.string("个匹配任务"))
                    .font(LaneFont.interface(9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var definitionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("文件夹"))
                .font(LaneFont.interface(11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                TextField(L10n.string("名称"), text: $name, prompt: Text(L10n.string("例如：最近的安装包")))
                    .textFieldStyle(.roundedBorder)

                Picker(L10n.string("匹配方式"), selection: $matchMode) {
                    ForEach(SmartFolderMatchMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 155)
            }
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("条件"))
                    .font(LaneFont.interface(11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    ForEach(SmartRuleField.allCases) { field in
                        Button {
                            rules.append(SmartFolderRule(field: field))
                        } label: {
                            Label(field.title, systemImage: field.systemImage)
                        }
                    }
                } label: {
                    Label(L10n.string("添加条件"), systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            VStack(spacing: 0) {
                ForEach($rules) { $rule in
                    SmartFolderRuleEditorRow(
                        rule: $rule,
                        canDelete: rules.count > 1,
                        onDelete: {
                            rules.removeAll { $0.id == rule.id }
                        }
                    )

                    if rule.id != rules.last?.id {
                        Divider()
                            .padding(.leading, 14)
                    }
                }
            }
            .background(
                LaneColor.surface,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(LaneColor.line, lineWidth: 1)
            }

            if showsValidationError {
                Text(L10n.string("请输入名称，并完整配置至少一条规则。"))
                    .font(LaneFont.interface(10))
                    .foregroundStyle(LaneColor.danger)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(L10n.string("智能文件夹只保存查询，不会移动或复制任务。"))
                .font(LaneFont.interface(10))
                .foregroundStyle(.tertiary)

            Spacer()

            Button(L10n.string("取消")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(folder == nil ? L10n.string("创建") : L10n.string("保存")) {
                if onSave(name.trimmed, matchMode, rules) {
                    dismiss()
                } else {
                    showsValidationError = true
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid)
        }
        .padding(16)
    }

    private var isValid: Bool {
        !name.trimmed.isEmpty && rules.contains(where: \.isConfigured)
    }

    private var previewCount: Int {
        organization.previewCount(matchMode: matchMode, rules: rules)
    }
}

private struct SmartFolderRuleEditorRow: View {
    @EnvironmentObject private var organization: TaskOrganizationStore

    @Binding var rule: SmartFolderRule
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker(L10n.string("字段"), selection: fieldBinding) {
                ForEach(SmartRuleField.allCases) { field in
                    Label(field.title, systemImage: field.systemImage)
                        .tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 128)

            Picker(L10n.string("比较"), selection: $rule.comparison) {
                ForEach(rule.field.allowedOperators) { comparison in
                    Text(comparison.title).tag(comparison)
                }
            }
            .labelsHidden()
            .frame(width: 126)

            valueEditor
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(
                        canDelete
                            ? LaneColor.danger
                            : Color.secondary.opacity(0.45)
                    )
            }
            .buttonStyle(.borderless)
            .disabled(!canDelete)
            .help(L10n.string("移除条件"))
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch rule.field {
        case .tag:
            valueMenu(
                options: organization.tags.map {
                    ($0.id.uuidString, $0.displayName)
                },
                emptyTitle: organization.tags.isEmpty ? L10n.string("请先创建标签") : L10n.string("选择标签")
            )
        case .contentType:
            valueMenu(
                options: TaskContentType.allCases.map { ($0.rawValue, $0.title) },
                emptyTitle: L10n.string("选择内容类型")
            )
        case .transferProtocol:
            valueMenu(
                options: TaskTransferProtocol.allCases.map { ($0.rawValue, $0.title) },
                emptyTitle: L10n.string("选择传输协议")
            )
        case .lifecycle:
            valueMenu(
                options: TaskLifecycle.allCases.map { ($0.rawValue, $0.title) },
                emptyTitle: L10n.string("选择任务状态")
            )
        case .sourceDomain:
            TextField(
                "example.com",
                text: $rule.textValue
            )
            .textFieldStyle(.roundedBorder)
        case .addedDate, .completedDate:
            dateEditor
        }
    }

    @ViewBuilder
    private var dateEditor: some View {
        switch rule.comparison {
        case .withinLastDays:
            Stepper(
                L10n.string("\(rule.dayCount) 天"),
                value: $rule.dayCount,
                in: 1...3_650
            )
            .fixedSize()
        case .between:
            HStack(spacing: 7) {
                DatePicker(
                    L10n.string("开始"),
                    selection: $rule.startDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                Text(L10n.string("至"))
                    .font(LaneFont.interface(10))
                    .foregroundStyle(.tertiary)
                DatePicker(
                    L10n.string("结束"),
                    selection: $rule.endDate,
                    displayedComponents: .date
                )
                .labelsHidden()
            }
        default:
            DatePicker(
                L10n.string("日期"),
                selection: $rule.startDate,
                displayedComponents: .date
            )
            .labelsHidden()
        }
    }

    private func valueMenu(
        options: [(String, String)],
        emptyTitle: String
    ) -> some View {
        Menu {
            if options.isEmpty {
                Text(emptyTitle)
            } else {
                ForEach(options, id: \.0) { value, title in
                    Button {
                        if rule.selectedValues.contains(value) {
                            rule.selectedValues.remove(value)
                        } else {
                            rule.selectedValues.insert(value)
                        }
                    } label: {
                        if rule.selectedValues.contains(value) {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            }
        } label: {
            Text(valueSummary(options: options, emptyTitle: emptyTitle))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
    }

    private func valueSummary(
        options: [(String, String)],
        emptyTitle: String
    ) -> String {
        let selectedTitles = options.compactMap { value, title in
            rule.selectedValues.contains(value) ? title : nil
        }
        if selectedTitles.isEmpty {
            return emptyTitle
        }
        if selectedTitles.count <= 2 {
            return selectedTitles.joined(separator: "、")
        }
        return L10n.string("\(selectedTitles[0])、\(selectedTitles[1]) 等 \(selectedTitles.count) 项")
    }

    private var fieldBinding: Binding<SmartRuleField> {
        Binding(
            get: { rule.field },
            set: { rule.reset(for: $0) }
        )
    }
}
