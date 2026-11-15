import XCTest
@testable import FMT_II

/// Messaggi del registro per l'utente: ogni codice d'errore ha un testo chiaro
/// e specifico, tradotto in inglese.
final class RegistroTextTests: XCTestCase {
    private var savedLanguage: AppLanguage = .italian
    override func setUp() { super.setUp(); savedLanguage = LanguageSettings.current }
    override func tearDown() { LanguageSettings.current = savedLanguage; super.tearDown() }

    private let codes = ["invalidCredentials", "rateLimited", "network", "sessionExpired", "notSupported",
                         "unexpectedFormat:client-version", "unexpectedFormat:profili", "unexpectedFormat",
                         "providerUnavailable", "alreadyConnected", "differentAccount", "keychain", "cancelled",
                         "writeBlocked", "snapshotFailed", "invalidPlan:deletion"]

    func testEveryKnownCodeHasItsOwnMessage() {
        LanguageSettings.current = .italian
        let generic = RegistroText.message(forCode: "qualcosa-di-nuovo")
        var seen = Set<String>()
        for code in codes {
            let m = RegistroText.message(forCode: code)
            XCTAssertNotEqual(m, generic, code)
            XCTAssertTrue(seen.insert(m).inserted, "messaggio ripetuto per \(code)")
            XCTAssertFalse(m.contains(code), "nessun codice tecnico nel testo")
        }
        XCTAssertEqual(RegistroText.message(forCode: "writeFailed"), RegistroText.message(forCode: "writeBlocked"))
    }

    func testProviderErrorsMapToTheRightMessage() {
        LanguageSettings.current = .italian
        XCTAssertTrue(RegistroText.message(for: RegistroError.unexpectedFormat("client-version")).contains("aggiornamento di FMT"))
        XCTAssertTrue(RegistroText.message(for: RegistroError.unexpectedFormat("profili")).contains("più studenti"))
        XCTAssertTrue(RegistroText.message(for: RegistroError.unexpectedFormat("choices")).contains("più studenti"))
        XCTAssertTrue(RegistroText.message(for: RegistroError.invalidCredentials).contains("password"))
        XCTAssertTrue(RegistroText.message(for: RegistroCoordinatorError.differentAccount).contains("altro account"))
        XCTAssertTrue(RegistroText.message(for: URLError(.timedOut)).contains("imprevisto"))
    }

    func testMessagesAreTranslated() {
        LanguageSettings.current = .english
        XCTAssertTrue(RegistroText.message(forCode: "unexpectedFormat:client-version").contains("FMT update"))
        XCTAssertEqual(RegistroText.status(.needsLogin), "Sign-in required")
        XCTAssertEqual(RegistroText.snapshotKind(.preLink), "Before linking")
        for code in codes {
            let en = RegistroText.message(forCode: code)
            LanguageSettings.current = .italian
            XCTAssertNotEqual(en, RegistroText.message(forCode: code), "manca l'inglese per \(code)")
            LanguageSettings.current = .english
        }
    }
}
