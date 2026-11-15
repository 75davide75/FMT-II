import XCTest
@testable import FMT_II

/// Problemi minori rimandati dalla revisione della 2.2, ora corretti.
@MainActor
final class DeferredFixTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    // 1. Eventi in ritardo di un motore di sync sostituito (cambio account)
    //    non devono toccare lo stato del motore nuovo.
    func testEventsFromReplacedEngineAreIgnored() {
        let current = NSObject(), old = NSObject()
        XCTAssertTrue(CloudSyncManager.isFromCurrentEngine(current, current: current))
        XCTAssertFalse(CloudSyncManager.isFromCurrentEngine(old, current: current))
        XCTAssertFalse(CloudSyncManager.isFromCurrentEngine(old, current: nil))
    }

    // 2. Conflitto: conta la copia attuale nello store, non quella (più
    //    vecchia) che stava viaggiando quando l'utente l'ha modificata di nuovo.
    func testConflictUsesStoreCopyWhenNewer() {
        XCTAssertTrue(SyncMerge.conflictWinsLocally(storeModified: t1, failedRecordModified: t0, serverModified: t0))
        XCTAssertFalse(SyncMerge.conflictWinsLocally(storeModified: t0, failedRecordModified: t0, serverModified: t1))
        XCTAssertTrue(SyncMerge.conflictWinsLocally(storeModified: nil, failedRecordModified: t1, serverModified: t0))
        XCTAssertFalse(SyncMerge.conflictWinsLocally(storeModified: t0, failedRecordModified: nil, serverModified: t0))
    }

    // 3. Un elemento appena cancellato qui non deve ricomparire per una
    //    modifica remota arrivata prima dell'invio della cancellazione.
    func testRemoteUpsertDoesNotResurrectPendingDelete() {
        let kept = SyncMerge.skippingPendingDeletes(["grade-A", "grade-B", "note-C"],
                                                    pendingDeletes: ["grade-B"])
        XCTAssertEqual(kept, ["grade-A", "note-C"])
    }

    // 4 + 9. Stato dopo una sincronizzazione riuscita.
    func testQuotaClearsOnlyWhenRecordsAreSavedAgain() {
        let now = Date()
        XCTAssertEqual(CloudSyncManager.statusAfterSync(current: .quotaExceeded, accountAvailable: true,
                                                        savedRecords: 3, quotaFailures: 0, now: now),
                       .upToDate(now))
        XCTAssertNil(CloudSyncManager.statusAfterSync(current: .quotaExceeded, accountAvailable: true,
                                                      savedRecords: 0, quotaFailures: 0, now: now))
        XCTAssertNil(CloudSyncManager.statusAfterSync(current: .quotaExceeded, accountAvailable: true,
                                                      savedRecords: 2, quotaFailures: 1, now: now))
    }

    func testNoSyncTimestampWithoutAccountOrWhilePaused() {
        let now = Date()
        XCTAssertNil(CloudSyncManager.statusAfterSync(current: .syncing, accountAvailable: false,
                                                      savedRecords: 0, quotaFailures: 0, now: now))
        XCTAssertNil(CloudSyncManager.statusAfterSync(current: .paused, accountAvailable: true,
                                                      savedRecords: 0, quotaFailures: 0, now: now))
        XCTAssertEqual(CloudSyncManager.statusAfterSync(current: .syncing, accountAvailable: true,
                                                        savedRecords: 0, quotaFailures: 0, now: now),
                       .upToDate(now))
    }

    // 6. Orario rimosso su un altro dispositivo: sparisce anche il PDF qui.
    func testRemoteScheduleRemovalDeletesSavedPDF() throws {
        let store = ScheduleStore()
        let original = store.schedule
        let pdf = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("loaded_schedule.pdf")
        let originalPDF = try? Data(contentsOf: pdf)
        defer {
            if let original { store.update(original) } else { store.clearSchedule() }
            if let originalPDF { try? originalPDF.write(to: pdf) }
            UserDefaults.standard.removeObject(forKey: "findmyteacher.scheduleClearedAt")
        }

        var local = ScheduleData.empty; local.id = "local"; local.edited = true
        store.update(local)
        try Data("%PDF-1.4".utf8).write(to: pdf)
        store.isPDFUnsupported = true

        store.applyRemote(schedule: nil, remoteModifiedAt: Date().addingTimeInterval(60), deleted: true)
        XCTAssertNil(store.schedule)
        XCTAssertNil(store.savedPDFURL)
        XCTAssertFalse(store.isPDFUnsupported)
    }

    // 8. Campi di una versione futura presenti nel record iCloud non vanno
    //    persi quando questo dispositivo modifica e rimanda l'elemento.
    func testUnknownFutureFieldsSurviveReupload() throws {
        let ours = Data(#"{"id":"X","value":8}"#.utf8)
        let previousRemote = Data(#"{"id":"X","value":6,"futureField":"keep"}"#.utf8)
        let merged = SyncMerge.mergePayload(ours: ours, previousRemote: previousRemote)
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: merged) as? [String: Any])
        XCTAssertEqual(dict["value"] as? Int, 8)
        XCTAssertEqual(dict["futureField"] as? String, "keep")
        XCTAssertEqual(SyncMerge.mergePayload(ours: ours, previousRemote: nil), ours)
    }

    func testOnlyPayloadsWithUnknownKeysAreKept() {
        let known = Data(#"{"id":"X","value":8}"#.utf8)
        XCTAssertTrue(SyncMerge.hasUnknownKeys(remote: Data(#"{"id":"X","value":8,"new":1}"#.utf8), known: known))
        XCTAssertFalse(SyncMerge.hasUnknownKeys(remote: Data(#"{"id":"X","value":5}"#.utf8), known: known))
    }
}
