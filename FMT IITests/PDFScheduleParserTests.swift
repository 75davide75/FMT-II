import XCTest
@testable import FMT_II

/// XCTest suite for the generalized PDF parser: the three real PDFs, the two
/// legacy formats (regression), and every synthetic accept/reject scenario.
final class PDFScheduleParserTests: XCTestCase {

    // MARK: Helpers

    private func realPDF(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        _ = url
        // Simulator processes see the host filesystem: load from ~/Downloads.
        let path = "/Users/davidesogos/Downloads/\(name)"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("PDF reale non presente: \(path)")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    private func assertPartial(_ outcome: ScheduleImportOutcome, missing: ScheduleField,
                               file: StaticString = #filePath, line: UInt = #line) -> ScheduleData? {
        if case .partial(let s, let m) = outcome {
            XCTAssertEqual(m, missing, "elemento mancante inatteso", file: file, line: line)
            return s
        }
        XCTFail("atteso import parziale (\(missing)), ottenuto \(outcome)", file: file, line: line)
        return nil
    }

    private func assertRejected(_ outcome: ScheduleImportOutcome,
                                file: StaticString = #filePath, line: UInt = #line) -> ScheduleRejectReason? {
        if case .rejected(let r) = outcome { return r }
        XCTFail("atteso rifiuto totale, ottenuto \(outcome)", file: file, line: line)
        return nil
    }

    // MARK: Real PDFs (goal condition 6)

    func testRealCassiaImportsWithSubjects() throws {
        let data = try realPDF("Orario-definitivo-per-classe-Cassia-734 (1).pdf")
        let outcome = importSchedulePDF(data: data, sourceName: "cassia.pdf")
        guard let s = assertPartial(outcome, missing: .teacher) else { return }
        XCTAssertEqual(s.classes, ["1BL", "2BL", "3BL", "4BL", "5BL", "2EL", "3EL", "4EL"])
        XCTAssertEqual(s.lessons.count, 231)
        XCTAssertTrue(s.lessons.allSatisfy { !$0.subject.isEmpty && $0.teacher.isEmpty })
        XCTAssertEqual(Set(s.lessons.map { $0.day }).count, 5)
        // Spot-check against the printed table.
        let mon1BL = s.lessons.first { $0.className == "1BL" && $0.day == .monday && $0.period == 1 }
        XCTAssertEqual(mon1BL?.subject, "INGLESE")
    }

    func testRealGallinaImportsWithSubjects() throws {
        let data = try realPDF("Orario-definitivo-per-classe-Gallina-Scientifico.pdf")
        let outcome = importSchedulePDF(data: data, sourceName: "gallina.pdf")
        guard let s = assertPartial(outcome, missing: .teacher) else { return }
        XCTAssertEqual(s.classes.count, 12)
        XCTAssertTrue(s.classes.contains("1BS") && s.classes.contains("3GS"))
        XCTAssertEqual(s.lessons.count, 342)
        let mon1BS = s.lessons.first { $0.className == "1BS" && $0.day == .monday && $0.period == 1 }
        XCTAssertEqual(mon1BS?.subject, "latino/geostoria")
    }

    func testRealCentraleScannedImportsViaOCR() throws {
        let data = try realPDF("Orario_def_materie_Centrale.pdf")
        let outcome = importSchedulePDF(data: data, sourceName: "centrale.pdf")
        guard let s = assertPartial(outcome, missing: .teacher) else { return }
        // 15 classes on page 1 (A/B/C) + 6 on page 2 (D + 1I).
        XCTAssertEqual(s.classes.count, 21)
        XCTAssertTrue(s.classes.contains("1A") && s.classes.contains("5C") && s.classes.contains("1I"))
        // Six-day week including Saturday.
        XCTAssertEqual(s.days.map { $0.id }, [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        XCTAssertGreaterThan(s.lessons.count, 450)
        let mon1A = s.lessons.filter { $0.className == "1A" && $0.day == .monday }.sorted { $0.period < $1.period }
        XCTAssertEqual(mon1A.first?.subject, "Ingl")
    }

    // MARK: Legacy format regression (the two formats supported before)

    func testLegacyClassFormatUnchanged() throws {
        let path = "/Users/davidesogos/Desktop/orario classi.pdf"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("orario classi.pdf non presente")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let legacy = try parseSchedulePDF(data: data, sourceName: "orario classi.pdf")
        let outcome = importSchedulePDF(data: data, sourceName: "orario classi.pdf")
        guard let s = assertPartial(outcome, missing: .subject) else { return }
        XCTAssertEqual(s.lessons.count, legacy.lessons.count)
        XCTAssertEqual(s.classes, legacy.classes)
        XCTAssertEqual(s.teachers, legacy.teachers)
        XCTAssertEqual(Set(s.lessons.map { $0.id }), Set(legacy.lessons.map { $0.id }))
        XCTAssertEqual(s.lessons.count, 822)
    }

    func testLegacyTeacherGlobalFormatUnchanged() throws {
        let data = SyntheticPDF.legacyTeacherGlobal()
        let legacy = try parseSchedulePDF(data: data, sourceName: "docenti.pdf")
        XCTAssertFalse(legacy.lessons.isEmpty)
        let outcome = importSchedulePDF(data: data, sourceName: "docenti.pdf")
        guard let s = assertPartial(outcome, missing: .subject) else { return }
        XCTAssertEqual(s.lessons.count, legacy.lessons.count)
        XCTAssertEqual(s.classes, legacy.classes)
        XCTAssertEqual(s.teachers, legacy.teachers)
        XCTAssertEqual(Set(s.lessons.map { $0.id }), Set(legacy.lessons.map { $0.id }))
    }

    // MARK: One missing element -> partial import (goal condition 7)

    func testMissingTeacherIsPartial() {
        let outcome = importSchedulePDF(data: SyntheticPDF.missingTeacher(), sourceName: "x.pdf")
        guard let s = assertPartial(outcome, missing: .teacher) else { return }
        XCTAssertEqual(s.classes, ["1A", "2A", "3A"])
        XCTAssertEqual(s.lessons.count, 36)
    }

    func testMissingSubjectIsPartial() {
        let outcome = importSchedulePDF(data: SyntheticPDF.missingSubject(), sourceName: "x.pdf")
        guard let s = assertPartial(outcome, missing: .subject) else { return }
        XCTAssertEqual(s.teachers.count, 6)
    }

    func testMissingClassesIsPartial() {
        let outcome = importSchedulePDF(data: SyntheticPDF.missingClasses(), sourceName: "x.pdf")
        guard let s = assertPartial(outcome, missing: .classes) else { return }
        XCTAssertFalse(s.lessons.isEmpty)
        XCTAssertTrue(s.lessons.allSatisfy { !$0.subject.isEmpty && !$0.teacher.isEmpty })
    }

    func testMissingDayTimeIsPartial() {
        let outcome = importSchedulePDF(data: SyntheticPDF.missingDayTime(), sourceName: "x.pdf")
        guard let s = assertPartial(outcome, missing: .dayTime) else { return }
        XCTAssertEqual(s.classes, ["1A", "2A", "3A", "4A"])
        XCTAssertTrue(s.lessons.isEmpty)
    }

    // MARK: Total rejection (goal condition 8)

    func testMissingTwoElementsIsRejected() {
        let reason = assertRejected(importSchedulePDF(data: SyntheticPDF.missingTwoElements(), sourceName: "x.pdf"))
        if case .missingElements(let fields)? = reason {
            XCTAssertEqual(Set(fields), Set([.classes, .teacher]))
        } else {
            XCTFail("atteso missingElements, ottenuto \(String(describing: reason))")
        }
    }

    func testUnstructuredTextIsRejected() {
        let reason = assertRejected(importSchedulePDF(data: SyntheticPDF.unstructured(), sourceName: "x.pdf"))
        XCTAssertEqual(reason, .unrecognizedStructure)
    }

    func testInvalidFileIsRejected() {
        let reason = assertRejected(importSchedulePDF(data: SyntheticPDF.notAPDF(), sourceName: "x.pdf"))
        XCTAssertEqual(reason, .invalidPDF)
    }

    // MARK: Conflicts and implausible times (goal condition 9)

    func testTeacherInTwoClassesSameHourIsRejected() {
        let reason = assertRejected(importSchedulePDF(data: SyntheticPDF.teacherConflict(), sourceName: "x.pdf"))
        if case .teacherConflict(let teacher, _, _)? = reason {
            XCTAssertEqual(teacher, "ROSSI")
        } else {
            XCTFail("atteso teacherConflict, ottenuto \(String(describing: reason))")
        }
    }

    func testClassWithTwoSubjectsSameHourIsRejected() {
        let reason = assertRejected(importSchedulePDF(data: SyntheticPDF.subjectConflict(), sourceName: "x.pdf"))
        if case .subjectConflict = reason! {} else {
            XCTFail("atteso subjectConflict, ottenuto \(String(describing: reason))")
        }
    }

    func testDayOutsideMonSatIsRejected() {
        let reason = assertRejected(importSchedulePDF(data: SyntheticPDF.implausibleDay(), sourceName: "x.pdf"))
        if case .implausibleDay(let day)? = reason {
            XCTAssertEqual(day, .sunday)
        } else {
            XCTFail("atteso implausibleDay, ottenuto \(String(describing: reason))")
        }
    }

    func testTimeOutside7to19IsRejected() {
        let reason = assertRejected(importSchedulePDF(data: SyntheticPDF.implausibleTime(), sourceName: "x.pdf"))
        if case .implausibleTime = reason! {} else {
            XCTFail("atteso implausibleTime, ottenuto \(String(describing: reason))")
        }
    }

    // MARK: Data-schema safety

    func testNormalizeKeepsSubjects() {
        let outcome = importSchedulePDF(data: SyntheticPDF.missingTeacher(), sourceName: "x.pdf")
        guard case .partial(let s, _) = outcome else { return XCTFail() }
        let normalized = normalizeScheduleTimes(s)
        XCTAssertTrue(normalized.lessons.allSatisfy { !$0.subject.isEmpty })
        XCTAssertEqual(Set(normalized.lessons.map { $0.id }).count, normalized.lessons.count, "id lezioni non unici")
    }
}
