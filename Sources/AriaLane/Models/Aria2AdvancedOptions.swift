import Foundation

enum Aria2BooleanOverride: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit
    case enabled
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inherit: return L10n.string("沿用服务器")
        case .enabled: return L10n.string("启用")
        case .disabled: return L10n.string("停用")
        }
    }

    var optionValue: String? {
        switch self {
        case .inherit: return nil
        case .enabled: return "true"
        case .disabled: return "false"
        }
    }
}

enum Aria2FTPType: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit
    case binary
    case ascii

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inherit: return L10n.string("沿用服务器")
        case .binary: return "Binary"
        case .ascii: return "ASCII"
        }
    }
}

enum Aria2MetalinkProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit
    case none
    case http
    case https
    case ftp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inherit: return L10n.string("沿用服务器")
        case .none: return L10n.string("不指定")
        case .http: return "HTTP"
        case .https: return "HTTPS"
        case .ftp: return "FTP"
        }
    }
}

enum Aria2BTCryptoLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit
    case plain
    case arc4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inherit: return L10n.string("沿用服务器")
        case .plain: return L10n.string("兼容模式")
        case .arc4: return L10n.string("仅 ARC4")
        }
    }
}

enum Aria2OptionTextError: LocalizedError, Equatable {
    case malformedLine(Int)
    case invalidKey(line: Int, key: String)
    case unsupportedRepeatedOption(line: Int, key: String)

    var errorDescription: String? {
        switch self {
        case .malformedLine(let line):
            return L10n.string("自定义参数第 \(line) 行需要使用 key=value")
        case .invalidKey(let line, let key):
            return L10n.string("自定义参数第 \(line) 行的名称“\(key)”无效")
        case .unsupportedRepeatedOption(let line, let key):
            return L10n.string("自定义参数第 \(line) 行的“\(key)”请使用专用输入框")
        }
    }
}

enum Aria2OptionTextParser {
    static func parse(_ text: String) throws -> [String: String] {
        var result: [String: String] = [:]
        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmed
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let separator = line.firstIndex(of: "=") else {
                throw Aria2OptionTextError.malformedLine(lineNumber)
            }

            var key = String(line[..<separator]).trimmed.lowercased()
            if key.hasPrefix("--") {
                key.removeFirst(2)
            }
            let value = String(line[line.index(after: separator)...]).trimmed
            let allowed = CharacterSet.lowercaseLetters
                .union(.decimalDigits)
                .union(CharacterSet(charactersIn: "-"))
            guard !key.isEmpty,
                  key.unicodeScalars.allSatisfy(allowed.contains),
                  key.first?.isLetter == true else {
                throw Aria2OptionTextError.invalidKey(line: lineNumber, key: key)
            }
            guard !["header", "index-out"].contains(key) else {
                throw Aria2OptionTextError.unsupportedRepeatedOption(
                    line: lineNumber,
                    key: key
                )
            }
            result[key] = value
        }
        return result
    }
}

struct Aria2AdvancedOptions: Codable, Equatable, Sendable {
    var allProxy = ""
    var httpProxy = ""
    var httpsProxy = ""
    var ftpProxy = ""
    var noProxy = ""
    var proxyUser = ""
    var proxyPassword = ""

    var checkCertificate = Aria2BooleanOverride.inherit
    var caCertificate = ""
    var clientCertificate = ""
    var privateKey = ""
    var loadCookies = ""
    var saveCookies = ""

    var ftpPassive = Aria2BooleanOverride.inherit
    var ftpReuseConnection = Aria2BooleanOverride.inherit
    var ftpType = Aria2FTPType.inherit
    var sshHostKeyDigest = ""

    var checkIntegrity = Aria2BooleanOverride.inherit
    var dryRun = Aria2BooleanOverride.inherit
    var contentDisposition = Aria2BooleanOverride.inherit
    var conditionalGet = Aria2BooleanOverride.inherit
    var httpAcceptGzip = Aria2BooleanOverride.inherit

    var btTrackers = ""
    var btExcludedTrackers = ""
    var btRequireCrypto = Aria2BooleanOverride.inherit
    var btForceEncryption = Aria2BooleanOverride.inherit
    var btMinimumCryptoLevel = Aria2BTCryptoLevel.inherit
    var btMetadataOnly = Aria2BooleanOverride.inherit
    var btSaveMetadata = Aria2BooleanOverride.inherit
    var enableDHT6 = Aria2BooleanOverride.inherit

    var metalinkLocation = ""
    var metalinkLanguage = ""
    var metalinkOS = ""
    var metalinkVersion = ""
    var metalinkPreferredProtocol = Aria2MetalinkProtocol.inherit

    var customOptionsText = ""

    static var defaultGlobalConfiguration: Aria2AdvancedOptions {
        var configuration = Aria2AdvancedOptions()
        configuration.checkCertificate = .disabled
        return configuration
    }

    var isDefault: Bool {
        self == Aria2AdvancedOptions()
    }

    var validationMessage: String? {
        do {
            _ = try optionValues()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func optionValues(
        proxyPassword passwordOverride: String? = nil
    ) throws -> [String: String] {
        var options: [String: String] = [:]

        set(allProxy, key: "all-proxy", in: &options)
        set(httpProxy, key: "http-proxy", in: &options)
        set(httpsProxy, key: "https-proxy", in: &options)
        set(ftpProxy, key: "ftp-proxy", in: &options)
        set(noProxy, key: "no-proxy", in: &options)

        let password = passwordOverride ?? proxyPassword
        for prefix in activeProxyPrefixes {
            set(proxyUser, key: "\(prefix)-proxy-user", in: &options)
            set(password, key: "\(prefix)-proxy-passwd", in: &options)
        }

        set(checkCertificate, key: "check-certificate", in: &options)
        set(caCertificate, key: "ca-certificate", in: &options)
        set(clientCertificate, key: "certificate", in: &options)
        set(privateKey, key: "private-key", in: &options)
        set(loadCookies, key: "load-cookies", in: &options)
        set(saveCookies, key: "save-cookies", in: &options)

        set(ftpPassive, key: "ftp-pasv", in: &options)
        set(ftpReuseConnection, key: "ftp-reuse-connection", in: &options)
        if ftpType != .inherit {
            options["ftp-type"] = ftpType.rawValue
        }
        set(sshHostKeyDigest, key: "ssh-host-key-md", in: &options)

        set(checkIntegrity, key: "check-integrity", in: &options)
        set(dryRun, key: "dry-run", in: &options)
        set(contentDisposition, key: "content-disposition-default-utf8", in: &options)
        set(conditionalGet, key: "conditional-get", in: &options)
        set(httpAcceptGzip, key: "http-accept-gzip", in: &options)

        set(btTrackers, key: "bt-tracker", in: &options)
        set(btExcludedTrackers, key: "bt-exclude-tracker", in: &options)
        set(btRequireCrypto, key: "bt-require-crypto", in: &options)
        set(btForceEncryption, key: "bt-force-encryption", in: &options)
        if btMinimumCryptoLevel != .inherit {
            options["bt-min-crypto-level"] = btMinimumCryptoLevel.rawValue
        }
        set(btMetadataOnly, key: "bt-metadata-only", in: &options)
        set(btSaveMetadata, key: "bt-save-metadata", in: &options)
        set(enableDHT6, key: "enable-dht6", in: &options)

        set(metalinkLocation, key: "metalink-location", in: &options)
        set(metalinkLanguage, key: "metalink-language", in: &options)
        set(metalinkOS, key: "metalink-os", in: &options)
        set(metalinkVersion, key: "metalink-version", in: &options)
        if metalinkPreferredProtocol != .inherit {
            options["metalink-preferred-protocol"] = metalinkPreferredProtocol.rawValue
        }

        options.merge(try Aria2OptionTextParser.parse(customOptionsText)) {
            _, customValue in customValue
        }
        return options
    }

    private var activeProxyPrefixes: [String] {
        var values: [String] = []
        if !allProxy.trimmed.isEmpty { values.append("all") }
        if !httpProxy.trimmed.isEmpty { values.append("http") }
        if !httpsProxy.trimmed.isEmpty { values.append("https") }
        if !ftpProxy.trimmed.isEmpty { values.append("ftp") }
        return values
    }

    private func set(
        _ value: String,
        key: String,
        in options: inout [String: String]
    ) {
        let normalized = value.trimmed
        if !normalized.isEmpty {
            options[key] = normalized
        }
    }

    private func set(
        _ value: Aria2BooleanOverride,
        key: String,
        in options: inout [String: String]
    ) {
        if let optionValue = value.optionValue {
            options[key] = optionValue
        }
    }
}

struct AdvancedDownloadTaskOptions: Codable, Equatable, Sendable {
    var additionalURIs: [String] = []
    var aria2 = Aria2AdvancedOptions()

    var isDefault: Bool {
        additionalURIs.isEmpty && aria2.isDefault
    }

    var normalizedAdditionalURIs: [String] {
        var seen = Set<String>()
        return additionalURIs
            .map(\.trimmed)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func validationMessage(primaryURLCount: Int) -> String? {
        if !normalizedAdditionalURIs.isEmpty, primaryURLCount != 1 {
            return L10n.string("备用镜像只能用于单个主链接")
        }
        for uri in normalizedAdditionalURIs {
            guard let scheme = URLComponents(string: uri)?.scheme?.lowercased(),
                  ["http", "https", "ftp", "sftp"].contains(scheme) else {
                return L10n.string("备用镜像只支持 HTTP、HTTPS、FTP 或 SFTP")
            }
        }
        return aria2.validationMessage
    }
}
