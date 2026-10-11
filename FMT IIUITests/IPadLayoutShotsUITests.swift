import XCTest

/// Screenshot del layout iPad in verticale e orizzontale (dati demo), salvati
/// in /private/tmp/fmtshots-ipad. Da lanciare su un simulatore iPad:
/// la rotazione passa da XCUIDevice, l'unico modo che iPadOS consente in test.
final class IPadLayoutShotsUITests: XCTestCase {
    private let outDir = "/private/tmp/fmtshots-ipad"

    override func setUpWithError() throws {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    }

    private func launch(section: String, viewMode: String = "now", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FMTSeedDemo", "-hasSeenTutorial", "YES", "-hasCompletedOnboarding", "YES",
                               "-appSectionRaw", section, "-FMTViewMode", viewMode] + extra
        app.launch()
        return app
    }

    func testIPadLayoutShots() throws {
        let cases: [(name: String, section: String, mode: String, extra: [String])] = [
            ("orario-settimana", "schedule", "week", []),
            ("orario-adesso", "schedule", "now", []),
            ("orario-giorno", "schedule", "day", []),
            ("orario-settimana-perclasse", "schedule", "week", ["-FMTDemoPerClass"]),
            ("diario", "notes", "now", []),
            ("voti", "grades", "now", []),
            ("banner", "schedule", "now", ["-FMTShowWhatsNew"]),
        ]
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            let tag = orientation == .portrait ? "verticale" : "orizzontale"
            for c in cases {
                XCUIDevice.shared.orientation = orientation
                let app = launch(section: c.section, viewMode: c.mode, extra: c.extra)
                sleep(3)
                shot("\(tag)-\(c.name)")
                app.terminate()
            }
        }
    }
}
