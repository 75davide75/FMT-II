import XCTest
import CryptoKit
@testable import FMT_II

final class ArgoProviderTests: XCTestCase {
    // URL documentati (Argo.md § 1).
    private let authURL = "https://auth.portaleargo.it/oauth2/auth"
    private let ssoURL = "https://www.portaleargo.it/auth/sso/login"
    private let tokenURL = "https://auth.portaleargo.it/oauth2/token"
    private let loginURL = "https://www.portaleargo.it/appfamiglia/api/rest/login"
    private let profiloURL = "https://www.portaleargo.it/appfamiglia/api/rest/profilo"
    private let dashboardURL = "https://www.portaleargo.it/appfamiglia/api/rest/dashboard/dashboard"
    private let clientId = "72fd6dea-d0ab-4bb9-8eaa-3ac24c84886c"
    private let callback = "it.argosoft.didup.famiglia.new://login-callback"

    // Catena di redirect inventata (passo 2): verifier OAuth -> consenso -> verifier del consenso -> callback.
    private let hop1 = "https://auth.portaleargo.it/oauth2/auth?client_id=x&login_verifier=lv-0001"
    private let hop2 = "https://www.portaleargo.it/auth/sso/consent?consent_challenge=cc-0001"
    private let hop3 = "https://auth.portaleargo.it/oauth2/auth?client_id=x&consent_verifier=cv-0001"
    private let code = "fixture-code-0001"

    private let creds = RegistroCredentials(username: "studente.prova", password: "pw&segreta/1?", schoolCode: "SC12345")

    /// "Adesso" fisso: 15:10:00 GMT, la stessa ora dell'header `Date` della risposta del token.
    private let fixedNow = ISO8601DateFormatter().date(from: "2026-11-15T16:10:00+01:00")!
    private let tokenDateHeader = "Sun, 15 Nov 2026 15:10:00 GMT"

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

    /// Byte "casuali" tutti a zero: ogni carattere generato è "A" (alfabeto A-Z a-z 0-9).
    private func makeProvider(_ m: HTTPTransport,
                              randomBytes: @escaping (Int) -> [UInt8]? = { [UInt8](repeating: 0, count: $0) }) -> ArgoProvider {
        ArgoProvider(transport: m, now: { self.fixedNow }, maxGradeProvider: { 10 },
                     randomBytes: randomBytes, timeZone: TimeZone(identifier: "Europe/Rome")!)
    }

    private var verifier: String { String(repeating: "A", count: 43) }
    private var challengeForVerifier: String { pkceChallenge(verifier) }

    private func pkceChallenge(_ v: String) -> String {
        Data(SHA256.hash(data: Data(v.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// URL del passo 1 esattamente come nel documento (§ 2, passo 1), con stato/nonce/verifier deterministici.
    private var startURL: String {
        let a22 = String(repeating: "A", count: 22)
        return authURL
            + "?redirect_uri=it.argosoft.didup.famiglia.new%3A%2F%2Flogin-callback"
            + "&client_id=\(clientId)"
            + "&response_type=code"
            + "&prompt=login"
            + "&state=\(a22)"
            + "&nonce=\(a22)"
            + "&scope=openid%20offline%20profile%20user.roles%20argo"
            + "&code_challenge=\(challengeForVerifier)"
            + "&code_challenge_method=S256"
    }

    private func session(expiresAt: Date? = nil) -> RegistroSession {
        RegistroSession(
            accountKey: "XX00000|ALU-0001", token: "fixture-argo-access-token-0001",
            expiresAt: expiresAt ?? fixedNow.addingTimeInterval(3599),
            extra: ["x-auth-token": "fixture-argo-x-auth-token-0001", "codMin": "XX00000",
                    "opzioni": #"{"VALUTAZIONI_GIORNALIERE":true,"VOTI_GIUDIZI":true}"#,
                    "annoInizio": "2026-09-01", "annoFine": "2027-08-31"])
    }

    /// Tutti i passi del login con esito positivo (1–5).
    private func stubLogin(_ m: MockTransport) throws {
        m.stub("GET", startURL, status: 302, headers: [
            "Location": "https://www.portaleargo.it/auth/sso/login/?login_challenge=0123abcdef",
            "Set-Cookie": "oauth2_authentication_csrf=csrf-0001; Path=/; Secure; HttpOnly"])
        m.stub("POST", ssoURL, status: 302, headers: [
            "Location": hop1, "Set-Cookie": "sso_session=sso-0001; Path=/; Secure"])
        m.stub("GET", hop1, status: 302, headers: ["Location": hop2])
        m.stub("GET", hop2, status: 302, headers: ["Location": hop3])
        m.stub("GET", hop3, status: 302, headers: ["Location": "\(callback)?code=\(code)&scope=openid&state=x"])
        m.stub("POST", tokenURL, body: try fixture("argo-token"), headers: ["Date": tokenDateHeader])
        m.stub("POST", loginURL, body: try fixture("argo-login"))
        m.stub("GET", profiloURL, body: try fixture("argo-profilo"))
    }

    private func bodyString(_ r: URLRequest) -> String? { r.httpBody.flatMap { String(data: $0, encoding: .utf8) } }

    private func request(_ m: MockTransport, _ method: String, _ url: String) throws -> URLRequest {
        try XCTUnwrap(m.requests.first { $0.httpMethod == method && $0.url?.absoluteString == url }, "\(method) \(url)")
    }

    private func assertError<T>(_ expected: RegistroError, _ op: () async throws -> T,
                                file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await op(); XCTFail("nessun errore, atteso \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? RegistroError, expected, file: file, line: line) }
    }

    // MARK: metadati

    func testProviderMetadata() {
        let p = makeProvider(MockTransport())
        XCTAssertEqual(p.id, .argo)
        XCTAssertTrue(p.isAvailable)
        XCTAssertEqual(p.loginFields, [.schoolCode, .username, .password])
        XCTAssertFalse(p.capabilities.contains(.forniscePeso))   // TODO-AR11
        XCTAssertFalse(p.capabilities.contains(.fornisceOra))    // solo date
    }

    // MARK: login, passo per passo

    func testSchoolCodeIsRequired() async {
        for school in [nil, "", "   "] as [String?] {
            let m = MockTransport()
            let c = RegistroCredentials(username: "u", password: "p", schoolCode: school)
            await assertError(.invalidCredentials) { try await self.makeProvider(m).login(c) }
            XCTAssertTrue(m.requests.isEmpty, "nessuna richiesta di rete")
        }
    }

    func testStep1StartsOAuthWithPKCEWithoutFollowingRedirect() async throws {
        let m = MockTransport()
        try stubLogin(m)
        _ = try await makeProvider(m).login(creds)
        let r = m.requests[0]
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertEqual(r.url?.absoluteString, startURL)
        XCTAssertNil(r.httpBody)
        XCTAssertNil(r.value(forHTTPHeaderField: "Cookie"))
        XCTAssertTrue(m.withoutRedirect[0])
    }

    func testStep2PostsCredentialsFormAndFollowsRedirectsWithCookies() async throws {
        let m = MockTransport()
        try stubLogin(m)
        _ = try await makeProvider(m).login(creds)
        let urls = m.requests.map { "\($0.httpMethod!) \($0.url!.absoluteString)" }
        XCTAssertEqual(urls, ["GET \(startURL)", "POST \(ssoURL)", "GET \(hop1)", "GET \(hop2)", "GET \(hop3)",
                              "POST \(tokenURL)", "POST \(loginURL)", "GET \(profiloURL)"])
        // Passi 1–2 senza redirect automatici; 3–5 normali.
        XCTAssertEqual(m.withoutRedirect, [true, true, true, true, true, false, false, false])

        let post = m.requests[1]
        XCTAssertEqual(post.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(bodyString(post),
                       "challenge=0123abcdef&client_id=\(clientId)&prefill=false&famiglia_customer_code=SC12345"
                       + "&username=studente.prova&password=pw%26segreta%2F1%3F&remember_me=false&login=true")
        // Cookie jar: il cookie di auth.portaleargo.it non va a www, e viceversa.
        XCTAssertNil(post.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(m.requests[2].value(forHTTPHeaderField: "Cookie"), "oauth2_authentication_csrf=csrf-0001")
        XCTAssertEqual(m.requests[3].value(forHTTPHeaderField: "Cookie"), "sso_session=sso-0001")
        XCTAssertEqual(m.requests[4].value(forHTTPHeaderField: "Cookie"), "oauth2_authentication_csrf=csrf-0001")
        for r in m.requests[2...4] { XCTAssertNil(r.httpBody) }
        // Nessun cookie oltre il passo 2.
        for r in m.requests[5...] { XCTAssertNil(r.value(forHTTPHeaderField: "Cookie")) }
    }

    func testStep2RelativeLocationIsResolved() async throws {
        let m = MockTransport()
        try stubLogin(m)
        m.stub("POST", ssoURL, status: 303, headers: ["Location": "/auth/sso/consent?consent_challenge=cc-0001"])
        _ = try await makeProvider(m).login(creds)
        XCTAssertEqual(m.requests[2].url?.absoluteString, hop2)
    }

    func testStep2CompletedLoginPageFollowsDataAuthAppRedirectLink() async throws {
        let m = MockTransport()
        try stubLogin(m)
        let html = """
        <html><body><h1>Accesso completato</h1>
        <a class="btn" href="https://www.portaleargo.it/altro">Altro</a>
        <a class="btn" data-auth-app-redirect href="https://auth.portaleargo.it/oauth2/auth?client_id=x&amp;login_verifier=lv-0001">Continua</a>
        </body></html>
        """
        m.stub("POST", ssoURL, body: Data(html.utf8))
        _ = try await makeProvider(m).login(creds)
        XCTAssertEqual(m.requests[2].url?.absoluteString, hop1)
        XCTAssertEqual(m.requests.count, 8)

        // Il link può puntare direttamente alla callback dell'app.
        let m2 = MockTransport()
        try stubLogin(m2)
        m2.stub("POST", ssoURL, body: Data(#"<a data-auth-app-redirect="" href='\#(callback)?code=\#(code)'>Apri</a>"#.utf8))
        _ = try await makeProvider(m2).login(creds)
        XCTAssertEqual(m2.requests.map { $0.url!.absoluteString }, [startURL, ssoURL, tokenURL, loginURL, profiloURL])
    }

    func testWrongPasswordMapsToInvalidCredentials() async throws {
        let m = MockTransport()
        try stubLogin(m)
        m.stub("POST", ssoURL, body: Data(#"<div class="alert">Username e/o password non validi</div>"#.utf8))
        await assertError(.invalidCredentials) { try await self.makeProvider(m).login(self.creds) }
        XCTAssertEqual(m.requests.count, 2) // nessun nuovo tentativo, nessun passo successivo
    }

    func testWrongPasswordWith4xxHTMLWithoutLocationMapsToInvalidCredentials() async throws {
        // Passo 2 senza `Location` = credenziali errate, qualunque sia lo status 4xx (§ 2.2);
        // 403/429 restano `.rateLimited` (vedi testLoginStatusMappingAtEveryStep).
        for status in [400, 401, 404, 422] {
            let m = MockTransport()
            try stubLogin(m)
            m.stub("POST", ssoURL, status: status,
                   body: Data(#"<div class="alert">Username e/o password non validi</div>"#.utf8))
            await assertError(.invalidCredentials) { try await self.makeProvider(m).login(self.creds) }
            XCTAssertEqual(m.requests.count, 2, "status \(status): nessun nuovo tentativo")
        }
    }

    func testMissingLoginChallengeIsUnexpectedFormat() async throws {
        for headers in [[:], ["Location": "https://www.portaleargo.it/auth/sso/login/"]] as [[String: String]] {
            let m = MockTransport()
            try stubLogin(m)
            m.stub("GET", startURL, status: 302, headers: headers)
            await assertError(.unexpectedFormat("login_challenge")) { try await self.makeProvider(m).login(self.creds) }
            XCTAssertEqual(m.requests.count, 1)
        }
    }

    func testRedirectChainWithoutCodeIsUnexpectedFormat() async throws {
        // Pagina intermedia senza Location né link.
        var m = MockTransport()
        try stubLogin(m)
        m.stub("GET", hop2, body: Data("<html>consenso</html>".utf8))
        await assertError(.unexpectedFormat("code")) { try await self.makeProvider(m).login(self.creds) }
        // Callback senza `code`.
        m = MockTransport()
        try stubLogin(m)
        m.stub("GET", hop3, status: 302, headers: ["Location": "\(callback)?error=access_denied"])
        await assertError(.unexpectedFormat("code")) { try await self.makeProvider(m).login(self.creds) }
        XCTAssertFalse(m.requests.contains { $0.url?.absoluteString == tokenURL })
    }

    func testRedirectOutsideArgoIsNotFollowed() async throws {
        for bad in ["https://example.com/steal", "http://auth.portaleargo.it/oauth2/auth?x=1", "https://portaleargo.it.example.com/x"] {
            let m = MockTransport()
            try stubLogin(m)
            m.stub("GET", hop1, status: 302, headers: ["Location": bad])
            await assertError(.unexpectedFormat("redirect")) { try await self.makeProvider(m).login(self.creds) }
            XCTAssertFalse(m.requests.contains { $0.url?.absoluteString == bad }, bad)
        }
    }

    func testRedirectLoopIsBounded() async throws {
        let m = MockTransport()
        try stubLogin(m)
        m.stub("GET", hop1, status: 302, headers: ["Location": hop1])
        await assertError(.unexpectedFormat("redirect")) { try await self.makeProvider(m).login(self.creds) }
        XCTAssertLessThan(m.requests.count, 20)
    }

    func testStep3ExchangesCodeWithVerifier() async throws {
        let m = MockTransport()
        try stubLogin(m)
        _ = try await makeProvider(m).login(creds)
        let r = try request(m, "POST", tokenURL)
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(bodyString(r),
                       "code=\(code)&grant_type=authorization_code"
                       + "&redirect_uri=it.argosoft.didup.famiglia.new%3A%2F%2Flogin-callback"
                       + "&code_verifier=\(verifier)&client_id=\(clientId)")
    }

    func testPKCEUsesSecureRandomValues() async throws {
        let m = MockTransport()
        try stubLogin(m)
        m.stubPrefix("GET", authURL + "?redirect_uri=", status: 302, headers: [
            "Location": "https://www.portaleargo.it/auth/sso/login/?login_challenge=0123abcdef"])
        let p = ArgoProvider(transport: m, now: { self.fixedNow }, maxGradeProvider: { 10 })
        _ = try await p.login(creds)
        _ = try await p.login(creds)
        let alnum = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let starts = m.requests.filter { $0.url!.absoluteString.hasPrefix(self.authURL + "?redirect_uri=") }
        let tokens = m.requests.filter { $0.url?.absoluteString == self.tokenURL }
        XCTAssertEqual(starts.count, 2); XCTAssertEqual(tokens.count, 2)
        var verifiers: [String] = []
        for (start, tokenReq) in zip(starts, tokens) {
            let items = try XCTUnwrap(URLComponents(url: start.url!, resolvingAgainstBaseURL: false)?.queryItems)
            let v = { (n: String) in items.first { $0.name == n }?.value ?? "" }
            XCTAssertEqual(v("state").count, 22); XCTAssertEqual(v("nonce").count, 22)
            XCTAssertNotEqual(v("state"), v("nonce"))
            XCTAssertTrue(CharacterSet(charactersIn: v("state") + v("nonce")).isSubset(of: alnum))
            XCTAssertEqual(v("code_challenge_method"), "S256")
            // Il verifier del passo 3 corrisponde alla challenge del passo 1.
            let ver = verifierIn(tokenReq)
            XCTAssertEqual(ver.count, 43)
            XCTAssertTrue(CharacterSet(charactersIn: ver).isSubset(of: alnum))
            XCTAssertEqual(v("code_challenge"), pkceChallenge(ver))
            verifiers.append(ver)
        }
        XCTAssertNotEqual(verifiers.first, verifiers.last)
    }

    private func verifierIn(_ r: URLRequest) -> String {
        let body = bodyString(r) ?? ""
        return URLComponents(string: "x:?" + body)?.queryItems?.first { $0.name == "code_verifier" }?.value ?? ""
    }

    func testRandomSourceFailureStopsLogin() async {
        let m = MockTransport()
        await assertError(.unexpectedFormat("random")) { try await self.makeProvider(m, randomBytes: { _ in nil }).login(self.creds) }
        XCTAssertTrue(m.requests.isEmpty)
    }

    func testStep3TokenErrorIsUnexpectedFormat() async throws {
        for status in [400, 200] {
            let m = MockTransport()
            try stubLogin(m)
            m.stub("POST", tokenURL, status: status, body: try fixture("argo-token-error"))
            await assertError(.unexpectedFormat("token")) { try await self.makeProvider(m).login(self.creds) }
            XCTAssertFalse(m.requests.contains { $0.url?.absoluteString == loginURL })
        }
    }

    func testStep4AppLoginRequest() async throws {
        let m = MockTransport()
        try stubLogin(m)
        _ = try await makeProvider(m).login(creds)
        let r = try request(m, "POST", loginURL)
        XCTAssertEqual(r.value(forHTTPHeaderField: "accept"), "application/json")
        XCTAssertEqual(r.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(r.value(forHTTPHeaderField: "authorization"), "Bearer fixture-argo-access-token-0001")
        XCTAssertEqual(r.value(forHTTPHeaderField: "argo-client-version"), "1.30.2")
        // Date (15:10:00 GMT) + expires_in 3599, in ora locale (Roma nel test).
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-date-exp-auth"), "2026-11-15 17:09:59.000")
        XCTAssertNil(r.value(forHTTPHeaderField: "x-auth-token"))
        XCTAssertNil(r.value(forHTTPHeaderField: "x-cod-min"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(r.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["lista-opzioni-notifiche", "lista-x-auth-token", "clientID"])
        XCTAssertEqual(body["lista-opzioni-notifiche"] as? String, "{}")
        XCTAssertEqual(body["lista-x-auth-token"] as? String, "[]")
        XCTAssertEqual((body["clientID"] as? String)?.count, 163)
    }

    func testStep5ProfiloRequestAndSessionMapping() async throws {
        let m = MockTransport()
        try stubLogin(m)
        let s = try await makeProvider(m).login(creds)
        let r = try request(m, "GET", profiloURL)
        XCTAssertNil(r.httpBody)
        XCTAssertEqual(r.value(forHTTPHeaderField: "authorization"), "Bearer fixture-argo-access-token-0001")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-auth-token"), "fixture-argo-x-auth-token-0001")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-cod-min"), "XX00000")
        XCTAssertEqual(r.value(forHTTPHeaderField: "argo-client-version"), "1.30.2")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-date-exp-auth"), "2026-11-15 17:09:59.000")
        XCTAssertEqual(r.value(forHTTPHeaderField: "accept"), "application/json")
        XCTAssertEqual(r.value(forHTTPHeaderField: "content-type"), "application/json")

        XCTAssertEqual(s.accountKey, "XX00000|ALU-0001")
        XCTAssertEqual(s.token, "fixture-argo-access-token-0001")
        XCTAssertEqual(s.expiresAt, fixedNow.addingTimeInterval(3599))
        XCTAssertEqual(s.extra, session().extra)
        // Nessun refresh_token / id_token salvato.
        XCTAssertFalse(s.extra.values.contains { $0.contains("refresh") || $0.contains("id-token") })
    }

    func testMissingDateHeaderUsesNow() async throws {
        let m = MockTransport()
        try stubLogin(m)
        m.stub("POST", tokenURL, body: try fixture("argo-token"))
        let s = try await makeProvider(m).login(creds)
        XCTAssertEqual(s.expiresAt, fixedNow.addingTimeInterval(3599))
    }

    func testLoginStatusMappingAtEveryStep() async throws {
        let steps: [(String, String)] = [("GET", startURL), ("POST", ssoURL), ("GET", hop2), ("POST", tokenURL),
                                         ("POST", loginURL), ("GET", profiloURL)]
        let cases: [(Int, RegistroError)] = [(403, .rateLimited), (429, .rateLimited), (500, .network), (503, .network)]
        for (method, url) in steps {
            for (status, expected) in cases {
                let m = MockTransport()
                try stubLogin(m)
                m.stub(method, url, status: status)
                await assertError(expected) { try await self.makeProvider(m).login(self.creds) }
                XCTAssertEqual(m.requests.last?.url?.absoluteString, url, "nessun passo dopo l'errore")
            }
        }
        // 401: sul profilo -> sessionExpired (§ 3.4); sul login applicativo non è documentato.
        var m = MockTransport()
        try stubLogin(m)
        m.stub("GET", profiloURL, status: 401)
        await assertError(.sessionExpired) { try await self.makeProvider(m).login(self.creds) }
        m = MockTransport()
        try stubLogin(m)
        m.stub("POST", loginURL, status: 401)
        await assertError(.unexpectedFormat("401")) { try await self.makeProvider(m).login(self.creds) }
    }

    func testApiSuccessFalseAndClientVersion() async throws {
        let outdated = Data(#"{"success":false,"msg":"Per continuare installa l'ULTIMA VERSIONE dell'app"}"#.utf8)
        for (method, url) in [("POST", loginURL), ("GET", profiloURL)] {
            var m = MockTransport()
            try stubLogin(m)
            m.stub(method, url, body: try fixture("argo-api-error"))
            await assertError(.unexpectedFormat("success")) { try await self.makeProvider(m).login(self.creds) }
            m = MockTransport()
            try stubLogin(m)
            m.stub(method, url, body: outdated)
            await assertError(.unexpectedFormat("client-version")) { try await self.makeProvider(m).login(self.creds) }
            XCTAssertEqual(m.requests.last?.url?.absoluteString, url, "nessun nuovo tentativo")
        }
        var m = MockTransport()
        m.stub("POST", dashboardURL, body: try fixture("argo-api-error"))
        await assertError(.unexpectedFormat("success")) { try await self.makeProvider(m).fetchGrades(self.session()) }
        m = MockTransport()
        m.stub("POST", dashboardURL, body: outdated)
        await assertError(.unexpectedFormat("client-version")) { try await self.makeProvider(m).fetchGrades(self.session()) }
        XCTAssertEqual(m.requests.count, 1)
    }

    func testDisabledProfileIsNotSupported() async throws {
        var login = try XCTUnwrap(JSONSerialization.jsonObject(with: try fixture("argo-login")) as? [String: Any])
        var data = try XCTUnwrap(login["data"] as? [[String: Any]])
        data[0]["profiloDisabilitato"] = true
        login["data"] = data
        var m = MockTransport()
        try stubLogin(m)
        m.stub("POST", loginURL, body: try JSONSerialization.data(withJSONObject: login))
        await assertError(.notSupported) { try await self.makeProvider(m).login(self.creds) }

        var profilo = try XCTUnwrap(JSONSerialization.jsonObject(with: try fixture("argo-profilo")) as? [String: Any])
        var pd = try XCTUnwrap(profilo["data"] as? [String: Any])
        pd["profiloDisabilitato"] = true
        profilo["data"] = pd
        m = MockTransport()
        try stubLogin(m)
        m.stub("GET", profiloURL, body: try JSONSerialization.data(withJSONObject: profilo))
        await assertError(.notSupported) { try await self.makeProvider(m).login(self.creds) }
    }

    func testMultipleProfilesAreRejected() async throws {
        var login = try XCTUnwrap(JSONSerialization.jsonObject(with: try fixture("argo-login")) as? [String: Any])
        let data = try XCTUnwrap(login["data"] as? [[String: Any]])
        login["data"] = data + data
        let m = MockTransport()
        try stubLogin(m)
        m.stub("POST", loginURL, body: try JSONSerialization.data(withJSONObject: login))
        await assertError(.unexpectedFormat("profili")) { try await self.makeProvider(m).login(self.creds) }
        XCTAssertFalse(m.requests.contains { $0.url?.absoluteString == profiloURL })
    }

    func testMalformedLoginOrProfiloIsUnexpectedFormat() async throws {
        for body in ["<html>", "{}", #"{"success":true,"data":[{"codMin":"XX00000"}]}"#] {
            let m = MockTransport()
            try stubLogin(m)
            m.stub("POST", loginURL, body: Data(body.utf8))
            do { _ = try await makeProvider(m).login(creds); XCTFail(body) }
            catch { guard case .unexpectedFormat = error as? RegistroError else { return XCTFail("\(error)") } }
        }
        for body in [#"{"success":true,"data":{"anno":{"dataInizio":"2026-09-01","dataFine":"2027-08-31"},"alunno":{}}}"#,
                     #"{"success":true,"data":{"anno":{"dataInizio":"01/09/2026","dataFine":"2027-08-31"},"alunno":{"pk":"A"}}}"#] {
            let m = MockTransport()
            try stubLogin(m)
            m.stub("GET", profiloURL, body: Data(body.utf8))
            do { _ = try await makeProvider(m).login(creds); XCTFail(body) }
            catch { guard case .unexpectedFormat = error as? RegistroError else { return XCTFail("\(error)") } }
        }
    }

    func testTransportErrorMapsToNetwork() async {
        struct Failing: HTTPTransport {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.notConnectedToInternet) }
            func sendWithoutRedirect(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.timedOut) }
        }
        let p = makeProvider(Failing())
        await assertError(.network) { try await p.login(self.creds) }
        await assertError(.network) { try await p.fetchGrades(self.session()) }
    }

    func testTransportWithoutRedirectSupportFailsSafely() async {
        // Un trasporto che non implementa `sendWithoutRedirect` non segue redirect "di nascosto": errore.
        struct SendOnly: HTTPTransport {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                XCTFail("il passo 1 non deve usare send"); throw URLError(.badURL)
            }
        }
        await assertError(.network) { try await self.makeProvider(SendOnly()).login(self.creds) }
    }

    func testCredentialsNeverAppearInRequestURL() async throws {
        let m = MockTransport()
        try stubLogin(m)
        m.stub("POST", dashboardURL, body: try fixture("argo-dashboard"))
        let p = makeProvider(m)
        let s = try await p.login(creds)
        _ = try await p.fetchGrades(s)
        XCTAssertEqual(m.requests.count, 9)
        for r in m.requests {
            let url = r.url!.absoluteString
            for secret in ["segreta", "pw%26", "studente.prova", "SC12345", s.token, s.extra["x-auth-token"]!, code] {
                XCTAssertFalse(url.contains(secret), "\(secret) in \(url)")
            }
        }
        // La password compare solo nel corpo del form SSO (passo 2).
        let withPassword = m.requests.filter { bodyString($0)?.contains("segreta") ?? false }
        XCTAssertEqual(withPassword.map { $0.url?.absoluteString }, [ssoURL])
    }

    // MARK: sessione

    func testRefreshAlwaysSessionExpired() async {
        let m = MockTransport()
        await assertError(.sessionExpired) { try await self.makeProvider(m).refresh(self.session()) }
        XCTAssertTrue(m.requests.isEmpty)
    }

    func testExpiredSessionThrowsWithoutCallingServer() async throws {
        // Scaduta, a meno di 2 minuti dalla scadenza (§ 3.4), o senza scadenza/extra.
        var stale = session(); stale.expiresAt = nil
        var noExtra = session(); noExtra.extra["x-auth-token"] = nil
        for s in [session(expiresAt: fixedNow.addingTimeInterval(-1)), session(expiresAt: fixedNow.addingTimeInterval(119)), stale, noExtra] {
            let m = MockTransport()
            await assertError(.sessionExpired) { try await self.makeProvider(m).fetchGrades(s) }
            XCTAssertTrue(m.requests.isEmpty)
        }
        // A 2 minuti esatti la sessione è ancora buona.
        let m = MockTransport()
        m.stub("POST", dashboardURL, body: Data(dashboardJSON([]).utf8))
        _ = try await makeProvider(m).fetchGrades(session(expiresAt: fixedNow.addingTimeInterval(120)))
        XCTAssertEqual(m.requests.count, 1)
    }

    func testUnauthorizedMapsToSessionExpired() async {
        let m = MockTransport()
        m.stub("POST", dashboardURL, status: 401)
        await assertError(.sessionExpired) { try await self.makeProvider(m).fetchGrades(self.session()) }
    }

    func testDataEndpointStatusMapping() async {
        let cases: [(Int, RegistroError)] = [(403, .rateLimited), (429, .rateLimited), (500, .network), (502, .network),
                                             (404, .unexpectedFormat("404")), (400, .unexpectedFormat("400"))]
        for (status, expected) in cases {
            let m = MockTransport()
            m.stub("POST", dashboardURL, status: status)
            await assertError(expected) { try await self.makeProvider(m).fetchGrades(self.session()) }
            XCTAssertEqual(m.requests.count, 1)
        }
        for body in ["<html>", #"{"success":true,"data":{"dati":[]}}"#, #"{"success":true,"data":{"dati":[{}]}}"#] {
            let m = MockTransport()
            m.stub("POST", dashboardURL, body: Data(body.utf8))
            do { _ = try await makeProvider(m).fetchGrades(session()); XCTFail(body) }
            catch { guard case .unexpectedFormat = error as? RegistroError else { return XCTFail("\(error)") } }
        }
    }

    // MARK: voti (passo 6)

    func testDashboardRequestCarriesDocumentedHeadersAndBody() async throws {
        let m = MockTransport()
        m.stub("POST", dashboardURL, body: try fixture("argo-dashboard"))
        _ = try await makeProvider(m).fetchGrades(session())
        XCTAssertEqual(m.requests.count, 1)
        let r = m.requests[0]
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.absoluteString, dashboardURL)
        XCTAssertFalse(m.withoutRedirect[0])
        XCTAssertEqual(r.value(forHTTPHeaderField: "authorization"), "Bearer fixture-argo-access-token-0001")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-auth-token"), "fixture-argo-x-auth-token-0001")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-cod-min"), "XX00000")
        XCTAssertEqual(r.value(forHTTPHeaderField: "argo-client-version"), "1.30.2")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-date-exp-auth"), "2026-11-15 17:09:59.000")
        XCTAssertEqual(r.value(forHTTPHeaderField: "accept"), "application/json")
        XCTAssertEqual(r.value(forHTTPHeaderField: "content-type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(r.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["dataultimoaggiornamento", "opzioni"])
        XCTAssertEqual(body["dataultimoaggiornamento"] as? String, "2026-09-01 00:00:00.000")
        // `opzioni` è una STRINGA JSON con l'oggetto {chiave: valore} del passo 4.
        let opz = try XCTUnwrap(body["opzioni"] as? String)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(opz.utf8)) as? [String: Bool])
        XCTAssertEqual(obj, ["VALUTAZIONI_GIORNALIERE": true, "VOTI_GIUDIZI": true])
    }

    func testGradesMapToVotoRemoto() async throws {
        let m = MockTransport()
        m.stub("POST", dashboardURL, body: try fixture("argo-dashboard"))
        let f = try await makeProvider(m).fetchGrades(session())
        XCTAssertEqual(f.skippedCount, 0)
        XCTAssertEqual(f.grades.count, 7)
        let by = Dictionary(uniqueKeysWithValues: f.grades.map { ($0.remoteId, $0) })

        let a = try XCTUnwrap(by["VOTO-0001"])
        XCTAssertEqual(a.provider, .argo)
        XCTAssertEqual(a.date, rome(2026, 9, 23))
        XCTAssertFalse(a.hasTime)
        XCTAssertEqual(a.subjectId, "MAT-0001")
        XCTAssertEqual(a.subjectName, "MATEMATICA")
        XCTAssertEqual(a.teacher, "Docente A.")
        XCTAssertEqual(a.rawValue, "7")
        XCTAssertEqual(a.numericValue, 7)
        XCTAssertEqual(a.kind, .written)
        XCTAssertEqual(a.kindRaw, "S")
        XCTAssertNil(a.weight)
        XCTAssertEqual(a.period, "PRIMO QUADRIMESTRE")
        XCTAssertEqual(a.comment, "Verifica sulle equazioni")
        XCTAssertFalse(a.notCounting)
        XCTAssertFalse(a.cancelled)
        XCTAssertNil(a.remoteModifiedAt)

        let b = try XCTUnwrap(by["VOTO-0002"])
        XCTAssertEqual(b.rawValue, "6+"); XCTAssertEqual(b.numericValue, 6.25)
        XCTAssertEqual(b.kind, .oral); XCTAssertEqual(b.kindRaw, "N"); XCTAssertNil(b.comment)
        let c = try XCTUnwrap(by["VOTO-0003"])
        XCTAssertEqual(c.rawValue, "7½"); XCTAssertEqual(c.numericValue, 7.5)
        XCTAssertEqual(c.comment, "Buon lavoro") // solo desCommento
        let d = try XCTUnwrap(by["VOTO-0004"])
        XCTAssertEqual(d.subjectName, "STORIA"); XCTAssertEqual(d.teacher, "Docente B.")

        // Giudizio con segnaposto `valore: 0`: il numero viene dal testo, non dallo 0.
        let e = try XCTUnwrap(by["VOTO-0005"])
        XCTAssertEqual(e.rawValue, "buono"); XCTAssertEqual(e.numericValue, 8)
        XCTAssertEqual(e.comment, "Lavoro di gruppo")

        let fm = try XCTUnwrap(by["VOTO-0006"])
        XCTAssertTrue(fm.notCounting) // faMenoMedia "S"
        XCTAssertEqual(fm.numericValue, 5)

        XCTAssertEqual(try XCTUnwrap(by["VOTO-0007"]).kind, .practical)
        XCTAssertTrue(f.grades.allSatisfy { $0.weight == nil && !$0.hasTime && !$0.cancelled && $0.remoteModifiedAt == nil })
    }

    func testRegisterValueWinsOverFMTModifierRule() async throws {
        // "8--": Argo dice 7,75; la regola di FMT (±0,25 per segno) darebbe 7,5.
        XCTAssertEqual(GradeValueNormalizer.normalize("8--", providedNumeric: nil, maxGrade: 10), 7.5)
        let m = MockTransport()
        m.stub("POST", dashboardURL, body: try fixture("argo-dashboard"))
        let f = try await makeProvider(m).fetchGrades(session())
        let g = try XCTUnwrap(f.grades.first { $0.remoteId == "VOTO-0004" })
        XCTAssertEqual(g.rawValue, "8--")
        XCTAssertEqual(g.numericValue, 7.75)

        // "6+" con un valore del registro diverso da 6,25.
        m.stub("POST", dashboardURL, body: Data(dashboardJSON([grade(codice: "6+", valore: 6.5)]).utf8))
        let h = try await makeProvider(m).fetchGrades(session())
        XCTAssertEqual(h.grades.first?.numericValue, 6.5)
    }

    func testDeletedAndNonGradeEntriesAreDroppedWithoutCounting() async throws {
        let m = MockTransport()
        m.stub("POST", dashboardURL, body: try fixture("argo-dashboard"))
        let f = try await makeProvider(m).fetchGrades(session())
        XCTAssertNil(f.grades.first { $0.remoteId == "VOTO-0008" }) // operazione "D"
        XCTAssertNil(f.grades.first { $0.remoteId == "VOTO-0009" }) // codTipo "N" (nota)
        XCTAssertEqual(f.skippedCount, 0)

        // "D" con soli campi parziali e note con campi mancanti: scartate, non contate.
        // codTipo mancante: voce malformata, contata.
        let entries = [
            #"{"pk":"X-1","operazione":"D"}"#,
            #"{"operazione":"D","codTipo":"V"}"#,
            #"{"pk":"X-2","codTipo":"N"}"#,
            grade(pk: "X-3", codTipo: nil),
            grade(pk: "X-4")
        ]
        m.stub("POST", dashboardURL, body: Data(dashboardJSON(entries).utf8))
        let g = try await makeProvider(m).fetchGrades(session())
        XCTAssertEqual(g.grades.map(\.remoteId), ["X-4"])
        XCTAssertEqual(g.skippedCount, 1)
    }

    func testMissingTeacherAndCommentsAreNil() async throws {
        let m = MockTransport()
        let entries = [grade(pk: "T-1", overrides: ["docente": "   ", "descrizioneProva": "", "desCommento": "  "]),
                       grade(pk: "T-2", overrides: ["descrizioneProva": " Stesso", "desCommento": "Stesso "]),
                       grade(pk: "T-3", overrides: ["descrizioneProva": "Prova", "desCommento": "Commento",
                                                    "codVotoPratico": "O", "pkPeriodo": "ALTRO"]),
                       grade(pk: "T-4", overrides: ["codVotoPratico": ""]),
                       grade(pk: "T-5", overrides: ["docente": NSNull(), "pkMateria": NSNull()])]
        m.stub("POST", dashboardURL, body: Data(dashboardJSON(entries).utf8))
        let f = try await makeProvider(m).fetchGrades(session())
        let by = Dictionary(uniqueKeysWithValues: f.grades.map { ($0.remoteId, $0) })
        let t1 = try XCTUnwrap(by["T-1"])
        XCTAssertNil(t1.teacher); XCTAssertNil(t1.comment)
        XCTAssertEqual(try XCTUnwrap(by["T-2"]).comment, "Stesso")
        let t3 = try XCTUnwrap(by["T-3"])
        XCTAssertEqual(t3.comment, "Prova\nCommento")
        XCTAssertEqual(t3.kind, .other); XCTAssertEqual(t3.kindRaw, "O") // TODO-AR10
        XCTAssertNil(t3.period) // pkPeriodo non in listaPeriodi
        let t4 = try XCTUnwrap(by["T-4"])
        XCTAssertNil(t4.kind); XCTAssertNil(t4.kindRaw)
        let t5 = try XCTUnwrap(by["T-5"])
        XCTAssertNil(t5.teacher); XCTAssertNil(t5.subjectId)
        XCTAssertEqual(f.skippedCount, 0)
    }

    func testDateOnlyIsRomeMidnight() async throws {
        let m = MockTransport()
        m.stub("POST", dashboardURL, body: Data(dashboardJSON([grade(date: "2026-11-14")]).utf8))
        let f = try await makeProvider(m).fetchGrades(session())
        let d = try XCTUnwrap(f.grades.first?.date)
        XCTAssertEqual(d, rome(2026, 11, 14))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute, c.second], [2026, 11, 14, 0, 0, 0])
        XCTAssertFalse(try XCTUnwrap(f.grades.first).hasTime)
        // Anche in ora legale (UTC+2).
        m.stub("POST", dashboardURL, body: Data(dashboardJSON([grade(date: "2026-07-01")]).utf8))
        let g = try await makeProvider(m).fetchGrades(session())
        XCTAssertEqual(g.grades.first?.date, rome(2026, 7, 1))
        XCTAssertEqual(g.grades.first?.date.timeIntervalSince1970, rome(2026, 6, 30).addingTimeInterval(24 * 3600).timeIntervalSince1970)
    }

    func testUnparseableGradeIsSkippedAndCounted() async throws {
        let m = MockTransport()
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: try fixture("argo-dashboard")) as? [String: Any])
        var data = try XCTUnwrap(obj["data"] as? [String: Any])
        var dati = try XCTUnwrap(data["dati"] as? [[String: Any]])
        var voti = try XCTUnwrap(dati[0]["voti"] as? [Any])
        var v2 = try XCTUnwrap(voti[1] as? [String: Any])
        v2["datGiorno"] = "non una data"
        voti[1] = v2
        voti.append("non un oggetto")
        dati[0]["voti"] = voti; data["dati"] = dati; obj["data"] = data
        m.stub("POST", dashboardURL, body: try JSONSerialization.data(withJSONObject: obj))
        let f = try await makeProvider(m).fetchGrades(session())
        XCTAssertEqual(f.skippedCount, 2)
        XCTAssertEqual(f.grades.count, 6)
        XCTAssertNil(f.grades.first { $0.remoteId == "VOTO-0002" })
        XCTAssertNotNil(f.grades.first { $0.remoteId == "VOTO-0001" })

        // Campi obbligatori mancanti o del tipo sbagliato.
        let bad = [grade(pk: "B-1", date: "2026-02-30"), grade(pk: "B-2", overrides: ["desMateria": ""]),
                   #"{"pk":7,"codTipo":"V","datGiorno":"2026-10-01","desMateria":"FISICA","codCodice":"7","valore":7}"#,
                   #"{"pk":"B-4","codTipo":"V","datGiorno":"2026-10-01","desMateria":"FISICA","valore":7}"#]
        m.stub("POST", dashboardURL, body: Data(dashboardJSON(bad).utf8))
        let g = try await makeProvider(m).fetchGrades(session())
        XCTAssertEqual(g.grades.count, 0)
        XCTAssertEqual(g.skippedCount, 4)
    }

    func testPlaceholderZeroIsNotNumeric() async throws {
        let m = MockTransport()
        let cases: [(String, Any, Double?)] = [
            ("ds", 0, nil),        // segnaposto, testo non numerico
            ("0", 0, 0),           // zero vero
            ("30", 30, nil),       // fuori scala (maxGrade 10)
            ("7", NSNull(), 7),    // valore nullo: decide il testo
            ("ds", true, nil),     // booleano JSON non è un numero
            ("ds", "7", nil)       // stringa non è un numero
        ]
        for (codice, valore, expected) in cases {
            m.stub("POST", dashboardURL, body: Data(dashboardJSON([grade(codice: codice, valore: valore)]).utf8))
            let f = try await makeProvider(m).fetchGrades(session())
            XCTAssertEqual(f.grades.count, 1, "\(codice) \(valore)")
            XCTAssertEqual(f.grades.first?.numericValue, expected, "\(codice) \(valore)")
        }
    }

    // MARK: periodo coperto

    func testCoveredRangeIsSchoolYear() async throws {
        let m = MockTransport()
        m.stub("POST", dashboardURL, body: try fixture("argo-dashboard"))
        let f = try await makeProvider(m).fetchGrades(session())
        let r = try XCTUnwrap(f.coveredRange)
        XCTAssertEqual(r.start, rome(2026, 9, 1))   // profilo.anno.dataInizio
        XCTAssertEqual(r.end, rome(2027, 9, 1))     // fine del giorno dataFine (2027-08-31)
    }

    // MARK: trasporto reale senza redirect

    func testURLSessionTransportCanStopAtRedirect() async throws {
        let t = URLSessionTransport(protocolClasses: [RedirectingURLProtocol.self])
        let start = URLRequest(url: URL(string: "https://redirect.test/start")!)
        let (stopData, stop) = try await t.sendWithoutRedirect(start)
        XCTAssertEqual(stop.statusCode, 302)
        XCTAssertEqual(stop.value(forHTTPHeaderField: "Location"), "https://redirect.test/next")
        XCTAssertEqual(String(data: stopData, encoding: .utf8), "redirect")
        // `send` resta com'era: segue il redirect (ClasseViva non cambia).
        let (data, followed) = try await t.send(start)
        XCTAssertEqual(followed.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "followed")
    }

    // MARK: JSON di supporto

    private func grade(pk: String = "G-1", codTipo: String? = "V", date: String = "2026-10-01",
                       codice: String = "7", valore: Any = 7, overrides: [String: Any] = [:]) -> String {
        var g: [String: Any] = [
            "pk": pk, "operazione": "I", "datGiorno": date, "pkPeriodo": "PER-0001", "codCodice": codice,
            "valore": valore, "codVotoPratico": "S", "docente": "Docente C.", "pkMateria": "MAT-0003",
            "desMateria": "FISICA", "descrizioneProva": "", "faMenoMedia": "", "numMedia": 1, "desCommento": ""]
        if let codTipo { g["codTipo"] = codTipo }
        g.merge(overrides) { $1 }
        return String(data: try! JSONSerialization.data(withJSONObject: g, options: [.sortedKeys]), encoding: .utf8)!
    }

    private func dashboardJSON(_ voti: [String]) -> String {
        """
        {"success":true,"msg":null,"data":{"dati":[{"voti":[\(voti.joined(separator: ","))],
        "listaPeriodi":[{"pkPeriodo":"PER-0001","descrizione":"PRIMO QUADRIMESTRE"}]}]}}
        """
    }
}

/// URLProtocol finto: `/start` risponde 302 verso `/next`, `/next` risponde 200. Nessuna rete.
final class RedirectingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "redirect.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        if url.path == "/start" {
            let next = URL(string: "https://redirect.test/next")!
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": next.absoluteString])!
            client.urlProtocol(self, wasRedirectedTo: URLRequest(url: next), redirectResponse: response)
            // Se il redirect viene rifiutato, il corpo della risposta 302 arriva al chiamante.
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data("redirect".utf8))
            client.urlProtocolDidFinishLoading(self)
        } else {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data("followed".utf8))
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
