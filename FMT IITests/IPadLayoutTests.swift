import XCTest
import SwiftUI
@testable import FMT_II

/// Layout iPad: scelta della modalità dalla finestra e colonne della Settimana.
final class IPadLayoutTests: XCTestCase {
    func testIPhoneIsCompact() {
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .compact, verticalSizeClass: .regular, width: 430), .compact)
    }

    func testNarrowIPadWindowIsCompact() {
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .compact, verticalSizeClass: .regular, width: 375), .compact)
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .regular, verticalSizeClass: .regular, width: 600), .compact)
    }

    func testIPadPortraitIsRegular() {
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .regular, verticalSizeClass: .regular, width: 834), .regular)
    }

    func testIPadLandscapeIsWide() {
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .regular, verticalSizeClass: .regular, width: 1194), .wide)
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .regular, verticalSizeClass: .regular, width: 1133), .wide)
    }

    // iPhone Pro Max / Plus in orizzontale: size class orizzontale regolare ma
    // verticale compatta → resta il layout iPhone.
    func testLargeIPhoneLandscapeIsCompact() {
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .regular, verticalSizeClass: .compact, width: 932), .compact)
    }

    // iPad Pro 13" in verticale (1032 pt) è verticale, non orizzontale.
    func testLargeIPadPortraitIsRegular() {
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .regular, verticalSizeClass: .regular, width: 1032), .regular)
    }

    func testFiveDaysFillWidth() {
        XCTAssertEqual(WeekGridMetrics.dayColumnWidth(available: 860, days: 5, timeColumn: 60, minimum: 88), 160)
    }

    func testSixDaysFillWidth() {
        XCTAssertEqual(WeekGridMetrics.dayColumnWidth(available: 780, days: 6, timeColumn: 60, minimum: 88), 120)
    }

    func testFallsBackToMinimumWidth() {
        XCTAssertEqual(WeekGridMetrics.dayColumnWidth(available: 400, days: 5, timeColumn: 60, minimum: 88), 88)
        XCTAssertEqual(WeekGridMetrics.dayColumnWidth(available: 800, days: 0, timeColumn: 60, minimum: 88), 88)
    }
}
