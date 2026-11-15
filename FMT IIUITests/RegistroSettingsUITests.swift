import XCTest

/// Impostazioni → Registro elettronico, con il provider finto in memoria
/// (`-FMTFakeRegistro`, solo DEBUG): nessuna rete, dati preparati a ogni avvio
/// (voti demo + due voti manuali che rendono ambiguo un voto del registro).
/// Screenshot in /private/tmp/registro-ui-*.png (iPad: in orizzontale, prefisso "ipad").
final class RegistroSettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUpWithError() throws {
        continueAfterFailure = false
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        app = XCUIApplication()
        app.launchArguments = ["-FMTSeedDemo", "-FMTFakeRegistro", "-hasSeenTutorial", "YES",
                               "-hasCompletedOnboarding", "YES", "-appSectionRaw", "grades",
                               "-appLanguage", "it"]
        app.launch()
    }

    override func tearDown() {
        if isPad { XCUIDevice.shared.orientation = .portrait }
        super.tearDown()
    }

    // MARK: Helper

    private func shot(_ name: String) {
        let prefix = isPad ? "registro-ui-ipad-" : "registro-ui-"
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "/private/tmp/\(prefix)\(name).png"))
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Scorre finché l'elemento non è toccabile.
    @discardableResult
    private func scrollTo(_ e: XCUIElement, in container: XCUIElement? = nil, maxSwipes: Int = 10) -> XCUIElement {
        // Il Form in primo piano (sheet o schermata spinta) è l'ultimo toccabile.
        let front = app.collectionViews.allElementsBoundByIndex.last { $0.exists && $0.isHittable }
        let area: XCUIElement = container ?? front ?? app
        var n = 0
        while !(e.exists && e.isHittable) && n < maxSwipes {
            area.swipeUp()
            n += 1
        }
        return e
    }

    /// Attende un elemento; se manca salva screenshot e albero per capire perché.
    @discardableResult
    private func wait(_ id: String, timeout: TimeInterval = 5) -> XCUIElement {
        let e = element(id)
        // Le righe dei Form sono caricate solo quando visibili: se manca si scorre.
        if !e.waitForExistence(timeout: timeout) { scrollTo(e) }
        if !e.exists {
            shot("debug-\(id)")
            try? app.debugDescription.write(toFile: "/private/tmp/registro-ui-debug.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(e.exists, "manca \(id)")
        return e
    }

    private func tap(_ id: String, timeout: TimeInterval = 5) {
        let e = element(id)
        // Le righe dei Form sono caricate solo quando visibili: prima si scorre.
        if !e.waitForExistence(timeout: timeout) { scrollTo(e) }
        if !e.exists {
            shot("debug-\(id)")
            try? app.debugDescription.write(toFile: "/private/tmp/registro-ui-debug.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(e.exists, "manca \(id)")
        scrollTo(e)
        e.tap()
    }

    private func openRegistroSettings() {
        let more = app.buttons["Altre azioni"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        let settings = app.buttons["Impostazioni"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        tap("settings.registro", timeout: 8)
        XCTAssertTrue(element("registro.provider.classeviva").waitForExistence(timeout: 5))
    }

    /// Scelta ClasseViva → disclaimer accettato → login con credenziali finte.
    private func loginWithFakeProvider() {
        tap("registro.provider.classeviva")
        let accept = wait("registro.disclaimer.accept")
        scrollTo(accept)
        accept.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        tap("registro.disclaimer.continue")

        let user = element("registro.login.username")
        XCTAssertTrue(user.waitForExistence(timeout: 5))
        user.tap()
        user.typeText("studente.prova")
        let password = element("registro.login.password")
        password.tap()
        password.typeText("prova")
        tap("registro.login.submit")
    }

    private func connectAndImport() {
        openRegistroSettings()
        loginWithFakeProvider()
        tap("registro.mapping.confirm", timeout: 10)
        XCTAssertTrue(element("registro.importedCount").waitForExistence(timeout: 10))
    }

    private func importedCount() -> Int {
        Int(element("registro.importedCount").label) ?? -1
    }

    // MARK: Test

    /// I registri non ancora pronti non si scelgono; il login appare solo dopo
    /// aver accettato il disclaimer.
    func testConnectFlowRequiresDisclaimer() {
        openRegistroSettings()
        let axios = element("registro.provider.axios")
        scrollTo(axios)
        XCTAssertTrue(axios.exists)
        XCTAssertFalse(axios.isEnabled, "gli stub non sono selezionabili")
        XCTAssertTrue(app.staticTexts["Presto disponibile"].firstMatch.exists)
        shot("01-scelta-registro")

        tap("registro.provider.classeviva")
        let unofficial = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'non ufficiale'")).firstMatch
        XCTAssertTrue(unofficial.waitForExistence(timeout: 5))
        XCTAssertFalse(element("registro.login.username").exists)
        shot("02-disclaimer")
        let accept = wait("registro.disclaimer.accept")
        let proceed = wait("registro.disclaimer.continue")
        XCTAssertFalse(proceed.isEnabled, "senza accettare non si va avanti")
        XCTAssertFalse(element("registro.login.username").exists)
        shot("02b-disclaimer-accetta")

        scrollTo(accept)
        accept.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        scrollTo(proceed)
        XCTAssertTrue(proceed.isEnabled)
        proceed.tap()
        XCTAssertTrue(element("registro.login.username").waitForExistence(timeout: 5))
        XCTAssertTrue(element("registro.login.password").exists)
        shot("03-login")
    }

    /// Dopo il login si vede il mapping proposto; finché non si conferma non
    /// viene importato nessun voto.
    func testFirstImportWaitsForMappingConfirmation() {
        openRegistroSettings()
        loginWithFakeProvider()
        XCTAssertTrue(app.staticTexts["suggerito"].firstMatch.waitForExistence(timeout: 10), "alias segnato come suggerimento")
        // Dietro il foglio Impostazioni mostra già il registro collegato, ma 0 voti importati.
        let behind = element("registro.importedCount")
        if behind.exists { XCTAssertEqual(behind.label, "0", "nessun voto prima della conferma") }
        shot("04-mapping")
        wait("registro.mapping.duplicate")
        shot("04b-mapping-doppione")
        wait("registro.mapping.confirm")

        tap("registro.mapping.later")
        XCTAssertTrue(element("registro.importedCount").waitForExistence(timeout: 5))
        XCTAssertEqual(importedCount(), 0, "nessun voto prima della conferma")
        XCTAssertTrue(element("registro.pendingSubjects").exists)

        tap("registro.pendingSubjects")
        tap("registro.mapping.confirm", timeout: 5)
        let count = element("registro.importedCount")
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        let imported = NSPredicate(format: "label != '0'")
        expectation(for: imported, evaluatedWith: count)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(element("registro.pendingSubjects").exists)
        shot("05-collegato")
    }

    /// "Sì, è questo" collega il voto del registro a quello scelto.
    func testConflictSheetLinksChosenGrade() {
        connectAndImport()
        let before = importedCount()
        XCTAssertGreaterThan(before, 0)
        tap("registro.conflicts")
        XCTAssertTrue(app.staticTexts["È questo il voto che hai già inserito?"].waitForExistence(timeout: 5))
        shot("06-conflitto")
        wait("registro.conflict.new")
        wait("registro.conflict.later")

        tap("registro.conflict.link.0")
        let conflicts = element("registro.conflicts")
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: conflicts)
        waitForExpectations(timeout: 10)
        // La sync parte alla chiusura del foglio: il voto manuale scelto ora è collegato.
        expectation(for: NSPredicate(format: "label == %@", "\(before + 1)"), evaluatedWith: element("registro.importedCount"))
        waitForExpectations(timeout: 10)
    }

    /// "Scollega" offre di tenere o eliminare i voti importati, con la spiegazione.
    func testUnlinkOffersKeepOrDelete() {
        connectAndImport()
        tap("registro.unlink")
        XCTAssertTrue(element("registro.unlink.keep").waitForExistence(timeout: 5))
        wait("registro.unlink.delete")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'mai eliminati'")).firstMatch.exists)
        shot("07-scollega")

        tap("registro.unlink.keep")
        XCTAssertTrue(element("registro.provider.classeviva").waitForExistence(timeout: 10))
        XCTAssertFalse(element("registro.unlink").exists)
    }

    /// "Ripristina voti" elenca le copie con data e numero di voti e chiede conferma.
    func testRestoreListsSnapshots() {
        connectAndImport()
        tap("registro.restore")
        let first = element("registro.snapshot.0")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Prima del collegamento"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS ' voti'")).firstMatch.exists)
        shot("08-ripristino")

        first.tap()
        let confirm = app.alerts.buttons["Ripristina"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot("09-ripristino-conferma")
        confirm.tap()
        let ok = app.alerts.buttons["OK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 5), "ripristino riuscito")
        ok.tap()
        // Il ripristino salva prima lo stato attuale: compare una nuova copia.
        XCTAssertTrue(app.staticTexts["Prima di un ripristino"].waitForExistence(timeout: 5))
    }
}
