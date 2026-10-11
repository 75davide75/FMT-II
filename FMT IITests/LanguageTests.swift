import XCTest
@testable import FMT_II

/// Lingua dell'app: regola iniziale in base al paese e locale per testi/date.
final class LanguageTests: XCTestCase {
    func testExistingUserStaysItalian() {
        XCTAssertEqual(AppLanguage.initial(storefrontCountry: "USA", region: "US", isExistingUser: true), .italian)
    }

    func testItalianStorefronts() {
        for sf in ["ITA", "SMR", "VAT", "ita"] {
            XCTAssertEqual(AppLanguage.initial(storefrontCountry: sf, region: "US", isExistingUser: false), .italian, sf)
        }
    }

    func testOtherStorefrontsAreEnglish() {
        for sf in ["USA", "CHE", "GBR", "DEU"] {
            XCTAssertEqual(AppLanguage.initial(storefrontCountry: sf, region: "IT", isExistingUser: false), .english, sf)
        }
    }

    func testRegionFallbackWithoutStorefront() {
        XCTAssertEqual(AppLanguage.initial(storefrontCountry: nil, region: "IT", isExistingUser: false), .italian)
        XCTAssertEqual(AppLanguage.initial(storefrontCountry: nil, region: "SM", isExistingUser: false), .italian)
        XCTAssertEqual(AppLanguage.initial(storefrontCountry: nil, region: "DE", isExistingUser: false), .english)
        XCTAssertEqual(AppLanguage.initial(storefrontCountry: nil, region: nil, isExistingUser: false), .english)
    }

    func testLocales() {
        XCTAssertEqual(AppLanguage.italian.locale(region: "US").identifier, "it_IT")
        XCTAssertEqual(AppLanguage.english.locale(region: "GB").identifier, "en_GB")
        XCTAssertEqual(AppLanguage.english.locale(region: "IT").identifier, "en_US")
        XCTAssertEqual(AppLanguage.english.locale(region: nil).identifier, "en_US")
    }

    func testNativeNames() {
        XCTAssertEqual(AppLanguage.italian.nativeName, "Italiano")
        XCTAssertEqual(AppLanguage.english.nativeName, "English")
    }

    func testLanguageIsNotSyncedThroughICloud() {
        XCTAssertFalse(SettingsSync.syncedKeys.contains(LanguageSettings.storageKey))
        XCTAssertFalse(SettingsSync.syncedKeys.contains("AppleLanguages"))
    }
}
