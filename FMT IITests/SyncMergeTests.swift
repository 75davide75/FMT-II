import XCTest
@testable import FMT_II

/// Regole di merge della sincronizzazione iCloud (last-writer-wins su
/// `modifiedAt`, unione per id) e nomi dei record CloudKit.
final class SyncMergeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    private func grade(_ id: UUID, _ value: Double, _ at: Date) -> Grade {
        var g = Grade(); g.id = id; g.value = value; g.modifiedAt = at; return g
    }

    func testRecordNamesRoundTrip() {
        let id = UUID()
        XCTAssertEqual(SyncItem(recordName: SyncItem.grade(id).recordName), .grade(id))
        XCTAssertEqual(SyncItem(recordName: SyncItem.note(id).recordName), .note(id))
        XCTAssertEqual(SyncItem(recordName: "schedule-current"), .schedule)
        XCTAssertNil(SyncItem(recordName: "grade-not-a-uuid"))
        XCTAssertNil(SyncItem(recordName: "photo-\(id.uuidString)"))
        XCTAssertEqual(SyncItem.grade(id).recordType, "Grade")
        XCTAssertEqual(SyncItem.schedule.recordType, "Schedule")
    }

    func testNewerLocalIsKept() {
        let id = UUID()
        let out = SyncMerge.apply(upserts: [grade(id, 4, t0)], deletions: [], to: [grade(id, 8, t1)], modifiedAt: \.modifiedAt)
        XCTAssertEqual(out.first?.value, 8)
    }

    func testNewerRemoteWins() {
        let id = UUID()
        let out = SyncMerge.apply(upserts: [grade(id, 9, t1)], deletions: [], to: [grade(id, 5, t0)], modifiedAt: \.modifiedAt)
        XCTAssertEqual(out.first?.value, 9)
    }

    func testTieGoesToRemote() {
        let id = UUID()
        let out = SyncMerge.apply(upserts: [grade(id, 7, t0)], deletions: [], to: [grade(id, 6, t0)], modifiedAt: \.modifiedAt)
        XCTAssertEqual(out.first?.value, 7)
    }

    func testApplyUnionKeepsBothSides() {
        let a = UUID(), b = UUID()
        let out = SyncMerge.apply(upserts: [grade(b, 7, t0)], deletions: [], to: [grade(a, 6, t0)], modifiedAt: \.modifiedAt)
        XCTAssertEqual(Set(out.map(\.id)), [a, b])
    }

    func testDeletionRemovesAndUnknownDeletionIsNoop() {
        let a = UUID(), b = UUID()
        let out = SyncMerge.apply(upserts: [], deletions: [a, UUID()], to: [grade(a, 6, t0), grade(b, 7, t0)], modifiedAt: \.modifiedAt)
        XCTAssertEqual(out.map(\.id), [b])
    }

    func testRemoteWinsWithoutLocal() {
        XCTAssertTrue(SyncMerge.remoteWins(local: nil, remote: .distantPast))
    }

    func testLegacyGradeDecodesModifiedAtFromDate() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","subject":"Mat","value":7,"date":1000}"#
        let g = try JSONDecoder().decode(Grade.self, from: Data(json.utf8))
        XCTAssertEqual(g.modifiedAt, g.date)
    }

    func testLegacyNoteDecodesModifiedAtFromCreatedAt() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","createdAt":5000}"#
        let n = try JSONDecoder().decode(Note.self, from: Data(json.utf8))
        XCTAssertEqual(n.modifiedAt, n.createdAt)
    }

    func testLegacyScheduleDecodesModifiedAtAsDistantPast() throws {
        let json = #"{"id":"x","classes":[]}"#
        let s = try JSONDecoder().decode(ScheduleData.self, from: Data(json.utf8))
        XCTAssertEqual(s.modifiedAt, .distantPast)
    }
}
