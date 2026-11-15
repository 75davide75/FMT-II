import XCTest
import Security
@testable import FMT_II

/// Trasporto finto: risposte per metodo+URL e registro delle richieste (usato dai test dei provider).
final class MockTransport: HTTPTransport {
    struct Canned { var status: Int; var body: Data; var headers: [String: String] = [:] }
    private(set) var requests: [URLRequest] = []
    private var responses: [String: Canned] = [:]

    private func key(_ method: String, _ url: String) -> String { method.uppercased() + " " + url }

    func stub(_ method: String = "GET", _ url: String, status: Int = 200, body: Data = Data(), headers: [String: String] = [:]) {
        responses[key(method, url)] = Canned(status: status, body: body, headers: headers)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard let url = request.url,
              let canned = responses[key(request.httpMethod ?? "GET", url.absoluteString)],
              let http = HTTPURLResponse(url: url, statusCode: canned.status, httpVersion: nil, headerFields: canned.headers)
        else { throw RegistroError.network }
        return (canned.body, http)
    }
}

final class RegistroCoreTests: XCTestCase {
    private let testService = "com.davide.fmtII.registro.tests"
    private var store: KeychainStore { KeychainStore(service: testService) }

    override func tearDown() {
        store.remove("k1")
        store.remove("k2")
        super.tearDown()
    }

    private func sample() -> VotoRemoto {
        VotoRemoto(provider: .classeviva, remoteId: "42", date: Date(timeIntervalSince1970: 1_700_000_000),
                   hasTime: false, subjectId: "S1", subjectName: "Matematica", teacher: "Rossi",
                   rawValue: "7+", numericValue: 7.25, kind: .written, kindRaw: "Scritto", weight: 100,
                   period: "Q1", comment: nil, notCounting: false, cancelled: false, remoteModifiedAt: nil)
    }

    func testStubsAreUnavailableAndThrowNotSupported() async {
        let stubs: [RegistroProvider] = [AxiosProvider(), NuvolaProvider(), MastercomProvider(), PronoteProvider()]
        let creds = RegistroCredentials(username: "u", password: "p", schoolCode: nil)
        let session = RegistroSession(accountKey: "a", token: "t", expiresAt: nil, extra: [:])
        for p in stubs {
            XCTAssertFalse(p.isAvailable, "\(p.id)")
            XCTAssertTrue(p.capabilities.isEmpty, "\(p.id)")
            do { _ = try await p.login(creds); XCTFail("login \(p.id)") }
            catch { XCTAssertEqual(error as? RegistroError, .notSupported) }
            do { _ = try await p.refresh(session); XCTFail("refresh \(p.id)") }
            catch { XCTAssertEqual(error as? RegistroError, .notSupported) }
            do { _ = try await p.fetchGrades(session); XCTFail("fetch \(p.id)") }
            catch { XCTAssertEqual(error as? RegistroError, .notSupported) }
        }
        XCTAssertEqual(stubs.map(\.id), [.axios, .nuvola, .mastercom, .pronote])
    }

    func testKeychainRoundTripAndRemove() throws {
        XCTAssertNil(store.data(for: "k1"))
        try store.set(Data("uno".utf8), for: "k1")
        XCTAssertEqual(store.data(for: "k1"), Data("uno".utf8))
        try store.set(Data("due".utf8), for: "k1")   // aggiorna l'elemento esistente
        XCTAssertEqual(store.data(for: "k1"), Data("due".utf8))
        store.remove("k1")
        XCTAssertNil(store.data(for: "k1"))
    }

    func testKeychainItemsAreThisDeviceOnly() throws {
        try store.set(Data("x".utf8), for: "k2")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testService,
            kSecAttrAccount as String: "k2",
            kSecReturnAttributes as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        var out: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &out), errSecSuccess)
        let attrs = try XCTUnwrap(out as? [String: Any])
        XCTAssertEqual(attrs[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        let sync = attrs[kSecAttrSynchronizable as String] as? Bool
        XCTAssertTrue(sync == nil || sync == false)
    }

    func testMockTransportRecordsRequestsAndMapsMissingToNetwork() async throws {
        let m = MockTransport()
        m.stub("POST", "https://x.test/a", status: 201, body: Data("ok".utf8))
        var r = URLRequest(url: URL(string: "https://x.test/a")!); r.httpMethod = "POST"
        let (d, resp) = try await m.send(r)
        XCTAssertEqual(resp.statusCode, 201); XCTAssertEqual(d, Data("ok".utf8))
        do { _ = try await m.send(URLRequest(url: URL(string: "https://x.test/b")!)); XCTFail() }
        catch { XCTAssertEqual(error as? RegistroError, .network) }
        XCTAssertEqual(m.requests.count, 2)
    }

    func testFingerprintChangesWhenValueChanges() {
        let a = sample()
        var b = a; b.rawValue = "8"
        var c = a; c.teacher = nil
        var d = a; d.subjectName = "Mate"; d.remoteId = "4"
        XCTAssertEqual(a.fingerprint().count, 64)
        XCTAssertEqual(a.fingerprint(), sample().fingerprint())
        XCTAssertNotEqual(a.fingerprint(), b.fingerprint())
        XCTAssertNotEqual(a.fingerprint(), c.fingerprint())
        // Confini tra campi non ambigui
        var e = a; e.remoteId = "4"; e.subjectName = "2Matematica"
        XCTAssertNotEqual(a.fingerprint(), e.fingerprint())
        var f = a; f.teacher = ""
        XCTAssertNotEqual(c.fingerprint(), f.fingerprint())
        var g = a; g.date = Date(timeIntervalSince1970: 1_700_000_000.5)
        XCTAssertNotEqual(a.fingerprint(), g.fingerprint())
        _ = d
    }
}
