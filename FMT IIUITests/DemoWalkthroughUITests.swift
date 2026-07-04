import XCTest

/// Walkthrough dimostrativo: naviga tutte le superfici salvando screenshot in
/// /private/tmp/fmtshots e dimostra tap, long-press (crea nota) e swipe.
final class DemoWalkthroughUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "/private/tmp/fmtshots/\(name).png"))
    }


    /// I segmenti AuroraSegmented sono Text con onTapGesture: prova
    /// staticTexts, poi buttons.
    private func tapSegment(_ app: XCUIApplication, _ label: String) {
        let t = app.staticTexts[label].firstMatch
        if t.waitForExistence(timeout: 3), t.isHittable { t.tap(); return }
        let b = app.buttons[label].firstMatch
        if b.waitForExistence(timeout: 2), b.isHittable { b.tap() }
    }

    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Consenti"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
    }

    private func skipTutorialIfPresent(_ app: XCUIApplication) {
        for _ in 0..<3 {
            let salta = app.buttons["Salta"]
            let inizia = app.buttons["Inizia"]
            if salta.exists && salta.isHittable { salta.tap(); sleep(1); continue }
            if inizia.exists && inizia.isHittable { inizia.tap(); sleep(1); continue }
            break
        }
        let skipHome = app.buttons["Salta per ora"]
        if skipHome.waitForExistence(timeout: 1) { skipHome.tap() }
    }

    private func launch(importing path: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let path { app.launchEnvironment["FMT_IMPORT_PDF"] = path }
        app.launch()
        dismissSystemAlerts()
        return app
    }

    // 1 — Orario completo (formato legacy docenti) + tutte le viste + interazioni
    func test1Walkthrough() throws {
        let app = launch(importing: "/Users/davidesogos/Desktop/orario classi.pdf")

        // Import parziale (mancano le materie): screenshot e rimando.
        let later = app.buttons["Più tardi"]
        if later.waitForExistence(timeout: 15) {
            shot(app, "10-import-parziale-classi-sheet")
            later.tap()
            sleep(1)
        }
        skipTutorialIfPresent(app)

        _ = app.staticTexts["Ora corrente"].waitForExistence(timeout: 8)
        shot(app, "01-orario-adesso")

        // Vista Giorno
        tapSegment(app, "Giorno")
        sleep(1)
        shot(app, "02-orario-giorno")

        // Vista Settimana
        tapSegment(app, "Settimana")
        sleep(1)
        shot(app, "03-orario-settimana")

        // Long-press su una lezione della settimana -> menu "Crea nota"
        let chip = app.buttons.matching(NSPredicate(format: "label MATCHES 'MARIUCCI|GRECO|DAVIDDE|MORO|DE LUCA'")).firstMatch
        if chip.waitForExistence(timeout: 3) {
            chip.press(forDuration: 1.0)
            sleep(1)
            shot(app, "04-longpress-crea-nota-menu")
            let crea = app.buttons["Crea nota"]
            if crea.waitForExistence(timeout: 3) {
                crea.tap()
                sleep(1)
                shot(app, "05-editor-nota-da-longpress")
                let annulla = app.buttons["Annulla"]
                if annulla.waitForExistence(timeout: 2), annulla.isHittable { annulla.tap() }
            } else {
                app.tap()
            }
            sleep(1)
        }

        // Modalità Docente (vista adattiva classe/docente)
        tapSegment(app, "Docente")
        sleep(1)
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 2) {
            field.tap()
            field.typeText("COLASANTI")
            sleep(1)
            let suggestion = app.buttons["COLASANTI"].firstMatch
            if suggestion.waitForExistence(timeout: 2) { suggestion.tap() }
            sleep(1)
        }
        shot(app, "06-orario-docente-settimana")

        // Swipe tra le sezioni: Orario -> Diario -> Voti
        app.swipeLeft()
        sleep(1)
        shot(app, "07-diario-lista")

        // Editor nota dal compose
        let compose = app.buttons["Nuova voce di diario"]
        if compose.waitForExistence(timeout: 3), compose.isHittable {
            compose.tap()
            sleep(1)
            let tv = app.textViews.firstMatch
            if tv.waitForExistence(timeout: 2) {
                tv.tap()
                tv.typeText("Ripassare fisica per venerdì")
            }
            shot(app, "08-diario-editor")
            let salvaNota = app.buttons["Salva"]
            if salvaNota.waitForExistence(timeout: 2), salvaNota.isHittable { salvaNota.tap() }
            sleep(1)
        }

        app.swipeLeft()
        sleep(1)
        shot(app, "09-voti-overview")

        // Dettaglio materia + grafico
        let materie = app.buttons["Elenco materie"]
        if materie.waitForExistence(timeout: 2) {
            materie.tap()
            sleep(1)
            shot(app, "11-voti-materie")
            let firstSubject = app.cells.firstMatch.exists ? app.cells.firstMatch : app.buttons.matching(NSPredicate(format: "label CONTAINS 'vot'")).firstMatch
            if firstSubject.waitForExistence(timeout: 2), firstSubject.isHittable {
                firstSubject.tap()
                sleep(1)
                shot(app, "12-voti-materia-grafico")
                if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
                sleep(1)
                if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
            }
        }

        // Torna all'Orario con swipe (comportamento invariato)
        app.swipeRight()
        sleep(1)
        app.swipeRight()
        sleep(1)

        // Impostazioni
        let gear = app.buttons["gearshape"].firstMatch
        let gearFallback = app.navigationBars.buttons.matching(NSPredicate(format: "identifier CONTAINS 'gear' OR label CONTAINS 'gear'")).firstMatch
        if gear.waitForExistence(timeout: 2) { gear.tap() }
        else if gearFallback.waitForExistence(timeout: 2) { gearFallback.tap() }
        sleep(1)
        shot(app, "13-impostazioni")
        app.swipeDown(velocity: .fast)
        sleep(1)

        // Modifica database (dal contatore classi)
        let classiPill = app.buttons.containing(NSPredicate(format: "label CONTAINS 'classi'")).firstMatch
        if classiPill.waitForExistence(timeout: 2) {
            classiPill.tap()
            let continua = app.alerts.buttons["Continua"]
            if continua.waitForExistence(timeout: 2) {
                continua.tap()
                sleep(1)
                shot(app, "14-modifica-database")
                app.swipeDown(velocity: .fast)
            }
        }

        // Tab bar (3 sezioni) in evidenza
        shot(app, "15-tabbar-orario")
    }

    // 2 — Import parziale (Cassia, mancano i docenti): l'utente sceglie le classi
    func test2PartialImportCassia() throws {
        let app = launch(importing: "/Users/davidesogos/Downloads/Orario-definitivo-per-classe-Cassia-734 (1).pdf")

        let later = app.buttons["Più tardi"]
        XCTAssertTrue(later.waitForExistence(timeout: 20), "sheet di completamento atteso")
        shot(app, "20-cassia-import-parziale")

        // Seleziono due classi
        app.buttons["1BL"].firstMatch.tap()
        app.buttons["2BL"].firstMatch.tap()
        shot(app, "21-cassia-classi-scelte")
        let completa = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Completa'")).firstMatch
        if completa.waitForExistence(timeout: 2) {
            completa.tap()
            sleep(1)
            shot(app, "22-cassia-editor-completamento")
            // Compilo il primo docente
            let tf = app.textFields.firstMatch
            if tf.waitForExistence(timeout: 2) {
                tf.tap()
                tf.typeText("ROSSI")
            }
            let salva = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Salva'")).firstMatch
            if salva.waitForExistence(timeout: 2) { salva.tap() }
            sleep(1)
        }

        // Vista adattiva: senza docenti -> filtro Materia/Classe
        skipTutorialIfPresent(app)
        _ = app.staticTexts["Ora corrente"].waitForExistence(timeout: 6)
        let materiaSeg = app.staticTexts["Materia"].firstMatch
        XCTAssertTrue(materiaSeg.waitForExistence(timeout: 4), "segmento Materia atteso (vista adattiva)")
        materiaSeg.tap()
        sleep(1)
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 2) {
            field.tap()
            field.typeText("INGLESE")
            sleep(1)
            let sugg = app.buttons["INGLESE"].firstMatch
            if sugg.waitForExistence(timeout: 2) { sugg.tap() }
        }
        tapSegment(app, "Settimana")
        sleep(1)
        shot(app, "23-cassia-filtro-materia")
    }

    // 3 — Rifiuti totali: conflitto docente, struttura non riconoscibile -> creazione manuale
    func test3Rejections() throws {
        let synthDir = "/private/tmp/claude-501/-Users-davidesogos-Desktop-FMT-II-FMT-II/e38a1110-1962-41c4-9a2a-042dc2b7f429/scratchpad/synth"

        var app = launch(importing: "\(synthDir)/teacherConflict.pdf")
        skipTutorialIfPresent(app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "alert di rifiuto atteso")
        shot(app, "30-rifiuto-conflitto-docente")
        if app.alerts.buttons["Annulla"].exists { app.alerts.buttons["Annulla"].tap() }
        app.terminate()

        app = launch(importing: "\(synthDir)/unstructured.pdf")
        skipTutorialIfPresent(app)
        let alert2 = app.alerts.firstMatch
        XCTAssertTrue(alert2.waitForExistence(timeout: 10))
        shot(app, "31-rifiuto-non-riconoscibile")
        let manual = app.alerts.buttons["Crea orario manualmente"]
        if manual.exists {
            manual.tap()
            sleep(1)
            shot(app, "32-creazione-manuale-proposta")
        }
    }
}

extension DemoWalkthroughUITests {
    // 4 — Superfici mancanti: filtro Materia (Cassia), editor diario, Voti completo
    func test4MissingSurfaces() throws {
        let app = launch(importing: "/Users/davidesogos/Downloads/Orario-definitivo-per-classe-Cassia-734 (1).pdf")
        let later = app.buttons["Più tardi"]
        if later.waitForExistence(timeout: 20) { later.tap(); sleep(1) }
        skipTutorialIfPresent(app)
        _ = app.staticTexts["Ora corrente"].waitForExistence(timeout: 8)

        // Vista adattiva: materie riconosciute -> segmento "Materia"
        let materiaSeg = app.staticTexts["Materia"].firstMatch
        if materiaSeg.waitForExistence(timeout: 4) {
            materiaSeg.tap()
            sleep(1)
            let field = app.textFields.firstMatch
            if field.waitForExistence(timeout: 2) {
                field.tap()
                field.typeText("INGLESE")
                sleep(1)
                let sugg = app.buttons.matching(NSPredicate(format: "label == 'INGLESE'")).firstMatch
                if sugg.waitForExistence(timeout: 2), sugg.isHittable { sugg.tap() }
                app.buttons["Fine"].firstMatch.exists ? app.buttons["Fine"].firstMatch.tap() : ()
            }
            let sett = app.buttons["Settimana"].firstMatch
            if sett.exists { sett.tap() }
            sleep(1)
            shot(app, "23-cassia-filtro-materia")
        } else {
            shot(app, "23-cassia-filtro-materia-MANCANTE")
        }

        // Diario: editor con testo
        app.swipeLeft()
        sleep(1)
        let compose = app.buttons["Nuova voce di diario"].firstMatch
        if compose.waitForExistence(timeout: 3), compose.isHittable {
            compose.tap()
            sleep(1)
            let tv = app.textViews.firstMatch
            if tv.waitForExistence(timeout: 2) {
                tv.tap()
                sleep(1)
                app.typeText("Ripassare inglese per la verifica")
            }
            shot(app, "08-diario-editor")
            let annulla = app.buttons["Annulla"].firstMatch
            if annulla.exists, annulla.isHittable { annulla.tap() }
            sleep(1)
        }

        // Voti: overview, elenco materie, dettaglio con grafico
        app.swipeLeft()
        sleep(2)
        shot(app, "09-voti-overview")
        let materie = app.buttons["Elenco materie"].firstMatch
        if materie.waitForExistence(timeout: 3), materie.isHittable {
            materie.tap()
            sleep(1)
            shot(app, "11-voti-materie")
            let cell = app.buttons.matching(NSPredicate(format: "label CONTAINS 'vot'")).firstMatch
            if cell.waitForExistence(timeout: 2), cell.isHittable {
                cell.tap()
                sleep(1)
                shot(app, "12-voti-materia-grafico")
            }
        }
    }
}

extension DemoWalkthroughUITests {
    // 5 — Diario editor e Voti (senza toccare i campi di ricerca)
    func test5DiaryAndGrades() throws {
        let app = launch()   // orario già persistito dal run precedente
        skipTutorialIfPresent(app)
        let later = app.buttons["Più tardi"]
        if later.waitForExistence(timeout: 3) { later.tap(); sleep(1) }
        sleep(2)

        // Vai al Diario tramite la barra sezioni (tap, non swipe)
        app.staticTexts["Diario"].firstMatch.tap()
        sleep(1)
        let compose = app.buttons["Nuova voce di diario"].firstMatch
        if compose.waitForExistence(timeout: 3) {
            compose.tap()
            sleep(1)
            let tv = app.textViews.firstMatch
            if tv.waitForExistence(timeout: 2) {
                tv.tap()
                sleep(1)
                app.typeText("Ripassare inglese per la verifica")
            }
            shot(app, "08-diario-editor")
            let annulla = app.buttons["Annulla"].firstMatch
            if annulla.exists, annulla.isHittable { annulla.tap() }
            sleep(1)
        }

        // Vai a Voti
        app.staticTexts["Voti"].firstMatch.tap()
        sleep(2)
        shot(app, "09-voti-overview")
        let materie = app.buttons["Elenco materie"].firstMatch
        if materie.waitForExistence(timeout: 3) {
            materie.tap()
            sleep(1)
            shot(app, "11-voti-materie")
            let cell = app.buttons.matching(NSPredicate(format: "label CONTAINS 'vot'")).firstMatch
            if cell.waitForExistence(timeout: 2) {
                cell.tap()
                sleep(1)
                shot(app, "12-voti-materia-grafico")
            }
        }
    }
}

extension DemoWalkthroughUITests {
    // 6 — Striscia date del Diario: tap su un giorno -> auto-scroll alle sue note
    func test6DiaryStripJump() throws {
        let app = launch()
        skipTutorialIfPresent(app)
        let later = app.buttons["Più tardi"]
        if later.waitForExistence(timeout: 3) { later.tap(); sleep(1) }
        sleep(1)

        app.staticTexts["Diario"].firstMatch.tap()
        sleep(1)
        shot(app, "60-diario-prima-del-salto")

        // Tocca la data di mercoledì nella striscia
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'MER'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 4), "tile MER attesa nella striscia")
        tile.tap()
        sleep(2)
        shot(app, "61-diario-salto-a-mercoledi")

        // E poi a sabato (scorrendo la striscia se serve)
        let sab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'SAB'")).firstMatch
        if !sab.exists || !sab.isHittable {
            app.scrollViews.firstMatch.swipeLeft()
            sleep(1)
        }
        if sab.waitForExistence(timeout: 3), sab.isHittable {
            sab.tap()
            sleep(2)
            shot(app, "62-diario-salto-a-sabato")
        }
    }
}

extension DemoWalkthroughUITests {
    // 7 — Nuove impostazioni, colori personalizzati, soglia voti live,
    //     manuale e dati orario
    func test7SettingsColorsAndMore() throws {
        let app = launch()
        skipTutorialIfPresent(app)
        let later = app.buttons["Più tardi"]
        if later.waitForExistence(timeout: 3) { later.tap(); sleep(1) }
        sleep(1)

        // Diario: niente più compose in toolbar (solo menu ••• e FAB)
        app.staticTexts["Diario"].firstMatch.tap()
        sleep(1)
        shot(app, "70-diario-senza-compose")

        // Orario > Giorno: etichette gradiente per docente
        app.staticTexts["Orario"].firstMatch.tap()
        sleep(1)
        tapSegment(app, "Giorno")
        sleep(1)
        shot(app, "71-giorno-etichette-gradiente")

        // Impostazioni riorganizzate
        let gear = app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'gear' OR label CONTAINS[c] 'impostazioni'")).firstMatch
        if gear.waitForExistence(timeout: 3) { gear.tap() } else { app.buttons["gearshape"].firstMatch.tap() }
        sleep(1)
        shot(app, "72-impostazioni-nuove")

        // Colori personalizzati
        let colori = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Colori'")).firstMatch
        if colori.waitForExistence(timeout: 3) {
            colori.tap()
            sleep(1)
            shot(app, "73-colori-elenco")
            let firstRow = app.buttons.matching(NSPredicate(format: "label MATCHES '.*1G.*|.*1BL.*|.*1A.*'")).firstMatch
            if firstRow.waitForExistence(timeout: 2) {
                firstRow.tap()
                sleep(1)
                shot(app, "74-colori-picker")
                // Scegli il primo colore della griglia e chiudi
                let circle = app.buttons.matching(NSPredicate(format: "label == ''")).firstMatch
                if circle.exists { circle.tap() }
                let fine = app.buttons["Fine"].firstMatch
                if fine.waitForExistence(timeout: 2) { fine.tap() }
                sleep(1)
            }
            app.navigationBars.buttons.firstMatch.tap()  // back
            sleep(1)
        }

        // Manuale ridisegnato
        let manuale = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Manuale'")).firstMatch
        if manuale.waitForExistence(timeout: 3) {
            manuale.tap()
            sleep(1)
            shot(app, "76-manuale-nuovo")
            app.swipeUp()
            sleep(1)
            shot(app, "76b-manuale-scroll")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // Dati orario (modifica database) ridisegnato
        let dati = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Dati orario'")).firstMatch
        if dati.waitForExistence(timeout: 3) {
            dati.tap()
            let continua = app.alerts.buttons["Continua"]
            if continua.waitForExistence(timeout: 3) {
                continua.tap()
                sleep(1)
                shot(app, "77-dati-orario-nuovo")
                app.swipeUp()
                sleep(1)
                shot(app, "77b-dati-orario-chips")
                let annulla = app.buttons["Annulla"].firstMatch
                if annulla.exists { annulla.tap() }
                sleep(1)
            }
        }

        // Soglia voti: colori aggiornati subito
        let fine = app.buttons["Fine"].firstMatch
        if fine.waitForExistence(timeout: 2) { fine.tap() }
        sleep(1)
        app.staticTexts["Voti"].firstMatch.tap()
        sleep(1)
        shot(app, "78-voti-soglia-6")

        // Riapri impostazioni e alza la sufficienza di 4 mezzi punti (6 -> 8)
        let gear2 = app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'gear' OR label CONTAINS[c] 'impostazioni'")).firstMatch
        let plus2 = app.buttons["plus"].firstMatch
        if gear2.waitForExistence(timeout: 3) { gear2.tap() } else if plus2.exists {}
        sleep(1)
        let inc = app.steppers.firstMatch.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'increment' OR label CONTAINS[c] 'aumenta' OR label CONTAINS[c] 'incrementa'")
        ).firstMatch
        if inc.waitForExistence(timeout: 3) {
            for _ in 0..<4 { inc.tap(); usleep(300000) }
            shot(app, "79-impostazioni-soglia-8")
            let fine2 = app.buttons["Fine"].firstMatch
            if fine2.exists { fine2.tap() }
            sleep(1)
            shot(app, "80-voti-soglia-8-live")
        }
    }
}

extension DemoWalkthroughUITests {
    // 8 — Demo restanti: giorno con lezioni, manuale, dati orario, soglia live
    func test8RemainingDemos() throws {
        let app = launch()
        skipTutorialIfPresent(app)
        let later = app.buttons["Più tardi"]
        if later.waitForExistence(timeout: 3) { later.tap(); sleep(1) }
        sleep(1)

        // Giorno con etichette gradiente (ora con classe selezionata)
        tapSegment(app, "Giorno")
        sleep(1)
        shot(app, "71-giorno-etichette-gradiente")

        // Tap su una lezione -> controparte con transizione morbida
        let lessonBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'INGLESE' OR label CONTAINS 'ITALIANO' OR label CONTAINS 'MATE'")).firstMatch
        if lessonBtn.waitForExistence(timeout: 3) {
            lessonBtn.tap()
            sleep(1)
            shot(app, "75-controparte-smooth")
        }

        // Impostazioni -> scroll -> Manuale
        let gear = app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'gear' OR label CONTAINS[c] 'impostazioni'")).firstMatch
        if gear.waitForExistence(timeout: 3) { gear.tap() }
        sleep(1)
        app.swipeUp(); app.swipeUp()
        sleep(1)
        let manuale = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Manuale'")).firstMatch
        if manuale.waitForExistence(timeout: 3) {
            manuale.tap()
            sleep(1)
            shot(app, "76-manuale-nuovo")
            app.swipeUp()
            sleep(1)
            shot(app, "76b-manuale-scroll")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // Dati orario
        app.swipeDown(); app.swipeDown()
        sleep(1)
        let dati = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Dati orario'")).firstMatch
        if dati.waitForExistence(timeout: 3) {
            dati.tap()
            let continua = app.alerts.buttons["Continua"]
            if continua.waitForExistence(timeout: 3) {
                continua.tap()
                sleep(1)
                shot(app, "77-dati-orario-nuovo")
                app.swipeUp()
                sleep(1)
                shot(app, "77b-dati-orario-chips")
                let annulla = app.buttons["Annulla"].firstMatch
                if annulla.exists { annulla.tap() }
                sleep(1)
            }
        }

        // Soglia voti live: 6 -> 8 e ritorno alla sezione Voti
        app.swipeUp()
        sleep(1)
        let inc = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'increment' OR label CONTAINS[c] 'aumenta' OR label CONTAINS[c] 'incrementa'")
        ).firstMatch
        if inc.waitForExistence(timeout: 3) {
            for _ in 0..<4 { inc.tap(); usleep(400000) }
            shot(app, "79-impostazioni-soglia-8")
        }
        let fine = app.buttons["Fine"].firstMatch
        if fine.waitForExistence(timeout: 2) { fine.tap() }
        sleep(1)
        app.staticTexts["Voti"].firstMatch.tap()
        sleep(2)
        shot(app, "80-voti-soglia-8-live")

        // Riporta la soglia a 6 per non alterare lo stato
        if gear.waitForExistence(timeout: 3) { gear.tap() }
        sleep(1)
        app.swipeUp()
        let dec = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'decrement' OR label CONTAINS[c] 'riduci' OR label CONTAINS[c] 'diminuisci'")
        ).firstMatch
        if dec.waitForExistence(timeout: 3) {
            for _ in 0..<4 { dec.tap(); usleep(300000) }
        }
        if fine.waitForExistence(timeout: 2) { fine.tap() }
    }
}

extension DemoWalkthroughUITests {
    // 9 — Controparte, Dati orario e soglia voti (senza swipe sullo sheet)
    func test9FinalDemos() throws {
        let app = launch()
        skipTutorialIfPresent(app)
        let later = app.buttons["Più tardi"]
        if later.waitForExistence(timeout: 3) { later.tap(); sleep(1) }
        sleep(1)

        // Parti sempre dalla sezione Orario (lo stato della sezione persiste)
        app.staticTexts["Orario"].firstMatch.tap()
        sleep(1)

        // Controparte con transizione morbida (tap su una lezione del giorno)
        tapSegment(app, "Giorno")
        sleep(1)
        let lessonBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'GEOSTORIA' OR label CONTAINS 'MATE' OR label CONTAINS 'SC.'")).firstMatch
        if lessonBtn.waitForExistence(timeout: 3) {
            lessonBtn.tap()
            sleep(1)
            shot(app, "75-controparte-smooth")
        }

        // Impostazioni: Dati orario è nella sezione ORARIO, visibile subito
        let gear = app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'gear' OR label CONTAINS[c] 'impostazioni'")).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 4))
        gear.tap()
        sleep(1)
        let dati = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Dati orario'")).firstMatch
        if !dati.exists { app.swipeUp() }
        XCTAssertTrue(dati.waitForExistence(timeout: 4), "riga Dati orario attesa")
        dati.tap()
        let continua = app.alerts.buttons["Continua"]
        XCTAssertTrue(continua.waitForExistence(timeout: 4))
        continua.tap()
        sleep(1)
        shot(app, "77-dati-orario-nuovo")
        app.swipeUp()
        sleep(1)
        shot(app, "77b-dati-orario-chips")
        let annulla = app.buttons["Annulla"].firstMatch
        if annulla.exists { annulla.tap() }
        sleep(1)

        // Soglia: porta la sufficienza da 6 a 8 (stepper con fallback coordinate)
        app.swipeUp()
        sleep(1)
        let stepper = app.steppers.firstMatch
        if stepper.waitForExistence(timeout: 3) {
            let inc = stepper.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'increment' OR label CONTAINS[c] 'aumenta' OR label CONTAINS[c] 'incrementa'")
            ).firstMatch
            for _ in 0..<4 {
                if inc.exists { inc.tap() }
                else { stepper.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
                usleep(350000)
            }
            shot(app, "79-impostazioni-soglia-8")
        }
        let fine = app.buttons["Fine"].firstMatch
        if fine.waitForExistence(timeout: 2) { fine.tap() }
        sleep(1)
        app.staticTexts["Voti"].firstMatch.tap()
        sleep(2)
        shot(app, "80-voti-soglia-8-live")

        // Ripristina 6 (il gear è nella toolbar dell'Orario)
        app.staticTexts["Orario"].firstMatch.tap()
        sleep(1)
        gear.tap()
        sleep(1)
        app.swipeUp()
        sleep(1)
        let stepper2 = app.steppers.firstMatch
        if stepper2.waitForExistence(timeout: 3) {
            let dec = stepper2.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'decrement' OR label CONTAINS[c] 'riduci' OR label CONTAINS[c] 'diminuisci'")
            ).firstMatch
            for _ in 0..<4 {
                if dec.exists { dec.tap() }
                else { stepper2.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.5)).tap() }
                usleep(300000)
            }
        }
        if fine.waitForExistence(timeout: 2) { fine.tap() }
    }
}
