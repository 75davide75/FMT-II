import XCTest
@testable import FMT_II

/// Traduzione inglese: ogni testo del catalogo è tradotto, coi segnaposto
/// giusti, e l'app la usa davvero (giorni, plurali, etichette).
final class LocalizationCompletenessTests: XCTestCase {
    private var savedLanguage: AppLanguage = .italian

    override func setUp() {
        super.setUp()
        savedLanguage = LanguageSettings.current
    }

    override func tearDown() {
        LanguageSettings.current = savedLanguage
        super.tearDown()
    }

    /// Il catalogo sorgente (il simulatore legge il filesystem del Mac).
    private func catalog() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("FMT II/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json?["strings"] as? [String: Any])
    }

    func testEveryKeyHasAnEnglishTranslation() throws {
        let strings = try catalog()
        XCTAssertGreaterThan(strings.count, 400)
        let spec = try NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:lld|@|%)")
        func placeholders(_ s: String) -> [String] {
            spec.matches(in: s, range: NSRange(s.startIndex..., in: s))
                .map { String(s[Range($0.range, in: s)!]) }.sorted()
        }
        for (key, entry) in strings {
            let en = ((entry as? [String: Any])?["localizations"] as? [String: Any])?["en"] as? [String: Any]
            let unit = en?["stringUnit"] as? [String: Any]
            XCTAssertEqual(unit?["state"] as? String, "translated", "manca l'inglese per «\(key)»")
            if let value = unit?["value"] as? String {
                XCTAssertEqual(placeholders(key), placeholders(value), "segnaposto diversi in «\(key)»")
            }
        }
    }

    func testDayNamesFollowTheAppLanguage() {
        LanguageSettings.current = .english
        XCTAssertEqual(DayId.monday.displayName, "Monday")
        XCTAssertEqual(DayId.saturday.shortName, "Sat")
        LanguageSettings.current = .italian
        XCTAssertEqual(DayId.monday.displayName, "Lunedì")
        XCTAssertEqual(DayId.saturday.shortName, "Sab")
    }

    func testPluralsAndInterpolation() {
        LanguageSettings.current = .english
        XCTAssertEqual(gradesCountLabel(1), "1 grade")
        XCTAssertEqual(gradesCountLabel(3), "3 grades")
        XCTAssertEqual(L("termina tra \(5) min"), "ends in 5 min")
        LanguageSettings.current = .italian
        XCTAssertEqual(gradesCountLabel(1), "1 voto")
        XCTAssertEqual(gradesCountLabel(3), "3 voti")
        XCTAssertEqual(L("termina tra \(5) min"), "termina tra 5 min")
    }

    func testModelLabelsAreTranslated() {
        LanguageSettings.current = .english
        XCTAssertEqual(GradeType.oral.label, "Oral")
        XCTAssertEqual(NoteTaskType.interrogazione.label, "Oral test")
        XCTAssertEqual(CloudSyncManager.Status.noAccount.label, "Sign in to iCloud")
    }
}
