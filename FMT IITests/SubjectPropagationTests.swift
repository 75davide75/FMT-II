import XCTest
@testable import FMT_II

/// Propagazione della materia inserita per un docente a tutte le sue altre
/// lezioni nel completamento dell'import parziale.
final class SubjectPropagationTests: XCTestCase {
    private func lesson(_ id: String, teacher: String) -> Lesson {
        Lesson(id: id, className: "5G", teacher: teacher, day: .monday, dayLabel: "Lunedì",
               period: 1, startTime: "08:00", endTime: "09:00", sourcePage: 0, subject: "")
    }

    func testPropagatesToEmptyFieldsOfSameTeacher() {
        let lessons = [lesson("a", teacher: "ROSSI"), lesson("b", teacher: "ROSSI"), lesson("c", teacher: "NERI")]
        let out = propagateSubject(edits: ["a": "Matematica"], autoFilled: [],
                                   lessons: lessons, teacher: "ROSSI", subject: "Matematica", sourceId: "a")
        XCTAssertEqual(out.edits["b"], "Matematica")
        XCTAssertNil(out.edits["c"])
        XCTAssertTrue(out.autoFilled.contains("b"))
        XCTAssertFalse(out.autoFilled.contains("a"))
    }

    func testDoesNotOverwriteManualEdits() {
        let lessons = [lesson("a", teacher: "ROSSI"), lesson("b", teacher: "ROSSI")]
        let out = propagateSubject(edits: ["a": "Matematica", "b": "Fisica"], autoFilled: [],
                                   lessons: lessons, teacher: "ROSSI", subject: "Matematica", sourceId: "a")
        XCTAssertEqual(out.edits["b"], "Fisica")
        XCTAssertFalse(out.autoFilled.contains("b"))
    }

    func testRefreshesPreviouslyAutoFilled() {
        let lessons = [lesson("a", teacher: "ROSSI"), lesson("b", teacher: "ROSSI")]
        let out = propagateSubject(edits: ["a": "Fisica", "b": "Matematica"], autoFilled: ["b"],
                                   lessons: lessons, teacher: "ROSSI", subject: "Fisica", sourceId: "a")
        XCTAssertEqual(out.edits["b"], "Fisica")
        XCTAssertTrue(out.autoFilled.contains("b"))
    }
}
