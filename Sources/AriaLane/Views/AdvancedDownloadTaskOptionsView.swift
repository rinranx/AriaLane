import SwiftUI

struct DownloadSourcesOptionsView: View {
    @ObservedObject var form: AddDownloadFormState
    let primaryURLCount: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OptionSectionHeader(
                    title: L10n.string("镜像与备用来源"),
                    detail: L10n.string("aria2 会把这些地址作为同一文件的并行来源。"),
                    systemImage: "point.3.filled.connected.trianglepath.dotted"
                )

                OptionTextEditor(
                    title: L10n.string("备用 URI · 每行一个"),
                    placeholder: "https://mirror.example.com/file.zip\nsftp://host/path/file.zip",
                    text: $form.additionalURIsText
                )

                if primaryURLCount != 1,
                   !form.additionalURIsText.trimmed.isEmpty {
                    Label(
                        L10n.string("备用镜像只能与一个主链接一起提交。"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(LaneColor.amber)
                }

                Text(
                    L10n.string("支持 HTTP、HTTPS、FTP 与 SFTP。重复地址会自动去除；")
                        + L10n.string("已创建任务也可以在详情面板中增删镜像。")
                )
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DownloadProtocolOptionsView: View {
    @ObservedObject var form: AddDownloadFormState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OptionSectionHeader(
                    title: L10n.string("代理、TLS 与传输协议"),
                    detail: L10n.string("只为当前任务覆盖服务器的协议设置。"),
                    systemImage: "lock.shield"
                )

                optionGroup(L10n.string("代理")) {
                    twoColumns {
                        OptionInput(L10n.string("全部协议代理")) {
                            plainField(
                                "http://127.0.0.1:7890",
                                text: $form.advancedAria2Options.allProxy
                            )
                        }
                    } trailing: {
                        OptionInput(L10n.string("不使用代理")) {
                            plainField(
                                "localhost,127.0.0.1",
                                text: $form.advancedAria2Options.noProxy
                            )
                        }
                    }

                    twoColumns {
                        OptionInput(L10n.string("HTTP 代理")) {
                            plainField(
                                "http://proxy:port",
                                text: $form.advancedAria2Options.httpProxy
                            )
                        }
                    } trailing: {
                        OptionInput(L10n.string("HTTPS 代理")) {
                            plainField(
                                "http://proxy:port",
                                text: $form.advancedAria2Options.httpsProxy
                            )
                        }
                    }

                    twoColumns {
                        OptionInput(L10n.string("FTP 代理")) {
                            plainField(
                                "http://proxy:port",
                                text: $form.advancedAria2Options.ftpProxy
                            )
                        }
                    } trailing: {
                        OptionInput(L10n.string("代理用户名")) {
                            plainField(
                                L10n.string("可选"),
                                text: $form.advancedAria2Options.proxyUser
                            )
                        }
                    }

                    OptionInput(L10n.string("代理密码")) {
                        SecureField(
                            L10n.string("可选"),
                            text: $form.advancedAria2Options.proxyPassword
                        )
                        .textFieldStyle(.plain)
                    }
                }

                optionGroup(L10n.string("TLS 与 Cookie")) {
                    twoColumns {
                        enumInput(
                            L10n.string("校验证书"),
                            selection: $form.advancedAria2Options.checkCertificate
                        )
                    } trailing: {
                        OptionInput(L10n.string("CA 证书")) {
                            plainField(
                                "/path/to/ca.pem",
                                text: $form.advancedAria2Options.caCertificate
                            )
                        }
                    }

                    twoColumns {
                        OptionInput(L10n.string("客户端证书")) {
                            plainField(
                                "/path/to/client.pem",
                                text: $form.advancedAria2Options.clientCertificate
                            )
                        }
                    } trailing: {
                        OptionInput(L10n.string("客户端私钥")) {
                            plainField(
                                "/path/to/client.key",
                                text: $form.advancedAria2Options.privateKey
                            )
                        }
                    }

                    twoColumns {
                        OptionInput(L10n.string("载入 Cookie")) {
                            plainField(
                                "/path/to/cookies.txt",
                                text: $form.advancedAria2Options.loadCookies
                            )
                        }
                    } trailing: {
                        OptionInput(L10n.string("保存 Cookie")) {
                            plainField(
                                "/path/to/cookies.txt",
                                text: $form.advancedAria2Options.saveCookies
                            )
                        }
                    }
                }

                optionGroup(L10n.string("FTP、SFTP 与 HTTP 行为")) {
                    twoColumns {
                        enumInput(
                            L10n.string("FTP 被动模式"),
                            selection: $form.advancedAria2Options.ftpPassive
                        )
                    } trailing: {
                        enumInput(
                            L10n.string("复用 FTP 连接"),
                            selection: $form.advancedAria2Options.ftpReuseConnection
                        )
                    }

                    twoColumns {
                        enumInput(
                            L10n.string("FTP 传输类型"),
                            selection: $form.advancedAria2Options.ftpType
                        )
                    } trailing: {
                        OptionInput(L10n.string("SSH 主机密钥摘要")) {
                            plainField(
                                "sha-256=…",
                                text: $form.advancedAria2Options.sshHostKeyDigest
                            )
                        }
                    }

                    twoColumns {
                        enumInput(
                            L10n.string("文件完整性检查"),
                            selection: $form.advancedAria2Options.checkIntegrity
                        )
                    } trailing: {
                        enumInput(
                            L10n.string("仅试运行"),
                            selection: $form.advancedAria2Options.dryRun
                        )
                    }

                    twoColumns {
                        enumInput(
                            L10n.string("Content-Disposition 使用 UTF-8"),
                            selection: $form.advancedAria2Options.contentDisposition
                        )
                    } trailing: {
                        enumInput(
                            L10n.string("条件请求"),
                            selection: $form.advancedAria2Options.conditionalGet
                        )
                    }

                    enumInput(
                        L10n.string("接受 gzip 响应"),
                        selection: $form.advancedAria2Options.httpAcceptGzip
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
        }
    }

    private func plainField(
        _ placeholder: String,
        text: Binding<String>
    ) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(LaneFont.utility(10.5, weight: .regular))
    }

    private func enumInput<Value>(
        _ title: String,
        selection: Binding<Value>
    ) -> some View where Value: Identifiable & Equatable, Value: CaseIterable,
        Value.AllCases == [Value] {
        OptionInput(title) {
            OptionSelectionMenu(
                selection: selection,
                values: Value.allCases,
                accessibilityLabel: title
            ) { value in
                if let value = value as? Aria2BooleanOverride {
                    return value.title
                }
                if let value = value as? Aria2FTPType {
                    return value.title
                }
                return String(describing: value)
            }
        }
    }

    @ViewBuilder
    private func optionGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LaneColor.label2)
            content()
        }
    }

    private func twoColumns<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            leading()
            trailing()
        }
    }
}

struct DownloadBitTorrentOptionsView: View {
    @ObservedObject var form: AddDownloadFormState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OptionSectionHeader(
                    title: L10n.string("BitTorrent 与 Metalink"),
                    detail: L10n.string("Tracker、加密、元数据与来源选择偏好。"),
                    systemImage: "dot.radiowaves.left.and.right"
                )

                optionGroup("BitTorrent") {
                    OptionTextEditor(
                        title: L10n.string("额外 Tracker · 使用逗号分隔"),
                        placeholder: "udp://tracker.example.com:80/announce",
                        text: $form.advancedAria2Options.btTrackers
                    )

                    OptionTextEditor(
                        title: L10n.string("排除 Tracker · 使用逗号分隔"),
                        placeholder: "udp://tracker.example.com:80/announce",
                        text: $form.advancedAria2Options.btExcludedTrackers
                    )

                    twoColumns {
                        booleanInput(
                            L10n.string("要求加密"),
                            selection: $form.advancedAria2Options.btRequireCrypto
                        )
                    } trailing: {
                        booleanInput(
                            L10n.string("强制加密"),
                            selection: $form.advancedAria2Options.btForceEncryption
                        )
                    }

                    twoColumns {
                        OptionInput(L10n.string("最低加密级别")) {
                            OptionSelectionMenu(
                                selection: $form.advancedAria2Options.btMinimumCryptoLevel,
                                values: Aria2BTCryptoLevel.allCases,
                                accessibilityLabel: L10n.string("最低加密级别")
                            ) { $0.title }
                        }
                    } trailing: {
                        booleanInput(
                            L10n.string("启用 IPv6 DHT"),
                            selection: $form.advancedAria2Options.enableDHT6
                        )
                    }

                    twoColumns {
                        booleanInput(
                            L10n.string("仅获取元数据"),
                            selection: $form.advancedAria2Options.btMetadataOnly
                        )
                    } trailing: {
                        booleanInput(
                            L10n.string("保存元数据"),
                            selection: $form.advancedAria2Options.btSaveMetadata
                        )
                    }
                }

                optionGroup("Metalink") {
                    twoColumns {
                        textInput(
                            L10n.string("地区偏好"),
                            placeholder:
                                L10n.resolvedLanguage.metalinkRegionPreference,
                            text: $form.advancedAria2Options.metalinkLocation
                        )
                    } trailing: {
                        textInput(
                            L10n.string("语言偏好"),
                            placeholder:
                                L10n.resolvedLanguage.metalinkLanguagePreference,
                            text: $form.advancedAria2Options.metalinkLanguage
                        )
                    }

                    twoColumns {
                        textInput(
                            L10n.string("操作系统"),
                            placeholder: "macos",
                            text: $form.advancedAria2Options.metalinkOS
                        )
                    } trailing: {
                        textInput(
                            L10n.string("版本"),
                            placeholder: "1.0",
                            text: $form.advancedAria2Options.metalinkVersion
                        )
                    }

                    OptionInput(L10n.string("首选协议")) {
                        OptionSelectionMenu(
                            selection: $form.advancedAria2Options.metalinkPreferredProtocol,
                            values: Aria2MetalinkProtocol.allCases,
                            accessibilityLabel: L10n.string("Metalink 首选协议")
                        ) { $0.title }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
        }
    }

    private func booleanInput(
        _ title: String,
        selection: Binding<Aria2BooleanOverride>
    ) -> some View {
        OptionInput(title) {
            OptionSelectionMenu(
                selection: selection,
                values: Aria2BooleanOverride.allCases,
                accessibilityLabel: title
            ) { $0.title }
        }
    }

    private func textInput(
        _ title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        OptionInput(title) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(LaneFont.utility(10.5, weight: .regular))
        }
    }

    @ViewBuilder
    private func optionGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LaneColor.label2)
            content()
        }
    }

    private func twoColumns<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            leading()
            trailing()
        }
    }
}

struct DownloadRawOptionsView: View {
    @ObservedObject var form: AddDownloadFormState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OptionSectionHeader(
                    title: L10n.string("其他 aria2 参数"),
                    detail: L10n.string("为当前任务传入专用界面未覆盖的参数。"),
                    systemImage: "terminal"
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("每行一个 key=value；可使用 # 添加注释"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    ZStack(alignment: .topLeading) {
                        TextEditor(
                            text: $form.advancedAria2Options.customOptionsText
                        )
                        .font(LaneFont.utility(10.5, weight: .regular))
                        .scrollContentBackground(.hidden)
                        .padding(7)

                        if form.advancedAria2Options.customOptionsText.isEmpty {
                            Text(
                                "continue=true\n"
                                    + "file-allocation=falloc\n"
                                    + L10n.string("# 任意 aria2 addUri 参数")
                            )
                            .font(LaneFont.utility(10.5, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                        }
                    }
                    .frame(height: 150)
                    .background(
                        LaneColor.fill1,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }

                if let message = form.advancedAria2Options.validationMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(LaneColor.amber)
                } else {
                    Label(
                        L10n.string("参数格式有效；同名参数会覆盖上方专用输入框的值。"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(LaneColor.mint)
                }

                Text(
                    L10n.string("header 与 index-out 可重复，需使用对应的专用界面；")
                        + L10n.string("其他参数会在提交时直接传给 aria2。")
                )
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
