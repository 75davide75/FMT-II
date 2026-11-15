import Foundation
import CryptoKit
import Security

/// Provider Argo didUP Famiglia, API "app" `appfamiglia` (Argo.md § 0).
/// Login, endpoint, header, corpi e mappature sono SOLO quelli di `docs/registri/Argo.md`.
/// Sicurezza: la password compare soltanto nel corpo del form SSO (passo 2); credenziali,
/// token e codici non finiscono mai in URL, log o messaggi di errore.
///
/// Mappatura della sessione Argo su `RegistroSession` (§ 3.4):
/// - `token`     = `access_token` OAuth del passo 3 (header `authorization: Bearer …`);
/// - `expiresAt` = header HTTP `Date` della risposta del passo 3 + `expires_in` secondi
///                 (header `x-date-exp-auth`);
/// - `extra["x-auth-token"]` = `token` del passo 4 (header `x-auth-token`);
/// - `extra["codMin"]`       = `codMin` del passo 4 (header `x-cod-min`);
/// - `extra["opzioni"]`      = stringa JSON `{chiave: valore}` dalle `opzioni` del passo 4
///                             (corpo della dashboard, § 4);
/// - `extra["annoInizio"]`, `extra["annoFine"]` = `profilo.anno.dataInizio/dataFine`
///                             (`YYYY-MM-DD`: download completo e `coveredRange`, § 4, § 4.1);
/// - `accountKey` = `codMin + "|" + profilo.alunno.pk` (§ 2.1).
/// `refresh_token` e `id_token` non si salvano: il rinnovo è un nuovo login (§ 3.3).
struct ArgoProvider: RegistroProvider {
    let id: RegistroProviderID = .argo
    let isAvailable = true
    /// Niente `forniscePeso` (TODO-AR11) e niente `fornisceOra` (solo date, § 9).
    let capabilities: RegistroCapabilities = [.fornisceDocente, .fornisceCommento, .forniscePeriodo]
    let loginFields: [LoginField] = [.schoolCode, .username, .password]

    private let transport: HTTPTransport
    private let now: () -> Date
    /// Fondo scala usato dal normalizzatore: per default l'impostazione globale `maxGrade`.
    private let maxGradeProvider: () -> Double
    /// Sorgente dei byte casuali per PKCE, `state`, `nonce` e `clientID` (iniettabile nei test).
    private let randomBytes: (Int) -> [UInt8]?
    /// Fuso delle date inviate ad Argo ("ora locale", § 9).
    private let timeZone: TimeZone

    // MARK: Costanti documentate (§ 1)

    private static let authURL = "https://auth.portaleargo.it/oauth2/auth"
    private static let tokenURL = "https://auth.portaleargo.it/oauth2/token"
    private static let ssoURL = "https://www.portaleargo.it/auth/sso/login"
    private static let apiBase = "https://www.portaleargo.it/appfamiglia/api/rest/"
    private static let clientId = "72fd6dea-d0ab-4bb9-8eaa-3ac24c84886c"
    private static let redirectURI = "it.argosoft.didup.famiglia.new://login-callback"
    private static let scope = "openid offline profile user.roles argo"
    /// Versione dell'app didUP Famiglia inviata in `argo-client-version` (§ 1, § 3.2): la più
    /// recente fra quelle documentate (`1.30.2`, fonti AR-D, AR-E, AR-H). Argo rifiuta le
    /// versioni vecchie: VA AGGIORNATA a ogni release di FMT (TODO-AR5).
    static let clientVersion = "1.30.2"

    /// Margine di scadenza: con meno di 2 minuti la sessione è già da rifare (§ 3.4).
    private static let expiryMargin: TimeInterval = 120
    /// Limite di sicurezza ai redirect seguiti a mano nel passo 2 (contro i cicli).
    private static let maxRedirects = 10

    init(transport: HTTPTransport,
         now: @escaping () -> Date = Date.init,
         maxGradeProvider: @escaping () -> Double = { maxGrade },
         randomBytes: @escaping (Int) -> [UInt8]? = ArgoProvider.secureRandomBytes,
         timeZone: TimeZone = .current) {
        self.transport = transport
        self.now = now
        self.maxGradeProvider = maxGradeProvider
        self.randomBytes = randomBytes
        self.timeZone = timeZone
    }

    // MARK: Login (§ 2)

    func login(_ c: RegistroCredentials) async throws -> RegistroSession {
        // Il codice scuola è obbligatorio: senza, nessuna richiesta di rete.
        guard let school = c.schoolCode?.trimmingCharacters(in: .whitespacesAndNewlines), !school.isEmpty else {
            throw RegistroError.invalidCredentials
        }
        let verifier = try randomString(43)
        let state = try randomString(22)
        let nonce = try randomString(22)

        // Cookie jar per tutta la sequenza dei passi 1–2 (§ 2).
        let jar = CookieJar()
        let challenge = try await startOAuth(verifier: verifier, state: state, nonce: nonce, jar: jar)
        let code = try await submitCredentials(c, school: school, challenge: challenge, jar: jar)
        let (accessToken, expiresAt) = try await exchangeCode(code, verifier: verifier)
        let app = try await appLogin(accessToken: accessToken, expiresAt: expiresAt)
        let profilo = try await fetchProfilo(accessToken: accessToken, expiresAt: expiresAt,
                                             xAuthToken: app.xAuthToken, codMin: app.codMin)

        return RegistroSession(
            accountKey: app.codMin + "|" + profilo.alunnoPk,
            token: accessToken,
            expiresAt: expiresAt,
            extra: [Extra.xAuthToken: app.xAuthToken, Extra.codMin: app.codMin, Extra.opzioni: app.opzioni,
                    Extra.annoInizio: profilo.dataInizio, Extra.annoFine: profilo.dataFine])
    }

    /// Fase 1: niente `auth/refresh-token` (una sola famiglia di fonti, § 3.3): il
    /// coordinatore rifà `login` una sola volta.
    func refresh(_ s: RegistroSession) async throws -> RegistroSession {
        throw RegistroError.sessionExpired
    }

    /// Logout solo locale (cancellazione dal Keychain): `rimuoviprofilo` non si chiama (TODO-AR7).
    func logout(_ s: RegistroSession) async {}

    /// Passo 1: avvio OAuth con PKCE; dalla risposta 302 si legge `login_challenge`.
    private func startOAuth(verifier: String, state: String, nonce: String, jar: CookieJar) async throws -> String {
        let query = "redirect_uri=" + Self.formEncode(Self.redirectURI)
            + "&client_id=" + Self.clientId
            + "&response_type=code"
            + "&prompt=login"
            + "&state=" + state
            + "&nonce=" + nonce
            + "&scope=" + Self.formEncode(Self.scope)
            + "&code_challenge=" + Self.pkceChallenge(verifier)
            + "&code_challenge_method=S256"
        guard let url = URL(string: Self.authURL + "?" + query) else { throw RegistroError.unexpectedFormat("url") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (_, http) = try await hop(request, jar: jar)
        try Self.checkLoginStatus(http.statusCode)
        guard (300...399).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let challenge = URLComponents(string: location)?.queryItems?
                .first(where: { $0.name == "login_challenge" })?.value,
              !challenge.isEmpty else {
            throw RegistroError.unexpectedFormat("login_challenge")
        }
        return challenge
    }

    /// Passo 2: form SSO con le credenziali, poi i redirect seguiti a mano fino alla
    /// callback `it.argosoft.didup.famiglia.new://login-callback?code=…`.
    private func submitCredentials(_ c: RegistroCredentials, school: String, challenge: String,
                                   jar: CookieJar) async throws -> String {
        guard let url = URL(string: Self.ssoURL) else { throw RegistroError.unexpectedFormat("url") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            ("challenge", challenge), ("client_id", Self.clientId), ("prefill", "false"),
            ("famiglia_customer_code", school), ("username", c.username), ("password", c.password),
            ("remember_me", "false"), ("login", "true")])

        let (data, http) = try await hop(request, jar: jar)
        try Self.checkLoginStatus(http.statusCode)
        guard var next = Self.nextURL(data, http) else {
            // Nessun redirect (pagina HTML del form): credenziali errate (§ 2.2).
            if (200...299).contains(http.statusCode) { throw RegistroError.invalidCredentials }
            throw Self.mapOtherStatus(http.statusCode)
        }
        for _ in 0..<Self.maxRedirects {
            if let code = try Self.callbackCode(next) { return code }
            guard Self.isArgoURL(next) else { throw RegistroError.unexpectedFormat("redirect") }
            var step = URLRequest(url: next)
            step.httpMethod = "GET"
            let (stepData, stepHTTP) = try await hop(step, jar: jar)
            try Self.checkLoginStatus(stepHTTP.statusCode)
            guard let n = Self.nextURL(stepData, stepHTTP) else { throw RegistroError.unexpectedFormat("code") }
            next = n
        }
        throw RegistroError.unexpectedFormat("redirect")
    }

    /// Passo 3: scambio del codice. Restituisce `access_token` e la scadenza
    /// (`Date` della risposta + `expires_in`).
    private func exchangeCode(_ code: String, verifier: String) async throws -> (String, Date) {
        guard let url = URL(string: Self.tokenURL) else { throw RegistroError.unexpectedFormat("url") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            ("code", code), ("grant_type", "authorization_code"), ("redirect_uri", Self.redirectURI),
            ("code_verifier", verifier), ("client_id", Self.clientId)])

        let (data, http) = try await send(request)
        try Self.checkLoginStatus(http.statusCode)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        // `{"error", "error_description"}`: formato inatteso (TODO-AR3 per `invalid_grant`).
        guard http.statusCode == 200, let json, json["error"] == nil,
              let accessToken = json["access_token"] as? String, !accessToken.isEmpty,
              let expiresIn = Self.number(json["expires_in"])?.doubleValue, expiresIn > 0 else {
            throw RegistroError.unexpectedFormat("token")
        }
        // Senza header `Date` leggibile si usa l'ora del dispositivo.
        let issued = http.value(forHTTPHeaderField: "Date").flatMap(Self.parseHTTPDate) ?? now()
        return (accessToken, issued.addingTimeInterval(expiresIn))
    }

    private struct AppLogin { var xAuthToken: String; var codMin: String; var opzioni: String }

    /// Passo 4: login applicativo (`x-auth-token`, `codMin`, `opzioni`).
    private func appLogin(accessToken: String, expiresAt: Date) async throws -> AppLogin {
        var request = try apiRequest("login", method: "POST", accessToken: accessToken, expiresAt: expiresAt,
                                     xAuthToken: nil, codMin: nil)
        let body: [String: Any] = ["lista-opzioni-notifiche": "{}", "lista-x-auth-token": "[]",
                                   "clientID": try randomString(163)]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, http) = try await send(request)
        switch http.statusCode {
        case 200: break
        case 403, 429: throw RegistroError.rateLimited
        default: throw Self.mapOtherStatus(http.statusCode)
        }
        let root = try Self.successfulJSON(data, context: "login")
        guard let list = root["data"] as? [Any] else { throw RegistroError.unexpectedFormat("login") }
        // Più profili (es. genitore con più figli): TODO-AR1, per ora rifiutati.
        guard list.count <= 1 else { throw RegistroError.unexpectedFormat("profili") }
        guard let item = list.first as? [String: Any] else { throw RegistroError.unexpectedFormat("login") }
        if (item["profiloDisabilitato"] as? Bool) == true { throw RegistroError.notSupported } // TODO-AR14
        guard let token = item["token"] as? String, !token.isEmpty,
              let codMin = item["codMin"] as? String, !codMin.isEmpty,
              let opzioniList = item["opzioni"] as? [Any] else {
            throw RegistroError.unexpectedFormat("login")
        }
        // `opzioni` della dashboard: oggetto {chiave: valore} serializzato come stringa (§ 4).
        var opzioni: [String: Any] = [:]
        for case let o as [String: Any] in opzioniList {
            if let chiave = o["chiave"] as? String, let valore = o["valore"] { opzioni[chiave] = valore }
        }
        guard let opzData = try? JSONSerialization.data(withJSONObject: opzioni, options: [.sortedKeys]),
              let opzString = String(data: opzData, encoding: .utf8) else {
            throw RegistroError.unexpectedFormat("opzioni")
        }
        return AppLogin(xAuthToken: token, codMin: codMin, opzioni: opzString)
    }

    private struct Profilo { var alunnoPk: String; var dataInizio: String; var dataFine: String }

    /// Passo 5: profilo (anno scolastico e `alunno.pk`). Nessun altro dato personale si legge.
    private func fetchProfilo(accessToken: String, expiresAt: Date, xAuthToken: String,
                              codMin: String) async throws -> Profilo {
        let request = try apiRequest("profilo", method: "GET", accessToken: accessToken, expiresAt: expiresAt,
                                     xAuthToken: xAuthToken, codMin: codMin)
        let (data, http) = try await send(request)
        try Self.checkDataStatus(http.statusCode)
        let root = try Self.successfulJSON(data, context: "profilo")
        guard let d = root["data"] as? [String: Any] else { throw RegistroError.unexpectedFormat("profilo") }
        if (d["profiloDisabilitato"] as? Bool) == true { throw RegistroError.notSupported } // TODO-AR14
        guard let anno = d["anno"] as? [String: Any],
              let inizio = anno["dataInizio"] as? String, Self.parseRomeDay(inizio) != nil,
              let fine = anno["dataFine"] as? String, Self.parseRomeDay(fine) != nil else {
            throw RegistroError.unexpectedFormat("anno")
        }
        guard let alunno = d["alunno"] as? [String: Any],
              let pk = alunno["pk"] as? String, !pk.isEmpty else {
            throw RegistroError.unexpectedFormat("alunno")
        }
        return Profilo(alunnoPk: pk, dataInizio: inizio, dataFine: fine)
    }

    // MARK: Voti (§ 4, § 6)

    func fetchGrades(_ s: RegistroSession) async throws -> RemoteFetch {
        // Sessione scaduta o a meno di 2 minuti dalla scadenza: nessuna chiamata (§ 3.4).
        // Una sessione senza i valori del login non è utilizzabile: va rifatto il login.
        guard let exp = s.expiresAt, exp.timeIntervalSince(now()) >= Self.expiryMargin,
              let xAuthToken = s.extra[Extra.xAuthToken], !xAuthToken.isEmpty,
              let codMin = s.extra[Extra.codMin], !codMin.isEmpty,
              let opzioni = s.extra[Extra.opzioni],
              let inizio = s.extra[Extra.annoInizio], let start = Self.parseRomeDay(inizio),
              let fine = s.extra[Extra.annoFine], let lastDay = Self.parseRomeDay(fine) else {
            throw RegistroError.sessionExpired
        }

        var request = try apiRequest("dashboard/dashboard", method: "POST", accessToken: s.token, expiresAt: exp,
                                     xAuthToken: xAuthToken, codMin: codMin)
        // Download completo: dall'inizio dell'anno scolastico (§ 4).
        let body: [String: Any] = ["dataultimoaggiornamento": inizio + " 00:00:00.000", "opzioni": opzioni]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, http) = try await send(request)
        try Self.checkDataStatus(http.statusCode)
        let root = try Self.successfulJSON(data, context: "dashboard")
        guard let d = root["data"] as? [String: Any],
              let dati = (d["dati"] as? [Any])?.first as? [String: Any],
              let voti = dati["voti"] as? [Any] else {
            throw RegistroError.unexpectedFormat("voti")
        }

        // pkPeriodo -> descrizione (§ 4.1).
        var periods: [String: String] = [:]
        for case let p as [String: Any] in (dati["listaPeriodi"] as? [Any]) ?? [] {
            if let pk = p["pkPeriodo"] as? String, let desc = p["descrizione"] as? String, !desc.isEmpty {
                periods[pk] = desc
            }
        }

        var grades: [VotoRemoto] = []
        var skipped = 0
        let maxG = maxGradeProvider()
        for item in voti {
            switch Self.mapEntry(item, periods: periods, maxGrade: maxG) {
            case .grade(let g): grades.append(g)
            case .ignored: break      // "D" e voci che non sono voti: non contate (§ 4, § 7)
            case .unreadable: skipped += 1
            }
        }

        // coveredRange = anno scolastico del profilo; il giorno `dataFine` è incluso (§ 4.1).
        var range: DateInterval?
        if let end = Self.romeCalendar.date(byAdding: .day, value: 1, to: lastDay), end > start {
            range = DateInterval(start: start, end: end)
        }
        return RemoteFetch(grades: grades, skippedCount: skipped, coveredRange: range)
    }

    // MARK: Mappatura (§ 6, § 7)

    private enum Entry { case grade(VotoRemoto), ignored, unreadable }

    private static func mapEntry(_ item: Any, periods: [String: String], maxGrade: Double) -> Entry {
        guard let g = item as? [String: Any] else { return .unreadable }
        // Cancellazione: scartata in silenzio, senza contarla (§ 4).
        if (g["operazione"] as? String) == "D" { return .ignored }
        // `codTipo` mancante: voce malformata; diverso da "V" (es. nota): non è un voto (§ 7).
        guard let codTipo = g["codTipo"] as? String else { return .unreadable }
        guard codTipo == "V" else { return .ignored }

        guard let pk = g["pk"] as? String, !pk.isEmpty,
              let subjectName = g["desMateria"] as? String,
              !subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let raw = g["codCodice"] as? String,
              let day = g["datGiorno"] as? String, let date = parseRomeDay(day) else { return .unreadable }

        // `valore` di Argo SEMPRE come providedNumeric (il suo "8--" vale 7,75, non 7,5).
        // Nullo -> nil; 0 con `codCodice` diverso da "0" è un segnaposto -> nil (§ 7).
        var provided = number(g["valore"])?.doubleValue
        if provided == 0, raw.trimmingCharacters(in: .whitespaces) != "0" { provided = nil }
        let numeric = GradeValueNormalizer.normalize(raw, providedNumeric: provided, maxGrade: maxGrade)

        let kindRaw = (g["codVotoPratico"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let teacher = (g["docente"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let period = (g["pkPeriodo"] as? String).flatMap { periods[$0] }

        // Commento: `descrizioneProva` e `desCommento` non vuoti, uniti con "\n" se diversi.
        var comments: [String] = []
        for key in ["descrizioneProva", "desCommento"] {
            if let t = (g[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !t.isEmpty, !comments.contains(t) { comments.append(t) }
        }

        return .grade(VotoRemoto(
            provider: .argo,
            remoteId: pk,
            date: date,
            hasTime: false,
            subjectId: (g["pkMateria"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            subjectName: subjectName,
            teacher: (teacher?.isEmpty ?? true) ? nil : teacher,
            rawValue: raw,
            numericValue: numeric,
            kind: kindRaw.map(kind(from:)),
            kindRaw: kindRaw,
            weight: nil, // TODO-AR11 (BLOCKED-ON-USER): scala di `numMedia` non verificata
            period: period,
            comment: comments.isEmpty ? nil : comments.joined(separator: "\n"),
            notCounting: (g["faMenoMedia"] as? String) == "S",
            cancelled: false, // Argo non ha un flag "annullato": le rimozioni sono `operazione: "D"`
            remoteModifiedAt: nil)) // TODO-AR12
    }

    /// `codVotoPratico`: "S" scritto, "N" orale, "P" pratico, altro -> `.other` (TODO-AR10).
    private static func kind(from code: String) -> RemoteGradeKind {
        switch code {
        case "S": return .written
        case "N": return .oral
        case "P": return .practical
        default: return .other
        }
    }

    /// NSNumber numerico, escluso il booleano JSON (`is Bool` darebbe vero anche per 0 e 1).
    private static func number(_ v: Any?) -> NSNumber? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n
    }

    // MARK: Errori (§ 2.2, § 3.4, § 10)

    /// Passi 1–3: 403/429 -> blocco, 5xx -> rete; il resto lo decide il singolo passo.
    private static func checkLoginStatus(_ status: Int) throws {
        if status == 403 || status == 429 { throw RegistroError.rateLimited }
        if (500...599).contains(status) { throw RegistroError.network }
    }

    /// `profilo` e `dashboard/dashboard`: 401 -> sessione scaduta, 403/429 -> blocco.
    private static func checkDataStatus(_ status: Int) throws {
        switch status {
        case 200: return
        case 401: throw RegistroError.sessionExpired
        case 403, 429: throw RegistroError.rateLimited
        default: throw mapOtherStatus(status)
        }
    }

    /// 5xx -> rete; altri -> formato inatteso. Si decide solo dallo status.
    private static func mapOtherStatus(_ status: Int) -> RegistroError {
        (500...599).contains(status) ? .network : .unexpectedFormat(String(status))
    }

    /// Risposta applicativa `{"success", "msg", "data"}`. `success: false` con "ultima versione"
    /// = `argo-client-version` troppo vecchia (§ 3.2): errore chiaro, nessun nuovo tentativo.
    private static func successfulJSON(_ data: Data, context: String) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RegistroError.unexpectedFormat(context)
        }
        guard (root["success"] as? Bool) == true else {
            if let msg = root["msg"] as? String, msg.lowercased().contains("ultima versione") {
                throw RegistroError.unexpectedFormat("client-version")
            }
            throw RegistroError.unexpectedFormat("success")
        }
        return root
    }

    // MARK: Redirect del passo 2

    /// Prossimo URL: header `Location`, oppure il link `data-auth-app-redirect` della
    /// pagina "Accesso completato" (§ 2, passo 2).
    private static func nextURL(_ data: Data, _ http: HTTPURLResponse) -> URL? {
        let base = http.url
        if let location = http.value(forHTTPHeaderField: "Location"), !location.isEmpty {
            return resolve(location, base: base)
        }
        guard (200...299).contains(http.statusCode) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        guard let tag = html.firstMatch(of: /<a\b[^>]*\bdata-auth-app-redirect\b[^>]*>/.ignoresCase()),
              let href = String(tag.output).firstMatch(of: /\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')/.ignoresCase()),
              let value = href.output.1 ?? href.output.2 else { return nil }
        return resolve(String(value).replacingOccurrences(of: "&amp;", with: "&"), base: base)
    }

    private static func resolve(_ s: String, base: URL?) -> URL? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(redirectURI) { return URL(string: trimmed) }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    /// Callback dell'app: si legge `code` e ci si ferma (lo schema `it.argosoft…` non si apre).
    /// `nil` se l'URL non è la callback; callback senza `code` -> formato inatteso.
    private static func callbackCode(_ url: URL) throws -> String? {
        guard url.absoluteString.hasPrefix(redirectURI) else { return nil }
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw RegistroError.unexpectedFormat("code")
        }
        return code
    }

    /// Si seguono solo URL https dei server Argo (`portaleargo.it`): cookie e codici non
    /// escono dal dominio del registro.
    private static func isArgoURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "portaleargo.it" || host.hasSuffix(".portaleargo.it")
    }

    // MARK: Rete

    private enum Extra {
        static let xAuthToken = "x-auth-token"
        static let codMin = "codMin"
        static let opzioni = "opzioni"
        static let annoInizio = "annoInizio"
        static let annoFine = "annoFine"
    }

    /// Header di ogni richiesta `appfamiglia` (§ 3.1); `x-auth-token`/`x-cod-min` dopo il passo 4.
    private func apiRequest(_ path: String, method: String, accessToken: String, expiresAt: Date,
                            xAuthToken: String?, codMin: String?) throws -> URLRequest {
        guard let url = URL(string: Self.apiBase + path) else { throw RegistroError.unexpectedFormat("url") }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "accept")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue("Bearer " + accessToken, forHTTPHeaderField: "authorization")
        r.setValue(Self.clientVersion, forHTTPHeaderField: "argo-client-version")
        r.setValue(formatArgoDate(expiresAt), forHTTPHeaderField: "x-date-exp-auth")
        if let xAuthToken { r.setValue(xAuthToken, forHTTPHeaderField: "x-auth-token") }
        if let codMin { r.setValue(codMin, forHTTPHeaderField: "x-cod-min") }
        return r
    }

    /// Qualunque errore del trasporto (URLError incluso) diventa `.network`.
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do { return try await transport.send(request) } catch { throw RegistroError.network }
    }

    /// Un passo dei punti 1–2: cookie del jar, nessun redirect automatico, nuovi cookie salvati.
    private func hop(_ request: URLRequest, jar: CookieJar) async throws -> (Data, HTTPURLResponse) {
        var r = request
        if let url = r.url, let cookie = jar.header(for: url) { r.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let result: (Data, HTTPURLResponse)
        do { result = try await transport.sendWithoutRedirect(r) } catch { throw RegistroError.network }
        if let url = r.url { jar.store(from: result.1, url: url, now: now()) }
        return result
    }

    /// Corpo `application/x-www-form-urlencoded` nell'ordine dato.
    private static func formBody(_ fields: [(String, String)]) -> Data {
        Data(fields.map { $0.0 + "=" + formEncode($0.1) }.joined(separator: "&").utf8)
    }

    /// Percent-encoding di tutto tranne i caratteri non riservati (A-Z a-z 0-9 - . _ ~).
    private static func formEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    // MARK: Casualità e PKCE

    static func secureRandomBytes(_ count: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: count)
        return SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess ? bytes : nil
    }

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    /// Stringa alfanumerica casuale; i byte >= 248 si scartano (248 = 4 × 62: nessuna distorsione).
    private func randomString(_ length: Int) throws -> String {
        var out: [Character] = []
        for _ in 0..<16 where out.count < length {
            guard let bytes = randomBytes(length), bytes.count == length else { break }
            for b in bytes where b < 248 && out.count < length {
                out.append(Self.alphabet[Int(b) % Self.alphabet.count])
            }
        }
        guard out.count == length else { throw RegistroError.unexpectedFormat("random") }
        return String(out)
    }

    /// base64url(SHA256(verifier)) senza "=" (§ 2, passo 1).
    private static func pkceChallenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: Date (§ 9)

    private static let romeCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        return cal
    }()

    /// "YYYY-MM-DD" -> mezzanotte del giorno a Roma; date inesistenti (es. 2026-02-30) -> nil.
    static func parseRomeDay(_ s: String) -> Date? {
        guard let m = s.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/),
              let y = Int(m.1), let mo = Int(m.2), let d = Int(m.3) else { return nil }
        guard let date = romeCalendar.date(from: DateComponents(year: y, month: mo, day: d)) else { return nil }
        let back = romeCalendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == mo, back.day == d else { return nil }
        return date
    }

    /// Date inviate ad Argo: `YYYY-MM-DD HH:mm:ss.SSS` in ora locale.
    private func formatArgoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: date)
    }

    /// Header HTTP `Date` (RFC 1123, GMT).
    private static func parseHTTPDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: s)
    }
}

/// Cookie jar in memoria, solo per i passi 1–2 di un singolo login (§ 2). Mai su disco.
private final class CookieJar {
    private var cookies: [HTTPCookie] = []

    func store(from response: HTTPURLResponse, url: URL, now: Date) {
        guard let header = response.value(forHTTPHeaderField: "Set-Cookie") else { return }
        for c in HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: url) {
            cookies.removeAll { $0.name == c.name && $0.domain == c.domain && $0.path == c.path }
            if let exp = c.expiresDate, exp <= now { continue } // cookie cancellato dal server
            cookies.append(c)
        }
    }

    func header(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path.isEmpty ? "/" : url.path
        let matching = cookies.filter { c in
            let domain = c.domain.lowercased()
            let domainOK = domain.hasPrefix(".")
                ? (host == String(domain.dropFirst()) || host.hasSuffix(domain))
                : host == domain
            let cp = c.path.isEmpty ? "/" : c.path
            let pathOK = path == cp || path.hasPrefix(cp.hasSuffix("/") ? cp : cp + "/")
            let secureOK = !c.isSecure || url.scheme?.lowercased() == "https"
            return domainOK && pathOK && secureOK
        }
        guard !matching.isEmpty else { return nil }
        return matching.map { $0.name + "=" + $0.value }.joined(separator: "; ")
    }
}
