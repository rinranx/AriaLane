import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore
    @EnvironmentObject private var organization: TaskOrganizationStore

    @SceneStorage("selectedFilter")
    private var selectedSidebarRaw = SidebarSelection.filter(.all).storageValue
    @SceneStorage("selectedTransferGID") private var selectedGID: String?
    @SceneStorage("transferSearchText") private var transferSearchText = ""
    @SceneStorage("organizedTaskSearchText") private var organizedTaskSearchText = ""
    @SceneStorage("historySearchText") private var historySearchText = ""
    @SceneStorage("pendingDownloadSearchText") private var pendingDownloadSearchText = ""
    @SceneStorage("scheduleSearchText") private var scheduleSearchText = ""
    @SceneStorage("rssSearchText") private var rssSearchText = ""
    @SceneStorage("librarySearchText") private var librarySearchText = ""
    @State private var isShowingComposer = false
    @AppStorage(WindowLayoutPersistence.mainSidebarWidthKey)
    private var sidebarWidth = 200.0
    @AppStorage(WindowLayoutPersistence.mainSidebarCollapsedKey)
    private var isSidebarCollapsed = false
    @AppStorage(WindowLayoutPersistence.mainSidebarManualSelectionKey)
    private var hasManualSidebarSelection = false
    @StateObject private var viewState = ContentViewState()
    @State private var composerInitialInput = ""
    @State private var composerRequestID = UUID()
    @State private var isEditingSelectedSmartFolder = false
    @State private var windowContentSize = CGSize(width: 1_120, height: 720)

    var body: some View {
        lifecycleView
    }

    private var layoutView: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                SidebarView(
                    selection: sidebarSelectionBinding,
                    isCompact: isSidebarCollapsed,
                    expandedWidth: sidebarWidth
                )
                .frame(width: isSidebarCollapsed ? 56 : sidebarWidth)
                .overlay(alignment: .trailing) {
                    SidebarResizeHandle(
                        width: $sidebarWidth,
                        isCollapsed: isSidebarCollapsed,
                        collapsedWidth: 56,
                        minimumWidth: 130,
                        maximumWidth: 320,
                        collapseThreshold: 130,
                        restoreDragThreshold: 8,
                        onBeginResize: {
                            hasManualSidebarSelection = true
                        },
                        onCollapse: {
                            isSidebarCollapsed = true
                        },
                        onRestore: {
                            isSidebarCollapsed = false
                        }
                    )
                }

                Group {
                    if case .tag = sidebarSelection {
                        organizedTasks
                    } else if case .smartFolder = sidebarSelection {
                        organizedTasks
                    } else if selectedFilter == .history {
                        DownloadHistoryView(searchText: $historySearchText)
                    } else if selectedFilter == .pending {
                        PendingDownloadsView(searchText: $pendingDownloadSearchText)
                    } else if selectedFilter == .scheduled {
                        ScheduledDownloadsView(searchText: $scheduleSearchText)
                    } else if selectedFilter == .rss {
                        RSSSubscriptionsView(searchText: $rssSearchText)
                    } else if selectedFilter == .library {
                        LibrarySearchView(
                            searchText: $librarySearchText,
                            onDownload: { openComposer(initialInput: $0) }
                        )
                    } else {
                        TransferListView(
                            filter: selectedFilter,
                            selectedGIDs: $viewState.selectedGIDs,
                            searchText: $transferSearchText,
                            onAdd: { openComposer() }
                        )
                    }
                }
                .inspector(isPresented: inspectorBinding) {
                    if let selectedItem {
                        TransferInspectorView(item: selectedItem)
                            .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
                    } else if let selectedHistoricalEntity {
                        TaskEntityInspectorView(entity: selectedHistoricalEntity)
                            .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.laneWindowContentSize, geometry.size)
            .onAppear {
                windowContentSize = geometry.size
                sidebarWidth = min(max(sidebarWidth, 130), 320)
                updateAutomaticSidebar(
                    for: geometry.size.width,
                    animated: false
                )
            }
            .onChange(of: geometry.size) { _, size in
                windowContentSize = size
                updateAutomaticSidebar(for: size.width)
            }
        }
        .animation(
            reduceMotion
                ? nil
                : .timingCurve(0.23, 1, 0.32, 1, duration: 0.22),
            value: isSidebarCollapsed
        )
        .tint(LaneColor.accent)
    }

    private var presentedView: some View {
        layoutView
        .searchable(
            text: activeSearchText,
            placement: .toolbar,
            prompt: Text(activeSearchPrompt)
        )
        .toolbar {
            mainToolbar
        }
        .toolbarBackground(LaneColor.toolbar, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .preferredColorScheme(.light)
        .background {
            ZStack {
                WindowChromeConfigurator()
                WindowFrameAutosaveConfigurator(
                    autosaveName: WindowLayoutPersistence.mainWindowFrameAutosaveName
                )
            }
            .frame(width: 0, height: 0)
        }
        .overlay(alignment: .top) {
            if let notice = store.notice {
                NoticeBanner(notice: notice)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.84),
            value: store.notice?.id
        )
        .sheet(isPresented: $isShowingComposer) {
            AddDownloadView(
                initialInput: composerInitialInput,
                availableSize: windowContentSize
            )
                .id(composerRequestID)
        }
        .sheet(isPresented: importSheetBinding) {
            if let draft = store.pendingImport {
                ImportSelectionView(draft: draft)
                    .id(draft.id)
            }
        }
        .sheet(isPresented: $isEditingSelectedSmartFolder) {
            if case .smartFolder(let id) = sidebarSelection,
               let folder = organization.smartFolder(id: id) {
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
        .alert(
            L10n.string("无法保存整理数据"),
            isPresented: organizationErrorBinding
        ) {
            Button(L10n.string("好")) {
                organization.dismissPersistenceError()
            }
        } message: {
            Text(organization.persistenceError ?? L10n.string("请稍后重试。"))
        }
    }

    private var eventView: some View {
        presentedView
        .onReceive(NotificationCenter.default.publisher(for: .ariaLaneAddDownload)) { note in
            openComposer(initialInput: note.object as? String ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .ariaLaneImportDownload)) { _ in
            chooseImportFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ariaLaneSelectTransfer)) {
            guard let gid = $0.object as? String else { return }
            selectedSidebarRaw = SidebarSelection.filter(.all).storageValue
            selectedGID = gid
            viewState.selectedGIDs = [gid]
            viewState.selectedEntityIDs.removeAll()
            store.selectedTransferGID = gid
        }
        .onOpenURL { url in
            if DownloadImportKind(url: url) != nil {
                Task { await store.importDownloadFile(at: url) }
            } else if let request = IncomingDownloadRequest.parse(url) {
                openComposer(initialInput: request.urls.joined(separator: "\n"))
            }
        }
    }

    private var lifecycleView: some View {
        eventView
        .onAppear {
            if sidebarSelection.fixedFilter != nil, let selectedGID {
                viewState.selectedGIDs = [selectedGID]
                store.selectedTransferGID = selectedGID
            } else {
                selectedGID = nil
                store.selectedTransferGID = nil
            }
        }
        .onChange(of: viewState.selectedGIDs) { _, gids in
            guard sidebarSelection.fixedFilter != nil else { return }
            let gid = gids.count == 1 ? gids.first : nil
            selectedGID = gid
            store.selectedTransferGID = gid
        }
        .onChange(of: viewState.selectedEntityIDs) { _, ids in
            guard sidebarSelection.fixedFilter == nil else { return }
            let item = liveTransfer(forSelectedEntityIDs: ids)
            selectedGID = item?.gid
            store.selectedTransferGID = item?.gid
        }
        .onChange(of: store.transfers.map(\.gid)) { _, availableGIDs in
            viewState.selectedGIDs.formIntersection(Set(availableGIDs))
        }
        .onChange(of: organization.entities.map(\.id)) { _, availableIDs in
            viewState.selectedEntityIDs.formIntersection(Set(availableIDs))
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            SidebarToggleButton(isCompact: isSidebarCollapsed) {
                hasManualSidebarSelection = true
                isSidebarCollapsed.toggle()
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await store.refresh() }
            } label: {
                Label(L10n.string("刷新"), systemImage: "arrow.clockwise")
            }
            .help(L10n.string("刷新任务（⌘R）"))
            .disabled(!store.connectionState.isConnected)

            quickDownloadLimitMenu
            moreActionsMenu

            Button {
                openComposer()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 26, height: 26)
                    .contentShape(
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    )
            }
            .buttonStyle(AddDownloadToolbarButtonStyle())
            .accessibilityLabel(L10n.string("添加下载"))
            .help(L10n.string("添加下载（⌘N）"))
        }
    }

    private var quickDownloadLimitMenu: some View {
        Menu {
            ForEach([0, 1_024, 5_120, 10_240, 20_480, 51_200], id: \.self) { limit in
                Button {
                    Task { await store.setQuickDownloadLimit(limit) }
                } label: {
                    if preferences.maxOverallDownloadLimitKiB == limit {
                        Label(limitTitle(limit), systemImage: "checkmark")
                    } else {
                        Text(limitTitle(limit))
                    }
                }
            }

            Divider()

            Button {
                SettingsPane.speed.select()
                openSettings()
            } label: {
                Label(L10n.string("更多速度设置…"), systemImage: "gearshape")
            }
        } label: {
            Label(
                L10n.string("下载限速：\(limitTitle(preferences.maxOverallDownloadLimitKiB))"),
                systemImage: "gauge.with.dots.needle.50percent"
            )
        }
        .help(L10n.string("快速设置全局下载速度"))
        .disabled(store.settingsApplyState == .applying)
    }

    private var moreActionsMenu: some View {
        Menu {
            Button(L10n.string("导入 Torrent / Metalink…")) {
                chooseImportFile()
            }

            Divider()

            Button(L10n.string("暂停全部")) {
                Task { await store.pauseAll() }
            }
            Button(L10n.string("强制暂停全部")) {
                Task { await store.forcePauseAll() }
            }
            Button(L10n.string("继续全部")) {
                Task { await store.resumeAll() }
            }
            Button(L10n.string("重试全部失败任务")) {
                let failed = store.transfers.filter(\.isRetryable)
                Task { await store.retry(failed) }
            }
            .disabled(!store.transfers.contains(where: \.isRetryable))

            Divider()

            Button(L10n.string("清理已完成记录")) {
                Task { await store.clearCompleted() }
            }
        } label: {
            Label(L10n.string("更多操作"), systemImage: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private var organizedTasks: some View {
        OrganizedTasksView(
            selection: sidebarSelection,
            selectedEntityIDs: $viewState.selectedEntityIDs,
            searchText: $organizedTaskSearchText,
            onEditSelection: {
                if case .smartFolder = sidebarSelection {
                    isEditingSelectedSmartFolder = true
                }
            }
        )
    }

    private var sidebarSelection: SidebarSelection {
        SidebarSelection(storageValue: selectedSidebarRaw)
    }

    private var selectedFilter: TransferFilter {
        sidebarSelection.fixedFilter ?? .all
    }

    private var activeSearchText: Binding<String> {
        if case .tag = sidebarSelection {
            return $organizedTaskSearchText
        }
        if case .smartFolder = sidebarSelection {
            return $organizedTaskSearchText
        }

        switch selectedFilter {
        case .history:
            return $historySearchText
        case .pending:
            return $pendingDownloadSearchText
        case .scheduled:
            return $scheduleSearchText
        case .rss:
            return $rssSearchText
        case .library:
            return $librarySearchText
        default:
            return $transferSearchText
        }
    }

    private var activeSearchPrompt: String {
        if case .tag = sidebarSelection {
            return L10n.string("搜索名称、来源、类型或标签")
        }
        if case .smartFolder = sidebarSelection {
            return L10n.string("搜索名称、来源、类型或标签")
        }

        switch selectedFilter {
        case .history:
            return L10n.string("搜索下载历史")
        case .pending:
            return L10n.string("搜索待发送任务")
        case .scheduled:
            return L10n.string("搜索计划任务")
        case .rss:
            return L10n.string("搜索 RSS 订阅")
        case .library:
            return L10n.string("搜索书名、作者或主题")
        default:
            return L10n.string("搜索名称、地址或路径")
        }
    }

    private var sidebarSelectionBinding: Binding<SidebarSelection> {
        Binding(
            get: { sidebarSelection },
            set: { selection in
                viewState.selectedGIDs.removeAll()
                viewState.selectedEntityIDs.removeAll()
                selectedGID = nil
                store.selectedTransferGID = nil
                selectedSidebarRaw = selection.storageValue
            }
        )
    }

    private var selectedItem: TransferItem? {
        if let entity = selectedEntity {
            return organization.liveTransfer(
                for: entity,
                in: store.transfers,
                profileID: preferences.activeServerProfileID
            )
        }

        guard selectedFilter != .history,
              selectedFilter != .pending,
              selectedFilter != .scheduled,
              selectedFilter != .rss,
              selectedFilter != .library,
              viewState.selectedGIDs.count == 1,
              let gid = viewState.selectedGIDs.first else {
            return nil
        }
        return store.transfers.first { $0.gid == gid }
    }

    private var selectedEntity: TaskEntityRecord? {
        guard sidebarSelection.fixedFilter == nil,
              viewState.selectedEntityIDs.count == 1,
              let id = viewState.selectedEntityIDs.first else {
            return nil
        }
        return organization.entity(id: id)
    }

    private var selectedHistoricalEntity: TaskEntityRecord? {
        guard selectedItem == nil else { return nil }
        return selectedEntity
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { selectedItem != nil || selectedHistoricalEntity != nil },
            set: { isPresented in
                if !isPresented {
                    viewState.selectedGIDs.removeAll()
                    viewState.selectedEntityIDs.removeAll()
                }
            }
        )
    }

    private var importSheetBinding: Binding<Bool> {
        Binding(
            get: { store.pendingImport != nil },
            set: { isPresented in
                guard !isPresented, let id = store.pendingImport?.id else { return }
                Task { await store.cancelPendingImport(id: id) }
            }
        )
    }

    private var organizationErrorBinding: Binding<Bool> {
        Binding(
            get: { organization.persistenceError != nil },
            set: {
                if !$0 {
                    organization.dismissPersistenceError()
                }
            }
        )
    }

    private func liveTransfer(forSelectedEntityIDs ids: Set<UUID>) -> TransferItem? {
        guard ids.count == 1,
              let id = ids.first,
              let entity = organization.entity(id: id) else {
            return nil
        }

        return organization.liveTransfer(
            for: entity,
            in: store.transfers,
            profileID: preferences.activeServerProfileID
        )
    }

    private func limitTitle(_ kibibytesPerSecond: Int) -> String {
        TransferFormatter.speedLimit(kibibytesPerSecond)
    }

    private func chooseImportFile() {
        DownloadImportPicker.choose { url in
            Task { await store.importDownloadFile(at: url) }
        }
    }

    private func openComposer(initialInput: String = "") {
        composerInitialInput = initialInput
        composerRequestID = UUID()
        isShowingComposer = true
    }

    private func updateAutomaticSidebar(
        for windowWidth: CGFloat,
        animated: Bool = true
    ) {
        guard !hasManualSidebarSelection else { return }
        let shouldCollapse = windowWidth < 680
        if animated {
            isSidebarCollapsed = shouldCollapse
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isSidebarCollapsed = shouldCollapse
            }
        }
    }
}

@MainActor
private final class ContentViewState: ObservableObject {
    @Published var selectedGIDs: Set<String> = []
    @Published var selectedEntityIDs: Set<UUID> = []
}

private struct SidebarResizeHandle: View {
    @Binding var width: Double
    let isCollapsed: Bool
    let collapsedWidth: Double
    let minimumWidth: Double
    let maximumWidth: Double
    let collapseThreshold: Double
    let restoreDragThreshold: Double
    let onBeginResize: () -> Void
    let onCollapse: () -> Void
    let onRestore: () -> Void

    @State private var dragStartWidth: Double?
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.clear

            Rectangle()
                .fill(
                    isHovering || dragStartWidth != nil
                        ? LaneColor.accent.opacity(0.32)
                        : LaneColor.line
                )
                .frame(width: 0.5)
        }
        .frame(width: 7)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    let baseline: Double
                    if let dragStartWidth {
                        baseline = dragStartWidth
                    } else {
                        baseline = width
                        dragStartWidth = baseline
                        onBeginResize()
                    }

                    guard !isCollapsed else { return }

                    let proposedWidth = baseline + Double(value.translation.width)
                    width = min(max(proposedWidth, collapsedWidth), maximumWidth)
                }
                .onEnded { value in
                    defer { dragStartWidth = nil }

                    if isCollapsed {
                        if Double(value.translation.width) >= restoreDragThreshold {
                            onRestore()
                        }
                        return
                    }

                    let baseline = dragStartWidth ?? width
                    let proposedWidth = baseline + Double(value.translation.width)
                    if proposedWidth < collapseThreshold {
                        width = min(max(baseline, minimumWidth), maximumWidth).rounded()
                        onCollapse()
                    } else {
                        width = min(max(proposedWidth, minimumWidth), maximumWidth).rounded()
                    }
                }
        )
        .help(isCollapsed ? L10n.string("向右拖动展开侧栏") : L10n.string("拖动调整侧栏宽度"))
        .accessibilityLabel(L10n.string("侧栏宽度"))
        .accessibilityValue(L10n.string("\(Int(isCollapsed ? collapsedWidth : width)) 点"))
        .accessibilityAdjustableAction { direction in
            onBeginResize()
            if isCollapsed {
                if direction == .increment {
                    onRestore()
                }
                return
            }

            switch direction {
            case .increment:
                width = min(width + 12, maximumWidth)
            case .decrement:
                width = max(width - 12, minimumWidth)
            @unknown default:
                break
            }
        }
    }
}

private struct SidebarToggleButton: View {
    let isCompact: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            SidebarReferenceGlyph()
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(
            SidebarToolbarButtonStyle(isHovering: isHovering)
        )
        .onHover { isHovering = $0 }
        .help(isCompact ? L10n.string("展开侧栏") : L10n.string("收起为图标"))
        .accessibilityLabel(isCompact ? L10n.string("展开侧栏") : L10n.string("收起为图标"))
    }
}

private struct SidebarReferenceGlyph: View {
    var body: some View {
        Canvas { context, size in
            let lineWidth = 1.2
            let inset = lineWidth / 2
            let bounds = CGRect(
                x: inset,
                y: inset,
                width: size.width - lineWidth,
                height: size.height - lineWidth
            )
            let stroke = StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            )

            let outline = Path(
                roundedRect: bounds,
                cornerRadius: 2.8
            )
            context.stroke(
                outline,
                with: .foreground,
                style: stroke
            )

            var divider = Path()
            divider.move(
                to: CGPoint(x: 4.8, y: bounds.minY)
            )
            divider.addLine(
                to: CGPoint(x: 4.8, y: bounds.maxY)
            )
            context.stroke(
                divider,
                with: .foreground,
                style: stroke
            )
        }
        .frame(width: 14, height: 13)
    }
}

private struct SidebarToolbarButtonStyle: ButtonStyle {
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                configuration.isPressed || isHovering
                    ? LaneColor.label1
                    : LaneColor.label2
            )
            .background(
                isHovering ? LaneColor.fill1 : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}

private struct AddDownloadToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(LaneColor.primaryActionFill)
                    .opacity(configuration.isPressed ? 0.82 : 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.24),
                                        Color.white.opacity(0.03),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.6
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(
                            configuration.isPressed ? 0.10 : 0.22
                        ),
                        radius: configuration.isPressed ? 0.5 : 1.5,
                        x: 0,
                        y: configuration.isPressed ? 0 : 1
                    )
            }
            .offset(y: configuration.isPressed ? 0.5 : 0)
    }
}
