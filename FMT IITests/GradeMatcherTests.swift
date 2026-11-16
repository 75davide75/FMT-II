import XCTest
@testable import FMT_II

final class GradeMatcherTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    private lazy var day: Date = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 10))!

    private func remote(value: Double? = 7, raw: String = "7", date: Date? = nil,
                        kind: RemoteGradeKind? = .oral, teacher: String? = nil) -> VotoRemoto {
        VotoRemoto(provider: .classeviva, remoteId: "r1", date: date ?? day, hasTime: false,
                   subjectId: nil, subjectName: "MATEMATICA", teacher: teacher, rawValue: raw,
                   numericValue: value, kind: kind, kindRaw: nil, weight: nil, period: nil,
                   comment: nil, notCounting: false, cancelled: false, remoteModifiedAt: nil)
    }

    private func grade(subject: String = "Matematica", value: Double = 7, offsetDays: Int = 0,
                       type: GradeType = .oral, teacher: String = "") -> Grade {
        var g = Grade()
        g.subject = subject
        g.value = value
        g.date = cal.date(byAdding: .day, value: offsetDays, to: day)!
        g.type = type
        g.teacher = teacher
        return g
    }

    private func run(_ r: VotoRemoto, _ grades: [Grade]) -> [MatchCandidate] {
        GradeMatcher.candidates(for: r, appSubject: "Matematica", among: grades, calendar: cal)
    }

    func testSameDaySameValueIsCertain() {
        let g = grade()
        let c = run(remote(), [g])
        XCTAssertEqual(c.map(\.gradeID), [g.id])
        XCTAssertEqual(c[0].score, 1.2, accuracy: 0.001)
        XCTAssertTrue(GradeMatcher.isCertain(c))
    }

    func testDifferentValueIsNeverACandidate() {
        XCTAssertTrue(run(remote(), [grade(value: 8)]).isEmpty)
    }

    func testDifferentSubjectIsNeverACandidate() {
        XCTAssertTrue(run(remote(), [grade(subject: "Storia")]).isEmpty)
    }

    func testSubjectComparisonIsNormalized() {
        XCTAssertEqual(run(remote(), [grade(subject: " matematica ")]).count, 1)
    }

    func testFourDaysApartIsExcluded() {
        XCTAssertTrue(run(remote(), [grade(offsetDays: 4)]).isEmpty)
        XCTAssertEqual(run(remote(), [grade(offsetDays: -3)]).count, 1)
    }

    func testTwoSameDayCandidatesAreNotCertain() {
        let c = run(remote(), [grade(), grade()])
        XCTAssertEqual(c.count, 2)
        XCTAssertFalse(GradeMatcher.isCertain(c))
    }

    func testOneDayApartWithSameTypeIsCertain() {
        let c = run(remote(), [grade(offsetDays: 1)])
        XCTAssertEqual(c[0].score, 0.9, accuracy: 0.001)
        XCTAssertTrue(GradeMatcher.isCertain(c))
    }

    func testOneDayApartWithoutTypeIsNotCertain() {
        let c = run(remote(kind: nil), [grade(offsetDays: 1)])
        XCTAssertEqual(c[0].score, 0.7, accuracy: 0.001)
        XCTAssertFalse(GradeMatcher.isCertain(c))
    }

    func testDifferentKnownTypePenalty() {
        let c = run(remote(kind: .written), [grade(type: .oral)])
        XCTAssertEqual(c[0].score, 0.7, accuracy: 0.001)
    }

    func testTeacherBonusOnlyWhenBothPresent() {
        let both = run(remote(kind: nil, teacher: "ROSSI "), [grade(teacher: "rossi")])
        XCTAssertEqual(both[0].score, 1.1, accuracy: 0.001)
        let one = run(remote(kind: nil, teacher: "ROSSI"), [grade()])
        XCTAssertEqual(one[0].score, 1.0, accuracy: 0.001)
    }

    func testNonNumericRemoteComparesDisplayValue() {
        var g = grade(); g.type = .giustifica; g.value = 0
        XCTAssertEqual(run(remote(value: nil, raw: "g", kind: nil), [g]).count, 1)
        XCTAssertTrue(run(remote(value: nil, raw: "ottimo", kind: nil), [g]).isEmpty)
    }

    func testNumericRemoteNeverMatchesGiustifica() {
        var g = grade(); g.type = .giustifica; g.value = 7
        XCTAssertTrue(run(remote(), [g]).isEmpty)
    }

    func testAlreadyLinkedGradeIsIgnored() {
        var g = grade()
        g.origin = RegistroOrigin(provider: .classeviva, accountKey: "a", remoteId: "x", rawValue: "7",
                                  numericValue: 7, hasTime: false, remoteSubjectId: nil,
                                  remoteSubjectName: "MATEMATICA", remoteTeacher: nil, remoteTypeRaw: nil,
                                  remoteKind: .oral, remoteWeight: nil, remotePeriod: nil, remoteComment: nil,
                                  notCounting: false, cancelled: false, remoteModifiedAt: nil,
                                  fingerprint: "f", applied: AppliedValues(g), manualSnapshot: nil, status: .active)
        XCTAssertTrue(run(remote(), [g]).isEmpty)
    }

    func testTieOrderIsDeterministic() {
        let a = grade(offsetDays: 1), b = grade(offsetDays: 0)
        let c = run(remote(), [a, b])
        XCTAssertEqual(c.map(\.gradeID), [b.id, a.id])
    }
}
