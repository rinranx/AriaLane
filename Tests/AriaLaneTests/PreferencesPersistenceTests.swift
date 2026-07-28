import Security
import XCTest
@testable import AriaLane

final class PreferencesPersistenceTests: XCTestCase {
    func testKeychainDeleteAcceptsMissingItem() {
        XCTAssertNoThrow(
            try KeychainStore.validateStatus(
                errSecItemNotFound,
                operation: .delete,
                allowsItemNotFound: true
            )
        )
    }

    func testKeychainFailureRetainsOperationAndStatus() {
        XCTAssertThrowsError(
            try KeychainStore.validateStatus(
                errSecInteractionNotAllowed,
                operation: .update
            )
        ) { error in
            XCTAssertEqual(
                error as? KeychainStoreError,
                .operationFailed(
                    operation: .update,
                    status: errSecInteractionNotAllowed
                )
            )
        }
    }

    @MainActor
    func testRPCSecretSaveFailureIsSurfacedWithoutSecretValue() {
        let suiteName = "PreferencesPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        struct ExpectedFailure: LocalizedError {
            var errorDescription: String? {
                "The login keychain is locked."
            }
        }

        let secret = "must-never-appear-in-an-error"
        let keychain = KeychainClient(
            read: { _, _ in nil },
            save: { value, _, _ in
                if value == secret {
                    throw ExpectedFailure()
                }
            }
        )
        let preferences = AppPreferences(
            defaults: defaults,
            keychain: keychain
        )

        preferences.rpcSecret = secret

        let issue = preferences.keychainPersistenceIssue
        XCTAssertEqual(issue?.credential, .rpcSecret)
        XCTAssertNotNil(issue)
        XCTAssertFalse(issue?.message.contains(secret) ?? true)

        preferences.dismissKeychainPersistenceIssue()
        XCTAssertNil(preferences.keychainPersistenceIssue)
    }

    @MainActor
    func testMetalinkLocaleHintsDoNotPopulateConfiguration() {
        let suiteName = "MetalinkLocaleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(
            AppLanguage.simplifiedChinese.rawValue,
            forKey: AppLanguage.preferenceKey
        )

        let preferences = AppPreferences(
            defaults: defaults,
            keychain: .inMemory
        )

        XCTAssertEqual(
            preferences.advancedConfiguration.metalinkLocation,
            ""
        )
        XCTAssertEqual(
            preferences.advancedConfiguration.metalinkLanguage,
            ""
        )
        XCTAssertEqual(
            preferences.appLanguage.resolved.metalinkRegionPreference,
            "CN"
        )
        XCTAssertEqual(
            preferences.appLanguage.resolved.metalinkLanguagePreference,
            "zh-CN"
        )

        preferences.appLanguage = .english

        XCTAssertEqual(
            preferences.advancedConfiguration.metalinkLocation,
            ""
        )
        XCTAssertEqual(
            preferences.advancedConfiguration.metalinkLanguage,
            ""
        )
        XCTAssertEqual(
            preferences.appLanguage.resolved.metalinkRegionPreference,
            "US"
        )
        XCTAssertEqual(
            preferences.appLanguage.resolved.metalinkLanguagePreference,
            "en-US"
        )
    }

    @MainActor
    func testMetalinkLanguageChangePreservesCustomPreferences() {
        let suiteName = "MetalinkCustomLocaleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(
            AppLanguage.english.rawValue,
            forKey: AppLanguage.preferenceKey
        )

        let preferences = AppPreferences(
            defaults: defaults,
            keychain: .inMemory
        )
        preferences.advancedConfiguration.metalinkLocation = "JP"
        preferences.advancedConfiguration.metalinkLanguage = "ja-JP"

        preferences.appLanguage = .simplifiedChinese

        XCTAssertEqual(
            preferences.advancedConfiguration.metalinkLocation,
            "JP"
        )
        XCTAssertEqual(
            preferences.advancedConfiguration.metalinkLanguage,
            "ja-JP"
        )
    }

    @MainActor
    func testLegacyMetalinkLocaleAutofillIsClearedOnlyOnce() throws {
        let suiteName = "MetalinkAutofillMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var legacyConfiguration = Aria2AdvancedOptions()
        legacyConfiguration.metalinkLocation = "CN"
        legacyConfiguration.metalinkLanguage = "zh-CN"
        defaults.set(
            try JSONEncoder().encode(legacyConfiguration),
            forKey: "aria2AdvancedConfiguration"
        )

        let migratedPreferences = AppPreferences(
            defaults: defaults,
            keychain: .inMemory
        )
        XCTAssertEqual(
            migratedPreferences.advancedConfiguration.metalinkLocation,
            ""
        )
        XCTAssertEqual(
            migratedPreferences.advancedConfiguration.metalinkLanguage,
            ""
        )

        let persistedConfiguration = try XCTUnwrap(
            defaults.data(forKey: "aria2AdvancedConfiguration")
        )
        let decodedConfiguration = try JSONDecoder().decode(
            Aria2AdvancedOptions.self,
            from: persistedConfiguration
        )
        XCTAssertEqual(decodedConfiguration.metalinkLocation, "")
        XCTAssertEqual(decodedConfiguration.metalinkLanguage, "")

        migratedPreferences.advancedConfiguration.metalinkLocation = "CN"
        migratedPreferences.advancedConfiguration.metalinkLanguage = "zh-CN"

        let relaunchedPreferences = AppPreferences(
            defaults: defaults,
            keychain: .inMemory
        )
        XCTAssertEqual(
            relaunchedPreferences.advancedConfiguration.metalinkLocation,
            "CN"
        )
        XCTAssertEqual(
            relaunchedPreferences.advancedConfiguration.metalinkLanguage,
            "zh-CN"
        )
    }
}

private extension KeychainClient {
    static var inMemory: KeychainClient {
        var values: [String: String] = [:]
        return KeychainClient(
            read: { service, account in
                values["\(service):\(account)"]
            },
            save: { value, service, account in
                let key = "\(service):\(account)"
                if value.isEmpty {
                    values.removeValue(forKey: key)
                } else {
                    values[key] = value
                }
            }
        )
    }
}

final class AdaptiveSheetSizingTests: XCTestCase {
    func testDownloadComposerTracksAvailableSizeWithinBounds() {
        XCTAssertEqual(
            LaneAdaptiveSheetSize.downloadComposer(
                in: CGSize(width: 560, height: 620)
            ),
            CGSize(width: 536, height: 596)
        )
        XCTAssertEqual(
            LaneAdaptiveSheetSize.downloadComposer(
                in: CGSize(width: 1_400, height: 1_000)
            ),
            CGSize(width: 1_040, height: 800)
        )
    }

    func testRSSEditorTracksAvailableSizeWithinBounds() {
        XCTAssertEqual(
            LaneAdaptiveSheetSize.rssEditor(
                in: CGSize(width: 500, height: 600)
            ),
            CGSize(width: 484, height: 584)
        )
        XCTAssertEqual(
            LaneAdaptiveSheetSize.rssEditor(
                in: CGSize(width: 1_400, height: 1_000)
            ),
            CGSize(width: 720, height: 760)
        )
    }
}

final class SettingsRoutingTests: XCTestCase {
    func testSpeedSettingsRouteSelectsSpeedPane() {
        let suiteName = "SettingsRoutingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        SettingsPane.speed.select(in: defaults)

        XCTAssertEqual(
            defaults.string(forKey: SettingsPane.preferenceKey),
            SettingsPane.speed.rawValue
        )
    }
}
