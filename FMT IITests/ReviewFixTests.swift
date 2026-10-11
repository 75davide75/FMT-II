import XCTest
import CloudKit
@testable import FMT_II

/// Correzioni dalla revisione finale della 2.2 (sync iCloud + inizio per classe).
@MainActor
final class ReviewFixTests: XCTestCase {

    // Critico: gli store sono unici per l'app, non per finestra (multi-scena iPad,
    // scene scollegate da iOS): la sync non deve mai restare senza store.
    func testAllWindowsShareTheSameStores() {
        XCTAssertTrue(AppStores.shared.grades === AppStores.shared.grades)
        XCTAssertTrue(AppStores.shared.notes === AppStores.shared.notes)
        XCTAssertTrue(AppStores.shared.schedule === AppStores.shared.schedule)
    }

    // Push silenziose di CloudKit: serve la background mode nel build reale.
    func testRemoteNotificationBackgroundModeIsInInfoPlist() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        XCTAssertTrue(modes.contains("remote-notification"))
    }

    // La rinomina di una classe (builder o editor) si porta dietro lezioni e ora d'inizio.
    func testRenameClassMovesLessonsAndCustomStart() {
        var s = ScheduleData.empty
        s.classes = ["1C", "3C"]
        s.lessons = [Lesson(id: "a", className: "1C", teacher: "T", day: .monday, dayLabel: "Lunedì",
                            period: 1, startTime: "08:10", endTime: "09:10", sourcePage: 0)]
        s.perClassStartTimes = true
        s.classStartTimes = ["1C": "09:10"]
        s.renameClass(from: "1C", to: "1D")
        XCTAssertEqual(s.classes, ["1D", "3C"])
        XCTAssertEqual(s.lessons.first?.className, "1D")
        XCTAssertEqual(s.classStartTimes, ["1D": "09:10"])
    }

    // Toggle per classe: solo le classi davvero personalizzate hanno un orario
    // proprio; le altre seguono l'inizio predefinito anche se cambia dopo.
    func testClassStartEqualToDefaultFollowsDefault() {
        var s = ScheduleData.empty
        s.classes = ["1C", "3C"]
        s.periods = [Period(number: 1, startTime: "08:10", endTime: "09:10")]
        s.perClassStartTimes = true
        s.setClassStart("09:10", forClass: "3C")
        s.setClassStart("08:10", forClass: "1C")
        XCTAssertEqual(s.classStartTimes, ["3C": "09:10"])
        s.periods = [Period(number: 1, startTime: "08:00", endTime: "09:00")]
        XCTAssertEqual(s.periods(forClass: "1C").first?.startTime, "08:00")
    }

    // Cambio di Apple ID: i dati locali non finiscono da soli nell'iCloud di un altro.
    func testAccountChangesNeverUploadLocalDataAutomatically() {
        let a = CKRecord.ID(recordName: "a"), b = CKRecord.ID(recordName: "b")
        XCTAssertFalse(CloudSyncManager.uploadsAllLocalData(after: .signIn(currentUser: a)))
        XCTAssertFalse(CloudSyncManager.uploadsAllLocalData(after: .signOut(previousUser: a)))
        XCTAssertFalse(CloudSyncManager.uploadsAllLocalData(after: .switchAccounts(previousUser: a, currentUser: b)))
    }

    // Dati iCloud eliminati dall'utente: non vanno ricaricati da soli.
    func testZoneDeletedByUserIsNotReuploaded() {
        XCTAssertFalse(CloudSyncManager.reuploadsAfterZoneDeletion(reason: .deleted))
        XCTAssertFalse(CloudSyncManager.reuploadsAfterZoneDeletion(reason: .purged))
        XCTAssertTrue(CloudSyncManager.reuploadsAfterZoneDeletion(reason: .encryptedDataReset))
        XCTAssertEqual(CloudSyncManager.Status.paused.label, "In pausa")
        XCTAssertTrue(CloudSyncManager.Status.paused.isProblem)
    }

    // Orario 2.1.1: la data di modifica viene dall'import, così tra due
    // dispositivi vince l'orario importato più di recente (non un pareggio).
    func testLegacyScheduleUsesImportedAtAsModifiedAt() throws {
        let json = #"{"id":"x","importedAt":"2026-03-01T10:00:00Z","classes":[]}"#
        let s = try JSONDecoder().decode(ScheduleData.self, from: Data(json.utf8))
        XCTAssertEqual(s.modifiedAt, ISO8601DateFormatter().date(from: "2026-03-01T10:00:00Z"))
    }

    // Un orario locale sostituito da iCloud resta recuperabile.
    func testRemoteScheduleReplacingLocalKeepsBackup() throws {
        let store = ScheduleStore()
        let original = store.schedule
        defer {
            if let original { store.update(original) } else { store.clearSchedule() }
            UserDefaults.standard.removeObject(forKey: "findmyteacher.scheduleClearedAt")
        }
        try? FileManager.default.removeItem(at: ScheduleStore.replacedScheduleBackupURL)

        var local = ScheduleData.empty; local.id = "local"; local.edited = true
        store.update(local)
        var remote = ScheduleData.empty; remote.id = "remote"; remote.edited = true
        store.applyRemote(schedule: remote, remoteModifiedAt: Date().addingTimeInterval(60), deleted: false)

        XCTAssertEqual(store.schedule?.id, "remote")
        let backup = try JSONDecoder().decode(ScheduleData.self,
                                              from: Data(contentsOf: ScheduleStore.replacedScheduleBackupURL))
        XCTAssertEqual(backup.id, "local")
    }
}
