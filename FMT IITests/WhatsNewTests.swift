import XCTest
@testable import FMT_II

/// Banner «Novità»: solo per chi aggiorna (tutorial già fatto), mai per chi
/// installa da zero, una sola volta.
final class WhatsNewTests: XCTestCase {
    func testUpdatingUserSeesBanner() {
        XCTAssertTrue(WhatsNew.shouldShow(tutorialDoneAtLaunch: true, lastSeen: ""))
    }

    func testNewInstallDoesNotSeeBanner() {
        XCTAssertFalse(WhatsNew.shouldShow(tutorialDoneAtLaunch: false, lastSeen: ""))
    }

    func testAlreadySeenDoesNotShow() {
        XCTAssertFalse(WhatsNew.shouldShow(tutorialDoneAtLaunch: true, lastSeen: "2.2"))
    }

    func testFutureVersionSeenDoesNotShow() {
        XCTAssertFalse(WhatsNew.shouldShow(tutorialDoneAtLaunch: true, lastSeen: "2.10"))
    }
}
