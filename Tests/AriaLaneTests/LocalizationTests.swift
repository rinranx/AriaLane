import XCTest
@testable import AriaLane

final class LocalizationTests: XCTestCase {
    func testSystemLanguageUsesChineseForSimplifiedAndTraditionalChinese() {
        XCTAssertEqual(
            AppLanguage.resolve(.system, preferredLanguages: ["zh-Hans-CN"]),
            .simplifiedChinese
        )
        XCTAssertEqual(
            AppLanguage.resolve(.system, preferredLanguages: ["zh-Hant-TW"]),
            .simplifiedChinese
        )
    }

    func testSystemLanguageFallsBackToEnglishForUnsupportedLanguages() {
        XCTAssertEqual(
            AppLanguage.resolve(.system, preferredLanguages: ["ja-JP", "zh-Hans"]),
            .english
        )
        XCTAssertEqual(
            AppLanguage.resolve(.system, preferredLanguages: []),
            .english
        )
    }

    func testExplicitLanguageOverridesSystemLanguage() {
        XCTAssertEqual(
            AppLanguage.resolve(.english, preferredLanguages: ["zh-Hant-HK"]),
            .english
        )
        XCTAssertEqual(
            AppLanguage.resolve(.simplifiedChinese, preferredLanguages: ["en-US"]),
            .simplifiedChinese
        )
    }
}
