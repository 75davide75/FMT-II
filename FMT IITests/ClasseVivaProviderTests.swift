import XCTest
@testable import FMT_II

final class ClasseVivaProviderTests: XCTestCase {
    private let base = "https://web.spaggiari.eu/rest/v1"
    private let loginURL = "https://web.spaggiari.eu/rest/v1/auth/login"
    private let gradesURL = "https://web.spaggiari.eu/rest/v1/students/9000001/grades"
    private let periodsURL = "https://web.spaggiari.eu/rest/v1/students/9000001/periods"
    private let creds = RegistroCredentials(username: "S9000001X", password: "pw&segreta/1?", schoolCode: nil)

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Registri/\(name).json")
        return try Data(contentsOf: url)
    }

    private func rome(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// "Adesso" fisso, prima della scadenza del token di fixture (17:30+01:00).
    private let fixedNow = ISO8601DateFormatter().date(from: "2026-11-15T16:10:00+01:00")!

    private func makeProvider(_ m: MockTransport) -> ClasseVivaProvider {
        ClasseVivaProvider(transport: m, now: { self.fixedNow }, maxGradeProvider: { 10 })
    }

    private func session(expiresAt: Date? = nil) -> RegistroSession {
        RegistroSession(accountKey: "9000001", token: "fixture-classeviva-token-0001", expiresAt: expiresAt, extra: [:])
    }

    private func stubbedGrades(_ m: MockTransport) throws {
        m.stub("GET", gradesURL, body: try fixture("classeviva-grades"))
        m.stub("GET", periodsURL, body: try fixture("classeviva-periods"))
    }

    // MARK: login

    func testLoginSendsDocumentedRequestAndParsesSession() async throws {
        let m = MockTransport()
        m.stub("POST", loginURL, body: try fixture("classeviva-login"))
        let s = try await makeProvider(m).login(creds)
        XCTAssertEqual(m.requests.count, 1)
        let r = m.requests[0]
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.absoluteString, loginURL)
        XCTAssertEqual(r.value(forHTTPHeaderField: "Z-Dev-Apikey"), "Tg1NWEwNGIgIC0K")
        XCTAssertEqual(r.value(forHTTPHeaderField: "User-Agent"), "CVVS/std/4.2.3 Android/12")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(r.value(forHTTPHeaderField: "Z-Auth-Token"))
        let body = String(data: try XCTUnwrap(r.httpBody), encoding: .utf8)
        XCTAssertEqual(body, #"{"ident":null,"pass":"pw&segreta/1?","uid":"S9000001X"}"#)
        XCTAssertEqual(s.accountKey, "9000001")
        XCTAssertEqual(s.token, "fixture-classeviva-token-0001")
        XCTAssertEqual(s.expiresAt, ISO8601DateFormatter().date(from: "2026-11-15T17:30:00+01:00"))
    }

    func testWrongPasswordMapsToInvalidCredentials() async throws {
        for status in [422, 401] {
            let m = MockTransport()
            m.stub("POST", loginURL, status: status, body: try fixture("classeviva-login-failure"))
            do { _ = try await makeProvider(m).login(creds); XCTFail("status \(status)") }
            catch { XCTAssertEqual(error as? RegistroError, .invalidCredentials) }
            XCTAssertEqual(m.requests.count, 1) // nessun nuovo tentativo
        }
    }

    func testLoginStatusMapping() async throws {
        let cases: [(Int, RegistroError)] = [(403, .rateLimited), (429, .rateLimited), (500, .network), (503, .network)]
        for (status, expected) in cases {
            let m = MockTransport()
            m.stub("POST", loginURL, status: status)
            do { _ = try await makeProvider(m).login(creds); XCTFail("status \(status)") }
            catch { XCTAssertEqual(error as? RegistroError, expected, "status \(status)") }
        }
        // 200 non JSON, senza token, o con più profili (TODO-CV4)
        for body in ["<html>", "{}", #"{"choices":[{"ident":"G1","name":"A"}]}"#] {
            let m = MockTransport()
            m.stub("POST", loginURL, body: Data(body.utf8))
            do { _ = try await makeProvider(m).login(creds); XCTFail(body) }
            catch { guard case .unexpectedFormat = error as? RegistroError else { return XCTFail("\(error)") } }
        }
    }

    func testTransportErrorMapsToNetwork() async {
        struct Boom: Error {}
        struct Failing: HTTPTransport {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.notConnectedToInternet) }
        }
        let p = ClasseVivaProvider(transport: Failing(), now: { Date() }, maxGradeProvider: { 10 })
        do { _ = try await p.login(creds); XCTFail() } catch { XCTAssertEqual(error as? RegistroError, .network) }
        do { _ = try await p.fetchGrades(session()); XCTFail() } catch { XCTAssertEqual(error as? RegistroError, .network) }
    }

    func testCredentialsNeverAppearInRequestURL() async throws {
        let m = MockTransport()
        m.stub("POST", loginURL, body: try fixture("classeviva-login"))
        try stubbedGrades(m)
        let p = makeProvider(m)
        let s = try await p.login(creds)
        _ = try await p.fetchGrades(s)
        XCTAssertEqual(m.requests.count, 3)
        for r in m.requests {
            let url = r.url!.absoluteString
            XCTAssertFalse(url.contains("segreta"), url)
            XCTAssertFalse(url.contains("pw"), url)
            XCTAssertFalse(url.contains(s.token), url)
            XCTAssertNil(r.url?.query)
        }
        // La password compare solo nel corpo del login.
        XCTAssertTrue(String(data: m.requests[0].httpBody!, encoding: .utf8)!.contains("segreta"))
        XCTAssertNil(m.requests[1].httpBody)
    }

    // MARK: sessione

    func testRefreshAlwaysSessionExpired() async {
        let m = MockTransport()
        do { _ = try await makeProvider(m).refresh(session()); XCTFail() }
        catch { XCTAssertEqual(error as? RegistroError, .sessionExpired) }
        XCTAssertTrue(m.requests.isEmpty)
    }

    func testExpiredSessionThrowsWithoutCallingServer() async {
        let m = MockTransport()
        do { _ = try await makeProvider(m).fetchGrades(session(expiresAt: fixedNow.addingTimeInterval(-1))); XCTFail() }
        catch { XCTAssertEqual(error as? RegistroError, .sessionExpired) }
        XCTAssertTrue(m.requests.isEmpty)
    }

    func testUnauthorizedMapsToSessionExpired() async {
        let m = MockTransport()
        m.stub("GET", gradesURL, status: 401)
        do { _ = try await makeProvider(m).fetchGrades(session()); XCTFail() }
        catch { XCTAssertEqual(error as? RegistroError, .sessionExpired) }
    }

    func testDataEndpointStatusMapping() async {
        let cases: [(Int, RegistroError)] = [
            (403, .rateLimited), (429, .rateLimited), (500, .network), (502, .network),
            (404, .unexpectedFormat("404")),
            // TODO-CV12: il 422 NON diventa "nessun voto" (decisione del coordinatore).
            (422, .unexpectedFormat("422"))]
        for (status, expected) in cases {
            let m = MockTransport()
            m.stub("GET", gradesURL, status: status)
            do { _ = try await makeProvider(m).fetchGrades(session()); XCTFail("status \(status)") }
            catch { XCTAssertEqual(error as? RegistroError, expected, "status \(status)") }
        }
        let m = MockTransport()
        m.stub("GET", gradesURL, body: Data("<html>".utf8))
        do { _ = try await makeProvider(m).fetchGrades(session()); XCTFail() }
        catch { guard case .unexpectedFormat = error as? RegistroError else { return XCTFail("\(error)") } }
    }

    // MARK: voti

    func testGradesRequestsCarryDocumentedHeaders() async throws {
        let m = MockTransport()
        try stubbedGrades(m)
        _ = try await makeProvider(m).fetchGrades(session())
        XCTAssertEqual(m.requests.map { $0.url?.absoluteString }, [gradesURL, periodsURL])
        for r in m.requests {
            XCTAssertEqual(r.httpMethod, "GET")
            XCTAssertEqual(r.value(forHTTPHeaderField: "Z-Auth-Token"), "fixture-classeviva-token-0001")
            XCTAssertEqual(r.value(forHTTPHeaderField: "Z-Dev-Apikey"), "Tg1NWEwNGIgIC0K")
            XCTAssertEqual(r.value(forHTTPHeaderField: "User-Agent"), "CVVS/std/4.2.3 Android/12")
            XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
        }
    }

    func testGradesMapToVotoRemoto() async throws {
        let m = MockTransport()
        try stubbedGrades(m)
        let f = try await makeProvider(m).fetchGrades(session())
        XCTAssertEqual(f.skippedCount, 0)
        XCTAssertEqual(f.grades.count, 9)
        let by = Dictionary(uniqueKeysWithValues: f.grades.map { ($0.remoteId, $0) })

        let a = try XCTUnwrap(by["7000001"])
        XCTAssertEqual(a.provider, .classeviva)
        XCTAssertEqual(a.date, rome(2026, 9, 22))
        XCTAssertFalse(a.hasTime)
        XCTAssertEqual(a.subjectId, "900101")
        XCTAssertEqual(a.subjectName, "MATEMATICA")
        XCTAssertEqual(a.teacher, "DOCENTE PRIMO")
        XCTAssertEqual(a.rawValue, "7")
        XCTAssertEqual(a.numericValue, 7)
        XCTAssertEqual(a.kind, .written)
        XCTAssertEqual(a.kindRaw, "Scritto")
        XCTAssertNil(a.weight)
        XCTAssertEqual(a.period, "TRIMESTRE")
        XCTAssertEqual(a.comment, "Verifica sulle equazioni")
        XCTAssertFalse(a.notCounting)
        XCTAssertFalse(a.cancelled)
        XCTAssertNil(a.remoteModifiedAt)

        // Valore del registro, non la regola +-0,25 di FMT; commento vuoto -> nil; orale.
        let b = try XCTUnwrap(by["7000002"])
        XCTAssertEqual(b.rawValue, "6+"); XCTAssertEqual(b.numericValue, 6.25)
        XCTAssertEqual(b.kind, .oral); XCTAssertNil(b.comment)
        XCTAssertEqual(try XCTUnwrap(by["7000003"]).numericValue, 8.5)
        XCTAssertEqual(try XCTUnwrap(by["7000004"]).numericValue, 4.75)

        // Giudizio: non numerico, noAverage -> notCounting, componente "Unico" -> other.
        let ds = try XCTUnwrap(by["7000005"])
        XCTAssertEqual(ds.rawValue, "ds"); XCTAssertNil(ds.numericValue)
        XCTAssertTrue(ds.notCounting)
        XCTAssertEqual(ds.kind, .other); XCTAssertEqual(ds.kindRaw, "Unico")
        XCTAssertEqual(ds.teacher, "DOCENTE SECONDO")

        // Colore blu -> notCounting anche con noAverage false.
        let blue = try XCTUnwrap(by["7000006"])
        XCTAssertTrue(blue.notCounting); XCTAssertEqual(blue.numericValue, 6)

        let canc = try XCTUnwrap(by["7000007"])
        XCTAssertTrue(canc.cancelled); XCTAssertFalse(canc.notCounting)

        XCTAssertEqual(try XCTUnwrap(by["7000008"]).kind, .practical)
        XCTAssertTrue(f.grades.allSatisfy { $0.weight == nil && !$0.hasTime && $0.remoteModifiedAt == nil })
    }

    func testMissingTeacherAndNoAverageUseDefaults() async throws {
        let m = MockTransport()
        try stubbedGrades(m)
        let f = try await makeProvider(m).fetchGrades(session())
        let g = try XCTUnwrap(f.grades.first { $0.remoteId == "7000009" })
        XCTAssertNil(g.teacher)
        XCTAssertFalse(g.notCounting) // noAverage assente: solo il colore decide
        XCTAssertEqual(g.numericValue, 7.5)
    }

    func testDateOnlyIsRomeMidnight() async throws {
        let m = MockTransport()
        m.stub("GET", gradesURL, body: Data(gradeJSON(evtId: 1, date: "2026-11-14").utf8))
        let f = try await makeProvider(m).fetchGrades(session())
        let d = try XCTUnwrap(f.grades.first?.date)
        XCTAssertEqual(d, rome(2026, 11, 14))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute, c.second], [2026, 11, 14, 0, 0, 0])
        // Anche in ora legale (UTC+2).
        m.stub("GET", gradesURL, body: Data(gradeJSON(evtId: 1, date: "2026-07-01").utf8))
        let g = try await makeProvider(m).fetchGrades(session())
        XCTAssertEqual(g.grades.first?.date, rome(2026, 7, 1))
        XCTAssertEqual(g.grades.first?.date.timeIntervalSince1970, rome(2026, 6, 30).addingTimeInterval(24 * 3600).timeIntervalSince1970)
    }

    private func gradeJSON(evtId: Int, date: String, decimal: String = "7", display: String = "7") -> String {
        """
        {"grades":[{"subjectId":1,"subjectDesc":"FISICA","evtId":\(evtId),"evtDate":"\(date)",
        "decimalValue":\(decimal),"displayValue":"\(display)","notesForFamily":"","color":"green",
        "canceled":false,"periodDesc":"TRIMESTRE","componentDesc":"Scritto","weightFactor":1}]}
        """
    }

    func testUnparseableGradeIsSkippedAndCounted() async throws {
        let m = MockTransport()
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: try fixture("classeviva-grades")) as? [String: Any])
        var arr = try XCTUnwrap(obj["grades"] as? [[String: Any]])
        arr[1]["evtDate"] = "non una data"
        obj["grades"] = arr
        m.stub("GET", gradesURL, body: try JSONSerialization.data(withJSONObject: obj))
        let f = try await makeProvider(m).fetchGrades(session())
        XCTAssertEqual(f.skippedCount, 1)
        XCTAssertEqual(f.grades.count, 8)
        XCTAssertNil(f.grades.first { $0.remoteId == "7000002" })
        XCTAssertNotNil(f.grades.first { $0.remoteId == "7000001" })
    }

    func testPlaceholderZeroIsNotNumeric() async throws {
        let m = MockTransport()
        m.stub("GET", gradesURL, body: Data(gradeJSON(evtId: 1, date: "2026-10-01", decimal: "0", display: "ds").utf8))
        var f = try await makeProvider(m).fetchGrades(session())
        XCTAssertNil(f.grades.first?.numericValue)
        m.stub("GET", gradesURL, body: Data(gradeJSON(evtId: 1, date: "2026-10-01", decimal: "0", display: "0").utf8))
        f = try await makeProvider(m).fetchGrades(session())
        XCTAssertEqual(f.grades.first?.numericValue, 0)
        // Fuori scala: nil (maxGrade iniettato).
        m.stub("GET", gradesURL, body: Data(gradeJSON(evtId: 1, date: "2026-10-01", decimal: "30", display: "30").utf8))
        f = try await makeProvider(m).fetchGrades(session())
        XCTAssertNil(f.grades.first?.numericValue)
    }

    // MARK: periodo coperto

    func testCoveredRangeIsCurrentSchoolYear() async throws {
        let m = MockTransport()
        try stubbedGrades(m)
        let f = try await makeProvider(m).fetchGrades(session())
        let r = try XCTUnwrap(f.coveredRange)
        XCTAssertEqual(r.start, rome(2026, 9, 14))          // dateStart del primo periodo
        XCTAssertEqual(r.end, rome(2027, 6, 9))             // fine del giorno dateEnd dell'ultimo (2027-06-08)
    }

    func testPeriodsFailureGivesNilCoveredRangeButKeepsGrades() async throws {
        let m = MockTransport()
        m.stub("GET", gradesURL, body: try fixture("classeviva-grades"))
        m.stub("GET", periodsURL, status: 500)
        let f = try await makeProvider(m).fetchGrades(session())
        XCTAssertNil(f.coveredRange)
        XCTAssertEqual(f.grades.count, 9)
    }
}
