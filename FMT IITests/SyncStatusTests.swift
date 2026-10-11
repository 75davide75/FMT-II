import XCTest
@testable import FMT_II

/// Stato della sincronizzazione mostrato in Impostazioni.
final class SyncStatusTests: XCTestCase {
    override func setUp() {
        super.setUp()
        LanguageSettings.current = .italian   // i testi attesi sono quelli italiani
    }

    func testLabels() {
        XCTAssertEqual(CloudSyncManager.Status.noAccount.label, "Accedi a iCloud")
        XCTAssertEqual(CloudSyncManager.Status.quotaExceeded.label, "Spazio iCloud esaurito")
        XCTAssertEqual(CloudSyncManager.Status.syncing.label, "In corso…")
        XCTAssertEqual(CloudSyncManager.Status.upToDate(nil).label, "Attiva")
        XCTAssertTrue(CloudSyncManager.Status.upToDate(Date()).label.hasPrefix("Aggiornata alle "))
        XCTAssertTrue(CloudSyncManager.Status.noAccount.isProblem)
        XCTAssertTrue(CloudSyncManager.Status.failed("x").isProblem)
        XCTAssertFalse(CloudSyncManager.Status.upToDate(nil).isProblem)
    }

    @MainActor func testSyncIsOffUnderTests() {
        XCTAssertEqual(CloudSyncManager.shared.status, .off)
    }
}
