import SwiftUI

struct ServerEditorDraft {
    let name: String
    let endpoint: String
    let secret: String
}

struct ServerEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var store: DownloadStore

    var saveButtonTitle = L10n.string("添加并连接")
    let onSave: (ServerEditorDraft) -> Void

    @State private var name = ""
    @State private var host = ""
    @State private var port = "6800"
    @State private var secret = ""
    @State private var testState = ServerConnectionTestState.idle

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(L10n.string("服务器")) {
                    TextField(
                        L10n.string("名称"),
                        text: $name,
                        prompt: Text(L10n.string("例如：群晖 NAS"))
                    )

                    TextField(
                        "Host",
                        text: $host,
                        prompt: Text("192.168.1.8")
                    )
                    .font(LaneFont.utility(11, weight: .regular))

                    TextField("Port", text: $port)
                        .font(LaneFont.utility(11, weight: .regular))

                    SecureField(
                        "Secret",
                        text: $secret,
                        prompt: Text(L10n.string("可选"))
                    )
                }

                Section(L10n.string("连接测试")) {
                    HStack(spacing: 10) {
                        testStatus

                        Spacer()

                        Button(L10n.string("测试连接")) {
                            testConnection()
                        }
                        .disabled(endpoint == nil || testState == .testing)
                    }

                    Text(L10n.string("仅调用 aria2.getVersion；测试过程不会保存 Secret。"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 8) {
                Spacer()

                Button(L10n.string("取消"), role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(saveButtonTitle) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil)
            }
            .padding(16)
        }
        .frame(width: 430, height: 340)
        .navigationTitle(L10n.string("添加服务器"))
        .onChange(of: host) { _, _ in resetTestState() }
        .onChange(of: port) { _, _ in resetTestState() }
        .onChange(of: secret) { _, _ in resetTestState() }
        .keychainPersistenceAlert(preferences: preferences)
    }

    @ViewBuilder
    private var testStatus: some View {
        switch testState {
        case .idle:
            if let validationMessage {
                Label(validationMessage, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label(L10n.string("尚未测试"), systemImage: "bolt.horizontal.circle")
                    .foregroundStyle(.secondary)
            }
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string("正在连接…"))
            }
            .foregroundStyle(.secondary)
        case .succeeded(let version):
            Label(
                L10n.string("aria2 \(version) · 连接成功"),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(Color(nsColor: .systemGreen))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(LaneColor.danger)
                .lineLimit(2)
        }
    }

    private var endpoint: String? {
        let normalizedHost = host.trimmed
        guard !normalizedHost.isEmpty,
              let normalizedPort = Int(port.trimmed),
              (1...65_535).contains(normalizedPort) else {
            return nil
        }

        let candidate = normalizedHost.contains("://")
            ? normalizedHost
            : "http://\(normalizedHost)"
        guard var components = URLComponents(string: candidate),
              components.host != nil else {
            return nil
        }
        components.port = normalizedPort
        components.path = "/jsonrpc"
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    private var validationMessage: String? {
        if name.trimmed.isEmpty {
            return L10n.string("请输入服务器名称")
        }
        if host.trimmed.isEmpty {
            return L10n.string("请输入 Host")
        }
        guard let normalizedPort = Int(port.trimmed),
              (1...65_535).contains(normalizedPort) else {
            return L10n.string("Port 需为 1–65535")
        }
        if endpoint == nil {
            return L10n.string("Host 格式无效")
        }
        return nil
    }

    private func testConnection() {
        guard let endpoint else { return }
        testState = .testing
        Task {
            do {
                let version = try await store.testServerConnection(
                    endpoint: endpoint,
                    secret: secret
                )
                guard !Task.isCancelled else { return }
                testState = .succeeded(version: version)
            } catch {
                guard !Task.isCancelled else { return }
                testState = .failed(
                    message: error.localizedDescription
                )
            }
        }
    }

    private func save() {
        guard validationMessage == nil, let endpoint else { return }
        let previousIssueID = preferences.keychainPersistenceIssue?.id
        onSave(
            ServerEditorDraft(
                name: name.trimmed,
                endpoint: endpoint,
                secret: secret
            )
        )
        guard preferences.keychainPersistenceIssue?.id == previousIssueID else {
            return
        }
        dismiss()
    }

    private func resetTestState() {
        guard testState != .testing else { return }
        testState = .idle
    }
}

private enum ServerConnectionTestState: Equatable {
    case idle
    case testing
    case succeeded(version: String)
    case failed(message: String)
}
