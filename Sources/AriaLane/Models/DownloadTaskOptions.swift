import Foundation

enum DownloadChecksumAlgorithm: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case sha1
    case sha224
    case sha256
    case sha384
    case sha512
    case md5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: L10n.string("不校验")
        case .sha1: "SHA-1"
        case .sha224: "SHA-224"
        case .sha256: "SHA-256"
        case .sha384: "SHA-384"
        case .sha512: "SHA-512"
        case .md5: "MD5"
        }
    }

    var aria2Name: String? {
        switch self {
        case .none: nil
        case .sha1: "sha-1"
        case .sha224: "sha-224"
        case .sha256: "sha-256"
        case .sha384: "sha-384"
        case .sha512: "sha-512"
        case .md5: "md5"
        }
    }

    var expectedHexLength: Int? {
        switch self {
        case .none: nil
        case .sha1: 40
        case .sha224: 56
        case .sha256: 64
        case .sha384: 96
        case .sha512: 128
        case .md5: 32
        }
    }
}

struct Aria2AddTaskPayload: Equatable, Sendable {
    let options: [String: String]
    let headers: [String]
    let additionalURIs: [String]
}

struct DownloadTaskOptions: Codable, Equatable, Sendable {
    var directory: String
    var outputFileName: String

    var maxDownloadLimitKiB: Int
    var maxUploadLimitKiB: Int
    var split: Int
    var maxConnectionPerServer: Int

    var referer: String
    var userAgent: String
    var customHeaders: [String]
    var cookie: String

    var username: String
    var password: String
    var checksumAlgorithm: DownloadChecksumAlgorithm
    var checksumDigest: String
    var advanced: AdvancedDownloadTaskOptions? = nil

    static func defaults(
        directory: String,
        maxDownloadLimitKiB: Int = 0,
        maxUploadLimitKiB: Int = 0,
        split: Int = 8,
        maxConnectionPerServer: Int = 8
    ) -> DownloadTaskOptions {
        DownloadTaskOptions(
            directory: directory,
            outputFileName: "",
            maxDownloadLimitKiB: max(maxDownloadLimitKiB, 0),
            maxUploadLimitKiB: max(maxUploadLimitKiB, 0),
            split: clamped(split, to: 1...16),
            maxConnectionPerServer: clamped(maxConnectionPerServer, to: 1...16),
            referer: "",
            userAgent: "",
            customHeaders: [],
            cookie: "",
            username: "",
            password: "",
            checksumAlgorithm: .none,
            checksumDigest: "",
            advanced: nil
        )
    }

    func validationMessage(forURLCount urlCount: Int) -> String? {
        let fileName = outputFileName.trimmed
        let folder = directory.trimmed
        let checksum = normalizedChecksum

        guard !folder.isEmpty else {
            return L10n.string("请选择保存目录")
        }
        guard !Self.containsLineBreak(folder) else {
            return L10n.string("保存目录不能包含换行符")
        }

        if !fileName.isEmpty {
            guard urlCount == 1 else {
                return L10n.string("多个链接不能共用同一个文件名")
            }
            guard fileName != ".", fileName != "..",
                  !fileName.contains("/"), !fileName.contains("\\"),
                  !fileName.contains("\0"), !Self.containsLineBreak(fileName) else {
                return L10n.string("文件名只能是名称，不能包含路径")
            }
        }

        for (label, value) in [
            ("Referer", referer),
            ("User-Agent", userAgent),
            ("Cookie", cookie),
            (L10n.string("用户名"), username),
            (L10n.string("密码"), password)
        ] where Self.containsLineBreak(value) {
            return L10n.string("\(label) 不能包含换行符")
        }

        if !password.isEmpty, username.trimmed.isEmpty {
            return L10n.string("填写密码时也需要用户名")
        }

        for header in normalizedHeaders {
            guard Self.isValidHeader(header) else {
                return L10n.string("Header 需要使用“名称: 值”的格式")
            }
        }

        if checksumAlgorithm == .none {
            if !checksum.isEmpty {
                return L10n.string("请选择校验算法")
            }
        } else {
            guard urlCount == 1 else {
                return L10n.string("多个链接不能共用同一个校验值")
            }
            guard let expectedLength = checksumAlgorithm.expectedHexLength,
                  checksum.count == expectedLength,
                  checksum.unicodeScalars.allSatisfy(Self.hexCharacters.contains) else {
                return L10n.string("\(checksumAlgorithm.title) 校验值应为 \(checksumAlgorithm.expectedHexLength ?? 0) 位十六进制")
            }
        }

        if let message = advanced?.validationMessage(primaryURLCount: urlCount) {
            return message
        }

        return nil
    }

    var payload: Aria2AddTaskPayload {
        var options: [String: String] = [
            "dir": directory.trimmed,
            "split": String(Self.clamped(split, to: 1...16)),
            "max-connection-per-server":
                String(Self.clamped(maxConnectionPerServer, to: 1...16))
        ]

        let fileName = outputFileName.trimmed
        if !fileName.isEmpty {
            options["out"] = fileName
        }
        options["max-download-limit"] =
            Aria2Configuration.speedOption(max(maxDownloadLimitKiB, 0))
        options["max-upload-limit"] =
            Aria2Configuration.speedOption(max(maxUploadLimitKiB, 0))

        let normalizedReferer = referer.trimmed
        if !normalizedReferer.isEmpty {
            options["referer"] = normalizedReferer
        }
        let normalizedUserAgent = userAgent.trimmed
        if !normalizedUserAgent.isEmpty {
            options["user-agent"] = normalizedUserAgent
        }

        let normalizedUsername = username.trimmed
        if !normalizedUsername.isEmpty {
            options["http-user"] = normalizedUsername
            options["ftp-user"] = normalizedUsername
        }
        if !password.isEmpty {
            options["http-passwd"] = password
            options["ftp-passwd"] = password
        }

        if let checksumName = checksumAlgorithm.aria2Name,
           !normalizedChecksum.isEmpty {
            options["checksum"] = "\(checksumName)=\(normalizedChecksum)"
        }
        if let advanced,
           let advancedOptions = try? advanced.aria2.optionValues() {
            options.merge(advancedOptions) { _, advancedValue in advancedValue }
        }

        var headers = normalizedHeaders
        let normalizedCookie = cookie.trimmed
        if !normalizedCookie.isEmpty {
            headers.append("Cookie: \(normalizedCookie)")
        }

        return Aria2AddTaskPayload(
            options: options,
            headers: headers,
            additionalURIs: advanced?.normalizedAdditionalURIs ?? []
        )
    }

    var normalizedHeaders: [String] {
        customHeaders
            .map(\.trimmed)
            .filter { !$0.isEmpty }
    }

    var normalizedChecksum: String {
        checksumDigest
            .filter { !$0.isWhitespace }
            .lowercased()
    }

    private static let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")

    private static func isValidHeader(_ header: String) -> Bool {
        guard !containsLineBreak(header),
              let separator = header.firstIndex(of: ":") else {
            return false
        }

        let name = String(header[..<separator])
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return false }

        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "!#$%&'*+-.^_`|~")
        )
        return name.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func containsLineBreak(_ value: String) -> Bool {
        value.contains("\n") || value.contains("\r")
    }

    private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
