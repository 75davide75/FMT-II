import XCTest
@testable import FMT_II

/// Ora d'inizio per classe (v2.2): traslazione delle fasce, vista docente,
/// riallineamento lezioni, rinomina e compatibilità con i dati 2.1.1.
final class ClassTimesTests: XCTestCase {
    private func lesson(_ id: String, _ cls: String, period: Int) -> Lesson {
        Lesson(id: id, className: cls, teacher: "ROSSI", day: .monday, dayLabel: "Lunedì",
               period: period, startTime: "08:10", endTime: "09:10", sourcePage: 0)
    }

    private func sample(perClass: Bool, starts: [String: String] = [:]) -> ScheduleData {
        var s = ScheduleData(
            id: "t", sourceName: "t", importedAt: "", startsFrom: nil,
            days: [DayInfo(id: .monday, label: "Lunedì")],
            periods: [Period(number: 1, startTime: "08:10", endTime: "09:10"),
                      Period(number: 2, startTime: "09:10", endTime: "10:10")],
            classes: ["1C", "3C"], teachers: ["ROSSI"],
            lessons: [lesson("a", "1C", period: 1), lesson("b", "3C", period: 1)],
            warnings: [])
        s.perClassStartTimes = perClass
        s.classStartTimes = starts
        return s
    }

    func testToggleOffIgnoresCustomStarts() {
        let s = sample(perClass: false, starts: ["3C": "09:10"])
        XCTAssertEqual(s.periods(forClass: "3C").map(\.startTime), ["08:10", "09:10"])
    }

    func testClassStartShiftsAllPeriods() {
        let s = sample(perClass: true, starts: ["3C": "09:10"])
        let p = s.periods(forClass: "3C")
        XCTAssertEqual(p.map(\.startTime), ["09:10", "10:10"])
        XCTAssertEqual(p.map(\.endTime), ["10:10", "11:10"])
        XCTAssertEqual(p.map(\.number), [1, 2])
    }

    func testClassWithoutCustomStartUsesGlobal() {
        let s = sample(perClass: true, starts: ["3C": "09:10"])
        XCTAssertEqual(s.periods(forClass: "1C").map(\.startTime), ["08:10", "09:10"])
    }

    func testEarlierClassStartShiftsBackwards() {
        let s = sample(perClass: true, starts: ["1C": "07:40"])
        XCTAssertEqual(s.periods(forClass: "1C").map(\.startTime), ["07:40", "08:40"])
        XCTAssertEqual(s.periods(forClass: "1C").last?.endTime, "09:40")
    }

    func testApplyManualEditsAlignsLessonsToTheirClass() {
        let s = applyManualEdits(sample(perClass: true, starts: ["3C": "09:10"]))
        let c1 = s.lessons.first { $0.className == "1C" }!
        let c3 = s.lessons.first { $0.className == "3C" }!
        XCTAssertEqual(c1.startTime, "08:10")
        XCTAssertEqual(c3.startTime, "09:10")
        XCTAssertEqual(c3.endTime, "10:10")
        XCTAssertNotEqual(c1.id, c3.id)
        XCTAssertTrue(s.edited)
    }

    func testTeacherViewUsesUnionOfStarts() {
        let s = sample(perClass: true, starts: ["3C": "09:10"])
        let rows = s.displayPeriods(forClass: nil)
        XCTAssertEqual(rows.map(\.startTime), ["08:10", "09:10", "10:10"])
        XCTAssertEqual(rows.map(\.number), [1, 2, 3])
    }

    func testTeacherViewWithToggleOffIsGlobal() {
        let s = sample(perClass: false, starts: ["3C": "09:10"])
        XCTAssertEqual(s.displayPeriods(forClass: nil).map(\.startTime), ["08:10", "09:10"])
    }

    func testTimeSlotsIncludeLastEnd() {
        let s = sample(perClass: true, starts: ["3C": "09:10"])
        XCTAssertEqual(s.timeSlots(forClass: "3C"), ["09:10", "10:10", "11:10"])
        XCTAssertEqual(s.timeSlots(forClass: nil), ["08:10", "09:10", "10:10", "11:10"])
    }

    func testRenameMovesCustomStart() {
        var s = sample(perClass: true, starts: ["3C": "09:10"])
        s.renameClassStartTime(from: "3C", to: "3D")
        XCTAssertNil(s.classStartTimes["3C"])
        XCTAssertEqual(s.classStartTimes["3D"], "09:10")
    }

    func testScheduleFrom211DecodesWithDefaults() throws {
        let json = """
        {"id":"x","sourceName":"a.pdf","importedAt":"","days":[],"periods":[],
         "classes":["1C"],"teachers":[],"lessons":[],"warnings":[],"edited":true}
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(ScheduleData.self, from: json)
        XCTAssertFalse(s.perClassStartTimes)
        XCTAssertTrue(s.classStartTimes.isEmpty)
    }
}
