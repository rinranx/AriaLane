import SwiftUI

struct TransferAdvancedDetailsView: View {
    @EnvironmentObject private var store: DownloadStore
    @ObservedObject var model: TransferAdvancedDetailsModel
    let item: TransferItem

    private var currentItem: TransferItem {
        model.details?.item ?? item
    }

    private var peers: [Aria2Peer] {
        model.details?.peers ?? []
    }

    private var servers: [Aria2ServerEndpoint] {
        model.details?.servers ?? []
    }

    private var files: [TransferFile] {
        model.details?.files ?? currentItem.files ?? []
    }

    private var selectedMirrorFile: TransferFile? {
        files.first { $0.indexValue == model.selectedMirrorFileIndex }
    }

    private var selectedFileURIs: [TransferURI] {
        if let uris = selectedMirrorFile?.uris, !uris.isEmpty {
            return uris
        }
        if model.selectedMirrorFileIndex == files.first?.indexValue {
            return model.details?.uris ?? []
        }
        return []
    }

    var body: some View {
        DisclosureGroup(isExpanded: $model.isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                connectionSummary

                if !files.isEmpty {
                    fileSelectionSection
                    mirrorSection
                }

                if currentItem.pieceCount > 0 {
                    pieceSection
                }

                if currentItem.isBitTorrent {
                    peerSection
                }

                if !servers.isEmpty {
                    serverSection
                }

                if let infoHash = currentItem.infoHash, !infoHash.isEmpty {
                    InfoPair(label: "Info Hash", value: infoHash, isMonospaced: true)
                }

                taskOptionsSection
            }
            .padding(.top, 12)
        } label: {
            HStack {
                Label(L10n.string("文件、来源与高级参数"), systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if model.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Button {
                        Task { await model.load(item: item, store: store) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.string("刷新高级详情"))
                }
            }
        }
        .task(id: item.gid) {
            await model.load(item: item, store: store)
        }
    }

    private var fileSelectionSection: some View {
        DisclosureGroup(isExpanded: $model.isFileSelectionExpanded) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(files, id: \.indexValue) { file in
                    Toggle(isOn: selectionBinding(for: file.indexValue)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(URL(fileURLWithPath: file.path).lastPathComponent)
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            HStack(spacing: 6) {
                                Text("#\(file.indexValue)")
                                Text(TransferFormatter.bytes(file.byteCount))
                                Text(TransferFormatter.percent(file.progress))
                            }
                            .font(LaneFont.utility(8.5, weight: .regular))
                            .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .help(file.path)
                }

                HStack {
                    Text(
                        L10n.string("已选择 \(model.selectedFileIndices.count) / \(files.count) 个文件")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button(L10n.string("应用文件选择")) {
                        Task {
                            await model.applyFileSelection(
                                item: currentItem,
                                store: store
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(
                        model.selectedFileIndices.isEmpty
                            || model.isApplying
                            || currentItem.status == .complete
                            || currentItem.status == .error
                    )
                }
            }
            .padding(.top, 9)
        } label: {
            HStack {
                Label(
                    files.count > 1 ? L10n.string("文件选择") : L10n.string("文件信息"),
                    systemImage: "checklist"
                )
                .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(model.selectedFileIndices.count) / \(files.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mirrorSection: some View {
        DisclosureGroup(isExpanded: $model.isMirrorEditorExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if files.count > 1 {
                    Picker(L10n.string("目标文件"), selection: $model.selectedMirrorFileIndex) {
                        ForEach(files, id: \.indexValue) { file in
                            Text(
                                "#\(file.indexValue) "
                                    + URL(fileURLWithPath: file.path).lastPathComponent
                            )
                            .tag(file.indexValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack(spacing: 7) {
                    TextField(
                        "https://mirror.example.com/file",
                        text: $model.mirrorURI
                    )
                    .font(LaneFont.utility(9.5, weight: .regular))
                    .textFieldStyle(.roundedBorder)

                    Button(L10n.string("添加")) {
                        Task {
                            await model.addMirror(
                                item: currentItem,
                                store: store
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(
                        model.mirrorURI.trimmed.isEmpty
                            || model.isApplying
                            || currentItem.status == .complete
                    )
                }

                if selectedFileURIs.isEmpty {
                    Text(L10n.string("aria2 暂未报告该文件的来源"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        Array(selectedFileURIs.enumerated()),
                        id: \.offset
                    ) { _, source in
                        HStack(spacing: 7) {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                                .foregroundStyle(LaneColor.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.uri)
                                    .font(LaneFont.utility(8.5, weight: .regular))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let status = source.status, !status.isEmpty {
                                    Text(status)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button {
                                Task {
                                    await model.removeMirror(
                                        source.uri,
                                        item: currentItem,
                                        store: store
                                    )
                                }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(L10n.string("移除这个来源"))
                            .disabled(
                                selectedFileURIs.count <= 1
                                    || model.isApplying
                                    || currentItem.status == .complete
                            )
                        }
                        .help(source.uri)
                    }
                }
            }
            .padding(.top, 9)
        } label: {
            HStack {
                Label(L10n.string("镜像来源"), systemImage: "link.badge.plus")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(L10n.string("\(selectedFileURIs.count) 个"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var taskOptionsSection: some View {
        DisclosureGroup(isExpanded: $model.isTaskOptionsExpanded) {
            VStack(alignment: .leading, spacing: 9) {
                TextEditor(text: $model.rawOptionText)
                    .font(LaneFont.utility(9.5, weight: .regular))
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(height: 88)
                    .background(
                        LaneColor.fill1,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .overlay(alignment: .topLeading) {
                        if model.rawOptionText.isEmpty {
                            Text("max-tries=10\nretry-wait=5")
                                .font(LaneFont.utility(9.5, weight: .regular))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    }

                HStack {
                    Text(L10n.string("每行一个 key=value"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.string("应用参数")) {
                        Task {
                            await model.applyTaskOptions(
                                item: currentItem,
                                store: store
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(
                        model.rawOptionText.trimmed.isEmpty
                            || model.isApplying
                            || currentItem.status == .complete
                    )
                }

                if let options = model.details?.options, !options.isEmpty {
                    Text(L10n.string("aria2 当前报告 \(options.count) 个任务参数"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 9)
        } label: {
            Label(L10n.string("运行中参数"), systemImage: "terminal")
                .font(.system(size: 11, weight: .semibold))
        }
    }

    private func selectionBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { model.selectedFileIndices.contains(index) },
            set: { isSelected in
                if isSelected {
                    model.selectedFileIndices.insert(index)
                } else {
                    model.selectedFileIndices.remove(index)
                }
            }
        )
    }

    private var connectionSummary: some View {
        HStack(spacing: 8) {
            detailMetric(
                title: L10n.string("连接"),
                value: String(currentItem.connectionCount),
                color: LaneColor.accent
            )
            detailMetric(
                title: L10n.string("BT 节点"),
                value: currentItem.isBitTorrent ? String(peers.count) : "—",
                color: LaneColor.mint
            )
            detailMetric(
                title: L10n.string("服务器"),
                value: servers.isEmpty ? "—" : String(servers.count),
                color: LaneColor.amber
            )
        }
    }

    private var pieceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.string("文件分块"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(pieceSummary)
                    .font(LaneFont.utility(9, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            let buckets = currentItem.pieceProgressBuckets(maximumCount: 72)
            if buckets.isEmpty {
                Text(L10n.string("aria2 暂未提供分块位图"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(minimum: 5), spacing: 3),
                        count: 12
                    ),
                    spacing: 3
                ) {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { _, fraction in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(pieceColor(fraction))
                            .frame(height: 7)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.string("文件分块完成情况"))
                .accessibilityValue(TransferFormatter.percent(currentItem.progress))
            }
        }
        .padding(11)
        .background(
            LaneColor.surface.opacity(0.6),
            in: RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: LaneMetric.compactRadius, style: .continuous)
                .stroke(LaneColor.line, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var peerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.string("BT 节点"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if currentItem.seederCount > 0 {
                    Text(L10n.string("\(currentItem.seederCount) 个做种者"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if peers.isEmpty {
                Text(model.isLoading ? L10n.string("正在读取节点…") : L10n.string("当前没有已连接的节点"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(peers.prefix(6)) { peer in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(peer.isSeeder ? LaneColor.mint : LaneColor.accent)
                            .frame(width: 6, height: 6)
                        Text(peer.address)
                            .font(LaneFont.utility(9, weight: .regular))
                            .lineLimit(1)
                        Spacer()
                        Text("↓ \(TransferFormatter.speed(peer.downloadSpeedValue))")
                            .font(LaneFont.utility(8, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                if peers.count > 6 {
                    Text(L10n.string("另有 \(peers.count - 6) 个节点"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("服务器连接"))
                .font(.system(size: 11, weight: .semibold))

            ForEach(servers.prefix(6)) { server in
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 9))
                        .foregroundStyle(LaneColor.amber)
                    Text(server.displayHost)
                        .font(LaneFont.utility(9, weight: .regular))
                        .lineLimit(1)
                    Spacer()
                    Text(TransferFormatter.speed(server.downloadSpeedValue))
                        .font(LaneFont.utility(8, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .help(server.currentUri ?? server.uri)
            }
        }
    }

    private var pieceSummary: String {
        var parts = [L10n.string("\(currentItem.pieceCount) 块")]
        if currentItem.pieceLengthValue > 0 {
            parts.append(L10n.string("每块 \(TransferFormatter.bytes(currentItem.pieceLengthValue))"))
        }
        if currentItem.verifiedByteCount > 0 {
            parts.append(L10n.string("已验证 \(TransferFormatter.bytes(currentItem.verifiedByteCount))"))
        }
        return parts.joined(separator: " · ")
    }

    private func pieceColor(_ fraction: Double) -> Color {
        if fraction <= 0 {
            return Color.primary.opacity(0.08)
        }
        return LaneColor.accent.opacity(0.28 + min(max(fraction, 0), 1) * 0.72)
    }

    private func detailMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(LaneFont.utility(11))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
final class TransferAdvancedDetailsModel: ObservableObject {
    @Published var isExpanded = true
    @Published var isFileSelectionExpanded = false
    @Published var isMirrorEditorExpanded = false
    @Published var isTaskOptionsExpanded = false
    @Published var selectedFileIndices = Set<Int>()
    @Published var selectedMirrorFileIndex = 1
    @Published var mirrorURI = ""
    @Published var rawOptionText = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published private(set) var details: TransferAdvancedDetails?

    func load(item: TransferItem, store: DownloadStore) async {
        guard !isLoading else { return }
        isLoading = true
        let nextDetails = await store.advancedDetails(for: item)
        guard !Task.isCancelled else {
            isLoading = false
            return
        }
        update(with: nextDetails)
        isLoading = false
    }

    func applyFileSelection(
        item: TransferItem,
        store: DownloadStore
    ) async {
        guard !isApplying else { return }
        isApplying = true
        let succeeded = await store.setSelectedFiles(selectedFileIndices, for: item)
        if succeeded {
            await reload(item: item, store: store)
        }
        isApplying = false
    }

    func addMirror(
        item: TransferItem,
        store: DownloadStore
    ) async {
        guard !isApplying else { return }
        isApplying = true
        let succeeded = await store.addMirror(
            mirrorURI,
            fileIndex: selectedMirrorFileIndex,
            to: item
        )
        if succeeded {
            mirrorURI = ""
            await reload(item: item, store: store)
        }
        isApplying = false
    }

    func removeMirror(
        _ uri: String,
        item: TransferItem,
        store: DownloadStore
    ) async {
        guard !isApplying else { return }
        isApplying = true
        let succeeded = await store.removeMirror(
            uri,
            fileIndex: selectedMirrorFileIndex,
            from: item
        )
        if succeeded {
            await reload(item: item, store: store)
        }
        isApplying = false
    }

    func applyTaskOptions(
        item: TransferItem,
        store: DownloadStore
    ) async {
        guard !isApplying else { return }
        isApplying = true
        let succeeded = await store.applyTaskOptionText(rawOptionText, to: item)
        if succeeded {
            rawOptionText = ""
            await reload(item: item, store: store)
        }
        isApplying = false
    }

    private func reload(
        item: TransferItem,
        store: DownloadStore
    ) async {
        let nextDetails = await store.advancedDetails(for: item)
        guard !Task.isCancelled else { return }
        update(with: nextDetails)
    }

    private func update(with nextDetails: TransferAdvancedDetails) {
        details = nextDetails
        let files = nextDetails.files
        selectedFileIndices = Set(
            files.filter(\.isSelected).map(\.indexValue)
        )
        if !files.contains(where: {
            $0.indexValue == selectedMirrorFileIndex
        }) {
            selectedMirrorFileIndex = files.first?.indexValue ?? 1
        }
    }
}
