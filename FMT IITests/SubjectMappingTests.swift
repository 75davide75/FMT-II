import XCTest
@testable import FMT_II

final class SubjectMappingTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SubjectMappingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testNormalizedKey() {
        XCTAssertEqual(SubjectMatcher.normalizedKey("MATEMATICA"), "matematica")
        XCTAssertEqual(SubjectMatcher.normalizedKey(" Matemàtica. "), "matematica")
        XCTAssertEqual(SubjectMatcher.normalizedKey("Ed. fisica"), "ed fisica")
        XCTAssertEqual(SubjectMatcher.normalizedKey("Lingua   e\tletteratura"), "lingua e letteratura")
    }

    func testReadableName() {
        XCTAssertEqual(SubjectMatcher.readableName("  SCIENZE   MOTORIE "), "Scienze motorie")
    }

    func testExactProposal() {
        let r = RemoteSubjectRef(id: nil, name: "MATEMATICA")
        XCTAssertEqual(SubjectMatcher.propose(r, appSubjects: ["Italiano", "Matematica"]),
                       .existing("Matematica", viaAlias: false))
    }

    func testAliasProposal() {
        let r = RemoteSubjectRef(id: "42", name: "LINGUA E LETTERATURA ITALIANA")
        XCTAssertEqual(SubjectMatcher.propose(r, appSubjects: ["Italiano"]),
                       .existing("Italiano", viaAlias: true))
    }

    func testExactBeatsAlias() {
        let r = RemoteSubjectRef(id: nil, name: "Lingua italiana")
        XCTAssertEqual(SubjectMatcher.propose(r, appSubjects: ["Italiano", "Lingua Italiana"]),
                       .existing("Lingua Italiana", viaAlias: false))
    }

    func testMultipleAliasMatchesAreDeterministic() {
        let r = RemoteSubjectRef(id: nil, name: "Italiano")
        XCTAssertEqual(SubjectMatcher.propose(r, appSubjects: ["Lingua italiana", "Italiano X"]),
                       .existing("Lingua italiana", viaAlias: true))
        XCTAssertEqual(SubjectMatcher.propose(r, appSubjects: ["Lingua italiana", "Lingua e letteratura italiana"]),
                       SubjectMatcher.propose(r, appSubjects: ["Lingua e letteratura italiana", "Lingua italiana"]))
    }

    func testNewProposalIsReadable() {
        let r = RemoteSubjectRef(id: nil, name: "SCIENZE MOTORIE E SPORTIVE")
        XCTAssertEqual(SubjectMatcher.propose(r, appSubjects: []), .new("Scienze motorie e sportive"))
    }

    func testRefKey() {
        XCTAssertEqual(RemoteSubjectRef(id: "7", name: "Storia").key, "7")
        XCTAssertEqual(RemoteSubjectRef(id: nil, name: " Matemàtica. ").key, "matematica")
    }

    func testUnconfirmedMappingReturnsNil() {
        let r = RemoteSubjectRef(id: nil, name: "Matematica")
        var table = SubjectMappingTable(entries: [r.key: "Mate"], confirmed: [])
        XCTAssertNil(table.appSubject(for: r))
        table.confirmed.insert(r.key)
        XCTAssertEqual(table.appSubject(for: r), "Mate")
    }

    func testStoreRoundTripsAndKeysAreSynced() {
        XCTAssertTrue(SettingsSync.syncedKeys.contains("registroSubjectMap"))
        XCTAssertTrue(SettingsSync.syncedKeys.contains("registroIgnored"))

        let store = RegistroSettingsStore(defaults: defaults)
        XCTAssertEqual(store.mapping, SubjectMappingTable(entries: [:], confirmed: []))
        XCTAssertTrue(store.ignored.isEmpty)

        store.mapping = SubjectMappingTable(entries: ["matematica": "Mate"], confirmed: ["matematica"])
        store.ignore("axios|1")
        let again = RegistroSettingsStore(defaults: defaults)
        XCTAssertEqual(again.mapping.entries, ["matematica": "Mate"])
        XCTAssertEqual(again.ignored, ["axios|1"])

        again.clearIgnored()
        XCTAssertTrue(RegistroSettingsStore(defaults: defaults).ignored.isEmpty)
        // Deve restare un valore scritto (altrimenti la sync non propaga l'azzeramento).
        XCTAssertNotNil(defaults.object(forKey: "registroIgnored"))
    }

    func testCorruptDataFallsBackToEmpty() {
        defaults.set(Data([0xFF, 0x00, 0x12]), forKey: "registroSubjectMap")
        defaults.set("non data", forKey: "registroIgnored")
        let store = RegistroSettingsStore(defaults: defaults)
        XCTAssertTrue(store.mapping.entries.isEmpty)
        XCTAssertTrue(store.ignored.isEmpty)
        store.ignore("x")
        XCTAssertEqual(store.ignored, ["x"])
    }
}
