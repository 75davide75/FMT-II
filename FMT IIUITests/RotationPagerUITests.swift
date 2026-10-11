import XCTest

/// Rotazione su iPad: la pagina della sezione deve restare allineata (prima il
/// pager restava a metà tra due sezioni, che si sovrapponevano).
final class RotationPagerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// Titolo grande della sezione (non l'etichetta della barra in alto).
    private func sectionTitle(_ app: XCUIApplication, _ text: String) -> XCUIElement? {
        let matches = app.staticTexts.matching(identifier: text).allElementsBoundByIndex
        return matches.max { $0.frame.height < $1.frame.height }
    }

    private func assertAligned(_ app: XCUIApplication, _ title: String, _ step: String) {
        sleep(2)
        guard let t = sectionTitle(app, title) else { return XCTFail("titolo \(title) non trovato (\(step))") }
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(t.frame.minX - window.minX, 80, "pagina non allineata dopo \(step): x=\(t.frame.minX)")
    }

    private func rotate(section: String, title: String) throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("solo iPad") }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-FMTSeedDemo", "-hasSeenTutorial", "YES", "-hasCompletedOnboarding", "YES",
                               "-appLanguage", "it", "-appSectionRaw", section]
        app.launch()
        assertAligned(app, title, "avvio")
        XCUIDevice.shared.orientation = .landscapeLeft
        assertAligned(app, title, "verticale → orizzontale")
        XCUIDevice.shared.orientation = .portrait
        assertAligned(app, title, "orizzontale → verticale")
        XCUIDevice.shared.orientation = .landscapeRight
        assertAligned(app, title, "verticale → orizzontale (destra)")
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "/private/tmp/rot-\(section).png"))
    }

    func testDiarioStaysAlignedAcrossRotations() throws { try rotate(section: "notes", title: "Diario") }
    func testOrarioStaysAlignedAcrossRotations() throws { try rotate(section: "schedule", title: "Orario") }
    func testVotiStaysAlignedAcrossRotations() throws { try rotate(section: "grades", title: "Voti") }

    /// Settimana: ruotando la pagina non deve diventare più larga dello schermo.
    func testWeekViewFitsAfterRotation() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("solo iPad") }
        let app = XCUIApplication()
        app.launchArguments = ["-FMTSeedDemo", "-hasSeenTutorial", "YES", "-hasCompletedOnboarding", "YES",
                               "-appLanguage", "it", "-appSectionRaw", "schedule", "-FMTViewMode", "week"]
        for (start, end, label) in [(UIDeviceOrientation.landscapeLeft, UIDeviceOrientation.portrait, "orizzontale → verticale"),
                                    (.portrait, .landscapeLeft, "verticale → orizzontale")] {
            XCUIDevice.shared.orientation = start
            app.launch()
            sleep(2)
            XCUIDevice.shared.orientation = end
            sleep(3)
            let window = app.windows.firstMatch.frame
            for text in ["Classe", "Docente", "Adesso", "Settimana"] {
                let els = app.staticTexts.matching(identifier: text).allElementsBoundByIndex.filter { $0.frame.height < 60 }
                guard let el = els.first else { XCTFail("\(text) non trovato (\(label))"); continue }
                XCTAssertGreaterThanOrEqual(el.frame.minX, window.minX, "\(text) esce a sinistra (\(label)): \(el.frame)")
                XCTAssertLessThanOrEqual(el.frame.maxX, window.maxX, "\(text) esce a destra (\(label)): \(el.frame)")
            }
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try? png.write(to: URL(fileURLWithPath: "/private/tmp/rot-week-\(end == .portrait ? "verticale" : "orizzontale").png"))
            app.terminate()
        }
    }
}
