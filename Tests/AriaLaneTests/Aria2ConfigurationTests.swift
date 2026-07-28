import XCTest
@testable import AriaLane

final class Aria2ConfigurationTests: XCTestCase {
    func testRecommendedConfigurationMapsToAria2Options() {
        let configuration = Aria2Configuration.recommended(
            downloadDirectory: "/Users/example/Downloads"
        )

        XCTAssertEqual(configuration.globalOptions["dir"], "/Users/example/Downloads")
        XCTAssertEqual(configuration.globalOptions["max-overall-download-limit"], "0")
        XCTAssertEqual(configuration.globalOptions["max-concurrent-downloads"], "5")
        XCTAssertEqual(configuration.globalOptions["max-connection-per-server"], "8")
        XCTAssertEqual(configuration.globalOptions["split"], "8")
        XCTAssertEqual(configuration.globalOptions["continue"], "true")
        XCTAssertEqual(configuration.globalOptions["file-allocation"], "trunc")
        XCTAssertEqual(configuration.globalOptions["listen-port"], "6881-6999")
    }

    func testConfigurationNormalizesRatesAndAria2Ranges() {
        var configuration = Aria2Configuration.recommended(downloadDirectory: "/tmp")
        configuration.maxOverallDownloadLimitKiB = 10_240
        configuration.maxUploadLimitKiB = 512
        configuration.maxConnectionPerServer = 99
        configuration.split = 0
        configuration.listenPortStart = 70_000
        configuration.listenPortEnd = 1_000
        configuration.seedRatio = 1.75

        let options = configuration.globalOptions

        XCTAssertEqual(options["max-overall-download-limit"], "10240K")
        XCTAssertEqual(options["max-upload-limit"], "512K")
        XCTAssertEqual(options["max-connection-per-server"], "16")
        XCTAssertEqual(options["split"], "1")
        XCTAssertEqual(options["listen-port"], "65535")
        XCTAssertEqual(options["seed-ratio"], "1.8")
        XCTAssertTrue(configuration.commandLineArguments.contains("--max-upload-limit=512K"))
    }

    func testTaskSpeedLimitsConvertAria2BytesToKiBAndBack() {
        let limits = TaskSpeedLimits(
            options: [
                "max-download-limit": "3145728",
                "max-upload-limit": "131072"
            ]
        )

        XCTAssertEqual(limits.downloadKiBPerSecond, 3_072)
        XCTAssertEqual(limits.uploadKiBPerSecond, 128)
        XCTAssertEqual(limits.optionValues["max-download-limit"], "3072K")
        XCTAssertEqual(limits.optionValues["max-upload-limit"], "128K")
    }

    func testTaskSpeedLimitTreatsMissingOrNegativeValuesAsUnlimited() {
        let limits = TaskSpeedLimits(
            options: [
                "max-download-limit": "-1"
            ]
        )

        XCTAssertEqual(limits, .unlimited)
        XCTAssertEqual(limits.optionValues["max-download-limit"], "0")
        XCTAssertEqual(limits.optionValues["max-upload-limit"], "0")
    }

    func testSpeedLimitFormattingUsesAria2BinaryUnits() {
        XCTAssertEqual(TransferFormatter.speedLimit(0), "不限速")
        XCTAssertEqual(TransferFormatter.speedLimit(512), "512 KB/s")
        XCTAssertEqual(TransferFormatter.speedLimit(1_024), "1 MB/s")
        XCTAssertEqual(TransferFormatter.speedLimit(5_120), "5 MB/s")
        XCTAssertEqual(TransferFormatter.speedLimit(1_536), "1.5 MB/s")
    }
}
