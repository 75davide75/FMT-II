import XCTest
@testable import FMT_II

/// Voti dal registro nella tab Voti: grafico, stato "rimosso", ora, dettagli.
final class RegistroGradeDisplayTests: XCTestCase {
    private var savedLanguage: AppLanguage = .italian
    override func setUp() { super.setUp(); savedLanguage = LanguageSettings.current; LanguageSettings.current = .italian }
    override func tearDown() { LanguageSettings.current = savedLanguage; super.tearDown() }

    private func grade(value: Double = 7, raw: String? = nil, numeric: Double? = 7, hasTime: Bool = false,
                       status: RemoteStatus = .active, period: String? = nil, comment: String? = nil,
                       teacher: String? = nil, kind: RemoteGradeKind? = nil, typeRaw: String? = nil,
                       imported: Bool = true) -> Grade {
        var g = Grade(subject: "Matematica", value: value, date: Date(timeIntervalSince1970: 1_780_000_000))
        guard imported else { return g }
        g.origin = RegistroOrigin(provider: .classeviva, accountKey: "a", remoteId: UUID().uuidString,
                                  rawValue: raw ?? "\(Int(value))", numericValue: numeric, hasTime: hasTime,
                                  remoteSubjectId: nil, remoteSubjectName: "MATEMATICA", remoteTeacher: teacher,
                                  remoteTypeRaw: typeRaw, remoteKind: kind, remoteWeight: nil, remotePeriod: period,
                                  remoteComment: comment, notCounting: false, cancelled: false, remoteModifiedAt: nil,
                                  fingerprint: "f", applied: AppliedValues(g), manualSnapshot: nil, status: status)
        return g
    }

    func testNonNumericGradesAreExcludedFromChartPoints() {
        let numeric = grade(value: 8, raw: "8", numeric: 8)
        let manual = grade(value: 6, imported: false)
        let judgement = grade(value: 6, raw: "N.C.", numeric: nil)
        var giustifica = grade(value: 6, imported: false); giustifica.type = .giustifica
        let points = RegistroGradeDisplay.chartPoints([judgement, numeric, giustifica, manual])
        XCTAssertEqual(Set(points.map(\.id)), [numeric.id, manual.id])
    }

    func testRemovedStatusLabel() {
        XCTAssertNil(RegistroGradeDisplay.removedLabel(for: grade()))
        XCTAssertNil(RegistroGradeDisplay.removedLabel(for: grade(imported: false)))
        let removed = grade(status: .removedFromRegistro)
        XCTAssertTrue(RegistroGradeDisplay.isRemoved(removed))
        XCTAssertEqual(RegistroGradeDisplay.removedLabel(for: removed), "Rimosso dal registro")
        LanguageSettings.current = .english
        XCTAssertEqual(RegistroGradeDisplay.removedLabel(for: removed), "Removed from the register")
    }

    func testKeepClearsOnlyTheRemovedState() {
        let removed = grade(status: .removedFromRegistro)
        let kept = RegistroGradeDisplay.keeping(removed)
        XCTAssertEqual(kept.origin?.status, .active)
        var expected = removed
        expected.origin?.status = .active
        XCTAssertEqual(kept, expected)
    }

    func testTimeShownOnlyWhenProvided() {
        XCTAssertNil(RegistroGradeDisplay.timeText(for: grade(hasTime: false)))
        XCTAssertNil(RegistroGradeDisplay.timeText(for: grade(imported: false)))
        XCTAssertNotNil(RegistroGradeDisplay.timeText(for: grade(hasTime: true)))
    }

    func testRegisterDetailListsOnlyWhatTheRegisterProvided() {
        XCTAssertNil(RegistroGradeDisplay.detail(for: grade(imported: false)))
        let bare = RegistroGradeDisplay.detail(for: grade(raw: "discreto", numeric: 7))!
        XCTAssertEqual(bare.rawValue, "discreto")
        XCTAssertNil(bare.time)
        XCTAssertNil(bare.period)
        XCTAssertNil(bare.comment)
        XCTAssertNil(bare.teacher)
        let full = RegistroGradeDisplay.detail(for: grade(hasTime: true, period: "Q1", comment: " bravo ",
                                                          teacher: "ROSSI", kind: .other, typeRaw: "Test"))!
        XCTAssertNotNil(full.time)
        XCTAssertEqual(full.period, "Q1")
        XCTAssertEqual(full.comment, "bravo")
        XCTAssertEqual(full.teacher, "ROSSI")
        XCTAssertEqual(full.typeLabel, "Altro")
        XCTAssertEqual(RegistroGradeDisplay.detail(for: grade(kind: .written))?.typeLabel, GradeType.written.label)
        XCTAssertNil(RegistroGradeDisplay.detail(for: grade(kind: nil))?.typeLabel)
    }

    func testBadgeAccessibilityKeepsTheFullValue() {
        let g = grade(value: 7, raw: "sufficiente", numeric: 6)
        XCTAssertEqual(RegistroGradeDisplay.accessibilityLabel(for: g), "sufficiente, Dal registro")
        XCTAssertEqual(RegistroGradeDisplay.accessibilityLabel(for: grade(status: .removedFromRegistro, imported: true)).hasSuffix("Rimosso dal registro"), true)
        XCTAssertEqual(RegistroGradeDisplay.accessibilityLabel(for: grade(imported: false)), "7")
    }

    /// "Tieni" dal foglio: le modifiche non salvate del modulo restano, il voto di
    /// partenza è quello attuale dello store (non la copia di quando si è aperto il foglio).
    func testKeepFromSheetKeepsUnsavedEditsAndLatestStoreState() {
        let opened = grade(status: .removedFromRegistro, comment: "vecchio")
        var latest = opened
        latest.origin?.remoteComment = "aggiornato dalla sync"
        latest.origin?.rawValue = "7+"
        var edited = opened            // modulo con modifiche non ancora salvate
        edited.note = "mia nota"
        edited.value = 8
        edited.weight = 0.5
        edited.countsForAverage = false

        let kept = RegistroGradeDisplay.keeping(latest, withEditsFrom: edited)
        XCTAssertEqual(kept.origin?.status, .active)
        XCTAssertEqual(kept.note, "mia nota")
        XCTAssertEqual(kept.value, 8)
        XCTAssertEqual(kept.weight, 0.5)
        XCTAssertFalse(kept.countsForAverage)
        XCTAssertEqual(kept.origin?.remoteComment, "aggiornato dalla sync", "i dati del registro vengono dallo store")
        XCTAssertEqual(kept.origin?.rawValue, "7+")
        XCTAssertEqual(kept.id, opened.id)
    }
}
