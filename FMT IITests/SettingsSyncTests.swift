import XCTest
@testable import FMT_II

/// Quali impostazioni viaggiano su iCloud (scuola) e quali restano sul
/// dispositivo (tema, testo, tutorial, banner novità).
final class SettingsSyncTests: XCTestCase {
    func testDevicePreferencesAreNotSynced() {
        for local in ["appearanceMode", "dynamicTypeLevel", "useLiveTime", "manualDayRaw", "manualTime",
                      "appSectionRaw", "hasSeenTutorial", "hasCompletedOnboarding", "lastSeenWhatsNew"] {
            XCTAssertFalse(SettingsSync.syncedKeys.contains(local), local)
        }
    }

    func testSchoolSettingsAreSynced() {
        XCTAssertEqual(Set(SettingsSync.syncedKeys),
                       ["sufficientGrade", "maxGrade", "periodSystem", "period1EndTimestamp",
                        "fmt_subject_colors", "fmt_entity_colors"])
    }

    func testSameComparesValues() {
        XCTAssertTrue(SettingsSync.same(6.0, 6.0))
        XCTAssertFalse(SettingsSync.same(6.0, 5.5))
        XCTAssertTrue(SettingsSync.same(Data([1, 2]), Data([1, 2])))
        XCTAssertFalse(SettingsSync.same(nil, 1))
        XCTAssertTrue(SettingsSync.same(nil, nil))
    }
}
