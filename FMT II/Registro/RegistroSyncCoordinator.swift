import Foundation

/// Stato del collegamento al registro, per Impostazioni.
enum RegistroStatus: Equatable {
    case disconnected
    case idle
    case syncing
    /// Credenziali assenti o rifiutate: nessuna sync (nemmeno manuale) finché l'utente non rifà il login.
    case needsLogin
    /// Il piano tocca più di 20 voti manuali: in attesa di `confirmPendingPlan()`.
    case needsConfirmation(Int)
    /// Codice tecnico dell'errore (la UI mostra un messaggio generico localizzato).
    case error(String)
}

enum SyncTrigger {
    case manual, appOpen, background
}

enum RegistroCoordinatorError: Error, Equatable {
    /// Provider sconosciuto o non ancora disponibile (stub).
    case providerUnavailable
    /// È già collegato un altro registro: prima va scollegato.
    case alreadyConnected
    /// Il login appartiene a un account diverso da quello collegato.
    case differentAccount
    /// Credenziali o sessione non salvabili nel Portachiavi.
    case keychain
    /// Il registro è stato scollegato mentre l'operazione era in corso.
    case cancelled
}

/// Coordina login, download, piano, validazione e applicazione (spec §5–§7).
/// Regole: download e calcolo non scrivono nulla; prima di ogni scrittura
/// un'istantanea; qualsiasi errore = nessuna scrittura dei voti.
@MainActor
final class RegistroSyncCoordinator: ObservableObject {
    /// Chiavi locali (mai sincronizzate). Credenziali e token solo nel Portachiavi.
    enum Keys {
        static let provider = "registroProvider"
        static let accountKey = "registroAccountKey"
        static let lastSync = "registroLastSync"
        static let lastAttempt = "registroLastAttempt"
        static let pendingConflicts = "registroPendingConflicts"
        static let decisions = "registroDecisions"
        /// Credenziali rifiutate: nessun tentativo, nemmeno manuale, fino al nuovo login (evita blocchi dell'account).
        static let needsLogin = "registroNeedsLogin"
        /// Codice dell'ultimo errore che fallirebbe di nuovo (accesso limitato o
        /// bloccato, account non supportato, versione dell'app rifiutata): niente
        /// tentativi automatici finché una sync manuale o un nuovo login non riescono.
        static let autoSyncBlocked = "registroAutoSyncBlocked"

        static let all = [provider, accountKey, lastSync, lastAttempt, pendingConflicts, decisions, needsLogin,
                          autoSyncBlocked]

        /// Preferenza "Notifiche voti nuovi" (spenta di default). Non è in `all`:
        /// è una scelta dell'utente, resta anche scollegando.
        static let notifyNewGrades = "registroNotifyNewGrades"
    }

    enum KeychainKeys {
        static let credentials = "credentials"
        static let session = "session"
    }

    /// Sync all'apertura al più ogni 15 minuti (dall'ultimo tentativo, riuscito o no).
    static let appOpenInterval: TimeInterval = 15 * 60
    /// Età massima del download del collegamento riusabile da `confirmMapping`.
    static let prefetchMaxAge: TimeInterval = 10 * 60

    @Published private(set) var status: RegistroStatus
    @Published private(set) var lastSync: Date?
    @Published private(set) var pendingConflicts: [PendingConflict]
    @Published private(set) var pendingSubjects: [RemoteSubjectRef] = []
    /// Voti del registro non letti nell'ultimo download ("voti non letti").
    @Published private(set) var lastSkippedCount = 0
    /// L'ultimo piano ha saltato il controllo "rimossi dal registro" per protezione.
    @Published private(set) var lastRemovalCheckSkipped = false

    /// Mapping materie attuale (solo lettura: si cambia con `confirmMapping`).
    var mapping: SubjectMappingTable { settings.mapping }

    /// Registro selezionabile (gli stub non lo sono).
    func isAvailable(_ id: RegistroProviderID) -> Bool {
        providers[id]?.isAvailable ?? false
    }

    /// Campi del modulo di accesso richiesti dal registro (es. codice scuola per Argo).
    func loginFields(for id: RegistroProviderID) -> [LoginField] {
        providers[id]?.loginFields ?? []
    }

    var connectedProvider: RegistroProviderID? {
        defaults.string(forKey: Keys.provider).flatMap(RegistroProviderID.init(rawValue:))
    }

    private let grades: GradesStore
    private let backups: GradeBackups
    private let settings: RegistroSettingsStore
    private let keychain: KeychainStore
    private let providers: [RegistroProviderID: RegistroProvider]
    private let defaults: UserDefaults
    private let now: () -> Date

    /// Piano in attesa di conferma, con il download da cui è nato (si ricalcola alla conferma).
    private var pending: (fetch: RemoteFetch, provider: RegistroProviderID, accountKey: String, generation: Int)?
    /// Download del collegamento, riusato solo dalla conferma del mapping che lo
    /// segue subito: scartato se è partita un'altra sync o se è più vecchio di
    /// `prefetchMaxAge` (un download vecchio farebbe tornare indietro i valori e
    /// segnerebbe "rimossi" i voti arrivati dopo).
    private var prefetched: (fetch: RemoteFetch, generation: Int, date: Date)?
    /// Cambia a ogni scollegamento: i risultati di operazioni iniziate prima vengono scartati.
    private var generation = 0

    init(grades: GradesStore, backups: GradeBackups, settings: RegistroSettingsStore, keychain: KeychainStore,
         providers: [RegistroProvider], defaults: UserDefaults, now: @escaping () -> Date = Date.init) {
        self.grades = grades
        self.backups = backups
        self.settings = settings
        self.keychain = keychain
        self.providers = Dictionary(providers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.defaults = defaults
        self.now = now
        lastSync = defaults.object(forKey: Keys.lastSync) as? Date
        pendingConflicts = Self.decode([PendingConflict].self, defaults.data(forKey: Keys.pendingConflicts)) ?? []
        if defaults.string(forKey: Keys.provider).flatMap(RegistroProviderID.init(rawValue:)) == nil {
            status = .disconnected
        } else {
            if defaults.bool(forKey: Keys.needsLogin) {
                status = .needsLogin
            } else if let code = defaults.string(forKey: Keys.autoSyncBlocked) {
                status = .error(code)
            } else {
                status = .idle
            }
        }
    }

    // MARK: - Collegamento

    /// Login e primo download, senza scrivere voti. Le credenziali vanno nel
    /// Portachiavi solo se login e download riescono. Restituisce le proposte per
    /// le materie del registro non ancora confermate. Serve anche a rifare il
    /// login dopo `.needsLogin` (stesso registro e stesso account).
    func connect(_ id: RegistroProviderID, credentials: RegistroCredentials) async throws -> [(RemoteSubjectRef, SubjectProposal)] {
        guard let provider = providers[id], provider.isAvailable else { throw RegistroCoordinatorError.providerUnavailable }
        if let current = connectedProvider, current != id { throw RegistroCoordinatorError.alreadyConnected }
        let gen = generation

        let session = try await provider.login(credentials)
        guard gen == generation else { throw RegistroCoordinatorError.cancelled }
        if connectedProvider != nil, let stored = defaults.string(forKey: Keys.accountKey), stored != session.accountKey {
            throw RegistroCoordinatorError.differentAccount
        }
        let fetch = try await provider.fetchGrades(session)
        guard gen == generation else { throw RegistroCoordinatorError.cancelled }

        guard let credData = try? JSONEncoder().encode(credentials),
              let sessionData = try? JSONEncoder().encode(session) else { throw RegistroCoordinatorError.keychain }
        do {
            try keychain.set(credData, for: KeychainKeys.credentials)
            try keychain.set(sessionData, for: KeychainKeys.session)
        } catch {
            throw RegistroCoordinatorError.keychain
        }

        defaults.set(id.rawValue, forKey: Keys.provider)
        defaults.set(session.accountKey, forKey: Keys.accountKey)
        defaults.set(now(), forKey: Keys.lastAttempt)
        defaults.removeObject(forKey: Keys.needsLogin)
        defaults.removeObject(forKey: Keys.autoSyncBlocked)
        prefetched = (fetch, gen, now())
        status = .idle
        RegistroBackgroundRefresh.scheduleAndSubmit(now: now())

        let mapping = settings.mapping
        var seen = Set<String>()
        var refs: [RemoteSubjectRef] = []
        for r in fetch.grades {
            let ref = RemoteSubjectRef(id: r.subjectId, name: r.subjectName.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !mapping.confirmed.contains(ref.key), seen.insert(ref.key).inserted else { continue }
            refs.append(ref)
        }
        pendingSubjects = refs
        let appSubjects = grades.subjects
        return refs.map { ($0, SubjectMatcher.propose($0, appSubjects: appSubjects)) }
    }

    /// Salva il mapping confermato e fa la prima sync (istantanea `.preLink` se è il primo import).
    /// Con le credenziali rifiutate il mapping viene salvato ma non parte nessuna
    /// sync: si applicherà dopo il nuovo login.
    func confirmMapping(_ table: SubjectMappingTable) async {
        settings.mapping = table
        guard !credentialsRejected() else { return }
        _ = await run(useFetch: takePrefetched())
    }

    // MARK: - Sync

    /// Download → piano → validazione → (istantanea → applicazione).
    /// Restituisce il piano calcolato (applicato o in attesa di conferma), nil se
    /// la sync non è partita o è fallita.
    @discardableResult
    func syncNow(_ trigger: SyncTrigger) async -> SyncPlan? {
        guard connectedProvider != nil else { status = .disconnected; return nil }
        guard status != .syncing else { return nil }
        // Credenziali rifiutate: nessun tentativo, nemmeno manuale (rimandarle
        // potrebbe bloccare l'account). Serve un nuovo login.
        guard !credentialsRejected() else { return nil }
        if trigger != .manual {
            // Errore che fallirebbe di nuovo: solo l'utente può riprovare.
            if let code = defaults.string(forKey: Keys.autoSyncBlocked) { status = .error(code); return nil }
            if trigger == .appOpen, let last = defaults.object(forKey: Keys.lastAttempt) as? Date,
               now().timeIntervalSince(last) < Self.appOpenInterval {
                return nil
            }
        }
        let isFirstImport = lastSync == nil
        let plan = await run(useFetch: nil)
        if let plan {
            let toNotify = RegistroNotificationPolicy.gradesToNotify(
                plan: plan, trigger: trigger, isFirstImport: isFirstImport,
                toggleOn: defaults.bool(forKey: Keys.notifyNewGrades), grades: grades.grades)
            if !toNotify.isEmpty { NotificationManager.shared.notifyNewGrades(toNotify) }
        }
        return plan
    }

    /// Applica il piano in attesa di conferma, ricalcolato sui voti attuali (così
    /// nessuna modifica fatta nel frattempo viene sovrascritta).
    func confirmPendingPlan() async {
        guard let p = pending, status != .syncing else { return }
        pending = nil
        guard p.generation == generation, connectedProvider == p.provider else { return }
        let plan = makePlan(p.fetch, provider: p.provider, accountKey: p.accountKey)
        if case .rejected(let reason) = SyncPlanValidator.validate(plan, local: grades.grades) {
            status = .error("invalidPlan:\(reason)")
            return
        }
        _ = apply(plan, provider: p.provider, accountKey: p.accountKey)
    }

    /// Risposta a un conflitto: viene ricordata e si risincronizza subito (senza
    /// throttle). `sync: false` la salva soltanto (più risposte, una sola sync).
    /// Con le credenziali rifiutate non parte nessuna sync: riuserebbe la password
    /// rifiutata (rischio di blocco dell'account); la decisione vale dal nuovo login.
    func resolve(_ conflictID: String, _ decision: ConflictDecision, sync: Bool = true) async {
        var decisions = Self.decode([String: ConflictDecision].self, defaults.data(forKey: Keys.decisions)) ?? [:]
        decisions[conflictID] = decision
        if let data = try? JSONEncoder().encode(decisions) { defaults.set(data, forKey: Keys.decisions) }
        if decision != .later {
            setConflicts(pendingConflicts.filter { $0.id != conflictID })
        }
        guard sync, !credentialsRejected() else { return }
        _ = await syncNow(.manual)
    }

    /// Una sola sync dopo più risposte salvate con `resolve(_:_:sync: false)`.
    /// Con le credenziali rifiutate non fa nulla (le decisioni restano salvate).
    func applyDecisions() async {
        guard !credentialsRejected() else { return }
        _ = await syncNow(.manual)
    }

    // MARK: - Scollega

    /// Istantanea `.preUnlink`, poi i voti tornano normali (spec §6.5), poi si
    /// cancellano credenziali, ignorati, mapping e stato locale. Se l'istantanea o
    /// la scrittura falliscono non cambia nulla e il registro resta collegato.
    func unlink(keepImported: Bool) async {
        guard grades.isWritable() else { status = .error("writeBlocked"); return }
        guard backups.snapshot(grades.grades, kind: .preUnlink, now: now()) != nil else {
            status = .error("snapshotFailed")
            return
        }
        guard grades.applyRegistroUnlink(keepImported: keepImported, now: now()) else {
            status = .error("writeFailed")
            return
        }

        generation += 1
        let provider = connectedProvider.flatMap { providers[$0] }
        let session = loadSession()
        keychain.remove(KeychainKeys.credentials)
        keychain.remove(KeychainKeys.session)
        settings.clearIgnored()
        settings.mapping = SubjectMappingTable(entries: [:], confirmed: [])
        for k in Keys.all { defaults.removeObject(forKey: k) }
        pending = nil
        prefetched = nil
        lastSync = nil
        pendingConflicts = []
        pendingSubjects = []
        lastSkippedCount = 0
        lastRemovalCheckSkipped = false
        status = .disconnected
        RegistroBackgroundRefresh.cancel()
        // Per cortesia verso il registro; lo stato locale è già pulito.
        if let provider, let session { await provider.logout(session) }
    }

    // MARK: - Interni

    /// Ultimo login rifiutato: nessuna sync finché l'utente non rifà l'accesso.
    private func credentialsRejected() -> Bool {
        guard defaults.bool(forKey: Keys.needsLogin) else { return false }
        status = .needsLogin
        return true
    }

    private func takePrefetched() -> RemoteFetch? {
        defer { prefetched = nil }
        guard let p = prefetched, p.generation == generation else { return nil }
        let age = now().timeIntervalSince(p.date)
        guard age >= 0, age < Self.prefetchMaxAge else { return nil }
        return p.fetch
    }

    private func run(useFetch: RemoteFetch?) async -> SyncPlan? {
        guard let id = connectedProvider, let accountKey = defaults.string(forKey: Keys.accountKey) else {
            status = .disconnected
            return nil
        }
        guard let provider = providers[id] else { status = .error("providerUnavailable"); return nil }
        guard status != .syncing else { return nil }
        guard let credentials = loadCredentials() else { status = .needsLogin; return nil }
        // Parte un'altra sync: il download del collegamento non è più il più recente.
        if useFetch == nil { prefetched = nil }

        let gen = generation
        defaults.set(now(), forKey: Keys.lastAttempt)
        status = .syncing
        do {
            let fetch: RemoteFetch
            if let useFetch {
                fetch = useFetch
            } else {
                fetch = try await download(provider, credentials: credentials, accountKey: accountKey, generation: gen)
            }
            guard gen == generation else { return nil }
            defaults.removeObject(forKey: Keys.needsLogin)
            defaults.removeObject(forKey: Keys.autoSyncBlocked)
            return finish(fetch, provider: id, accountKey: accountKey)
        } catch {
            // Scollegato nel frattempo: lo stato è già quello giusto.
            guard gen == generation else { return nil }
            if case RegistroError.invalidCredentials? = error as? RegistroError {
                defaults.set(true, forKey: Keys.needsLogin)
                status = .needsLogin
            } else {
                let code = Self.code(for: error)
                if Self.blocksAutomaticRetries(error) { defaults.set(code, forKey: Keys.autoSyncBlocked) }
                status = .error(code)
            }
            return nil
        }
    }

    /// Errori che un nuovo tentativo automatico ripeterebbe di sicuro (e ogni
    /// tentativo può essere un login con password): accesso limitato o bloccato
    /// dal registro (403/429; per ClasseViva un 403 può anche voler dire password
    /// cambiata), account non supportato, versione dell'app rifiutata da Argo.
    nonisolated static func blocksAutomaticRetries(_ error: Error) -> Bool {
        guard let e = error as? RegistroError else { return false }
        switch e {
        case .rateLimited, .notSupported: return true
        case .unexpectedFormat(let detail): return detail == "client-version"
        case .invalidCredentials, .sessionExpired, .network: return false
        }
    }

    /// Sessione salvata (o nuovo login) → fetch; sessione scaduta → refresh → fetch;
    /// refresh rifiutato → nuovo login → fetch. Le sessioni nuove si salvano solo
    /// se il registro è ancora collegato e appartengono allo stesso account.
    private func download(_ provider: RegistroProvider, credentials: RegistroCredentials,
                          accountKey: String, generation gen: Int) async throws -> RemoteFetch {
        func adopt(_ s: RegistroSession) throws {
            guard gen == generation else { throw RegistroCoordinatorError.cancelled }
            guard s.accountKey == accountKey else { throw RegistroCoordinatorError.differentAccount }
            storeSession(s)
        }

        var session: RegistroSession
        if let saved = loadSession() {
            session = saved
        } else {
            session = try await provider.login(credentials)
            try adopt(session)
        }

        do {
            return try await provider.fetchGrades(session)
        } catch RegistroError.sessionExpired {
            guard gen == generation else { throw RegistroCoordinatorError.cancelled }
            do {
                session = try await provider.refresh(session)
            } catch let e as RegistroError where e != .network && e != .rateLimited {
                guard gen == generation else { throw RegistroCoordinatorError.cancelled }
                session = try await provider.login(credentials)
            }
            try adopt(session)
            return try await provider.fetchGrades(session)
        }
    }

    /// Calcola e valida il piano; lo applica se valido, lo tiene in attesa se
    /// serve conferma. Nessun `await`: i voti non cambiano fra calcolo e scrittura.
    private func finish(_ raw: RemoteFetch, provider: RegistroProviderID, accountKey: String) -> SyncPlan? {
        var fetch = raw
        lastSkippedCount = fetch.skippedCount
        // Download non letto del tutto: niente controllo "rimossi dal registro".
        if fetch.skippedCount > 0 { fetch.coveredRange = nil }
        // Se il file voti era bloccato prova a rileggerlo prima di calcolare il piano.
        _ = grades.isWritable()
        let plan = makePlan(fetch, provider: provider, accountKey: accountKey)
        pending = nil

        switch SyncPlanValidator.validate(plan, local: grades.grades) {
        case .rejected(let reason):
            status = .error("invalidPlan:\(reason)")
            return nil
        case .needsConfirmation(let n):
            pending = (fetch, provider, accountKey, generation)
            publish(plan)
            status = .needsConfirmation(n)
            return plan
        case .ok:
            return apply(plan, provider: provider, accountKey: accountKey) ? plan : nil
        }
    }

    private func makePlan(_ fetch: RemoteFetch, provider: RegistroProviderID, accountKey: String) -> SyncPlan {
        let decisions = Self.decode([String: ConflictDecision].self, defaults.data(forKey: Keys.decisions)) ?? [:]
        return RegistroSyncEngine.plan(RegistroSyncInput(
            local: grades.grades, fetch: fetch, provider: provider, accountKey: accountKey,
            mapping: settings.mapping, ignored: settings.ignored, decisions: decisions,
            maxGrade: maxGrade, calendar: .current))
    }

    /// Istantanea (`.preLink` al primo import per questo account, poi `.preSync`)
    /// e scrittura. Piano vuoto: nessuna istantanea, nessuna scrittura.
    private func apply(_ plan: SyncPlan, provider: RegistroProviderID, accountKey: String) -> Bool {
        if !plan.isEmpty {
            guard grades.isWritable() else { status = .error("writeBlocked"); return false }
            let firstImport = !grades.grades.contains {
                $0.origin?.provider == provider && $0.origin?.accountKey == accountKey
            }
            guard backups.snapshot(grades.grades, kind: firstImport ? .preLink : .preSync, now: now()) != nil else {
                status = .error("snapshotFailed")
                return false
            }
            guard grades.applyRegistroPlan(plan, now: now()) else {
                status = .error("writeFailed")
                return false
            }
        }
        publish(plan)
        let date = now()
        lastSync = date
        defaults.set(date, forKey: Keys.lastSync)
        status = .idle
        return true
    }

    private func publish(_ plan: SyncPlan) {
        setConflicts(plan.conflicts)
        pendingSubjects = plan.pendingSubjects
        lastRemovalCheckSkipped = plan.removalCheckSkipped
    }

    private func setConflicts(_ conflicts: [PendingConflict]) {
        pendingConflicts = conflicts
        if let data = try? JSONEncoder().encode(conflicts) { defaults.set(data, forKey: Keys.pendingConflicts) }
    }

    private func loadCredentials() -> RegistroCredentials? {
        Self.decode(RegistroCredentials.self, keychain.data(for: KeychainKeys.credentials))
    }

    private func loadSession() -> RegistroSession? {
        Self.decode(RegistroSession.self, keychain.data(for: KeychainKeys.session))
    }

    private func storeSession(_ s: RegistroSession) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? keychain.set(data, for: KeychainKeys.session)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Codice tecnico, senza dettagli che potrebbero contenere dati del registro.
    nonisolated static func code(for error: Error) -> String {
        switch error {
        case let e as RegistroError:
            switch e {
            case .invalidCredentials: return "invalidCredentials"
            case .sessionExpired: return "sessionExpired"
            case .network: return "network"
            case .unexpectedFormat(let detail):
                // Solo i casi che l'utente deve conoscere (testi costanti del provider,
                // mai dati del registro): versione dell'app rifiutata, più profili.
                switch detail {
                case "client-version": return "unexpectedFormat:client-version"
                case "profili", "choices": return "unexpectedFormat:profili"
                default: return "unexpectedFormat"
                }
            case .notSupported: return "notSupported"
            case .rateLimited: return "rateLimited"
            }
        case let e as RegistroCoordinatorError:
            return "\(e)"
        default:
            return "unexpected"
        }
    }
}
