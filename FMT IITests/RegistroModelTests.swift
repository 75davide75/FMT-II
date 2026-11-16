import XCTest
@testable import FMT_II

/// Modello del voto collegato al registro e compatibilità con la 2.2.
@MainActor
final class RegistroModelTests: XCTestCase {

    private func fixtureData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/grades-v2.2.json")
        return try Data(contentsOf: url)
    }

    private func makeOrigin(rawValue: String = "7½", value: Double = 7.5, manual: Grade? = nil) -> RegistroOrigin {
        let g = Grade(subject: "Matematica", teacher: "Rossi", value: value,
                      date: Date(timeIntervalSince1970: 1_700_000_000), type: .written, weight: 1)
        return RegistroOrigin(
            provider: .classeviva, accountKey: "S123", remoteId: "4567",
            rawValue: rawValue, numericValue: value, hasTime: false,
            remoteSubjectId: "12", remoteSubjectName: "MATEMATICA", remoteTeacher: "Rossi",
            remoteTypeRaw: "Scritto", remoteKind: .written, remoteWeight: nil, remotePeriod: "Q1",
            remoteComment: "bravo", notCounting: false, cancelled: false,
            remoteModifiedAt: nil, fingerprint: "abc",
            applied: AppliedValues(g),
            manualSnapshot: manual.map(ManualGradeSnapshot.init),
            status: .active)
    }

    func testV22FileDecodesIdentically() throws {
        let data = try fixtureData()
        let grades = try JSONDecoder().decode([Grade].self, from: data)
        XCTAssertEqual(grades.count, 4)
        XCTAssertEqual(grades[0].id.uuidString, "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(grades[0].value, 7.5)
        XCTAssertEqual(grades[0].subject, "Matematica")
        XCTAssertEqual(grades[0].date, Date(timeIntervalSinceReferenceDate: 782000000))
        XCTAssertEqual(grades[0].type, .written)
        XCTAssertEqual(grades[3].type, .giustifica)
        XCTAssertTrue(grades.allSatisfy { $0.origin == nil })
        let reencoded = try JSONEncoder().encode(grades)
        let json = try XCTUnwrap(String(data: reencoded, encoding: .utf8))
        XCTAssertFalse(json.contains("origin"))
        XCTAssertEqual(try JSONDecoder().decode([Grade].self, from: reencoded), grades)
    }

    func testOriginRoundTripsThroughJSON() throws {
        var manual = Grade(subject: "Mat", teacher: "R", value: 7, note: "mia", type: .oral, weight: 0.5)
        manual.modifiedAt = Date(timeIntervalSince1970: 1_600_000_000)
        var g = Grade(subject: "Matematica", value: 7.5)
        g.origin = makeOrigin(manual: manual)
        let data = try JSONEncoder().encode(g)
        let back = try JSONDecoder().decode(Grade.self, from: data)
        XCTAssertEqual(back, g)
        XCTAssertEqual(back.origin?.manualSnapshot?.restored(id: manual.id), manual)
    }

    /// Copia del decoder 2.2 (solo le chiavi note alla 2.2).
    private struct V22Grade: Decodable {
        var id: UUID, subject: String, teacher: String, value: Double, date: Date
        var note: String, type: GradeType, weight: Double, countsForAverage: Bool, modifiedAt: Date
        enum CodingKeys: String, CodingKey {
            case id, subject, teacher, value, date, note, type, weight, countsForAverage, modifiedAt
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
            teacher = try c.decodeIfPresent(String.self, forKey: .teacher) ?? ""
            value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 6.0
            date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
            type = try c.decodeIfPresent(GradeType.self, forKey: .type) ?? .oral
            weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1.0
            countsForAverage = try c.decodeIfPresent(Bool.self, forKey: .countsForAverage) ?? true
            modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? date
        }
    }

    func testV22CanDecodeGradeWithOrigin() throws {
        var g = Grade(subject: "Matematica", value: 7.5)
        g.origin = makeOrigin(manual: Grade(subject: "Mat"))
        let data = try JSONEncoder().encode(g)
        let old = try JSONDecoder().decode(V22Grade.self, from: data)
        XCTAssertEqual(old.id, g.id)
        XCTAssertEqual(old.value, 7.5)
        XCTAssertEqual(old.type, g.type)
    }

    func testDisplayValueUsesRawValueUntilUserEditsValue() {
        var g = Grade(subject: "Matematica", value: 7.5)
        g.origin = makeOrigin(rawValue: "7½", value: 7.5)
        XCTAssertEqual(g.displayValue, "7½")
        g.value = 8
        XCTAssertEqual(g.displayValue, 8.0.italianGrade)
        var gi = Grade(subject: "X", type: .giustifica)
        gi.origin = makeOrigin()
        XCTAssertEqual(gi.displayValue, "G")
    }

    func testIsImported() {
        var g = Grade(subject: "A")
        XCTAssertFalse(g.isImported)
        g.origin = makeOrigin()
        XCTAssertTrue(g.isImported)
        g.origin = makeOrigin(manual: Grade(subject: "A"))
        XCTAssertFalse(g.isImported)
    }

    func testRemoteKey() {
        XCTAssertEqual(makeOrigin().remoteKey, "classeviva|S123|4567")
    }

    func testDeterministicIDIsStable() {
        let a = RegistroIdentity.gradeID(provider: .classeviva, accountKey: "S123", remoteId: "4567")
        let b = RegistroIdentity.gradeID(provider: .classeviva, accountKey: "S123", remoteId: "4567")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, RegistroIdentity.gradeID(provider: .classeviva, accountKey: "S123", remoteId: "4568"))
        XCTAssertNotEqual(a, RegistroIdentity.gradeID(provider: .argo, accountKey: "S123", remoteId: "4567"))
        XCTAssertEqual(a.uuidString, "2072D1C3-A62E-5AA3-97B1-29E893DB463A")
        // Versione 5, variante RFC 4122.
        XCTAssertEqual(a.uuidString[a.uuidString.index(a.uuidString.startIndex, offsetBy: 14)], "5")
    }

    func testEditedFieldsDetectsChanges() {
        let g = Grade(subject: "Mat", teacher: "R", value: 7, date: Date(timeIntervalSince1970: 1_700_000_000), type: .written, weight: 1)
        let applied = AppliedValues(g)
        XCTAssertEqual(applied.editedFields(in: g), [])
        var h = g
        h.value = 8
        h.teacher = "Altro"
        h.countsForAverage = false
        XCTAssertEqual(applied.editedFields(in: h), [.value, .teacher, .countsForAverage])
        h = g; h.subject = "X"; h.type = .oral; h.weight = 0.5; h.date = g.date.addingTimeInterval(60)
        XCTAssertEqual(applied.editedFields(in: h), [.subject, .type, .weight, .date])
        h = g; h.note = "solo nota"
        XCTAssertEqual(applied.editedFields(in: h), [])
    }

    func testManualBackupIncludesManualSnapshotsOfLinkedGrades() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RegistroModelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let backups = GradeBackups(directory: dir)
        let manual = Grade(subject: "Solo manuale", value: 5)
        let original = Grade(subject: "Originale", teacher: "T", value: 6.5, note: "n", type: .written, weight: 0.5)
        var linked = original
        linked.subject = "Dal registro"; linked.value = 8
        linked.origin = makeOrigin(manual: original)
        var imported = Grade(subject: "Importato")
        imported.origin = makeOrigin()
        backups.writeManualBackup([manual, linked, imported])
        let saved = backups.manualBackup()
        XCTAssertEqual(Set(saved.map(\.id)), Set([manual.id, original.id]))
        XCTAssertEqual(saved.first { $0.id == original.id }, original)
        XCTAssertNil(saved.first { $0.id == original.id }?.origin)
    }
}
