import XCTest
@testable import FMT_II

/// Data reale delle note del diario: prossima occorrenza di un giorno
/// settimanale, round-trip Codable e migrazione delle note legacy.
final class NoteDateTests: XCTestCase {
    // 2026-07-04 alle 12:00 locali è un sabato.
    private var saturday: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 4; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    func testNextOccurrenceSameDayIsToday() {
        let d = nextOccurrence(of: .saturday, from: saturday)
        XCTAssertTrue(Calendar.current.isDate(d, inSameDayAs: saturday))
    }

    func testNextOccurrenceForward() {
        let d = nextOccurrence(of: .monday, from: saturday)   // lunedì 6 luglio
        XCTAssertEqual(Calendar.current.component(.day, from: d), 6)
        XCTAssertEqual(Calendar.current.component(.weekday, from: d), 2)
    }

    func testDateRoundTripCodable() throws {
        var n = Note(); n.date = saturday
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(decoded.date?.timeIntervalSince1970 ?? 0,
                       saturday.timeIntervalSince1970, accuracy: 1)
    }

    func testLegacyNoteMigratesToNextOccurrence() {
        var n = Note(); n.day = DayId.friday.rawValue; n.date = nil
        let migrated = n.migratingDate(from: saturday)        // venerdì 10 luglio
        XCTAssertNotNil(migrated.date)
        XCTAssertEqual(Calendar.current.component(.day, from: migrated.date!), 10)
    }

    func testNoteWithoutWeekdayStaysUndated() {
        let n = Note()
        XCTAssertNil(n.migratingDate(from: saturday).date)
    }
}
