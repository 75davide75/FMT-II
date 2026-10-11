import XCTest
@testable import FMT_II

/// Correzioni dalla revisione della traduzione inglese.
final class LocalizationReviewTests: XCTestCase {
    private var savedLanguage: AppLanguage = .italian
    override func setUp() { super.setUp(); savedLanguage = LanguageSettings.current }
    override func tearDown() { LanguageSettings.current = savedLanguage; super.tearDown() }

    private var appSources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("FMT II")
    }

    private func catalog() throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: appSources.appendingPathComponent("Localizable.xcstrings"))) as? [String: Any]
        return try XCTUnwrap(json?["strings"] as? [String: Any])
    }

    // Rete di sicurezza: testo passato come etichetta a un componente, senza L().
    func testNoUntranslatedLabelArguments() throws {
        let pattern = try NSRegularExpression(pattern: #"\b(label|title|text|placeholder|subtitle|detail|screen):\s*"([A-ZÀ-Ý][^"]*[a-zà-ÿ][^"]*)""#)
        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" && url.lastPathComponent != "DemoSeed.swift" {
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                let range = NSRange(line.startIndex..., in: line)
                for m in pattern.matches(in: line, range: range) {
                    let literal = String(line[Range(m.range(at: 2), in: line)!])
                    if literal == "FindMyTeacher" { continue }
                    offenders.append("\(url.lastPathComponent):\(i + 1) «\(literal)»")
                }
            }
        }
        XCTAssertEqual(offenders, [], "testi non tradotti")
    }

    // Identificativi (icone SF, chiavi) non devono passare dal catalogo.
    func testIdentifiersAreNotInTheCatalog() throws {
        let strings = try catalog()
        for id in ["checkmark", "textformat", "calendar", "monday", "tuesday", "wednesday",
                   "thursday", "friday", "saturday", "n"] {
            XCTAssertNil(strings[id], "identificativo nel catalogo: \(id)")
        }
    }

    // Nessuna localizzazione «it» nel catalogo: altrimenti Xcode genera
    // it.lproj e l'italiano di L() smette di usare il testo sorgente.
    func testCatalogHasNoItalianLocalizations() throws {
        for (key, entry) in try catalog() {
            let locs = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            XCTAssertNil(locs["it"], "localizzazione it per «\(key)»")
        }
    }

    // Elenchi tradotti ricalcolati a ogni lettura (non congelati alla prima).
    func testSubjectSuggestionsFollowTheLanguage() {
        LanguageSettings.current = .italian
        XCTAssertTrue(SubjectSuggestions.all.contains("Matematica"))
        LanguageSettings.current = .english
        XCTAssertTrue(SubjectSuggestions.all.contains("Maths"))
    }

    // Messaggi di rifiuto del PDF: il giorno nella lingua dell'app.
    func testRejectMessagesUseTranslatedDayNames() {
        LanguageSettings.current = .english
        XCTAssertTrue(ScheduleRejectReason.implausibleDay(.sunday).message.contains("Sunday"))
        XCTAssertTrue(ScheduleRejectReason.teacherConflict(teacher: "ROSSI", day: .monday, time: "08:10")
            .message.contains("Monday 08:10"))
    }

    // Lingua scelta nelle Impostazioni di iOS (per-app): viene adottata.
    func testSystemPerAppLanguageIsAdopted() {
        XCTAssertEqual(AppLanguage.systemOverride(appleLanguages: ["en-IT"], lastWritten: "it"), .english)
        XCTAssertEqual(AppLanguage.systemOverride(appleLanguages: ["it"], lastWritten: "en"), .italian)
        XCTAssertNil(AppLanguage.systemOverride(appleLanguages: ["it"], lastWritten: "it"))
        XCTAssertNil(AppLanguage.systemOverride(appleLanguages: ["fr"], lastWritten: "it"))
        XCTAssertNil(AppLanguage.systemOverride(appleLanguages: nil, lastWritten: "it"))
    }

    // Numeri e «N/D» nella lingua dell'app.
    func testDeltaAndNotAvailableAreLocalized() {
        LanguageSettings.current = .english
        XCTAssertEqual(gradeDeltaText(0.5), "+0.5")
        XCTAssertEqual(L("N/D"), "N/A")
        LanguageSettings.current = .italian
        XCTAssertEqual(gradeDeltaText(0.5), "+0,5")
        XCTAssertEqual(gradeDeltaText(-1), "−1")
    }
}
