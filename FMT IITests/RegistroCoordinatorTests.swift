import XCTest
@testable import FMT_II

// MARK: - Provider finto in memoria

/// Provider scriptabile: errori in coda per login/refresh/fetch (nil = successo),
/// registro delle chiamate, voti remoti modificabili.
final class FakeRegistroProvider: RegistroProvider {
    let id: RegistroProviderID = .classeviva
    var isAvailable = true
    let capabilities: RegistroCapabilities = []
    let loginFields: [LoginField] = [.username, .password]

    var accountKey = "S1234567"
    var remoteGrades: [VotoRemoto] = []
    var skippedCount = 0
    var coveredRange: DateInterval?

    var loginErrors: [Error?] = []
    var refreshErrors: [Error?] = []
    var fetchErrors: [Error?] = []
    /// Eseguito una sola volta durante il prossimo fetch (prima del risultato).
    var onFetch: (() async -> Void)?

    private(set) var calls: [String] = []
    private(set) var fetchTokens: [String] = []
    private var logins = 0
    private var refreshes = 0

    func resetCalls() { calls = []; fetchTokens = [] }

    func login(_ c: RegistroCredentials) async throws -> RegistroSession {
        calls.append("login")
        if !loginErrors.isEmpty, let e = loginErrors.removeFirst() { throw e }
        logins += 1
        return RegistroSession(accountKey: accountKey, token: "login-\(logins)", expiresAt: nil, extra: [:])
    }

    func refresh(_ s: RegistroSession) async throws -> RegistroSession {
        calls.append("refresh")
        if !refreshErrors.isEmpty, let e = refreshErrors.removeFirst() { throw e }
        refreshes += 1
        return RegistroSession(accountKey: s.accountKey, token: "refresh-\(refreshes)", expiresAt: nil, extra: [:])
    }

    func fetchGrades(_ s: RegistroSession) async throws -> RemoteFetch {
        calls.append("fetch")
        fetchTokens.append(s.token)
        if let hook = onFetch { onFetch = nil; await hook() }
        if !fetchErrors.isEmpty, let e = fetchErrors.removeFirst() { throw e }
        return RemoteFetch(grades: remoteGrades, skippedCount: skippedCount, coveredRange: coveredRange)
    }

    func logout(_ s: RegistroSession) async { calls.append("logout") }
}

/// Orologio controllabile per throttle e `modifiedAt`.
final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

// MARK: - Test

/// Coordinatore di sync, validazione del piano, deduplicazione, voti ignorati e
/// scollegamento. Regola: nessun voto dell'utente perso; ogni errore = nessuna scrittura.
@MainActor
final class RegistroCoordinatorTests: XCTestCase {
    private var dir: URL!
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var backups: GradeBackups!
    private var settings: RegistroSettingsStore!
    private var store: GradesStore!
    private var provider: FakeRegistroProvider!
    private var clock: TestClock!
    private let keychain = KeychainStore(service: "com.davide.fmtII.registro.coordinatortests")
    private let account = "S1234567"
    private let creds = RegistroCredentials(username: "studente", password: "segreta", schoolCode: nil)
    private let mapping = SubjectMappingTable(entries: ["S1": "Matematica"], confirmed: ["S1"])

    private var fileURL: URL { dir.appendingPathComponent("fmt_grades.json") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("RegistroCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        suiteName = "RegistroCoordinatorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        backups = GradeBackups(directory: dir.appendingPathComponent("Backups"))
        settings = RegistroSettingsStore(defaults: defaults)
        store = GradesStore(fileStore: GradeFileStore(url: fileURL), backups: backups, registroSettings: settings)
        provider = FakeRegistroProvider()
        provider.coveredRange = DateInterval(start: d(9, 1, 2025), end: d(9, 1, 2026))
        clock = TestClock(d(3, 20, hour: 12))
        keychain.remove("credentials")
        keychain.remove("session")
    }

    override func tearDownWithError() throws {
        keychain.remove("credentials")
        keychain.remove("session")
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Helper

    private func d(_ month: Int, _ day: Int, _ year: Int = 2026, hour: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeCoordinator(backups: GradeBackups? = nil) -> RegistroSyncCoordinator {
        let clock = self.clock!
        return RegistroSyncCoordinator(grades: store, backups: backups ?? self.backups, settings: settings,
                                       keychain: keychain, providers: [provider], defaults: defaults,
                                       now: { clock.now })
    }

    private func remote(_ id: String, value: Double? = 7, raw: String = "7", date: Date? = nil,
                        kind: RemoteGradeKind? = .oral, teacher: String? = nil) -> VotoRemoto {
        VotoRemoto(provider: .classeviva, remoteId: id, date: date ?? d(3, 10), hasTime: false,
                   subjectId: "S1", subjectName: "MATEMATICA", teacher: teacher, rawValue: raw,
                   numericValue: value, kind: kind, kindRaw: kind?.rawValue, weight: nil, period: nil,
                   comment: nil, notCounting: false, cancelled: false, remoteModifiedAt: nil)
    }

    private func gid(_ id: String) -> UUID {
        RegistroIdentity.gradeID(provider: .classeviva, accountKey: account, remoteId: id)
    }

    private func key(_ id: String) -> String { "classeviva|\(account)|\(id)" }

    private func origin(_ g: Grade, remoteId: String, manualSnapshot: ManualGradeSnapshot? = nil) -> RegistroOrigin {
        RegistroOrigin(provider: .classeviva, accountKey: account, remoteId: remoteId, rawValue: "\(g.value)",
                       numericValue: g.value, hasTime: false, remoteSubjectId: "S1", remoteSubjectName: "MATEMATICA",
                       remoteTeacher: nil, remoteTypeRaw: nil, remoteKind: nil, remoteWeight: nil, remotePeriod: nil,
                       remoteComment: nil, notCounting: false, cancelled: false, remoteModifiedAt: nil,
                       fingerprint: "f-\(remoteId)", applied: AppliedValues(g), manualSnapshot: manualSnapshot,
                       status: .active)
    }

    /// Voto importato dal registro (id deterministico, nessun manualSnapshot).
    private func imported(_ remoteId: String, value: Double = 7, note: String = "", modifiedAt: Date? = nil) -> Grade {
        var g = Grade(id: gid(remoteId), subject: "Matematica", value: value, date: d(3, 10), note: note,
                      modifiedAt: modifiedAt ?? d(3, 10))
        g.origin = origin(g, remoteId: remoteId)
        return g
    }

    /// Voto manuale collegato a un remoto (stesso id, manualSnapshot salvato).
    private func linkedManual(_ remoteId: String, value: Double = 7, note: String = "", modifiedAt: Date? = nil) -> Grade {
        let manual = Grade(subject: "Matematica", value: value, date: d(3, 10, hour: 10), note: note,
                           modifiedAt: modifiedAt ?? d(3, 10))
        var g = manual
        g.date = d(3, 10)
        g.teacher = "Rossi"
        g.origin = origin(g, remoteId: remoteId, manualSnapshot: ManualGradeSnapshot(manual))
        return g
    }

    private func connectAndImport(_ c: RegistroSyncCoordinator) async throws {
        _ = try await c.connect(.classeviva, credentials: creds)
        await c.confirmMapping(mapping)
    }

    private func isError(_ s: RegistroStatus) -> Bool {
        if case .error = s { return true }
        return false
    }

    private func storedSessionToken() -> String? {
        guard let data = keychain.data(for: "session") else { return nil }
        return (try? JSONDecoder().decode(RegistroSession.self, from: data))?.token
    }

    // MARK: Primo collegamento e import

    func testFirstSyncTakesPreLinkSnapshotThenImports() async throws {
        let manual = Grade(subject: "Storia", value: 8, date: d(3, 1))
        store.add(manual)
        provider.remoteGrades = [remote("1"), remote("2", value: 6, raw: "6", date: d(3, 12))]
        let c = makeCoordinator()
        XCTAssertEqual(c.status, .disconnected)

        let proposals = try await c.connect(.classeviva, credentials: creds)
        XCTAssertEqual(proposals.map { $0.0 }, [RemoteSubjectRef(id: "S1", name: "MATEMATICA")])
        XCTAssertEqual(proposals.first?.1, .new("Matematica"))
        // connect: login + download, nessuna scrittura di voti né istantanee.
        XCTAssertEqual(store.grades.map(\.id), [manual.id])
        XCTAssertTrue(backups.list().isEmpty)
        XCTAssertEqual(c.connectedProvider, .classeviva)
        XCTAssertEqual(c.status, .idle)
        XCTAssertNotNil(keychain.data(for: "credentials"))
        XCTAssertNotNil(keychain.data(for: "session"))
        XCTAssertNil(defaults.data(forKey: "credentials"), "credenziali mai in UserDefaults")

        await c.confirmMapping(mapping)
        XCTAssertEqual(c.status, .idle)
        XCTAssertEqual(settings.mapping, mapping)
        let snaps = backups.list()
        XCTAssertEqual(snaps.map(\.kind), [.preLink])
        XCTAssertEqual(backups.load(snaps[0])?.map(\.id), [manual.id], "l'istantanea precede l'import")
        XCTAssertEqual(Set(store.grades.map(\.id)), [manual.id, gid("1"), gid("2")])
        for id in [gid("1"), gid("2")] {
            XCTAssertEqual(store.grades.first { $0.id == id }?.modifiedAt, clock.now)
        }
        XCTAssertEqual(c.lastSync, clock.now)
        XCTAssertEqual(GradeFileStore(url: fileURL).load().grades.count, 3, "scritto su disco")

        // Sync successive con modifiche: istantanea .preSync, non un altro .preLink.
        clock.advance(3600)
        provider.remoteGrades.append(remote("3", value: 5, raw: "5", date: d(3, 14)))
        let plan = await c.syncNow(.manual)
        XCTAssertEqual(plan?.inserts.map(\.id), [gid("3")])
        XCTAssertEqual(backups.list().map(\.kind).sorted { $0.rawValue < $1.rawValue }, [.preLink, .preSync])
        XCTAssertEqual(store.grades.count, 4)
    }

    // MARK: Download del collegamento (prefetched)

    func testSyncAfterConnectMakesConfirmMappingFetchAgain() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        _ = try await c.connect(.classeviva, credentials: creds)
        provider.resetCalls()
        provider.remoteGrades = [remote("1", value: 8, raw: "8")]

        // Una sync qualsiasi rende vecchio il download del collegamento.
        await c.syncNow(.manual)
        XCTAssertEqual(provider.calls, ["fetch"])

        clock.advance(60)
        await c.confirmMapping(mapping)
        XCTAssertEqual(provider.calls, ["fetch", "fetch"], "confirmMapping deve scaricare di nuovo")
        XCTAssertEqual(store.grades.first { $0.id == gid("1") }?.value, 8)
    }

    func testPrefetchedOlderThanTenMinutesIsDiscarded() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        _ = try await c.connect(.classeviva, credentials: creds)
        provider.resetCalls()
        provider.remoteGrades = [remote("1", value: 8, raw: "8")]

        clock.advance(11 * 60)
        await c.confirmMapping(mapping)
        XCTAssertEqual(provider.calls, ["fetch"], "download del collegamento troppo vecchio")
        XCTAssertEqual(store.grades.first { $0.id == gid("1") }?.value, 8)
    }

    func testPrefetchedWithinTenMinutesIsReused() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        _ = try await c.connect(.classeviva, credentials: creds)
        provider.resetCalls()

        clock.advance(9 * 60)
        await c.confirmMapping(mapping)
        XCTAssertTrue(provider.calls.isEmpty, "nessuna seconda richiesta al registro")
        XCTAssertEqual(store.grades.map(\.id), [gid("1")])
    }

    func testDisconnectedSyncDoesNothing() async {
        let c = makeCoordinator()
        let plan = await c.syncNow(.manual)
        XCTAssertNil(plan)
        XCTAssertEqual(c.status, .disconnected)
        XCTAssertTrue(provider.calls.isEmpty)
    }

    // MARK: Errori = nessuna scrittura

    func testProviderFailureWritesNothing() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        try await connectAndImport(c)
        let lastSync = c.lastSync
        provider.remoteGrades.append(remote("2", value: 6, raw: "6"))

        for error in [RegistroError.network as Error, RegistroError.unexpectedFormat("x"),
                      URLError(.notConnectedToInternet)] {
            let grades = store.grades
            let snaps = backups.list().map(\.id)
            let data = try Data(contentsOf: fileURL)
            provider.fetchErrors = [error]
            clock.advance(3600)

            let plan = await c.syncNow(.manual)
            XCTAssertNil(plan)
            XCTAssertTrue(isError(c.status), "\(error) → .error, trovato \(c.status)")
            XCTAssertEqual(store.grades, grades)
            XCTAssertEqual(backups.list().map(\.id), snaps)
            XCTAssertEqual(try Data(contentsOf: fileURL), data)
            XCTAssertEqual(c.lastSync, lastSync)
        }
    }

    func testInvalidCredentialsStopsAutomaticRetries() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        try await connectAndImport(c)
        keychain.remove("session") // forza un nuovo login
        provider.loginErrors = [RegistroError.invalidCredentials]
        provider.resetCalls()
        let grades = store.grades

        clock.advance(3600)
        await c.syncNow(.manual)
        XCTAssertEqual(c.status, .needsLogin)
        XCTAssertEqual(provider.calls, ["login"])
        XCTAssertEqual(store.grades, grades)

        clock.advance(3600)
        await c.syncNow(.appOpen)
        await c.syncNow(.background)
        XCTAssertEqual(provider.calls, ["login"], "nessun nuovo tentativo automatico")
        XCTAssertEqual(c.status, .needsLogin)

        // Anche dopo un riavvio dell'app.
        let relaunched = makeCoordinator()
        XCTAssertEqual(relaunched.status, .needsLogin)
        await relaunched.syncNow(.appOpen)
        XCTAssertEqual(provider.calls, ["login"])

        // Un nuovo login manuale riuscito riattiva le sync automatiche.
        _ = try await relaunched.connect(.classeviva, credentials: creds)
        XCTAssertEqual(relaunched.status, .idle)
        provider.resetCalls()
        clock.advance(3600)
        await relaunched.syncNow(.appOpen)
        XCTAssertEqual(provider.calls, ["fetch"])
        XCTAssertEqual(relaunched.status, .idle)
    }

    /// Con le credenziali rifiutate anche una sync manuale non le rimanda
    /// (rischio di blocco dell'account): serve un nuovo login.
    func testManualSyncAfterRejectedCredentialsDoesNotResendThem() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        try await connectAndImport(c)
        keychain.remove("session")
        provider.loginErrors = [RegistroError.invalidCredentials]
        clock.advance(3600)
        await c.syncNow(.manual)
        XCTAssertEqual(c.status, .needsLogin)
        provider.resetCalls()
        let grades = store.grades

        clock.advance(3600)
        let plan = await c.syncNow(.manual)
        XCTAssertNil(plan)
        XCTAssertEqual(c.status, .needsLogin)
        XCTAssertTrue(provider.calls.isEmpty, "nessun login con le credenziali rifiutate")
        XCTAssertEqual(store.grades, grades)

        // Anche dopo un riavvio dell'app.
        let relaunched = makeCoordinator()
        let relaunchedPlan = await relaunched.syncNow(.manual)
        XCTAssertNil(relaunchedPlan)
        XCTAssertEqual(relaunched.status, .needsLogin)
        XCTAssertTrue(provider.calls.isEmpty)
    }

    /// Accesso limitato/bloccato (403/429), account non supportato, versione
    /// dell'app rifiutata da Argo: riprovare fallirebbe di nuovo (e ogni tentativo
    /// può essere un login con password). Nessun tentativo automatico finché
    /// l'utente non sincronizza a mano; una sync manuale riuscita li riattiva.
    func testBlockingErrorsStopAutomaticRetriesUntilManualSync() async throws {
        let cases: [(RegistroError, String, Bool)] = [
            (.rateLimited, "rateLimited", false),
            (.rateLimited, "rateLimited", true),          // 403/429 sul login
            (.notSupported, "notSupported", false),
            (.unexpectedFormat("client-version"), "unexpectedFormat:client-version", true),
        ]
        for (error, code, onLogin) in cases {
            try setUpWithError()
            let c = makeCoordinator()
            provider.remoteGrades = [remote("1")]
            try await connectAndImport(c)
            if onLogin {
                keychain.remove("session")
                provider.loginErrors = [error]
            } else {
                provider.fetchErrors = [error]
            }
            let grades = store.grades

            clock.advance(3600)
            await c.syncNow(.manual)
            XCTAssertEqual(c.status, .error(code), code)
            provider.resetCalls()

            clock.advance(3600)
            let openPlan = await c.syncNow(.appOpen)
            let backgroundPlan = await c.syncNow(.background)
            XCTAssertNil(openPlan)
            XCTAssertNil(backgroundPlan)
            XCTAssertTrue(provider.calls.isEmpty, "\(code): nessun tentativo automatico, trovato \(provider.calls)")
            XCTAssertEqual(c.status, .error(code))
            XCTAssertEqual(store.grades, grades)

            // Anche dopo un riavvio dell'app.
            let relaunched = makeCoordinator()
            XCTAssertEqual(relaunched.status, .error(code))
            clock.advance(3600)
            await relaunched.syncNow(.appOpen)
            XCTAssertTrue(provider.calls.isEmpty, code)

            // La sync manuale funziona e, se riesce, riattiva quelle automatiche.
            await relaunched.syncNow(.manual)
            XCTAssertFalse(provider.calls.isEmpty, "\(code): la sync manuale parte")
            XCTAssertEqual(relaunched.status, .idle, code)
            provider.resetCalls()
            clock.advance(3600)
            await relaunched.syncNow(.appOpen)
            XCTAssertEqual(provider.calls, ["fetch"], code)
            try tearDownWithError()
        }
        try setUpWithError()
    }

    /// Un errore di rete invece non blocca i tentativi automatici.
    func testNetworkErrorKeepsAutomaticRetries() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        try await connectAndImport(c)
        provider.fetchErrors = [RegistroError.network]
        clock.advance(3600)
        await c.syncNow(.manual)
        XCTAssertEqual(c.status, .error("network"))
        provider.resetCalls()
        clock.advance(3600)
        await c.syncNow(.appOpen)
        XCTAssertEqual(provider.calls, ["fetch"])
        XCTAssertEqual(c.status, .idle)
    }

    func testMissingCredentialsNeedsLogin() async {
        defaults.set("classeviva", forKey: "registroProvider")
        defaults.set(account, forKey: "registroAccountKey")
        store.add(Grade(subject: "Storia"))
        let grades = store.grades
        let c = makeCoordinator()
        XCTAssertEqual(c.connectedProvider, .classeviva)

        let plan = await c.syncNow(.manual)
        XCTAssertNil(plan)
        XCTAssertEqual(c.status, .needsLogin)
        XCTAssertTrue(provider.calls.isEmpty)
        XCTAssertEqual(store.grades, grades)
        XCTAssertTrue(backups.list().isEmpty)

        await c.syncNow(.appOpen)
        XCTAssertTrue(provider.calls.isEmpty)
    }

    func testAppOpenThrottleFifteenMinutes() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        try await connectAndImport(c)
        provider.resetCalls()

        clock.advance(14 * 60)
        await c.syncNow(.appOpen)
        XCTAssertTrue(provider.calls.isEmpty, "meno di 15 minuti dall'ultimo tentativo")

        clock.advance(2 * 60)
        await c.syncNow(.appOpen)
        XCTAssertEqual(provider.calls, ["fetch"])

        // Anche un tentativo fallito conta.
        provider.fetchErrors = [RegistroError.network]
        clock.advance(16 * 60)
        await c.syncNow(.appOpen)
        XCTAssertEqual(provider.calls, ["fetch", "fetch"])
        XCTAssertTrue(isError(c.status))

        clock.advance(5 * 60)
        await c.syncNow(.appOpen)
        XCTAssertEqual(provider.calls, ["fetch", "fetch"])

        // "Sincronizza ora" non ha throttle.
        await c.syncNow(.manual)
        XCTAssertEqual(provider.calls, ["fetch", "fetch", "fetch"])
        XCTAssertEqual(c.status, .idle)
    }

    func testExpiredSessionRefreshesThenRelogins() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        try await connectAndImport(c)
        provider.resetCalls()

        // Sessione scaduta → refresh → fetch.
        provider.fetchErrors = [RegistroError.sessionExpired]
        clock.advance(3600)
        await c.syncNow(.manual)
        XCTAssertEqual(provider.calls, ["fetch", "refresh", "fetch"])
        XCTAssertEqual(provider.fetchTokens.last, "refresh-1")
        XCTAssertEqual(storedSessionToken(), "refresh-1")
        XCTAssertEqual(c.status, .idle)

        // Refresh rifiutato → nuovo login con le credenziali salvate.
        provider.resetCalls()
        provider.fetchErrors = [RegistroError.sessionExpired]
        provider.refreshErrors = [RegistroError.sessionExpired]
        clock.advance(3600)
        await c.syncNow(.manual)
        XCTAssertEqual(provider.calls, ["fetch", "refresh", "login", "fetch"])
        XCTAssertEqual(provider.fetchTokens.last, storedSessionToken())
        XCTAssertEqual(storedSessionToken(), "login-2")
        XCTAssertEqual(c.status, .idle)
    }

    func testLoginWithDifferentAccountWritesNothing() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        try await connectAndImport(c)
        keychain.remove("session")
        provider.accountKey = "ALTRO"
        provider.remoteGrades.append(remote("2", value: 6, raw: "6"))
        let grades = store.grades
        clock.advance(3600)
        await c.syncNow(.manual)
        XCTAssertTrue(isError(c.status))
        XCTAssertEqual(store.grades, grades)
        XCTAssertNil(keychain.data(for: "session"), "la sessione dell'altro account non viene salvata")
    }

    // MARK: Validazione

    func testPlanTouchingMoreThanTwentyManualGradesNeedsConfirmation() async throws {
        let manuals = (0..<21).map { i in
            Grade(subject: "Matematica", value: 4 + Double(i) * 0.25, date: d(3, 10, hour: 9), type: .oral)
        }
        for m in manuals { store.add(m) }
        provider.remoteGrades = manuals.enumerated().map { remote("\($0.offset)", value: $0.element.value, raw: "v") }
        let before = store.grades
        let c = makeCoordinator()

        try await connectAndImport(c)
        XCTAssertEqual(c.status, .needsConfirmation(21))
        XCTAssertEqual(store.grades, before, "nulla applicato senza conferma")
        XCTAssertTrue(backups.list().isEmpty)

        await c.confirmPendingPlan()
        XCTAssertEqual(c.status, .idle)
        XCTAssertEqual(backups.list().map(\.kind), [.preLink])
        XCTAssertEqual(Set(store.grades.map(\.id)), Set(manuals.map(\.id)), "stessi id, nessun voto nuovo")
        XCTAssertTrue(store.grades.allSatisfy { $0.origin?.manualSnapshot != nil })
        for m in manuals {
            XCTAssertEqual(store.grades.first { $0.id == m.id }?.value, m.value)
        }
    }

    func testValidatorRejectsLinkChangingValue() {
        let manual = Grade(subject: "Matematica", value: 7, date: d(3, 10))
        var link = manual
        link.value = 7.5
        link.origin = origin(link, remoteId: "1", manualSnapshot: ManualGradeSnapshot(manual))
        XCTAssertEqual(SyncPlanValidator.validate(SyncPlan(links: [link]), local: [manual]).isRejected, true)

        // Entro la tolleranza (7.005 → 7) il collegamento è valido.
        var near = manual
        near.value = 7.005
        var nearLink = near
        nearLink.value = 7
        nearLink.origin = origin(nearLink, remoteId: "1", manualSnapshot: ManualGradeSnapshot(near))
        XCTAssertEqual(SyncPlanValidator.validate(SyncPlan(links: [nearLink]), local: [near]), .ok)

        // Id: aggiornamenti e collegamenti devono esistere, inserimenti no.
        let other = imported("9")
        XCTAssertTrue(SyncPlanValidator.validate(SyncPlan(updates: [other]), local: [manual]).isRejected)
        XCTAssertTrue(SyncPlanValidator.validate(SyncPlan(inserts: [other]), local: [other]).isRejected)
        XCTAssertTrue(SyncPlanValidator.validate(SyncPlan(links: [nearLink]), local: []).isRejected)
        XCTAssertEqual(SyncPlanValidator.validate(SyncPlan(inserts: [other]), local: [manual]), .ok)

        // Un aggiornamento non cambia mai la nota dell'utente.
        var noted = other
        noted.note = "cambiata"
        XCTAssertTrue(SyncPlanValidator.validate(SyncPlan(updates: [noted]), local: [other]).isRejected)
    }

    func testValidatorThresholdIsMoreThanTwentyManualGrades() {
        func links(_ n: Int) -> (SyncPlan, [Grade]) {
            let manuals = (0..<n).map { _ in Grade(subject: "Matematica", value: 7, date: d(3, 10)) }
            let linked = manuals.enumerated().map { i, m -> Grade in
                var g = m
                g.origin = origin(g, remoteId: "\(i)", manualSnapshot: ManualGradeSnapshot(m))
                return g
            }
            return (SyncPlan(links: linked), manuals)
        }
        let (p20, l20) = links(20)
        XCTAssertEqual(SyncPlanValidator.validate(p20, local: l20), .ok)
        let (p21, l21) = links(21)
        XCTAssertEqual(SyncPlanValidator.validate(p21, local: l21), .needsConfirmation(manualTouched: 21))
    }

    // MARK: Doppioni

    func testDuplicateRemoteKeysCollapseKeepingLinkedManual() throws {
        let linked = linkedManual("9", note: "mia nota", modifiedAt: d(3, 10))
        store.replaceAll([linked])
        // Lo stesso voto importato su un altro dispositivo, più recente.
        let dup = imported("9", note: "nota iPad", modifiedAt: d(3, 19))

        store.applyRemote(upserts: [dup], deletions: [])

        XCTAssertEqual(store.grades.map(\.id), [linked.id], "si tiene il manuale collegato")
        XCTAssertEqual(store.grades.first?.note, "mia nota\nnota iPad")
        XCTAssertEqual(store.grades.first?.origin?.manualSnapshot, linked.origin?.manualSnapshot)
        let snap = try XCTUnwrap(backups.list().first { $0.kind == .preSync })
        XCTAssertTrue(backups.load(snap)?.contains { $0.id == dup.id } == true, "il doppione è nell'istantanea")
        XCTAssertEqual(GradeFileStore(url: fileURL).load().grades.map(\.id), [linked.id])
        XCTAssertFalse(settings.ignored.contains(key("9")), "la rimozione del doppione non è un'eliminazione dell'utente")
    }

    /// Due voti manuali diversi (es. due 7 veri, uno inserito su ogni dispositivo)
    /// collegati allo stesso voto del registro: nessuno dei due si perde. Uno resta
    /// collegato, l'altro torna un voto manuale normale con il suo id, i suoi valori
    /// originali e le modifiche dell'utente. Scelta deterministica e idempotente.
    func testDedupeRestoresSecondLinkedManualInsteadOfDeletingIt() throws {
        let a = linkedManual("9", value: 7, note: "compito A", modifiedAt: d(3, 10))
        var b = linkedManual("9", value: 7, note: "compito B", modifiedAt: d(3, 19))
        b.weight = 0.5 // modificato dall'utente dopo il collegamento
        let (winner, loser) = a.id.uuidString < b.id.uuidString ? (a, b) : (b, a)
        store.replaceAll([a])

        store.applyRemote(upserts: [b], deletions: [])

        XCTAssertEqual(Set(store.grades.map(\.id)), [a.id, b.id], "nessun voto dell'utente eliminato")
        let kept = try XCTUnwrap(store.grades.first { $0.id == winner.id })
        XCTAssertEqual(kept.origin?.remoteKey, key("9"))
        XCTAssertEqual(kept.note, winner.note, "la nota dell'altro voto resta sul suo voto")
        let restored = try XCTUnwrap(store.grades.first { $0.id == loser.id })
        let snap = try XCTUnwrap(loser.origin?.manualSnapshot)
        XCTAssertNil(restored.origin, "torna un voto manuale normale")
        XCTAssertEqual(restored.value, snap.value)
        XCTAssertEqual(restored.date, snap.date)
        XCTAssertEqual(restored.teacher, snap.teacher)
        XCTAssertEqual(restored.subject, snap.subject)
        XCTAssertEqual(restored.type, snap.type)
        XCTAssertEqual(restored.countsForAverage, snap.countsForAverage)
        XCTAssertEqual(restored.note, loser.note)
        XCTAssertEqual(restored.weight, loser.weight, "le modifiche dell'utente restano")
        XCTAssertEqual(Set(GradeFileStore(url: fileURL).load().grades.map(\.id)), [a.id, b.id])
        XCTAssertFalse(settings.ignored.contains(key("9")))

        // Idempotente: una seconda passata non cambia nulla.
        let once = store.grades
        store.applyRemote(upserts: [], deletions: [])
        XCTAssertEqual(store.grades, once)
        let again = RegistroDedupe.resolve(once)
        XCTAssertEqual(again.grades, once)
        XCTAssertTrue(again.dropped.isEmpty)

        // Deterministico: stesso esito in qualunque ordine e con qualunque modifiedAt
        // (i due dispositivi convergono allo stesso insieme).
        var bOlder = b; bOlder.modifiedAt = d(3, 1)
        let r1 = RegistroDedupe.resolve([a, b])
        let r2 = RegistroDedupe.resolve([bOlder, a])
        XCTAssertTrue(r1.dropped.isEmpty && r2.dropped.isEmpty)
        func byID(_ gs: [Grade]) -> [UUID: Grade] {
            Dictionary(uniqueKeysWithValues: gs.map { var g = $0; g.modifiedAt = .distantPast; return (g.id, g) })
        }
        XCTAssertEqual(byID(r1.grades), byID(r2.grades))
        XCTAssertNotNil(byID(r1.grades)[winner.id]?.origin)
        XCTAssertNil(byID(r1.grades)[loser.id]?.origin)
    }

    func testDedupePrefersEditedThenMostRecent() {
        let older = imported("5", modifiedAt: d(3, 11))
        var edited = imported("5", modifiedAt: d(3, 10))
        edited.id = UUID()
        edited.value = 8 // diverso da applied → modificato dall'utente
        var newer = imported("5", note: "n", modifiedAt: d(3, 15))
        newer.id = UUID()

        let r1 = RegistroDedupe.resolve([older, edited, newer])
        XCTAssertEqual(r1.grades.map(\.id), [edited.id])
        XCTAssertEqual(r1.grades.first?.note, "n")
        XCTAssertEqual(Set(r1.dropped.map(\.id)), [older.id, newer.id])

        let r2 = RegistroDedupe.resolve([older, newer, Grade(subject: "Storia")])
        XCTAssertEqual(r2.grades.count, 2)
        XCTAssertEqual(r2.grades.first?.id, newer.id)
        XCTAssertEqual(r2.dropped.map(\.id), [older.id])

        // Note uguali non vengono ripetute; nessun doppione → nulla cambia.
        var a = imported("6", note: "x"); a.id = UUID()
        let b = imported("6", note: "x", modifiedAt: d(3, 12))
        XCTAssertEqual(RegistroDedupe.resolve([a, b]).grades.first?.note, "x")
        let single = [imported("7"), Grade(subject: "Storia")]
        XCTAssertEqual(RegistroDedupe.resolve(single).grades, single)
        XCTAssertTrue(RegistroDedupe.resolve(single).dropped.isEmpty)
    }

    // MARK: Eliminazioni dell'utente → ignorati

    func testDeletingImportedGradeIgnoresIt() {
        let manual = Grade(subject: "Storia")
        let i1 = imported("1"), i2 = imported("2"), i3 = imported("3"), i4 = imported("4")
        let linked = linkedManual("5")
        store.replaceAll([manual, i1, i2, i3, i4, linked])
        XCTAssertTrue(settings.ignored.isEmpty)

        store.delete(ids: [i1.id, manual.id])
        XCTAssertEqual(settings.ignored, [key("1")])

        store.replaceAll(store.grades.filter { $0.id != i2.id })
        XCTAssertEqual(settings.ignored, [key("1"), key("2")])

        store.deleteAll()
        XCTAssertEqual(settings.ignored, [key("1"), key("2"), key("3"), key("4"), key("5")])
    }

    func testRemoteDeletionsAreNotIgnored() {
        let i1 = imported("1")
        store.replaceAll([i1])
        store.applyRemote(upserts: [], deletions: [i1.id])
        XCTAssertTrue(store.grades.isEmpty)
        XCTAssertTrue(settings.ignored.isEmpty, "una cancellazione da iCloud non è dell'utente su questo dispositivo")
    }

    func testDeletedImportedGradeIsNotReimported() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1"), remote("2", value: 6, raw: "6")]
        try await connectAndImport(c)
        store.delete(ids: [gid("1")])
        clock.advance(3600)
        let plan = await c.syncNow(.manual)
        XCTAssertEqual(plan?.isEmpty, true)
        XCTAssertEqual(store.grades.map(\.id), [gid("2")])
    }

    // MARK: Applicazione del piano

    func testNoWritesWhenPlanIsEmpty() async throws {
        let c = makeCoordinator()
        store.add(Grade(subject: "Storia"))
        provider.remoteGrades = [remote("1"), remote("2", value: 6, raw: "6")]
        try await connectAndImport(c)
        let grades = store.grades
        let snaps = backups.list().map(\.id)
        let data = try Data(contentsOf: fileURL)

        clock.advance(3600)
        let plan = await c.syncNow(.manual)
        XCTAssertEqual(plan?.isEmpty, true)
        XCTAssertEqual(store.grades, grades, "modifiedAt di tutti i voti invariato")
        XCTAssertEqual(store.grades.map(\.modifiedAt), grades.map(\.modifiedAt))
        XCTAssertEqual(backups.list().map(\.id), snaps, "nessuna istantanea per un piano vuoto")
        XCTAssertEqual(try Data(contentsOf: fileURL), data)
        XCTAssertEqual(c.status, .idle)
        XCTAssertEqual(c.lastSync, clock.now)
    }

    func testUpdateStampsOnlyChangedGrades() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1"), remote("2", value: 6, raw: "6")]
        try await connectAndImport(c)
        let before = store.grades
        clock.advance(3600)
        provider.remoteGrades[0] = remote("1", value: 8, raw: "8")

        let plan = await c.syncNow(.manual)
        XCTAssertEqual(plan?.updates.map(\.id), [gid("1")])
        let g1 = try XCTUnwrap(store.grades.first { $0.id == gid("1") })
        XCTAssertEqual(g1.value, 8)
        XCTAssertEqual(g1.modifiedAt, clock.now)
        XCTAssertEqual(store.grades.first { $0.id == gid("2") }, before.first { $0.id == gid("2") })
    }

    func testSkippedGradesDisableRemovalMarking() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1"), remote("2", value: 6, raw: "6"), remote("3", value: 5, raw: "5")]
        try await connectAndImport(c)
        XCTAssertEqual(c.lastSkippedCount, 0)

        // Download non letto del tutto: nessun voto segnato "rimosso".
        provider.remoteGrades.removeLast()
        provider.skippedCount = 1
        clock.advance(3600)
        await c.syncNow(.manual)
        XCTAssertEqual(c.lastSkippedCount, 1)
        XCTAssertTrue(store.grades.allSatisfy { $0.origin?.status == .active })

        // Stesso download letto per intero: il voto mancante è segnato (non cancellato).
        provider.skippedCount = 0
        clock.advance(3600)
        await c.syncNow(.manual)
        XCTAssertEqual(c.lastSkippedCount, 0)
        XCTAssertEqual(store.grades.first { $0.id == gid("3") }?.origin?.status, .removedFromRegistro)
        XCTAssertEqual(store.grades.count, 3)
    }

    func testWriteBlockedStoreAppliesNothing() async throws {
        try Data("{non json".utf8).write(to: fileURL)
        var fs = GradeFileStore(url: fileURL)
        fs.quarantineWriter = { _, _ in throw CocoaError(.fileWriteUnknown) }
        store = GradesStore(fileStore: fs, backups: backups, registroSettings: settings)
        provider.remoteGrades = [remote("1")]
        let c = makeCoordinator()

        try await connectAndImport(c)
        XCTAssertTrue(isError(c.status))
        XCTAssertTrue(store.grades.isEmpty)
        XCTAssertTrue(backups.list().isEmpty, "nessuna istantanea se il piano non si può applicare")
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("{non json".utf8))

        var g = Grade(id: gid("1"), subject: "Matematica")
        g.origin = origin(g, remoteId: "1")
        XCTAssertFalse(store.applyRegistroPlan(SyncPlan(inserts: [g])))
        XCTAssertTrue(store.grades.isEmpty)
    }

    func testSnapshotFailureAbortsSync() async throws {
        let badDir = dir.appendingPathComponent("NonUnaCartella")
        try Data("x".utf8).write(to: badDir)
        let bad = GradeBackups(directory: badDir)
        store.add(Grade(subject: "Storia"))
        let grades = store.grades
        provider.remoteGrades = [remote("1")]
        let c = makeCoordinator(backups: bad)

        try await connectAndImport(c)
        XCTAssertTrue(isError(c.status))
        XCTAssertEqual(store.grades, grades, "senza istantanea non si applica nulla")
        XCTAssertNil(c.lastSync)
    }

    // MARK: Conflitti

    func testConflictIsPersistedAndResolveLinks() async throws {
        let m1 = Grade(subject: "Matematica", value: 7, date: d(3, 10, hour: 9), type: .oral)
        let m2 = Grade(subject: "Matematica", value: 7, date: d(3, 10, hour: 11), type: .oral)
        store.add(m1); store.add(m2)
        provider.remoteGrades = [remote("1")]
        let c = makeCoordinator()
        try await connectAndImport(c)

        XCTAssertEqual(c.pendingConflicts.map(\.id), [key("1")])
        XCTAssertTrue(backups.list().isEmpty, "solo conflitti: nessuna scrittura")
        XCTAssertEqual(makeCoordinator().pendingConflicts.map(\.id), [key("1")], "salvati sul dispositivo")

        clock.advance(60)
        await c.resolve(key("1"), .linkTo(m2.id))
        XCTAssertTrue(c.pendingConflicts.isEmpty)
        XCTAssertEqual(store.grades.first { $0.id == m2.id }?.origin?.remoteKey, key("1"))
        XCTAssertNil(store.grades.first { $0.id == m1.id }?.origin)
        XCTAssertNotNil(defaults.data(forKey: "registroDecisions"))
        XCTAssertTrue(makeCoordinator().pendingConflicts.isEmpty)
    }

    /// Credenziali rifiutate: la risposta al conflitto viene salvata ma non parte
    /// nessuna sync (riuserebbe la password rifiutata); si applica dopo il nuovo login.
    func testResolveWhileNeedsLoginStoresDecisionWithoutSyncing() async throws {
        let m1 = Grade(subject: "Matematica", value: 7, date: d(3, 10, hour: 9), type: .oral)
        let m2 = Grade(subject: "Matematica", value: 7, date: d(3, 10, hour: 11), type: .oral)
        store.add(m1); store.add(m2)
        provider.remoteGrades = [remote("1")]
        let c = makeCoordinator()
        try await connectAndImport(c)
        XCTAssertEqual(c.pendingConflicts.map(\.id), [key("1")])

        keychain.remove("session")
        provider.loginErrors = [RegistroError.invalidCredentials]
        clock.advance(3600)
        await c.syncNow(.manual)
        XCTAssertEqual(c.status, .needsLogin)
        provider.resetCalls()

        await c.resolve(key("1"), .linkTo(m2.id))
        XCTAssertEqual(provider.calls, [], "nessun login con le credenziali rifiutate")
        XCTAssertEqual(c.status, .needsLogin)
        XCTAssertTrue(c.pendingConflicts.isEmpty)
        XCTAssertNil(store.grades.first { $0.id == m2.id }?.origin)
        XCTAssertNotNil(defaults.data(forKey: "registroDecisions"))
        await c.applyDecisions()
        XCTAssertEqual(provider.calls, [], "applyDecisions rispetta il login rifiutato")
        XCTAssertEqual(c.status, .needsLogin)

        // Nuovo login: la decisione salvata viene applicata.
        _ = try await c.connect(.classeviva, credentials: creds)
        await c.confirmMapping(c.mapping)
        XCTAssertEqual(store.grades.first { $0.id == m2.id }?.origin?.remoteKey, key("1"))
        XCTAssertNil(store.grades.first { $0.id == m1.id }?.origin)
    }

    /// `sync: false`: più risposte di fila, una sola sync alla fine.
    func testResolveWithoutSyncOnlyStoresDecision() async throws {
        let m1 = Grade(subject: "Matematica", value: 7, date: d(3, 10, hour: 9), type: .oral)
        let m2 = Grade(subject: "Matematica", value: 7, date: d(3, 10, hour: 11), type: .oral)
        store.add(m1); store.add(m2)
        provider.remoteGrades = [remote("1")]
        let c = makeCoordinator()
        try await connectAndImport(c)
        provider.resetCalls()

        await c.resolve(key("1"), .linkTo(m1.id), sync: false)
        XCTAssertEqual(provider.calls, [])
        XCTAssertTrue(c.pendingConflicts.isEmpty)
        XCTAssertNil(store.grades.first { $0.id == m1.id }?.origin)

        clock.advance(60)
        await c.applyDecisions()
        XCTAssertEqual(provider.calls, ["fetch"])
        XCTAssertEqual(store.grades.first { $0.id == m1.id }?.origin?.remoteKey, key("1"))
    }

    /// Mapping modificato mentre serve un nuovo login: salvato, nessuna sync.
    func testConfirmMappingWhileNeedsLoginDoesNotSync() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        try await connectAndImport(c)
        keychain.remove("session")
        provider.loginErrors = [RegistroError.invalidCredentials]
        clock.advance(3600)
        await c.syncNow(.manual)
        XCTAssertEqual(c.status, .needsLogin)
        provider.resetCalls()

        let edited = SubjectMappingTable(entries: ["S1": "Algebra"], confirmed: ["S1"])
        await c.confirmMapping(edited)
        XCTAssertEqual(provider.calls, [])
        XCTAssertEqual(c.status, .needsLogin)
        XCTAssertEqual(c.mapping, edited)
    }

    /// Errori di formato con un significato preciso per l'utente: il codice lo conserva.
    func testUnexpectedFormatKeepsKnownDetails() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        try await connectAndImport(c)
        let cases: [(String, String)] = [("client-version", "unexpectedFormat:client-version"),
                                         ("profili", "unexpectedFormat:profili"),
                                         ("choices", "unexpectedFormat:profili"),
                                         ("voti", "unexpectedFormat")]
        for (detail, expected) in cases {
            provider.fetchErrors = [RegistroError.unexpectedFormat(detail)]
            clock.advance(3600)
            await c.syncNow(.manual)
            XCTAssertEqual(c.status, .error(expected), detail)
        }
    }

    func testProviderAvailabilityAndLoginFields() {
        let c = makeCoordinator()
        XCTAssertTrue(c.isAvailable(.classeviva))
        XCTAssertEqual(c.loginFields(for: .classeviva), [.username, .password])
        XCTAssertFalse(c.isAvailable(.argo), "provider non registrato")
        XCTAssertEqual(c.loginFields(for: .argo), [])
        provider.isAvailable = false
        XCTAssertFalse(makeCoordinator().isAvailable(.classeviva))
    }

    // MARK: Scollega

    func testUnlinkKeepImported() async throws {
        let manual = Grade(subject: "Matematica", teacher: "", value: 7, date: d(3, 10, hour: 10), type: .oral)
        let other = Grade(subject: "Storia", value: 9)
        store.add(manual); store.add(other)
        provider.remoteGrades = [remote("1", teacher: "Rossi"), remote("2", value: 6, raw: "6", date: d(3, 12))]
        let c = makeCoordinator()
        try await connectAndImport(c)
        XCTAssertNotNil(store.grades.first { $0.id == manual.id }?.origin?.manualSnapshot)
        settings.ignore(key("99"))
        provider.resetCalls()

        await c.unlink(keepImported: true)

        let snap = try XCTUnwrap(backups.list().first { $0.kind == .preUnlink })
        XCTAssertEqual(backups.load(snap)?.count, 3)
        XCTAssertEqual(Set(store.grades.map(\.id)), [manual.id, other.id, gid("2")])
        XCTAssertTrue(store.grades.allSatisfy { $0.origin == nil })
        let restored = try XCTUnwrap(store.grades.first { $0.id == manual.id })
        XCTAssertEqual(restored.date, manual.date, "campi non modificati tornano al voto manuale")
        XCTAssertEqual(restored.teacher, "")
        XCTAssertEqual(store.grades.first { $0.id == gid("2") }?.value, 6)

        XCTAssertTrue(settings.ignored.isEmpty)
        XCTAssertTrue(settings.mapping.entries.isEmpty)
        XCTAssertNil(keychain.data(for: "credentials"))
        XCTAssertNil(keychain.data(for: "session"))
        XCTAssertEqual(c.status, .disconnected)
        XCTAssertNil(c.connectedProvider)
        XCTAssertNil(c.lastSync)
        for k in ["registroProvider", "registroAccountKey", "registroLastSync", "registroLastAttempt",
                  "registroPendingConflicts", "registroDecisions"] {
            XCTAssertNil(defaults.object(forKey: k), k)
        }
        XCTAssertEqual(provider.calls, ["logout"])

        let plan = await c.syncNow(.manual)
        XCTAssertNil(plan)
        XCTAssertEqual(provider.calls, ["logout"])
        XCTAssertEqual(c.status, .disconnected)
    }

    func testUnlinkDeleteImportedKeepsEditedAndManual() async throws {
        let manual = Grade(subject: "Matematica", value: 7, date: d(3, 10, hour: 10), type: .oral)
        let other = Grade(subject: "Storia", value: 9)
        store.add(manual); store.add(other)
        provider.remoteGrades = [remote("1"), remote("2", value: 6, raw: "6", date: d(3, 12)),
                                 remote("3", value: 5, raw: "5", date: d(3, 13)),
                                 remote("4", value: 4, raw: "4", date: d(3, 14))]
        let c = makeCoordinator()
        try await connectAndImport(c)

        // L'utente modifica: valore del manuale collegato, valore di un importato, nota di un altro.
        var linked = try XCTUnwrap(store.grades.first { $0.id == manual.id })
        linked.value = 8
        store.update(linked)
        var edited = try XCTUnwrap(store.grades.first { $0.id == gid("3") })
        edited.value = 5.5
        store.update(edited)
        var noted = try XCTUnwrap(store.grades.first { $0.id == gid("4") })
        noted.note = "da ripassare"
        store.update(noted)

        await c.unlink(keepImported: false)

        let snap = try XCTUnwrap(backups.list().first { $0.kind == .preUnlink })
        XCTAssertEqual(backups.load(snap)?.count, 5)
        XCTAssertEqual(Set(store.grades.map(\.id)), [manual.id, other.id, gid("3"), gid("4")])
        XCTAssertTrue(store.grades.allSatisfy { $0.origin == nil })
        let m = try XCTUnwrap(store.grades.first { $0.id == manual.id })
        XCTAssertEqual(m.value, 8, "la modifica dell'utente resta")
        XCTAssertEqual(m.date, manual.date)
        XCTAssertEqual(store.grades.first { $0.id == gid("3") }?.value, 5.5)
        XCTAssertEqual(store.grades.first { $0.id == gid("4") }?.note, "da ripassare")
        XCTAssertEqual(GradeFileStore(url: fileURL).load().grades.count, 4)
        XCTAssertTrue(settings.ignored.isEmpty, "i voti rimossi dallo scollegamento non sono ignorati")
        XCTAssertNil(keychain.data(for: "credentials"))
        XCTAssertEqual(c.status, .disconnected)
    }

    func testUnlinkAbortsWhenSnapshotFails() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        try await connectAndImport(c)
        let grades = store.grades
        let badDir = dir.appendingPathComponent("NonUnaCartella")
        try Data("x".utf8).write(to: badDir)
        let c2 = makeCoordinator(backups: GradeBackups(directory: badDir))

        await c2.unlink(keepImported: false)
        XCTAssertTrue(isError(c2.status))
        XCTAssertEqual(store.grades, grades)
        XCTAssertNotNil(keychain.data(for: "credentials"))
        XCTAssertEqual(c2.connectedProvider, .classeviva)
    }

    func testUnlinkDuringSyncDiscardsDownload() async throws {
        let c = makeCoordinator()
        provider.remoteGrades = [remote("1")]
        try await connectAndImport(c)
        provider.remoteGrades.append(remote("2", value: 6, raw: "6"))
        provider.fetchErrors = [RegistroError.sessionExpired]
        provider.onFetch = { await c.unlink(keepImported: true) }

        clock.advance(3600)
        let plan = await c.syncNow(.manual)
        XCTAssertNil(plan)
        XCTAssertEqual(c.status, .disconnected)
        XCTAssertFalse(store.grades.contains { $0.id == gid("2") })
        XCTAssertNil(keychain.data(for: "session"), "nessuna sessione risalvata dopo lo scollegamento")
        XCTAssertNil(keychain.data(for: "credentials"))
    }
}

private extension PlanValidation {
    var isRejected: Bool {
        if case .rejected = self { return true }
        return false
    }
}
