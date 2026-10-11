import XCTest
@testable import FMT_II

/// Store ↔ sync: le modifiche locali aggiornano `modifiedAt`, quelle remote
/// vengono unite (mai sostituzione totale) e un orario locale più recente
/// non viene sovrascritto da uno remoto più vecchio.
@MainActor
final class StoreSyncTests: XCTestCase {
    func testGradeUpdateStampsAndRemoteMerges() {
        let store = GradesStore()
        let original = store.grades
        defer { store.replaceAll(original) }

        var g = Grade(); g.value = 5; g.modifiedAt = .distantPast
        store.add(g)
        let stamped = store.grades.first { $0.id == g.id }!
        XCTAssertGreaterThan(stamped.modifiedAt, Date().addingTimeInterval(-5))

        var remote = stamped; remote.value = 9; remote.modifiedAt = Date().addingTimeInterval(60)
        let other = Grade()
        store.applyRemote(upserts: [remote, other], deletions: [])
        XCTAssertEqual(store.grades.first { $0.id == g.id }?.value, 9)
        XCTAssertTrue(store.grades.contains { $0.id == other.id })

        store.applyRemote(upserts: [], deletions: [other.id])
        XCTAssertFalse(store.grades.contains { $0.id == other.id })
    }

    func testNoteArchiveStampsModifiedAt() {
        let store = NotesStore()
        let original = store.notes
        defer { store.replaceAll(original) }

        var n = Note(); n.modifiedAt = .distantPast
        store.add(n)
        store.archive(ids: [n.id])
        let archived = store.notes.first { $0.id == n.id }!
        XCTAssertTrue(archived.isArchived)
        XCTAssertGreaterThan(archived.modifiedAt, Date().addingTimeInterval(-5))
    }

    func testOlderRemoteScheduleDoesNotOverwriteNewerLocal() {
        let store = ScheduleStore()
        let original = store.schedule
        defer { if let original { store.update(original) } else { store.clearSchedule() } }

        var local = ScheduleData.empty; local.id = "local"; local.edited = true
        store.update(local)
        var remote = ScheduleData.empty; remote.id = "remote"; remote.edited = true
        store.applyRemote(schedule: remote, remoteModifiedAt: .distantPast, deleted: false)
        XCTAssertEqual(store.schedule?.id, "local")

        store.applyRemote(schedule: nil, remoteModifiedAt: Date().addingTimeInterval(60), deleted: true)
        XCTAssertNil(store.schedule)
        XCTAssertNotNil(store.clearedAt)
    }
}
