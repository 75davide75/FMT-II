#if DEBUG
import Foundation

/// Registro finto per i test di interfaccia: nessuna rete, voti scriptati.
///
/// Attivo **solo** nei build DEBUG e **solo** se l'app è lanciata con
/// `-FMTFakeRegistro` **insieme a** `-FMTSeedDemo` (che spegne iCloud e prepara i
/// dati demo, così nulla di finto arriva su iCloud). L'intero file è in `#if DEBUG`:
/// nel build Release non esiste.
///
/// Dati: materie da mappare (uguali, alias "suggeriti", nuove, due materie del
/// registro sulla stessa dell'app), un voto ambiguo fra due voti manuali, un
/// giudizio non numerico e un voto non letto.
@MainActor
enum FakeRegistro {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-FMTFakeRegistro") && DemoSeed.isRequested
    }

    private static var prepared = false

    /// Portachiavi separato da quello vero.
    static let keychain = KeychainStore(service: "com.davide.fmtII.registro.fake")

    /// Copie dei voti in una cartella a parte, svuotata a ogni avvio.
    static let backups: GradeBackups = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("GradeBackups-FakeRegistro", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        return GradeBackups(directory: dir)
    }()

    static func makeCoordinator(grades: GradesStore) -> RegistroSyncCoordinator {
        RegistroSyncCoordinator(
            grades: grades, backups: backups, settings: RegistroSettingsStore(), keychain: keychain,
            providers: [ScriptedRegistroProvider(id: .classeviva, loginFields: [.username, .password]),
                        ScriptedRegistroProvider(id: .argo, loginFields: [.schoolCode, .username, .password]),
                        AxiosProvider(), NuvolaProvider(), MastercomProvider(), PronoteProvider()],
            defaults: .standard)
    }

    /// Da chiamare dopo il seed demo e prima del primo uso del coordinatore:
    /// stato del registro azzerato e due voti manuali che rendono ambiguo `MAT-1`.
    static func prepareIfRequested(grades: GradesStore) {
        // Una volta sola per processo (su iPad ogni finestra chiama onAppear).
        guard isRequested, !prepared else { return }
        prepared = true
        let defaults = UserDefaults.standard
        for k in RegistroSyncCoordinator.Keys.all { defaults.removeObject(forKey: k) }
        let settings = RegistroSettingsStore()
        settings.mapping = SubjectMappingTable(entries: [:], confirmed: [])
        settings.clearIgnored()
        keychain.remove(RegistroSyncCoordinator.KeychainKeys.credentials)
        keychain.remove(RegistroSyncCoordinator.KeychainKeys.session)
        for hour in [9, 11] {
            grades.add(Grade(subject: "Matematica", teacher: "Bianchi", value: 7,
                             date: date(2026, 5, 20, hour: hour), type: .oral))
        }
    }

    /// Con `-FMTFakeRegistroAutoConnect` il registro finto parte già collegato e con i
    /// voti importati (mapping accettato come proposto), senza passare dal login: serve
    /// agli screenshot dove digitare nel login non è affidabile (iPad). Insieme a
    /// `-FMTFakeRegistroRemoval` fa anche la seconda lettura, così un voto risulta rimosso.
    static func autoConnectIfRequested(_ coordinator: RegistroSyncCoordinator) {
        let args = ProcessInfo.processInfo.arguments
        guard isRequested, args.contains("-FMTFakeRegistroAutoConnect") else { return }
        Task { @MainActor in
            do {
                let proposals = try await coordinator.connect(
                    .classeviva, credentials: RegistroCredentials(username: "studente.prova", password: "prova", schoolCode: nil))
                var table = coordinator.mapping
                for (ref, proposal) in proposals {
                    switch proposal {
                    case .existing(let name, _), .new(let name): table.entries[ref.key] = name
                    }
                    table.confirmed.insert(ref.key)
                }
                await coordinator.confirmMapping(table)
                if args.contains("-FMTFakeRegistroRemoval") { _ = await coordinator.syncNow(.manual) }
            } catch {}
        }
    }

    private static let fetchLock = NSLock()
    nonisolated(unsafe) private static var fetches = 0

    /// Numero progressivo della sincronizzazione (1 = prima).
    nonisolated static func nextFetchNumber() -> Int {
        fetchLock.lock(); defer { fetchLock.unlock() }
        fetches += 1
        return fetches
    }

    nonisolated static func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: hour)) ?? Date()
    }
}

/// Provider in memoria: accetta qualsiasi credenziale tranne la password
/// "sbagliata" (per provare l'errore di login).
struct ScriptedRegistroProvider: RegistroProvider {
    let id: RegistroProviderID
    let isAvailable = true
    let capabilities: RegistroCapabilities = [.fornisceDocente, .forniscePeriodo]
    let loginFields: [LoginField]

    func login(_ c: RegistroCredentials) async throws -> RegistroSession {
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard c.password != "sbagliata" else { throw RegistroError.invalidCredentials }
        return RegistroSession(accountKey: "FAKE0001", token: "fake", expiresAt: nil, extra: [:])
    }

    func refresh(_ s: RegistroSession) async throws -> RegistroSession { s }

    func fetchGrades(_ s: RegistroSession) async throws -> RemoteFetch {
        try? await Task.sleep(nanoseconds: 300_000_000)
        let fetchNumber = FakeRegistro.nextFetchNumber()
        let d = { (m: Int, day: Int) in FakeRegistro.date(2026, m, day) }
        let grades: [VotoRemoto] = [
            voto("MAT-1", d(5, 20), "MAT", "MATEMATICA", "7", 7, .oral),
            voto("MAT-2", d(5, 12), "MAT", "MATEMATICA", "8", 8, .written),
            // Con ora, docente, periodo e commento del registro (per il dettaglio "Dal registro").
            voto("ITA-1", Calendar.current.date(byAdding: .minute, value: 630, to: d(5, 14)) ?? d(5, 14), "ITA",
                 "LINGUA E LETTERATURA ITALIANA", "6.5", 6.5, .written,
                 hasTime: true, teacher: "VERDI MARIA", comment: "Tema ben strutturato"),
            voto("ING-1", d(5, 15), "ING", "LINGUA INGLESE", "buono", 8, .oral),
            voto("ING-2", d(5, 16), "ING", "LINGUA INGLESE", "N.C.", nil, .other, notCounting: true),
            voto("SCI-1", d(5, 18), "SCI", "SCIENZE NATURALI", "7.5", 7.5, .oral),
            voto("STO-1", d(5, 19), "STO", "STORIA", "7", 7, .oral),
            voto("GEO-1", d(5, 21), "GEO", "STORIA E GEOGRAFIA", "6", 6, .written),
            voto("TEC-1", d(5, 22), "TEC", "TECNOLOGIE INFORMATICHE", "8.5", 8.5, .practical),
        ]
        // Con `-FMTFakeRegistroRemoval` dalla seconda lettura "TEC-1" (il più recente) non c'è più
        // sul registro: il voto collegato diventa "rimosso dal registro".
        let removal = ProcessInfo.processInfo.arguments.contains("-FMTFakeRegistroRemoval")
        let visible = (removal && fetchNumber >= 2) ? grades.filter { $0.remoteId != "TEC-1" } : grades
        // Con un voto saltato il controllo "rimossi" non parte: nella lettura con rimozione
        // il download è completo.
        return RemoteFetch(grades: visible, skippedCount: visible.count < grades.count ? 0 : 1,
                           coveredRange: DateInterval(start: FakeRegistro.date(2025, 9, 1), end: d(8, 31)))
    }

    func logout(_ s: RegistroSession) async {}

    private func voto(_ remoteId: String, _ date: Date, _ subjectId: String, _ subject: String,
                      _ raw: String, _ value: Double?, _ kind: RemoteGradeKind,
                      notCounting: Bool = false, hasTime: Bool = false, teacher: String? = nil,
                      comment: String? = nil) -> VotoRemoto {
        VotoRemoto(provider: id, remoteId: remoteId, date: date, hasTime: hasTime, subjectId: subjectId,
                   subjectName: subject, teacher: teacher, rawValue: raw, numericValue: value, kind: kind,
                   kindRaw: kind.rawValue, weight: nil, period: "1", comment: comment, notCounting: notCounting,
                   cancelled: false, remoteModifiedAt: nil)
    }
}
#endif
