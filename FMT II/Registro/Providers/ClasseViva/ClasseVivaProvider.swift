import Foundation

/// Provider ClasseViva (Spaggiari), API "app" `rest/v1`.
/// Endpoint, header, corpo e mappature sono SOLO quelli di `docs/registri/ClasseViva.md`.
/// Sicurezza: la password compare soltanto nel corpo del login; token e credenziali
/// non finiscono mai in URL, log o messaggi di errore.
struct ClasseVivaProvider: RegistroProvider {
    let id: RegistroProviderID = .classeviva
    let isAvailable = true
    /// Niente `forniscePeso` (TODO-CV7) e niente `fornisceOra` (le date non hanno ora).
    let capabilities: RegistroCapabilities = [.fornisceDocente, .fornisceCommento, .forniscePeriodo]
    let loginFields: [LoginField] = [.username, .password]

    private let transport: HTTPTransport
    private let now: () -> Date
    /// Fondo scala usato dal normalizzatore: per default l'impostazione globale `maxGrade`
    /// dell'app (iniettabile nei test).
    private let maxGradeProvider: () -> Double

    // Valori documentati (§ 1).
    private static let base = "https://web.spaggiari.eu/rest/v1"
    private static let apiKey = "Tg1NWEwNGIgIC0K"
    private static let userAgent = "CVVS/std/4.2.3 Android/12"

    init(transport: HTTPTransport,
         now: @escaping () -> Date = Date.init,
         maxGradeProvider: @escaping () -> Double = { maxGrade }) {
        self.transport = transport
        self.now = now
        self.maxGradeProvider = maxGradeProvider
    }

    // MARK: Login (§ 2)

    func login(_ c: RegistroCredentials) async throws -> RegistroSession {
        guard let url = URL(string: Self.base + "/auth/login") else { throw RegistroError.unexpectedFormat("url") }
        var request = makeRequest(url, method: "POST", token: nil)
        // Corpo documentato: {"ident":null,"pass":...,"uid":...} (chiavi in ordine alfabetico).
        let payload: [String: Any] = ["ident": NSNull(), "pass": c.password, "uid": c.username]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])

        let (data, http) = try await send(request)
        switch http.statusCode {
        case 200: break
        case 401, 422: throw RegistroError.invalidCredentials
        case 403, 429: throw RegistroError.rateLimited
        default: throw Self.mapOtherStatus(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RegistroError.unexpectedFormat("login")
        }
        guard let token = json["token"] as? String, !token.isEmpty else {
            // Con `choices` e senza token: più profili (TODO-CV4), per ora non gestito.
            throw RegistroError.unexpectedFormat(json["choices"] != nil ? "choices" : "token")
        }
        guard let ident = json["ident"] as? String else { throw RegistroError.unexpectedFormat("ident") }
        // accountKey = studentId = solo le cifre di `ident` (§ 2.1).
        let studentId = ident.filter { $0.isASCII && $0.isNumber }
        guard !studentId.isEmpty else { throw RegistroError.unexpectedFormat("ident") }

        // expiresAt = `expire`; ripiego a 1 ora come CV-C se manca o non è leggibile (§ 3).
        let expires = (json["expire"] as? String).flatMap(Self.parseISO) ?? now().addingTimeInterval(3600)
        return RegistroSession(accountKey: studentId, token: token, expiresAt: expires, extra: [:])
    }

    /// `v1` non ha refresh token (§ 3.1): il coordinatore rifà `login` una sola volta.
    func refresh(_ s: RegistroSession) async throws -> RegistroSession {
        throw RegistroError.sessionExpired
    }

    /// Nessun endpoint di logout in `v1`: la cancellazione dal Keychain è locale (§ 3).
    func logout(_ s: RegistroSession) async {}

    // MARK: Voti (§ 4, § 6)

    func fetchGrades(_ s: RegistroSession) async throws -> RemoteFetch {
        // Sessione già scaduta: nessuna chiamata al server (§ 3.1).
        if let exp = s.expiresAt, exp <= now() { throw RegistroError.sessionExpired }
        guard let gradesURL = URL(string: Self.base + "/students/\(s.accountKey)/grades") else {
            throw RegistroError.unexpectedFormat("url")
        }
        let (data, http) = try await send(makeRequest(gradesURL, method: "GET", token: s.token))
        switch http.statusCode {
        case 200: break
        case 401: throw RegistroError.sessionExpired
        case 403, 429: throw RegistroError.rateLimited
        // TODO-CV12: il doc (§ 10) tratterebbe il 422 "school year not started yet" come "nessun voto";
        // per decisione del coordinatore resta un errore (nessuna sync "vuota" spacciata per riuscita).
        default: throw Self.mapOtherStatus(http.statusCode)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["grades"] as? [Any] else {
            throw RegistroError.unexpectedFormat("grades")
        }

        var grades: [VotoRemoto] = []
        var skipped = 0
        let maxG = maxGradeProvider()
        for item in items {
            if let dict = item as? [String: Any], let g = Self.mapGrade(dict, maxGrade: maxG) {
                grades.append(g)
            } else {
                skipped += 1
            }
        }
        let range = await fetchCoveredRange(s)
        return RemoteFetch(grades: grades, skippedCount: skipped, coveredRange: range)
    }

    /// § 4.1: dal `dateStart` del primo al `dateEnd` dell'ultimo periodo. Qualunque
    /// problema -> nil (nessuna cancellazione automatica comunque).
    private func fetchCoveredRange(_ s: RegistroSession) async -> DateInterval? {
        guard let url = URL(string: Self.base + "/students/\(s.accountKey)/periods"),
              let (data, http) = try? await send(makeRequest(url, method: "GET", token: s.token)),
              http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let periods = root["periods"] as? [[String: Any]] else { return nil }
        let starts = periods.compactMap { ($0["dateStart"] as? String).flatMap(Self.parseRomeDay) }
        let ends = periods.compactMap { ($0["dateEnd"] as? String).flatMap(Self.parseRomeDay) }
        guard let start = starts.min(), let lastDay = ends.max(),
              let end = Self.romeCalendar.date(byAdding: .day, value: 1, to: lastDay), end > start else { return nil }
        // Il giorno `dateEnd` è incluso: l'intervallo finisce a mezzanotte del giorno dopo.
        return DateInterval(start: start, end: end)
    }

    // MARK: Mappatura

    private static func mapGrade(_ g: [String: Any], maxGrade: Double) -> VotoRemoto? {
        guard let evtId = intValue(g["evtId"]),
              let subjectId = intValue(g["subjectId"]),
              let subjectName = g["subjectDesc"] as? String, !subjectName.isEmpty,
              let raw = g["displayValue"] as? String,
              let dateString = g["evtDate"] as? String, let date = parseRomeDay(dateString) else { return nil }

        // decimalValue: null/assente -> nil; 0 con displayValue diverso da "0" è un segnaposto -> nil (§ 7).
        var provided = number(g["decimalValue"])?.doubleValue
        if provided == 0, raw.trimmingCharacters(in: .whitespaces) != "0" { provided = nil }
        let numeric = GradeValueNormalizer.normalize(raw, providedNumeric: provided, maxGrade: maxGrade)

        let kindRaw = (g["componentDesc"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let color = (g["color"] as? String)?.lowercased()
        let noAverage = (g["noAverage"] as? Bool) ?? false
        let comment = (g["notesForFamily"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let teacher = (g["teacherName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let period = (g["periodDesc"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        return VotoRemoto(
            provider: .classeviva,
            remoteId: String(evtId),
            date: date,
            hasTime: false,
            subjectId: String(subjectId),
            subjectName: subjectName,
            teacher: (teacher?.isEmpty ?? true) ? nil : teacher,
            rawValue: raw,
            numericValue: numeric,
            kind: kindRaw.map(kind(from:)),
            kindRaw: kindRaw,
            weight: nil, // TODO-CV7 (BLOCKED-ON-USER): scala di weightFactor non verificata
            period: period,
            comment: (comment?.isEmpty ?? true) ? nil : comment,
            notCounting: color == "blue" || noAverage,
            cancelled: (g["canceled"] as? Bool) ?? false, // "canceled" con una sola "l"
            remoteModifiedAt: nil)
    }

    /// Tipo da `componentDesc` per sottostringa (§ 6); `evtCode` e `componentPos` non si usano.
    private static func kind(from desc: String) -> RemoteGradeKind {
        let d = desc.lowercased()
        if d.contains("scritt") { return .written }
        if d.contains("oral") { return .oral }
        if d.contains("pratic") { return .practical }
        return .other
    }

    /// NSNumber numerico, escluso il booleano JSON (`is Bool` darebbe vero anche per 0 e 1).
    private static func number(_ v: Any?) -> NSNumber? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n
    }

    private static func intValue(_ v: Any?) -> Int? {
        guard let n = number(v), n.doubleValue == n.doubleValue.rounded() else { return nil }
        return n.intValue
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
        let comps = DateComponents(year: y, month: mo, day: d)
        guard let date = romeCalendar.date(from: comps) else { return nil }
        let back = romeCalendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == mo, back.day == d else { return nil }
        return date
    }

    /// ISO 8601 con offset (`2026-11-15T17:30:00+01:00`).
    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    // MARK: Rete

    private func makeRequest(_ url: URL, method: String, token: String?) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue(Self.apiKey, forHTTPHeaderField: "Z-Dev-Apikey")
        r.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { r.setValue(token, forHTTPHeaderField: "Z-Auth-Token") }
        return r
    }

    /// Qualunque errore del trasporto (URLError incluso) diventa `.network`.
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do { return try await transport.send(request) } catch { throw RegistroError.network }
    }

    /// 5xx -> rete; 404 e altri -> formato inatteso (§ 10). Si decide solo dallo status.
    private static func mapOtherStatus(_ status: Int) -> RegistroError {
        (500...599).contains(status) ? .network : .unexpectedFormat(String(status))
    }
}
