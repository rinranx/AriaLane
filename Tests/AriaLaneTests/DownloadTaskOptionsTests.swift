import XCTest
@testable import AriaLane

final class DownloadTaskOptionsTests: XCTestCase {
    func testMapsAdvancedTaskOptionsToAria2Payload() {
        var options = DownloadTaskOptions.defaults(
            directory: "/Users/example/Downloads",
            split: 6,
            maxConnectionPerServer: 4
        )
        options.outputFileName = "release.zip"
        options.maxDownloadLimitKiB = 5_120
        options.maxUploadLimitKiB = 256
        options.referer = "https://example.com/releases"
        options.userAgent = "AriaLane-Test/1.0"
        options.customHeaders = [
            "Authorization: Bearer token",
            "Accept-Language: zh-TW"
        ]
        options.cookie = "session=abc"
        options.username = "reader"
        options.password = "secret"
        options.checksumAlgorithm = .sha256
        options.checksumDigest = String(repeating: "A", count: 64)
        var advanced = Aria2AdvancedOptions()
        advanced.allProxy = "http://127.0.0.1:7890"
        advanced.proxyUser = "proxy-reader"
        advanced.proxyPassword = "proxy-secret"
        advanced.checkCertificate = .enabled
        advanced.sshHostKeyDigest = "sha-256=abcdef"
        advanced.btForceEncryption = .enabled
        advanced.metalinkLanguage = "zh-TW"
        advanced.customOptionsText = "continue=true\nmax-tries=9"
        options.advanced = AdvancedDownloadTaskOptions(
            additionalURIs: [
                "https://mirror.example.test/release.zip",
                "https://mirror.example.test/release.zip",
                "sftp://mirror.example.test/release.zip"
            ],
            aria2: advanced
        )

        XCTAssertNil(options.validationMessage(forURLCount: 1))

        let payload = options.payload
        XCTAssertEqual(payload.options["dir"], "/Users/example/Downloads")
        XCTAssertEqual(payload.options["out"], "release.zip")
        XCTAssertEqual(payload.options["max-download-limit"], "5120K")
        XCTAssertEqual(payload.options["max-upload-limit"], "256K")
        XCTAssertEqual(payload.options["split"], "6")
        XCTAssertEqual(payload.options["max-connection-per-server"], "4")
        XCTAssertEqual(payload.options["referer"], "https://example.com/releases")
        XCTAssertEqual(payload.options["user-agent"], "AriaLane-Test/1.0")
        XCTAssertEqual(payload.options["http-user"], "reader")
        XCTAssertEqual(payload.options["ftp-user"], "reader")
        XCTAssertEqual(payload.options["http-passwd"], "secret")
        XCTAssertEqual(
            payload.options["checksum"],
            "sha-256=\(String(repeating: "a", count: 64))"
        )
        XCTAssertEqual(
            payload.headers,
            [
                "Authorization: Bearer token",
                "Accept-Language: zh-TW",
                "Cookie: session=abc"
            ]
        )
        XCTAssertEqual(
            payload.additionalURIs,
            [
                "https://mirror.example.test/release.zip",
                "sftp://mirror.example.test/release.zip"
            ]
        )
        XCTAssertEqual(
            payload.options["all-proxy"],
            "http://127.0.0.1:7890"
        )
        XCTAssertEqual(payload.options["all-proxy-user"], "proxy-reader")
        XCTAssertEqual(payload.options["all-proxy-passwd"], "proxy-secret")
        XCTAssertEqual(payload.options["check-certificate"], "true")
        XCTAssertEqual(payload.options["ssh-host-key-md"], "sha-256=abcdef")
        XCTAssertEqual(payload.options["bt-force-encryption"], "true")
        XCTAssertEqual(payload.options["metalink-language"], "zh-TW")
        XCTAssertEqual(payload.options["continue"], "true")
        XCTAssertEqual(payload.options["max-tries"], "9")
    }

    func testZeroSpeedLimitsExplicitlyDisableTaskLimits() {
        let options = DownloadTaskOptions.defaults(directory: "/tmp")
        let payload = options.payload

        XCTAssertEqual(payload.options["max-download-limit"], "0")
        XCTAssertEqual(payload.options["max-upload-limit"], "0")
    }

    func testRejectsFilenameAndChecksumForMultipleURLs() {
        var options = DownloadTaskOptions.defaults(directory: "/tmp")
        options.outputFileName = "shared.zip"

        XCTAssertEqual(
            options.validationMessage(forURLCount: 2),
            "多个链接不能共用同一个文件名"
        )

        options.outputFileName = ""
        options.checksumAlgorithm = .md5
        options.checksumDigest = String(repeating: "0", count: 32)

        XCTAssertEqual(
            options.validationMessage(forURLCount: 2),
            "多个链接不能共用同一个校验值"
        )
    }

    func testValidatesChecksumLengthAndCharacters() {
        var options = DownloadTaskOptions.defaults(directory: "/tmp")
        options.checksumAlgorithm = .md5
        options.checksumDigest = "not-a-digest"

        XCTAssertEqual(
            options.validationMessage(forURLCount: 1),
            "MD5 校验值应为 32 位十六进制"
        )
    }

    func testRejectsMalformedCustomHeader() {
        var options = DownloadTaskOptions.defaults(directory: "/tmp")
        options.customHeaders = ["Missing separator"]

        XCTAssertEqual(
            options.validationMessage(forURLCount: 1),
            "Header 需要使用“名称: 值”的格式"
        )
    }

    func testPasswordRequiresUsername() {
        var options = DownloadTaskOptions.defaults(directory: "/tmp")
        options.password = "secret"

        XCTAssertEqual(
            options.validationMessage(forURLCount: 1),
            "填写密码时也需要用户名"
        )
    }

    func testRejectsMalformedRawAria2Option() {
        var options = DownloadTaskOptions.defaults(directory: "/tmp")
        var advanced = Aria2AdvancedOptions()
        advanced.customOptionsText = "max-tries 10"
        options.advanced = AdvancedDownloadTaskOptions(aria2: advanced)

        XCTAssertEqual(
            options.validationMessage(forURLCount: 1),
            "自定义参数第 1 行需要使用 key=value"
        )
    }

    func testAdditionalMirrorRequiresSinglePrimaryURL() {
        var options = DownloadTaskOptions.defaults(directory: "/tmp")
        options.advanced = AdvancedDownloadTaskOptions(
            additionalURIs: ["https://mirror.example.test/file.zip"]
        )

        XCTAssertEqual(
            options.validationMessage(forURLCount: 2),
            "备用镜像只能用于单个主链接"
        )
    }
}
