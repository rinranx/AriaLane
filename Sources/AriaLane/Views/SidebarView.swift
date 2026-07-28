import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore
    @EnvironmentObject private var organization: TaskOrganizationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: SidebarSelection

    let isCompact: Bool
    let expandedWidth: Double
    @State private var isShowingServerSwitcher = false
    @State private var isShowingServerEditor = false
    @State private var shouldOpenServerEditor = false
    @State private var isServerSwitcherHovering = false
    @State private var isShowingOrganizationPopover = false
    @State private var organizationEditor: OrganizationEditorRoute?
    @State private var pendingOrganizationDeletion: OrganizationDeletion?

    var body: some View {
        Group {
            if isCompact {
                compactSidebar
                    .transition(.identity)
            } else {
                expandedSidebar
                    .transition(.identity)
            }
        }
        .background(LaneColor.sidebar)
        .sheet(isPresented: $isShowingServerEditor) {
            ServerEditorSheet { draft in
                let profileID = preferences.addServerProfile(
                    name: draft.name,
                    endpoint: draft.endpoint,
                    secret: draft.secret
                )
                Task { await store.switchServer(to: profileID) }
            }
        }
        .sheet(item: $organizationEditor) { route in
            organizationEditorView(for: route)
        }
        .confirmationDialog(
            pendingOrganizationDeletion?.title ?? L10n.string("删除整理项目？"),
            isPresented: organizationDeletionBinding,
            titleVisibility: .visible
        ) {
            Button(L10n.string("删除"), role: .destructive) {
                commitOrganizationDeletion()
            }
            Button(L10n.string("取消"), role: .cancel) {
                pendingOrganizationDeletion = nil
            }
        } message: {
            Text(
                pendingOrganizationDeletion?.message
                    ?? L10n.string("任务本身不会被删除。")
            )
        }
        .onChange(of: isShowingServerSwitcher) { _, isShowing in
            guard !isShowing, shouldOpenServerEditor else { return }
            shouldOpenServerEditor = false
            DispatchQueue.main.async {
                isShowingServerEditor = true
            }
        }
        .onChange(of: organization.tags.map(\.id)) { _, ids in
            if case .tag(let id) = selection, !ids.contains(id) {
                selection = .filter(.all)
            }
        }
        .onChange(of: organization.smartFolders.map(\.id)) { _, ids in
            if case .smartFolder(let id) = selection, !ids.contains(id) {
                selection = .filter(.all)
            }
        }
    }

    private var expandedSidebar: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(TransferFilter.liveCases) { item in
                        expandedRow(for: item)
                    }
                } header: {
                    HStack(spacing: 9) {
                        FlowMark(size: 22)
                        Text("AriaLane")
                            .font(LaneFont.label(13))
                            .textCase(nil)
                            .foregroundStyle(.primary)
                    }
                    .padding(.bottom, 8)
                }

                Section {
                    ForEach(organization.smartFolders) { folder in
                        expandedSmartFolderRow(folder)
                    }
                } header: {
                    organizationSectionHeader(
                        L10n.string("智能文件夹"),
                        action: { organizationEditor = .newSmartFolder }
                    )
                }

                Section {
                    ForEach(organization.tags) { tag in
                        expandedTagRow(tag)
                    }
                } header: {
                    organizationSectionHeader(
                        L10n.string("标签"),
                        action: { organizationEditor = .newTag }
                    )
                }

                Section {
                    expandedRow(for: .pending)
                    expandedRow(for: .scheduled)
                    expandedRow(for: .rss)
                } header: {
                    sectionHeader(L10n.string("自动化"))
                }

                Section {
                    expandedRow(for: .history)
                } header: {
                    sectionHeader(L10n.string("记录"))
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .contentMargins(
                .horizontal,
                compressedSpacing(regular: 12, narrow: 2),
                for: .scrollContent
            )

            expandedServerSwitcher
        }
    }

    private var compactSidebar: some View {
        VStack(spacing: 0) {
            FlowMark(size: 26)
                .frame(width: 56, height: 47)
                .help("AriaLane")

            Divider()
                .opacity(0.55)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(TransferFilter.liveCases) { item in
                        compactRow(for: item)
                    }

                    compactDivider

                    compactOrganizationButton

                    compactDivider

                    compactRow(for: .pending)
                    compactRow(for: .scheduled)
                    compactRow(for: .rss)

                    compactDivider

                    compactRow(for: .history)
                }
                .padding(.vertical, 9)
            }
            .scrollIndicators(.hidden)

            compactServerSwitcher
        }
    }

    private var expandedServerSwitcher: some View {
        serverSwitcherButton {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    ServerStatusDot(
                        color: connectionColor,
                        isPulsing: isConnectionPulsing,
                        size: 7
                    )

                    Text(preferences.activeServerProfileName)
                        .font(LaneFont.interface(12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer(minLength: 5)

                    Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(
                        .degrees(isShowingServerSwitcher ? 180 : 0)
                    )
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.15),
                        value: isShowingServerSwitcher
                    )
                }

                Text(serverVersionLine)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.leading, 15)
            }
            .padding(.horizontal, compressedSpacing(regular: 9, narrow: 4))
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isServerSwitcherHovering
                    ? Color.primary.opacity(0.045)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .padding(.horizontal, compressedSpacing(regular: 5, narrow: 2))
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .background(LaneColor.sidebar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LaneColor.line)
                .frame(height: 0.5)
        }
    }

    private var compactServerSwitcher: some View {
        serverSwitcherButton {
            ServerStatusDot(
                color: connectionColor,
                isPulsing: isConnectionPulsing,
                size: 7
            )
            .frame(width: 46, height: 38)
            .background(
                isServerSwitcherHovering
                    ? Color.primary.opacity(0.045)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .padding(5)
            .contentShape(Rectangle())
        }
        .help(
            "\(preferences.activeServerProfileName) · \(connectionStatusTitle)"
        )
        .background(LaneColor.sidebar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LaneColor.line)
                .frame(height: 0.5)
        }
    }

    private func serverSwitcherButton<MenuLabel: View>(
        @ViewBuilder label: () -> MenuLabel
    ) -> some View {
        Button {
            isShowingServerSwitcher.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .onHover { isServerSwitcherHovering = $0 }
        .accessibilityLabel(L10n.string("切换服务器"))
        .accessibilityValue(
            "\(preferences.activeServerProfileName)，\(connectionStatusTitle)"
        )
        .popover(
            isPresented: $isShowingServerSwitcher,
            arrowEdge: .top
        ) {
            serverSwitcherPopover
        }
        .contextMenu {
            Button {
                Task { await store.reconnect() }
            } label: {
                Label(L10n.string("重新连接当前服务器"), systemImage: "arrow.clockwise")
            }
        }
    }

    private var serverSwitcherPopover: some View {
        VStack(spacing: 2) {
            ForEach(preferences.serverProfiles) { profile in
                Button {
                    isShowingServerSwitcher = false
                    Task { await store.switchServer(to: profile.id) }
                } label: {
                    ServerProfileSwitcherRow(
                        profile: profile,
                        isActive: profile.id == preferences.activeServerProfileID,
                        statusColor: profile.id == preferences.activeServerProfileID
                            ? connectionColor
                            : Color.secondary.opacity(0.5),
                        isPulsing: profile.id == preferences.activeServerProfileID
                            && isConnectionPulsing
                    )
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(LaneColor.line)
                .frame(height: 0.5)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)

            Button {
                shouldOpenServerEditor = true
                isShowingServerSwitcher = false
            } label: {
                Label(L10n.string("添加服务器…"), systemImage: "plus")
                    .font(LaneFont.interface(13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(5)
        .frame(width: 208)
        .presentationBackground(LaneColor.surface)
    }

    private func expandedRow(for item: TransferFilter) -> some View {
        Button {
            selection = .filter(item)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor(for: item))
                    .frame(width: 17)

                Text(item.title)
                    .font(LaneFont.interface(12, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)

                if showsExpandedCounts {
                    Spacer(minLength: 8)

                    Text(String(count(for: item)))
                        .font(LaneFont.utility(10, weight: .regular))
                        .foregroundStyle(.tertiary)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, compressedSpacing(regular: 8, narrow: 2))
            .frame(height: 28)
            .background {
                if selection == .filter(item) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.065))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(
            EdgeInsets(
                top: 1,
                leading: compressedSpacing(regular: 7, narrow: 2),
                bottom: 1,
                trailing: compressedSpacing(regular: 7, narrow: 2)
            )
        )
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(selection == .filter(item) ? .isSelected : [])
        .accessibilityValue("\(count(for: item))")
    }

    private func compactRow(for item: TransferFilter) -> some View {
        Button {
            selection = .filter(item)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor(for: item))
                    .frame(width: 36, height: 32)
                    .background {
                        if selection == .filter(item) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.075))
                        }
                    }

                if item == .active, count(for: .active) > 0 {
                    Circle()
                        .fill(LaneColor.accent)
                        .frame(width: 6, height: 6)
                        .overlay {
                            Circle()
                                .stroke(LaneColor.sidebar, lineWidth: 1.5)
                        }
                        .offset(x: 1, y: -1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 56)
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityValue("\(count(for: item))")
        .accessibilityAddTraits(selection == .filter(item) ? .isSelected : [])
    }

    private var compactDivider: some View {
        Divider()
            .frame(width: 26)
            .padding(.vertical, 5)
            .opacity(0.6)
    }

    private func expandedSmartFolderRow(_ folder: SmartFolder) -> some View {
        Button {
            selection = .smartFolder(folder.id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 17)

                Text(folder.displayName)
                    .font(LaneFont.interface(12, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)

                if showsExpandedCounts {
                    Spacer(minLength: 8)
                    Text(String(organization.count(for: folder)))
                        .font(LaneFont.utility(10, weight: .regular))
                        .foregroundStyle(.tertiary)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, compressedSpacing(regular: 8, narrow: 2))
            .frame(height: 28)
            .background {
                if selection == .smartFolder(folder.id) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.065))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .organizationListRowInsets(
            leading: compressedSpacing(regular: 7, narrow: 2),
            trailing: compressedSpacing(regular: 7, narrow: 2)
        )
        .contextMenu {
            Button(L10n.string("编辑智能文件夹…")) {
                organizationEditor = .editSmartFolder(folder.id)
            }
            Divider()
            Button(L10n.string("删除智能文件夹"), role: .destructive) {
                pendingOrganizationDeletion = .smartFolder(folder)
            }
        }
        .accessibilityAddTraits(
            selection == .smartFolder(folder.id) ? .isSelected : []
        )
        .accessibilityValue("\(organization.count(for: folder))")
    }

    private func expandedTagRow(_ tag: TaskTag) -> some View {
        Button {
            selection = .tag(tag.id)
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(tag.color.color)
                    .frame(width: 8, height: 8)
                    .frame(width: 17)

                Text(tag.displayName)
                    .font(LaneFont.interface(12, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)

                if showsExpandedCounts {
                    Spacer(minLength: 8)
                    Text(String(organization.count(for: tag)))
                        .font(LaneFont.utility(10, weight: .regular))
                        .foregroundStyle(.tertiary)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, compressedSpacing(regular: 8, narrow: 2))
            .frame(height: 28)
            .background {
                if selection == .tag(tag.id) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.065))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .organizationListRowInsets(
            leading: compressedSpacing(regular: 7, narrow: 2),
            trailing: compressedSpacing(regular: 7, narrow: 2)
        )
        .contextMenu {
            Button(L10n.string("编辑标签…")) {
                organizationEditor = .editTag(tag.id)
            }
            Divider()
            Button(L10n.string("删除标签"), role: .destructive) {
                pendingOrganizationDeletion = .tag(tag)
            }
        }
        .accessibilityAddTraits(selection == .tag(tag.id) ? .isSelected : [])
        .accessibilityValue("\(organization.count(for: tag))")
    }

    private var compactOrganizationButton: some View {
        Button {
            isShowingOrganizationPopover.toggle()
        } label: {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 32)
                .background {
                    if isOrganizationSelection {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.075))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 56)
        .help(L10n.string("智能文件夹与标签"))
        .popover(
            isPresented: $isShowingOrganizationPopover,
            arrowEdge: .leading
        ) {
            compactOrganizationPopover
        }
        .accessibilityLabel(L10n.string("智能文件夹与标签"))
        .accessibilityAddTraits(isOrganizationSelection ? .isSelected : [])
    }

    private var compactOrganizationPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            compactOrganizationGroup(
                title: L10n.string("智能文件夹"),
                addAction: {
                    isShowingOrganizationPopover = false
                    organizationEditor = .newSmartFolder
                }
            ) {
                if organization.smartFolders.isEmpty {
                    compactOrganizationEmpty(L10n.string("还没有智能文件夹"))
                } else {
                    ForEach(organization.smartFolders) { folder in
                        compactOrganizationRow(
                            title: folder.displayName,
                            systemImage: "folder.badge.gearshape",
                            color: .secondary,
                            count: organization.count(for: folder),
                            isSelected: selection == .smartFolder(folder.id)
                        ) {
                            selection = .smartFolder(folder.id)
                            isShowingOrganizationPopover = false
                        }
                    }
                }
            }

            Divider()

            compactOrganizationGroup(
                title: L10n.string("标签"),
                addAction: {
                    isShowingOrganizationPopover = false
                    organizationEditor = .newTag
                }
            ) {
                if organization.tags.isEmpty {
                    compactOrganizationEmpty(L10n.string("还没有标签"))
                } else {
                    ForEach(organization.tags) { tag in
                        compactOrganizationRow(
                            title: tag.displayName,
                            systemImage: "circle.fill",
                            color: tag.color.color,
                            count: organization.count(for: tag),
                            isSelected: selection == .tag(tag.id)
                        ) {
                            selection = .tag(tag.id)
                            isShowingOrganizationPopover = false
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 250)
        .presentationBackground(LaneColor.surface)
    }

    private func compactOrganizationGroup<Content: View>(
        title: String,
        addAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(LaneFont.interface(10, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(action: addAction) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(L10n.string("新建\(title)"))
            }

            content()
        }
    }

    private func compactOrganizationRow(
        title: String,
        systemImage: String,
        color: Color,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 15)
                Text(title)
                    .font(LaneFont.interface(12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(String(count))
                    .font(LaneFont.utility(10, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 29)
            .background(
                isSelected ? Color.primary.opacity(0.06) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func compactOrganizationEmpty(_ title: String) -> some View {
        Text(title)
            .font(LaneFont.interface(10))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .frame(height: 28)
    }

    private var isOrganizationSelection: Bool {
        switch selection {
        case .tag, .smartFolder: true
        case .filter: false
        }
    }

    private var connectionColor: Color {
        if store.isConnectedToActiveServer {
            return Color(nsColor: .systemGreen)
        }
        switch store.connectionState {
        case .idle, .connected: return Color.secondary.opacity(0.5)
        case .connecting: return LaneColor.accent
        case .failed: return LaneColor.danger
        }
    }

    private var isConnectionPulsing: Bool {
        guard case .connecting = store.connectionState else { return false }
        return true
    }

    private var connectionStatusTitle: String {
        switch store.connectionState {
        case .connected where store.isConnectedToActiveServer: return L10n.string("已连接")
        case .connecting: return L10n.string("正在连接")
        case .failed: return L10n.string("连接失败")
        case .idle, .connected: return L10n.string("未连接")
        }
    }

    private var serverVersionLine: String {
        switch store.connectionState {
        case .connected(let version) where store.isConnectedToActiveServer:
            return "aria2 \(version)"
        case .connecting:
            return L10n.string("正在连接…")
        case .failed:
            return L10n.string("连接失败")
        case .idle, .connected:
            return L10n.string("未连接")
        }
    }

    private func count(for filter: TransferFilter) -> Int {
        switch filter {
        case .pending:
            return store.pendingDownloads.count
        case .scheduled:
            return store.scheduledDownloads.count
        case .rss:
            return store.rssSubscriptions.count
        case .history:
            return store.historyEntries.count
        default:
            return store.transfers.filter(filter.includes).count
        }
    }

    private func iconColor(for item: TransferFilter) -> Color {
        guard item == .active, count(for: .active) > 0 else {
            return .secondary
        }
        return LaneColor.accent
    }

    private var edgeCompressionProgress: CGFloat {
        let regularWidth = 200.0
        let fullyCompressedWidth = 160.0
        let progress = (regularWidth - expandedWidth)
            / (regularWidth - fullyCompressedWidth)
        return CGFloat(min(max(progress, 0), 1))
    }

    private var showsExpandedCounts: Bool {
        expandedWidth >= 160
    }

    private func compressedSpacing(
        regular: CGFloat,
        narrow: CGFloat
    ) -> CGFloat {
        regular + (narrow - regular) * edgeCompressionProgress
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(LaneFont.interface(10, weight: .medium))
            .foregroundStyle(.tertiary)
            .textCase(nil)
    }

    private func organizationSectionHeader(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            sectionHeader(title)
            Spacer(minLength: 4)
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(L10n.string("新建\(title)"))
        }
    }

    @ViewBuilder
    private func organizationEditorView(
        for route: OrganizationEditorRoute
    ) -> some View {
        switch route {
        case .newTag:
            TagEditorView(tag: nil) { name, color in
                guard let tag = organization.createTag(name: name, color: color) else {
                    return false
                }
                selection = .tag(tag.id)
                return true
            }
            .environmentObject(organization)

        case .editTag(let id):
            if let tag = organization.tag(id: id) {
                TagEditorView(tag: tag) { name, color in
                    organization.updateTag(id: id, name: name, color: color)
                }
                .environmentObject(organization)
            }

        case .newSmartFolder:
            SmartFolderEditorView(folder: nil) { name, mode, rules in
                guard let folder = organization.createSmartFolder(
                    name: name,
                    matchMode: mode,
                    rules: rules
                ) else {
                    return false
                }
                selection = .smartFolder(folder.id)
                return true
            }
            .environmentObject(organization)

        case .editSmartFolder(let id):
            if let folder = organization.smartFolder(id: id) {
                SmartFolderEditorView(folder: folder) { name, mode, rules in
                    organization.updateSmartFolder(
                        id: id,
                        name: name,
                        matchMode: mode,
                        rules: rules
                    )
                }
                .environmentObject(organization)
            }
        }
    }

    private var organizationDeletionBinding: Binding<Bool> {
        Binding(
            get: { pendingOrganizationDeletion != nil },
            set: {
                if !$0 {
                    pendingOrganizationDeletion = nil
                }
            }
        )
    }

    private func commitOrganizationDeletion() {
        switch pendingOrganizationDeletion {
        case .tag(let tag):
            organization.deleteTag(id: tag.id)
            if selection == .tag(tag.id) {
                selection = .filter(.all)
            }
        case .smartFolder(let folder):
            organization.deleteSmartFolder(id: folder.id)
            if selection == .smartFolder(folder.id) {
                selection = .filter(.all)
            }
        case nil:
            break
        }
        pendingOrganizationDeletion = nil
    }
}

private enum OrganizationEditorRoute: Identifiable {
    case newTag
    case editTag(UUID)
    case newSmartFolder
    case editSmartFolder(UUID)

    var id: String {
        switch self {
        case .newTag: "new-tag"
        case .editTag(let id): "edit-tag-\(id.uuidString)"
        case .newSmartFolder: "new-smart-folder"
        case .editSmartFolder(let id): "edit-smart-folder-\(id.uuidString)"
        }
    }
}

private enum OrganizationDeletion {
    case tag(TaskTag)
    case smartFolder(SmartFolder)

    var title: String {
        switch self {
        case .tag(let tag): L10n.string("删除标签“\(tag.displayName)”？")
        case .smartFolder(let folder):
            L10n.string("删除智能文件夹“\(folder.displayName)”？")
        }
    }

    var message: String {
        switch self {
        case .tag:
            L10n.string("标签会从相关任务移除，任务与下载历史不会被删除。")
        case .smartFolder:
            L10n.string("只会删除保存的查询，任务与下载历史不会被删除。")
        }
    }
}

private extension View {
    func organizationListRowInsets(
        leading: CGFloat,
        trailing: CGFloat
    ) -> some View {
        listRowInsets(
            EdgeInsets(
                top: 1,
                leading: leading,
                bottom: 1,
                trailing: trailing
            )
        )
        .listRowBackground(Color.clear)
    }
}

private struct ServerProfileSwitcherRow: View {
    let profile: Aria2ServerProfile
    let isActive: Bool
    let statusColor: Color
    let isPulsing: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ServerStatusDot(
                color: statusColor,
                isPulsing: isPulsing,
                size: 7
            )

            Text(profile.displayName)
                .font(LaneFont.interface(13, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 4)

            Text(profile.endpointSummary)
                .font(LaneFont.utility(11, weight: .regular))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 11)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            isHovering
                ? Color.primary.opacity(0.045)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(profile.displayName)，\(profile.endpointSummary)"
        )
        .accessibilityValue(isActive ? L10n.string("当前服务器") : "")
    }
}

private struct ServerStatusDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let color: Color
    let isPulsing: Bool
    let size: CGFloat

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 30,
                paused: !isPulsing || reduceMotion
            )
        ) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1)
            let pulse = (sin(phase * .pi * 2) + 1) / 2

            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .scaleEffect(isPulsing && !reduceMotion ? 1 + pulse * 0.12 : 1)
                .opacity(isPulsing && !reduceMotion ? 0.55 + pulse * 0.45 : 1)
        }
        .frame(width: size, height: size)
    }
}
