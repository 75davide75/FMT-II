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

    // MARK: Tab Voti

    private func votiShot(_ name: String) {
        let prefix = isPad ? "registro-voti-ipad-" : "registro-voti-"
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "/private/tmp/\(prefix)\(name).png"))
    }

    /// Voti dal registro nella tab Voti: badge, giudizio non numerico, voto "rimosso"
    /// (con Tieni/Elimina) e sezione "Dal registro" nel foglio di modifica.
    func testGradesTabShowsRegisterGrades() {
        app.terminate()
        app.launchArguments += ["-FMTFakeRegistroRemoval"]
        app.launch()
        connectAndImport()
        // Seconda sincronizzazione: "TEC-1" non è più sul registro.
        tap("registro.syncNow")
        sleep(3)
        // Dalla schermata Registro si torna alle Impostazioni, poi "Fine".
        var done = app.buttons["Fine"].firstMatch
        if !done.exists { app.buttons["BackButton"].firstMatch.tap() }
        done = app.buttons["Fine"].firstMatch
        if !done.waitForExistence(timeout: 5) {
            try? app.debugDescription.write(toFile: "/private/tmp/registro-voti-debug.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(done.exists)
        done.tap()

        let keep = element("grade.removed.keep")
        // L'elenco è pigro: si scorre un poco alla volta finché compare il voto rimosso.
        var swipes = 0
        while !keep.waitForExistence(timeout: 1) && swipes < 12 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        if !keep.exists {
            votiShot("debug")
            try? app.debugDescription.write(toFile: "/private/tmp/registro-voti-debug.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(keep.exists, "voto rimosso con azione Tieni")
        XCTAssertTrue(app.staticTexts["Rimosso dal registro"].firstMatch.exists)
        XCTAssertTrue(element("grade.removed.delete").exists)
        XCTAssertTrue(app.images["Dal registro"].firstMatch.exists, "badge con etichetta di accessibilità")
        votiShot("lista")

        // Foglio di modifica di un voto con ora, docente e commento del registro.
        let ita = app.staticTexts["VERDI MARIA"].firstMatch
        XCTAssertTrue(ita.waitForExistence(timeout: 5))
        var up = 0
        while !ita.isHittable && up < 12 { app.swipeUp(velocity: .slow); up += 1 }
        if !ita.isHittable { votiShot("debug-ita") }
        ita.tap()
        // Le righe del foglio sono elementi combinati: "titolo, valore".
        func row(_ text: String) -> XCUIElement {
            app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        let original = row("Valore originale")
        // Le righe del Form si caricano solo quando visibili: si scorre.
        if !original.waitForExistence(timeout: 3) { scrollTo(original) }
        if !original.exists {
            votiShot("debug-sheet")
            try? app.debugDescription.write(toFile: "/private/tmp/registro-voti-debug-sheet.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(original.exists, "sezione Dal registro")
        scrollTo(original)
        votiShot("debug-sheet")
        try? app.debugDescription.write(toFile: "/private/tmp/registro-voti-debug-sheet.txt", atomically: true, encoding: .utf8)
        let comment = row("Tema ben strutturato")
        if !comment.exists { scrollTo(comment) }
        XCTAssertTrue(comment.exists, "commento del registro")
        XCTAssertTrue(row("Docente del registro").exists)
        XCTAssertTrue(row("Periodo").exists)
        votiShot("dettaglio")
        app.buttons["Annulla"].firstMatch.tap()

        // Tieni: toglie solo lo stato "rimosso" (si torna in cima all'elenco).
        var down = 0
        while !keep.isHittable && down < 15 { app.swipeDown(velocity: .fast); down += 1 }
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        sleep(1)
        // Elimina chiede conferma; annullando il voto resta.
        let dialogTitle = app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS 'Eliminare questo voto'")).firstMatch
        // Il bersaglio è piccolo e l'elenco può ancora assestarsi: si riprova il tocco.
        var taps = 0
        repeat {
            element("grade.removed.delete").tap()
            taps += 1
        } while !dialogTitle.waitForExistence(timeout: 2) && taps < 4
        if !dialogTitle.waitForExistence(timeout: 5) {
            votiShot("debug-conferma")
            try? app.debugDescription.write(toFile: "/private/tmp/registro-voti-debug-conferma.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(dialogTitle.exists, "conferma prima di eliminare")
        votiShot("conferma-elimina")
        // Su iPhone il dialogo è un popover senza "Annulla": si chiude toccando fuori.
        let cancel = app.buttons["Annulla"].firstMatch
        if cancel.exists { cancel.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.3)).tap() }
        sleep(1)
        XCTAssertFalse(dialogTitle.exists, "dialogo chiuso")
        XCTAssertTrue(keep.waitForExistence(timeout: 5), "annullando il voto resta")
        keep.tap()
        let removedLabel = app.staticTexts["Rimosso dal registro"].firstMatch
        let gone = NSPredicate(format: "exists == false")
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: removedLabel)], timeout: 5)
        if result != .completed {
            votiShot("debug-keep")
            try? app.debugDescription.write(toFile: "/private/tmp/registro-voti-debug-keep.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(result, .completed, "Tieni toglie lo stato rimosso")
        votiShot("dopo-tieni")
    }
}
