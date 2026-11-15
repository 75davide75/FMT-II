import XCTest
@testable import FMT_II

/// Normalizzazione dei voti del registro (v2.3): stringa originale -> numero per le medie.
final class GradeValueNormalizerTests: XCTestCase {
    private func n(_ raw: String, provided: Double? = nil, max: Double = 10) -> Double? {
        GradeValueNormalizer.normalize(raw, providedNumeric: provided, maxGrade: max)
    }

    private func assertValue(_ raw: String, _ expected: Double?, file: StaticString = #filePath, line: UInt = #line) {
        let v = n(raw)
        if let expected {
            guard let v else { return XCTFail("\"\(raw)\" -> nil, atteso \(expected)", file: file, line: line) }
            XCTAssertEqual(v, expected, accuracy: 0.0001, "\"\(raw)\"", file: file, line: line)
        } else {
            XCTAssertNil(v, "\"\(raw)\" doveva essere nil", file: file, line: line)
        }
    }

    func testNumeriEModificatori() {
        let cases: [(String, Double)] = [
            ("7", 7), ("7+", 7.25), ("7-", 6.75), ("7++", 7.5), ("7--", 6.5),
            ("10-", 9.75), ("7.5", 7.5), ("7,25", 7.25), ("0", 0), ("10", 10)
        ]
        for (raw, v) in cases { assertValue(raw, v) }
    }

    func testMezzi() {
        for raw in ["7½", "7 ½", "7 1/2", "7  1/2"] { assertValue(raw, 7.5) }
    }

    func testCoppieAdiacenti() {
        for raw in ["6/7", "6-7", "6 / 7", "6 - 7"] { assertValue(raw, 6.5) }
        assertValue("7/8", 7.5)
        // Non adiacenti o rapporti tipo "3/10": non sono una coppia di voti.
        assertValue("3/10", nil)
        assertValue("6/8", nil)
    }

    func testGiudizi() {
        let cases: [(String, Double)] = [
            ("ottimo", 10), ("Distinto", 9), ("buono", 8), ("discreto", 7),
            ("sufficiente", 6), ("insufficiente", 5), ("gravemente insufficiente", 4),
            ("OTTIMO", 10), ("Ottimo.", 10), ("  Buono  ", 8),
            ("Gravemente   Insufficiente", 4), ("SUFFICIENTE.", 6)
        ]
        for (raw, v) in cases { assertValue(raw, v) }
    }

    func testNonNumerici() {
        for raw in ["N.C.", "NC", "n.c.", "non classificato", "Non Classificato", "", "   ",
                    "ass.", "Assente", "giust.", "abc", "7a", "--", "+", "7+-", "1/2/3"] {
            assertValue(raw, nil)
        }
    }

    func testSpaziIntorno() {
        assertValue(" 8 ", 8)
        assertValue("\t7+\n", 7.25)
        assertValue(" 7,5 ", 7.5)
    }

    func testFuoriScala() {
        assertValue("11", nil)
        assertValue("-1", nil)
        assertValue("10+", nil)
        assertValue("0-", nil)
        XCTAssertEqual(n("30", max: 30) ?? -1, 30, accuracy: 0.0001)
        XCTAssertNil(n("ottimo", max: 5), "giudizio oltre la scala dell'app")
    }

    func testValoreFornitoDalRegistro() {
        XCTAssertEqual(n("7/8", provided: 7.75) ?? -1, 7.75, accuracy: 0.0001)
        XCTAssertEqual(n("ottimo", provided: 9.5) ?? -1, 9.5, accuracy: 0.0001)
        XCTAssertEqual(n("", provided: 6) ?? -1, 6, accuracy: 0.0001)
        XCTAssertEqual(n("x", provided: 0) ?? -1, 0, accuracy: 0.0001)
        XCTAssertNil(n("7/8", provided: 12), "fuori scala: nil, non si ricade sulla stringa")
        XCTAssertNil(n("7", provided: -1))
        XCTAssertNil(n("7", provided: .nan))
        XCTAssertEqual(n("7", provided: nil) ?? -1, 7, accuracy: 0.0001)
    }
}
