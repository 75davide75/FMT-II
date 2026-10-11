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

}
