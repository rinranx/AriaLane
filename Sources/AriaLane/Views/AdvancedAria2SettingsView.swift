import SwiftUI

struct AdvancedAria2SettingsPane: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Form {
            Section(L10n.string("代理")) {
                settingsField(
                    L10n.string("全部协议代理"),
                    placeholder: "http://127.0.0.1:7890",
                    text: $preferences.advancedConfiguration.allProxy
                )
                settingsField(
                    L10n.string("HTTP 代理"),
                    placeholder: "http://proxy:port",
                    text: $preferences.advancedConfiguration.httpProxy
                )
                settingsField(
                    L10n.string("HTTPS 代理"),
                    placeholder: "http://proxy:port",
                    text: $preferences.advancedConfiguration.httpsProxy
                )
                settingsField(
                    L10n.string("FTP 代理"),
                    placeholder: "http://proxy:port",
                    text: $preferences.advancedConfiguration.ftpProxy
                )
                settingsField(
                    L10n.string("不使用代理"),
                    placeholder: "localhost,127.0.0.1",
                    text: $preferences.advancedConfiguration.noProxy
                )
                settingsField(
                    L10n.string("代理用户名"),
                    placeholder: L10n.string("可选"),
                    text: $preferences.advancedConfiguration.proxyUser
                )

                LabeledContent(L10n.string("代理密码")) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 24)
                        AdvancedSettingsSecureInput(
                            text: $preferences.proxyPassword,
                            placeholder: L10n.string("可选"),
                            accessibilityLabel: L10n.string("代理密码")
                        )
                    }
                    .frame(maxWidth: .infinity)
                }

                Text(L10n.string("代理密码单独保存在 macOS 钥匙串中。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("TLS 与 Cookie")) {
                overridePicker(
                    L10n.string("校验证书"),
                    selection: $preferences.advancedConfiguration.checkCertificate
                )
                if preferences.advancedConfiguration.checkCertificate == .disabled {
                    Label(
                        L10n.string("HTTPS 证书校验已关闭；连接可能被冒充或篡改。"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(LaneColor.amber)
                }
                settingsField(
                    L10n.string("CA 证书"),
                    placeholder: "/path/to/ca.pem",
                    text: $preferences.advancedConfiguration.caCertificate
                )
                settingsField(
                    L10n.string("客户端证书"),
                    placeholder: "/path/to/client.pem",
                    text: $preferences.advancedConfiguration.clientCertificate
                )
                settingsField(
                    L10n.string("客户端私钥"),
                    placeholder: "/path/to/client.key",
                    text: $preferences.advancedConfiguration.privateKey
                )
                settingsField(
                    L10n.string("载入 Cookie"),
                    placeholder: "/path/to/cookies.txt",
                    text: $preferences.advancedConfiguration.loadCookies
                )
                settingsField(
                    L10n.string("保存 Cookie"),
                    placeholder: "/path/to/cookies.txt",
                    text: $preferences.advancedConfiguration.saveCookies
                )
            }

            Section(L10n.string("FTP、SFTP 与 HTTP")) {
                overridePicker(
                    L10n.string("FTP 被动模式"),
                    selection: $preferences.advancedConfiguration.ftpPassive
                )
                overridePicker(
                    L10n.string("复用 FTP 连接"),
                    selection: $preferences.advancedConfiguration.ftpReuseConnection
                )
                Picker(
                    L10n.string("FTP 传输类型"),
                    selection: $preferences.advancedConfiguration.ftpType
                ) {
                    ForEach(Aria2FTPType.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                settingsField(
                    L10n.string("SSH 主机密钥摘要"),
                    placeholder: "sha-256=…",
                    text: $preferences.advancedConfiguration.sshHostKeyDigest
                )
                overridePicker(
                    L10n.string("文件完整性检查"),
                    selection: $preferences.advancedConfiguration.checkIntegrity
                )
                overridePicker(
                    L10n.string("仅试运行"),
                    selection: $preferences.advancedConfiguration.dryRun
                )
                overridePicker(
                    L10n.string("Content-Disposition 使用 UTF-8"),
                    selection: $preferences.advancedConfiguration.contentDisposition
                )
                overridePicker(
                    L10n.string("条件请求"),
                    selection: $preferences.advancedConfiguration.conditionalGet
                )
                overridePicker(
                    L10n.string("接受 gzip 响应"),
                    selection: $preferences.advancedConfiguration.httpAcceptGzip
                )
            }

            Section("BitTorrent") {
                settingsField(
                    L10n.string("额外 Tracker"),
                    placeholder: L10n.string("使用逗号分隔"),
                    text: $preferences.advancedConfiguration.btTrackers
                )
                settingsField(
                    L10n.string("排除 Tracker"),
                    placeholder: L10n.string("使用逗号分隔"),
                    text: $preferences.advancedConfiguration.btExcludedTrackers
                )
                overridePicker(
                    L10n.string("要求加密"),
                    selection: $preferences.advancedConfiguration.btRequireCrypto
                )
                overridePicker(
                    L10n.string("强制加密"),
                    selection: $preferences.advancedConfiguration.btForceEncryption
                )
                Picker(
                    L10n.string("最低加密级别"),
                    selection: $preferences.advancedConfiguration.btMinimumCryptoLevel
                ) {
                    ForEach(Aria2BTCryptoLevel.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                overridePicker(
                    L10n.string("仅获取元数据"),
                    selection: $preferences.advancedConfiguration.btMetadataOnly
                )
                overridePicker(
                    L10n.string("保存元数据"),
                    selection: $preferences.advancedConfiguration.btSaveMetadata
                )
                overridePicker(
                    L10n.string("启用 IPv6 DHT"),
                    selection: $preferences.advancedConfiguration.enableDHT6
                )
            }

            Section("Metalink") {
                settingsField(
                    L10n.string("地区偏好"),
                    placeholder:
                        preferences.appLanguage.resolved.metalinkRegionPreference,
                    text: $preferences.advancedConfiguration.metalinkLocation
                )
                settingsField(
                    L10n.string("语言偏好"),
                    placeholder:
                        preferences.appLanguage.resolved.metalinkLanguagePreference,
                    text: $preferences.advancedConfiguration.metalinkLanguage
                )
                settingsField(
                    L10n.string("操作系统"),
                    placeholder: "macos",
                    text: $preferences.advancedConfiguration.metalinkOS
                )
                settingsField(
                    L10n.string("版本"),
                    placeholder: "1.0",
                    text: $preferences.advancedConfiguration.metalinkVersion
                )
                Picker(
                    L10n.string("首选协议"),
                    selection: $preferences.advancedConfiguration.metalinkPreferredProtocol
                ) {
                    ForEach(Aria2MetalinkProtocol.allCases) {
                        Text($0.title).tag($0)
                    }
                }
            }

            Section(L10n.string("其他 aria2 参数")) {
                AdvancedSettingsMultilineInput(
                    text: $preferences.advancedConfiguration.customOptionsText,
                    accessibilityLabel: L10n.string("其他 aria2 参数")
                )

                Text(L10n.string("每行一个 key=value，可用 # 添加注释。自定义值会覆盖上方同名设置。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let message = preferences.advancedConfiguration.validationMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(LaneColor.danger)
                }
            }

            SettingsActionFooter()
        }
        .formStyle(.grouped)
    }

    private func settingsField(
        _ title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 0) {
                Spacer(minLength: 24)
                AdvancedSettingsTextInput(
                    text: text,
                    placeholder: placeholder,
                    accessibilityLabel: title
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func overridePicker(
        _ title: String,
        selection: Binding<Aria2BooleanOverride>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(Aria2BooleanOverride.allCases) {
                Text($0.title).tag($0)
            }
        }
    }
}

private struct AdvancedSettingsTextInput: View {
    @Binding var text: String
    let placeholder: String
    let accessibilityLabel: String

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder)
        )
        .labelsHidden()
        .textFieldStyle(.plain)
        .font(LaneFont.utility(10.5, weight: .regular))
        .multilineTextAlignment(.trailing)
        .focused($isFocused)
        .accessibilityLabel(accessibilityLabel)
        .padding(.horizontal, 11)
        .frame(width: 330, height: 34)
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
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct AdvancedSettingsSecureInput: View {
    @Binding var text: String
    let placeholder: String
    let accessibilityLabel: String

    @FocusState private var isFocused: Bool

    var body: some View {
        SecureField(
            "",
            text: $text,
            prompt: Text(placeholder)
        )
        .labelsHidden()
        .textFieldStyle(.plain)
        .font(LaneFont.utility(10.5, weight: .regular))
        .multilineTextAlignment(.trailing)
        .focused($isFocused)
        .accessibilityLabel(accessibilityLabel)
        .padding(.horizontal, 11)
        .frame(width: 330, height: 34)
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
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct AdvancedSettingsMultilineInput: View {
    @Binding var text: String
    let accessibilityLabel: String

    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .font(LaneFont.utility(10.5, weight: .regular))
            .focused($isFocused)
            .accessibilityLabel(accessibilityLabel)
            .padding(9)
            .frame(minHeight: 118)
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
            .transaction { transaction in
                transaction.animation = nil
            }
    }
}
