import XCTest
@testable import FMT_II

/// Salvataggio sicuro dei voti: un file illeggibile non viene mai sovrascritto.
@MainActor
final class GradeFileStoreTests: XCTestCase {
    private var dir: URL!
    private var fileURL: URL { dir.appendingPathComponent("fmt_grades.json") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("GradeFileStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func quarantineFiles() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.lastPathComponent.hasPrefix("fmt_grades.unreadable-") }
    }

    func testUnreadableFileIsQuarantinedNotOverwritten() throws {
        try Data("{non json".utf8).write(to: fileURL)
        let result = GradeFileStore(url: fileURL).load()
        XCTAssertEqual(result.grades, [])
        let q = try XCTUnwrap(result.quarantinedURL)
        XCTAssertTrue(q.lastPathComponent.hasPrefix("fmt_grades.unreadable-"))
        XCTAssertEqual(q.pathExtension, "json")
        XCTAssertEqual(try Data(contentsOf: q), Data("{non json".utf8))
        // L'originale non viene toccato dal load.
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("{non json".utf8))
    }

    func testMissingFileIsEmptyWithoutQuarantine() {
        let result = GradeFileStore(url: fileURL).load()
        XCTAssertEqual(result.grades, [])
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertNil(result.quarantinedURL)
        XCTAssertTrue(quarantineFiles().isEmpty)
    }

    func testOneCorruptGradeDoesNotLoseTheOthers() throws {
        let a = Grade(subject: "Matematica", value: 7)
        let b = Grade(subject: "Storia", value: 8)
        let enc = JSONEncoder()
        let ja = try JSONSerialization.jsonObject(with: enc.encode(a))
        let jb = try JSONSerialization.jsonObject(with: enc.encode(b))
        let bad: [String: Any] = ["subject": "Rotto", "value": "x"]
        let original = try JSONSerialization.data(withJSONObject: [ja, bad, jb])
        try original.write(to: fileURL)

        let result = GradeFileStore(url: fileURL).load()
        XCTAssertEqual(result.grades.count, 2)
        XCTAssertEqual(result.grades.map(\.id), [a.id, b.id])
        XCTAssertEqual(result.skippedCount, 1)
        let q = try XCTUnwrap(result.quarantinedURL)
        XCTAssertEqual(try Data(contentsOf: q), original)
    }

    func testSaveIsAtomicAndRoundTrips() throws {
        let grades = [
            Grade(subject: "Matematica", teacher: "Rossi", value: 7.5, note: "ok", type: .written, weight: 0.5),
            Grade(subject: "Storia", value: 6, type: .oral),
            Grade(subject: "Inglese", value: 9, countsForAverage: false),
        ]
        let store = GradeFileStore(url: fileURL)
        try store.save(grades)
        let result = store.load()
        XCTAssertEqual(result.grades, grades)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertNil(result.quarantinedURL)
        // Nessun file temporaneo rimasto accanto al file voti.
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(names, ["fmt_grades.json"])
    }

    func testGradesStoreDoesNotWipeUnreadableFile() throws {
        try Data("{non json".utf8).write(to: fileURL)
        let store = GradesStore(storageURL: fileURL)
        XCTAssertTrue(store.grades.isEmpty)
        store.add(Grade(subject: "Fisica", value: 8))
        let copies = quarantineFiles()
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(try Data(contentsOf: copies[0]), Data("{non json".utf8))
        // Il nuovo voto è stato salvato regolarmente.
        XCTAssertEqual(GradeFileStore(url: fileURL).load().grades.count, 1)
    }
}
