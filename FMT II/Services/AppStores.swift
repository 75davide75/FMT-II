import Foundation

/// Gli store dell'app, unici per processo: tutte le finestre (multi-scena su
/// iPad) e la sincronizzazione iCloud lavorano sugli stessi dati. Prima erano
/// `@StateObject` di ogni `ContentView`, e la sync restava legata alla prima
/// finestra anche dopo la sua chiusura.
@MainActor
final class AppStores {
    static let shared = AppStores()

    let schedule = ScheduleStore()
    let notes = NotesStore()
    let grades = GradesStore(backups: AppStores.gradeBackups)

    /// Backup e istantanee dei voti (le stesse per lo store e per il registro).
    static let gradeBackups: GradeBackups = {
        #if DEBUG
        if FakeRegistro.isRequested { return FakeRegistro.backups }
        #endif
        return .standard
    }()

    /// Coordinatore del registro elettronico. Creato al primo uso: se nessun
    /// registro è collegato non fa nulla (nessuna rete, nessuna scrittura).
    private(set) lazy var registro: RegistroSyncCoordinator = {
        #if DEBUG
        // Test di interfaccia: provider finto, nessuna rete (-FMTFakeRegistro).
        if FakeRegistro.isRequested { return FakeRegistro.makeCoordinator(grades: grades) }
        #endif
        return RegistroSyncCoordinator(
            grades: grades, backups: Self.gradeBackups, settings: RegistroSettingsStore(), keychain: KeychainStore(),
            // ClasseViva e Argo hanno il loro provider; gli altri sono ancora stub.
            providers: [ClasseVivaProvider(transport: URLSessionTransport()), ArgoProvider(transport: URLSessionTransport()),
                        AxiosProvider(), NuvolaProvider(), MastercomProvider(), PronoteProvider()],
            defaults: .standard)
    }()

    private init() {}
}
