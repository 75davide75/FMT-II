import XCTest
@testable import FMT_II

/// Backup dei voti manuali e istantanee ripristinabili.
@MainActor
final class GradeBackupsTests: XCTestCase {
    private var dir: URL!
    private var backups: GradeBackups!
    private var fileURL: URL { dir.appendingPathComponent("fmt_grades.json") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("GradeBackupsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        backups = GradeBackups(directory: dir.appendingPathComponent("Backups"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func g(_ subject: String) -> Grade { Grade(subject: subject) }

    func testManualBackupKeepsOnlyManualGrades() {
        let grades = [g("A"), g("B"), g("C")]
        backups.writeManualBackup(grades)
        XCTAssertEqual(Set(backups.manualBackup().map(\.id)), Set(grades.map(\.id)))
        XCTAssertEqual(backups.manualBackup().count, 3)
    }

    func testManualBackupMissingIsEmpty() {
        XCTAssertEqual(backups.manualBackup(), [])
    }

    func testPreLinkSnapshotIsNeverRotatedAway() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        backups.snapshot([g("L")], kind: .preLink, now: t0)
        for i in 1...15 {
            backups.snapshot([g("S\(i)")], kind: .preSync, now: t0.addingTimeInterval(Double(i) * 60))
        }
        let list = backups.list()
        XCTAssertEqual(list.count, 11)
        XCTAssertTrue(list.contains { $0.kind == .preLink })
    }

    func testRotationKeepsNewestTen() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<12 {
            backups.snapshot([g("S\(i)")], kind: .preSync, now: t0.addingTimeInterval(Double(i) * 60))
        }
        let list = backups.list()
        XCTAssertEqual(list.count, 10)
        let dates = list.map(\.date).sorted()
        XCTAssertEqual(dates.first, t0.addingTimeInterval(2 * 60))
        XCTAssertEqual(dates.last, t0.addingTimeInterval(11 * 60))
        // Il più recente è il primo.
        XCTAssertEqual(list.first?.date, t0.addingTimeInterval(11 * 60))
    }

    func testSnapshotSameSecondDoesNotOverwrite() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        backups.snapshot([g("A")], kind: .preSync, now: t)
        backups.snapshot([g("A"), g("B")], kind: .preSync, now: t)
        XCTAssertEqual(backups.list().count, 2)
    }

    func testListAndLoad() throws {
        let grades = [g("A"), g("B")]
        let s = try XCTUnwrap(backups.snapshot(grades, kind: .preLink))
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.kind, .preLink)
        XCTAssertEqual(backups.load(s)?.map(\.id), grades.map(\.id))
    }

    func testRestoreTakesSnapshotOfCurrentStateFirst() throws {
        let store = GradesStore(fileStore: GradeFileStore(url: fileURL), backups: backups)
        let old = [g("Vecchio1"), g("Vecchio2")]
        let s = try XCTUnwrap(backups.snapshot(old, kind: .preSync))
        store.add(g("Corrente"))
        let before = store.grades
        XCTAssertTrue(store.restore(s))
        XCTAssertEqual(Set(store.grades.map(\.id)), Set(old.map(\.id)))
        let pre = try XCTUnwrap(backups.list().first { $0.kind == .preRestore })
        XCTAssertEqual(Set((backups.load(pre) ?? []).map(\.id)), Set(before.map(\.id)))
    }

    func testRestoreFailsWithoutChangingAnything() throws {
        let store = GradesStore(fileStore: GradeFileStore(url: fileURL), backups: backups)
        store.add(g("Corrente"))
        let s = try XCTUnwrap(backups.snapshot([g("X")], kind: .preSync))
        try FileManager.default.removeItem(at: s.url)
        let before = store.grades
        XCTAssertFalse(store.restore(s))
        XCTAssertEqual(store.grades, before)
    }

    func testStoreSaveUpdatesManualBackup() {
        let store = GradesStore(fileStore: GradeFileStore(url: fileURL), backups: backups)
        let grade = g("Manuale")
        store.add(grade)
        XCTAssertTrue(backups.manualBackup().contains { $0.id == grade.id })
    }

    func testBlockedStoreNeverWritesBackup() throws {
        // File presente ma illeggibile dal disco: store bloccato, nessun backup scritto.
        try Data("{non json".utf8).write(to: fileURL)
        var fs = GradeFileStore(url: fileURL)
        fs.quarantineWriter = { _, _ in throw CocoaError(.fileWriteUnknown) }
        let store = GradesStore(fileStore: fs, backups: backups)
        backups.writeManualBackup([g("Buono")])
        store.add(g("Nuovo"))
        XCTAssertEqual(backups.manualBackup().map(\.subject), ["Buono"])
    }

    func testRestoreFailsWhenPreRestoreSnapshotCannotBeWritten() throws {
        // La cartella dei backup è un file normale: l'istantanea .preRestore non si può scrivere.
        let badDir = dir.appendingPathComponent("NonUnaCartella")
        try Data("x".utf8).write(to: badDir)
        let store = GradesStore(fileStore: GradeFileStore(url: fileURL), backups: GradeBackups(directory: badDir))
        store.add(g("Corrente"))
        let s = try XCTUnwrap(backups.snapshot([g("Altro")], kind: .preSync))
        let before = store.grades
        XCTAssertFalse(store.restore(s))
        XCTAssertEqual(store.grades, before)
    }

    func testRestoreWhileWriteBlockedChangesNothing() throws {
        try Data("{non json".utf8).write(to: fileURL)
        var fs = GradeFileStore(url: fileURL)
        fs.quarantineWriter = { _, _ in throw CocoaError(.fileWriteUnknown) }
        let store = GradesStore(fileStore: fs, backups: backups)
        let s = try XCTUnwrap(backups.snapshot([g("Snap")], kind: .preSync))
        let before = store.grades
        XCTAssertFalse(store.restore(s))
        XCTAssertEqual(store.grades, before)
        XCTAssertFalse(backups.list().contains { $0.kind == .preRestore })
    }
}
