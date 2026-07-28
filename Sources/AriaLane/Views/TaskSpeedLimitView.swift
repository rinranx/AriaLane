import SwiftUI

@MainActor
final class TaskSpeedLimitEditorModel: ObservableObject {
    @Published var downloadKiBPerSecond = 0
    @Published var uploadKiBPerSecond = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?

    private var loadedGID: String?

    func load(item: TransferItem, store: DownloadStore) async {
        guard loadedGID != item.gid else { return }
        loadedGID = item.gid
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let limits = await store.taskSpeedLimits(for: item) else {
            loadedGID = nil
            errorMessage = L10n.string("无法读取任务限速")
            return
        }
        downloadKiBPerSecond = limits.downloadKiBPerSecond
        uploadKiBPerSecond = limits.uploadKiBPerSecond
    }

    func apply(item: TransferItem, store: DownloadStore) async {
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }

        let limits = TaskSpeedLimits(
            downloadKiBPerSecond: downloadKiBPerSecond,
            uploadKiBPerSecond: uploadKiBPerSecond
        )
        if !(await store.setTaskSpeedLimits(limits, for: item)) {
            errorMessage = L10n.string("任务限速未能应用")
        }
    }
}

struct TaskSpeedLimitView: View {
    @EnvironmentObject private var store: DownloadStore
    @StateObject private var model = TaskSpeedLimitEditorModel()

    let item: TransferItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.string("任务限速"), systemImage: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if model.isLoading || model.isApplying {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            compactLimitField(
                title: L10n.string("下载"),
                value: downloadBinding,
                kibibytesPerSecond: model.downloadKiBPerSecond
            )
            compactLimitField(
                title: L10n.string("上传"),
                value: uploadBinding,
                kibibytesPerSecond: model.uploadKiBPerSecond
            )

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(LaneColor.danger)
            }

            HStack {
                Text(L10n.string("0 表示不限速"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.string("应用")) {
                    Task { await model.apply(item: item, store: store) }
                }
                .buttonStyle(.bordered)
                .disabled(model.isLoading || model.isApplying)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
        .task(id: item.gid) {
            await model.load(item: item, store: store)
        }
    }

    private var downloadBinding: Binding<Double> {
        Binding(
            get: { Double(model.downloadKiBPerSecond) / 1_024 },
            set: { model.downloadKiBPerSecond = max(Int(($0 * 1_024).rounded()), 0) }
        )
    }

    private var uploadBinding: Binding<Double> {
        Binding(
            get: { Double(model.uploadKiBPerSecond) / 1_024 },
            set: { model.uploadKiBPerSecond = max(Int(($0 * 1_024).rounded()), 0) }
        )
    }

    private func compactLimitField(
        title: String,
        value: Binding<Double>,
        kibibytesPerSecond: Int
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            TextField(
                "0",
                value: value,
                format: .number.precision(.fractionLength(0...2))
            )
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 64)
            Text("MB/s")
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)

            if kibibytesPerSecond > 0 {
                Text(TransferFormatter.speedLimit(kibibytesPerSecond))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 54, alignment: .trailing)
            }
        }
        .font(.system(size: 11))
    }
}
