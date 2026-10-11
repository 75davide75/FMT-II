import Foundation
import CloudKit
import os

/// Sincronizzazione iCloud (CloudKit, database privato) di voti, note e orario.
/// Gli store restano la fonte di verità locale: il manager accoda le modifiche
/// locali e applica quelle remote (vedi `SyncMerge`).
///
/// Record: `Grade`/`Note` con `payload` (JSON del modello) e `modifiedAt`;
/// `Schedule` (unico, "schedule-current") con `payloadAsset` (JSON),
/// `modifiedAt` e `deleted` (1 = orario rimosso).
@MainActor
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    static let containerIdentifier = "iCloud.com.davide.fmtII"
    static let zoneID = CKRecordZone.ID(zoneName: "FMTZone", ownerName: CKCurrentUserDefaultName)

    enum Status: Equatable {
        case off, checking, syncing, upToDate(Date?), noAccount, quotaExceeded, paused, failed(String)

        var label: String {
            switch self {
            case .off:            return L("Non attiva")
            case .checking:       return L("Verifica…")
            case .syncing:        return L("In corso…")
            case .upToDate(let d):
                guard let d else { return L("Attiva") }
                return L("Aggiornata alle \(d.appFormatted(date: .omitted, time: .shortened))")
            case .noAccount:      return L("Accedi a iCloud")
            case .quotaExceeded:  return L("Spazio iCloud esaurito")
            case .paused:         return L("In pausa")
            case .failed:         return L("Errore")
            }
        }

        var isProblem: Bool {
            switch self {
            case .noAccount, .quotaExceeded, .paused, .failed: return true
            default: return false
            }
        }
    }

    @Published private(set) var status: Status = .off

    private var engine: CKSyncEngine?
    // Riferimenti forti: gli store sono quelli unici dell'app (`AppStores`).
    private var grades: GradesStore?
    private var notes: NotesStore?
    private var scheduleStore: ScheduleStore?
    private let log = Logger(subsystem: "com.davide.fmtII", category: "sync")
    /// Campi di sistema (change tag) dell'ultimo record noto, per nome record:
    /// così un salvataggio aggiorna il record invece di generare un conflitto.
    private var systemFields: [String: Data] = [:]
    private let lastSyncKey = "fmt_lastCloudSync"
    /// Esito dell'ultimo controllo dell'account iCloud.
    private var accountAvailable = false
    private let pausedKey = "fmt_syncPausedAfterICloudDelete"

    /// In pausa dopo che l'utente ha eliminato i dati di FMT da iCloud: niente
    /// invii finché non tocca «Sincronizza ora».
    private var isPaused: Bool {
        get { UserDefaults.standard.bool(forKey: pausedKey) }
        set { UserDefaults.standard.set(newValue, forKey: pausedKey) }
    }

    // MARK: - Regole (pure, testate)

    /// Solo gli eventi del motore attuale contano (dopo un cambio di account il
    /// vecchio può ancora inviare eventi in ritardo).
    nonisolated static func isFromCurrentEngine(_ source: AnyObject, current: AnyObject?) -> Bool {
        guard let current else { return false }
        return source === current
    }

    /// Nuovo stato dopo una sincronizzazione riuscita (nil = nessun cambio e
    /// nessun timestamp): niente senza account o in pausa; «spazio esaurito»
    /// sparisce solo quando dei record tornano a salvarsi senza errori di quota.
    nonisolated static func statusAfterSync(current: Status, accountAvailable: Bool,
                                            savedRecords: Int, quotaFailures: Int, now: Date) -> Status? {
        guard accountAvailable else { return nil }
        switch current {
        case .paused:
            return nil
        case .quotaExceeded:
            return savedRecords > 0 && quotaFailures == 0 ? .upToDate(now) : nil
        default:
            return quotaFailures > 0 ? .quotaExceeded : .upToDate(now)
        }
    }

    /// Un cambio di account non carica mai da solo i dati locali: potrebbero
    /// appartenere a un'altra persona (voti e diario sono dati sensibili).
    /// Tutto il locale sale solo al primo avvio della sync su questo dispositivo.
    nonisolated static func uploadsAllLocalData(after change: CKSyncEngine.Event.AccountChange.ChangeType) -> Bool {
        switch change {
        case .signIn, .signOut, .switchAccounts: return false
        @unknown default: return false
        }
    }

    /// Zona eliminata: si ricarica solo dopo un reset della crittografia di
    /// iCloud; se l'ha eliminata l'utente (Impostazioni iOS) la sync va in pausa.
    nonisolated static func reuploadsAfterZoneDeletion(reason: CKDatabase.DatabaseChange.Deletion.Reason) -> Bool {
        switch reason {
        case .encryptedDataReset: return true
        case .deleted, .purged:   return false
        @unknown default:         return false
        }
    }

    var lastSync: Date? { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }

    private init() {}

    /// Niente sync durante i test e il seed demo per gli screenshot.
    private static var isDisabledForProcess: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        return ProcessInfo.processInfo.arguments.contains("-FMTSeedDemo") || env["FMT_SEED_DEMO"] == "1"
    }

    // MARK: - API

    func start(grades: GradesStore, notes: NotesStore, schedule: ScheduleStore) {
        guard engine == nil, !Self.isDisabledForProcess else { return }
        self.grades = grades
        self.notes = notes
        self.scheduleStore = schedule
        systemFields = loadSystemFields()
        // Copie temporanee degli asset di invii precedenti.
        try? FileManager.default.removeItem(at: assetsDirectory)
        status = .checking
        NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccountStatus() }
        }
        startEngine(state: loadState())
        Task { await refreshAccountStatus() }
    }

    func enqueueSave(_ items: [SyncItem]) {
        guard let engine, !items.isEmpty, !isPaused else { return }
        engine.state.add(pendingRecordZoneChanges: items.map { .saveRecord(recordID(for: $0)) })
    }

    func enqueueDelete(_ items: [SyncItem]) {
        guard let engine, !items.isEmpty, !isPaused else { return }
        engine.state.add(pendingRecordZoneChanges: items.map { .deleteRecord(recordID(for: $0)) })
    }

    /// «Sincronizza ora»: invia e scarica subito.
    func syncNow() async {
        guard let engine else { return }
        if isPaused {
            // Ripresa voluta dall'utente: ricrea la zona e ricarica questo dispositivo.
            isPaused = false
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            enqueueAllLocal()
        }
        status = .syncing
        do {
            try await engine.sendChanges()
            try await engine.fetchChanges()
            markSynced()
        } catch {
            handle(error)
        }
    }

    // MARK: - Engine

    private func startEngine(state: CKSyncEngine.State.Serialization?, uploadLocal: Bool = true) {
        let container = CKContainer(identifier: Self.containerIdentifier)
        var config = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                stateSerialization: state, delegate: self)
        config.automaticallySync = true
        let engine = CKSyncEngine(config)
        self.engine = engine
        if state == nil, !isPaused {
            // Primo avvio della sync: crea la zona e carica tutto il locale.
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            if uploadLocal { enqueueAllLocal() }
        }
    }

    private func refreshAccountStatus() async {
        let account = try? await CKContainer(identifier: Self.containerIdentifier).accountStatus()
        accountAvailable = account == .available
        if account != .available {
            status = .noAccount
        } else if isPaused {
            status = .paused
        } else if status == .noAccount || status == .checking {
            status = .upToDate(lastSync)
        }
    }

    private func enqueueAllLocal() {
        var items: [SyncItem] = []
        items += (grades?.grades ?? []).map { .grade($0.id) }
        items += (notes?.notes ?? []).map { .note($0.id) }
        if scheduleStore?.schedule != nil || scheduleStore?.clearedAt != nil { items.append(.schedule) }
        enqueueSave(items)
    }

    private func recordID(for item: SyncItem) -> CKRecord.ID {
        CKRecord.ID(recordName: item.recordName, zoneID: Self.zoneID)
    }

    private func markSynced(savedRecords: Int = 0, quotaFailures: Int = 0) {
        let now = Date()
        if let next = Self.statusAfterSync(current: status, accountAvailable: accountAvailable,
                                           savedRecords: savedRecords, quotaFailures: quotaFailures, now: now) {
            status = next
            if case .upToDate = next { UserDefaults.standard.set(now, forKey: lastSyncKey) }
        } else if status == .syncing {
            // Nessuna sync reale (es. senza account): non restare su «In corso…».
            status = accountAvailable ? .upToDate(lastSync) : .noAccount
        }
    }

    /// Data di modifica attuale nello store per un elemento (per i conflitti).
    private func storeModifiedAt(_ item: SyncItem) -> Date? {
        switch item {
        case .grade(let id): return grades?.grades.first { $0.id == id }?.modifiedAt
        case .note(let id):  return notes?.notes.first { $0.id == id }?.modifiedAt
        case .schedule:      return scheduleStore?.schedule?.modifiedAt ?? scheduleStore?.clearedAt
        }
    }

    /// Nomi dei record con una cancellazione locale ancora da inviare.
    private var pendingDeleteNames: Set<String> {
        Set((engine?.state.pendingRecordZoneChanges ?? []).compactMap {
            if case .deleteRecord(let id) = $0 { return id.recordName }
            return nil
        })
    }

    // MARK: - Campi di versioni future

    /// Copie remote che contengono campi sconosciuti a questa versione: li
    /// rimandiamo invariati, così una versione più nuova non li perde.
    private var payloadsDirectory: URL {
        let url = supportDirectory.appendingPathComponent("payloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cachedRemotePayload(_ recordName: String) -> Data? {
        try? Data(contentsOf: payloadsDirectory.appendingPathComponent(recordName + ".json"))
    }

    private func rememberRemotePayload(_ remote: Data, known: Data?, for recordName: String) {
        let url = payloadsDirectory.appendingPathComponent(recordName + ".json")
        if let known, SyncMerge.hasUnknownKeys(remote: remote, known: known) {
            try? remote.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func outgoingPayload<T: Encodable>(_ model: T, recordName: String) -> Data? {
        guard let ours = try? JSONEncoder().encode(model) else { return nil }
        return SyncMerge.mergePayload(ours: ours, previousRemote: cachedRemotePayload(recordName))
    }

    private func handle(_ error: Error) {
        switch (error as? CKError)?.code {
        case .notAuthenticated?: status = .noAccount
        case .quotaExceeded?:    status = .quotaExceeded
        default:                 status = .failed(error.localizedDescription)
        }
        log.error("sync: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Record ⇄ modelli

    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let item = SyncItem(recordName: recordID.recordName) else { return nil }
        let record = existingRecord(recordID, type: item.recordType)
        switch item {
        case .grade(let id):
            guard let g = grades?.grades.first(where: { $0.id == id }),
                  let data = outgoingPayload(g, recordName: recordID.recordName) else { return nil }
            record["payload"] = data as NSData
            record["modifiedAt"] = g.modifiedAt as NSDate
        case .note(let id):
            guard let n = notes?.notes.first(where: { $0.id == id }),
                  let data = outgoingPayload(n, recordName: recordID.recordName) else { return nil }
            record["payload"] = data as NSData
            record["modifiedAt"] = n.modifiedAt as NSDate
        case .schedule:
            if let s = scheduleStore?.schedule, let data = outgoingPayload(s, recordName: recordID.recordName) {
                let url = assetsDirectory.appendingPathComponent("schedule-\(UUID().uuidString).json")
                guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
                record["payloadAsset"] = CKAsset(fileURL: url)
                record["modifiedAt"] = s.modifiedAt as NSDate
                record["deleted"] = 0 as NSNumber
            } else if let cleared = scheduleStore?.clearedAt {
                record["payloadAsset"] = nil
                record["modifiedAt"] = cleared as NSDate
                record["deleted"] = 1 as NSNumber
            } else {
                return nil
            }
        }
        return record
    }

    private func existingRecord(_ id: CKRecord.ID, type: String) -> CKRecord {
        if let data = systemFields[id.recordName],
           let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            coder.requiresSecureCoding = true
            let record = CKRecord(coder: coder)
            coder.finishDecoding()
            if let record { return record }
        }
        return CKRecord(recordType: type, recordID: id)
    }

    private func remember(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        systemFields[record.recordID.recordName] = coder.encodedData
    }

    /// Applica agli store i record scaricati (o vincenti in un conflitto).
    private func apply(modified records: [CKRecord], deleted ids: [CKRecord.ID]) {
        let dec = JSONDecoder()
        var gradeUps: [Grade] = [], noteUps: [Note] = []
        var gradeDels = Set<UUID>(), noteDels = Set<UUID>()
        let enc = JSONEncoder()
        let applicable = Set(SyncMerge.skippingPendingDeletes(records.map(\.recordID.recordName),
                                                              pendingDeletes: pendingDeleteNames))
        for record in records {
            remember(record)
            let name = record.recordID.recordName
            // Cancellato qui ma non ancora inviato: non deve ricomparire.
            guard applicable.contains(name) else { continue }
            switch SyncItem(recordName: name) {
            case .grade?:
                if let d = record["payload"] as? Data, let g = try? dec.decode(Grade.self, from: d) {
                    gradeUps.append(g)
                    rememberRemotePayload(d, known: try? enc.encode(g), for: name)
                }
            case .note?:
                if let d = record["payload"] as? Data, let n = try? dec.decode(Note.self, from: d) {
                    noteUps.append(n)
                    rememberRemotePayload(d, known: try? enc.encode(n), for: name)
                }
            case .schedule?:
                let deleted = (record["deleted"] as? Int ?? 0) == 1
                let modified = record["modifiedAt"] as? Date ?? .distantPast
                let data = (record["payloadAsset"] as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) }
                let s = data.flatMap { try? dec.decode(ScheduleData.self, from: $0) }
                if let data, let s { rememberRemotePayload(data, known: try? enc.encode(s), for: name) }
                scheduleStore?.applyRemote(schedule: s, remoteModifiedAt: modified, deleted: deleted)
            case nil:
                break
            }
        }
        for id in ids {
            systemFields[id.recordName] = nil
            try? FileManager.default.removeItem(at: payloadsDirectory.appendingPathComponent(id.recordName + ".json"))
            switch SyncItem(recordName: id.recordName) {
            case .grade(let uuid)?: gradeDels.insert(uuid)
            case .note(let uuid)?:  noteDels.insert(uuid)
            default: break
            }
        }
        saveSystemFields()
        if !gradeUps.isEmpty || !gradeDels.isEmpty { grades?.applyRemote(upserts: gradeUps, deletions: gradeDels) }
        if !noteUps.isEmpty || !noteDels.isEmpty { notes?.applyRemote(upserts: noteUps, deletions: noteDels) }
    }

    private func handleSent(_ e: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
        for saved in e.savedRecords { remember(saved) }
        for id in e.deletedRecordIDs { systemFields[id.recordName] = nil }
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var serverWinners: [CKRecord] = []
        var quotaFailures = 0
        for failure in e.failedRecordSaves {
            let record = failure.record
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { continue }
                remember(server)
                // Conta la copia attuale nello store: l'utente può averla
                // modificata di nuovo mentre questa era in viaggio.
                let current = SyncItem(recordName: record.recordID.recordName).flatMap(storeModifiedAt)
                let remote = server["modifiedAt"] as? Date ?? .distantPast
                if SyncMerge.conflictWinsLocally(storeModified: current,
                                                 failedRecordModified: record["modifiedAt"] as? Date,
                                                 serverModified: remote) {
                    retry.append(.saveRecord(record.recordID))
                } else {
                    serverWinners.append(server)
                }
            case .zoneNotFound:
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                systemFields[record.recordID.recordName] = nil
                retry.append(.saveRecord(record.recordID))
            case .unknownItem:
                systemFields[record.recordID.recordName] = nil
                retry.append(.saveRecord(record.recordID))
            case .quotaExceeded:
                quotaFailures += 1
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled, .requestRateLimited:
                break   // CKSyncEngine riprova da solo
            default:
                log.error("save \(record.recordID.recordName, privacy: .public): \(failure.error.localizedDescription, privacy: .public)")
            }
        }
        for (id, error) in e.failedRecordDeletes {
            switch error.code {
            case .unknownItem, .zoneNotFound:
                systemFields[id.recordName] = nil   // già sparito dal server: va bene così
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled, .requestRateLimited:
                break   // CKSyncEngine riprova da solo
            default:
                log.error("delete \(id.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        saveSystemFields()
        if !serverWinners.isEmpty { apply(modified: serverWinners, deleted: []) }
        if !retry.isEmpty { engine.state.add(pendingRecordZoneChanges: retry) }
        if quotaFailures > 0 || status == .quotaExceeded {
            markSynced(savedRecords: e.savedRecords.count, quotaFailures: quotaFailures)
        }
    }

    private func handleAccountChange(_ e: CKSyncEngine.Event.AccountChange) {
        switch e.changeType {
        case .signIn:
            if Self.uploadsAllLocalData(after: e.changeType) { enqueueAllLocal() }
            Task { await refreshAccountStatus() }
        case .signOut, .switchAccounts:
            // I dati locali restano sul dispositivo ma non salgono da soli nel
            // nuovo account; si riparte da zero (si scaricano i suoi dati).
            systemFields = [:]
            saveSystemFields()
            try? FileManager.default.removeItem(at: stateURL)
            engine = nil
            startEngine(state: nil, uploadLocal: Self.uploadsAllLocalData(after: e.changeType))
            Task { await refreshAccountStatus() }
        @unknown default:
            break
        }
    }

    // MARK: - Persistenza dello stato

    private var supportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private var stateURL: URL { supportDirectory.appendingPathComponent("engine_state.json") }
    private var systemFieldsURL: URL { supportDirectory.appendingPathComponent("system_fields.plist") }
    private var assetsDirectory: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudSyncAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        try? JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }

    private func loadSystemFields() -> [String: Data] {
        guard let data = try? Data(contentsOf: systemFieldsURL) else { return [:] }
        return (try? PropertyListDecoder().decode([String: Data].self, from: data)) ?? [:]
    }

    private func saveSystemFields() {
        try? PropertyListEncoder().encode(systemFields).write(to: systemFieldsURL, options: .atomic)
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSyncManager: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // Dopo un cambio di account il vecchio motore può mandare eventi in ritardo.
        guard Self.isFromCurrentEngine(syncEngine, current: engine) else { return }
        switch event {
        case .stateUpdate(let e):
            saveState(e.stateSerialization)
        case .accountChange(let e):
            handleAccountChange(e)
        case .fetchedDatabaseChanges(let e):
            guard let deletion = e.deletions.first(where: { $0.zoneID == Self.zoneID }) else { break }
            systemFields = [:]
            saveSystemFields()
            if Self.reuploadsAfterZoneDeletion(reason: deletion.reason) {
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                enqueueAllLocal()
            } else {
                // L'utente ha eliminato i dati di FMT da iCloud: non li ricarichiamo.
                isPaused = true
                syncEngine.state.remove(pendingRecordZoneChanges: syncEngine.state.pendingRecordZoneChanges)
                syncEngine.state.remove(pendingDatabaseChanges: syncEngine.state.pendingDatabaseChanges)
                status = .paused
            }
        case .fetchedRecordZoneChanges(let e):
            apply(modified: e.modifications.map(\.record), deleted: e.deletions.map(\.recordID))
        case .sentRecordZoneChanges(let e):
            handleSent(e, engine: syncEngine)
        case .willFetchChanges, .willSendChanges:
            if !status.isProblem { status = .syncing }
        case .didFetchChanges, .didSendChanges:
            markSynced()
        case .sentDatabaseChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard Self.isFromCurrentEngine(syncEngine, current: engine) else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await self.recordForSending(recordID, engine: syncEngine)
        }
    }

    private func recordForSending(_ id: CKRecord.ID, engine: CKSyncEngine) -> CKRecord? {
        // Store non ancora collegati: il salvataggio resta in coda.
        guard grades != nil, notes != nil, scheduleStore != nil else { return nil }
        if let record = record(for: id) { return record }
        // L'elemento non esiste più in locale: togliamo il salvataggio in coda.
        engine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
        return nil
    }
}
