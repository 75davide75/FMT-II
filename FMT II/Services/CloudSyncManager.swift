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
            case .off:            return "Non attiva"
            case .checking:       return "Verifica…"
            case .syncing:        return "In corso…"
            case .upToDate(let d):
                guard let d else { return "Attiva" }
                return "Aggiornata alle " + d.formatted(date: .omitted, time: .shortened)
            case .noAccount:      return "Accedi a iCloud"
            case .quotaExceeded:  return "Spazio iCloud esaurito"
            case .paused:         return "In pausa"
            case .failed:         return "Errore"
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
    private let pausedKey = "fmt_syncPausedAfterICloudDelete"

    /// In pausa dopo che l'utente ha eliminato i dati di FMT da iCloud: niente
    /// invii finché non tocca «Sincronizza ora».
    private var isPaused: Bool {
        get { UserDefaults.standard.bool(forKey: pausedKey) }
        set { UserDefaults.standard.set(newValue, forKey: pausedKey) }
    }

    // MARK: - Regole (pure, testate)

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

    private func markSynced() {
        let now = Date()
        UserDefaults.standard.set(now, forKey: lastSyncKey)
        switch status {
        case .noAccount, .quotaExceeded, .paused: break
        default: status = .upToDate(now)
        }
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
        let enc = JSONEncoder()
        let record = existingRecord(recordID, type: item.recordType)
        switch item {
        case .grade(let id):
            guard let g = grades?.grades.first(where: { $0.id == id }),
                  let data = try? enc.encode(g) else { return nil }
            record["payload"] = data as NSData
            record["modifiedAt"] = g.modifiedAt as NSDate
        case .note(let id):
            guard let n = notes?.notes.first(where: { $0.id == id }),
                  let data = try? enc.encode(n) else { return nil }
            record["payload"] = data as NSData
            record["modifiedAt"] = n.modifiedAt as NSDate
        case .schedule:
            if let s = scheduleStore?.schedule, let data = try? enc.encode(s) {
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
        for record in records {
            remember(record)
            switch SyncItem(recordName: record.recordID.recordName) {
            case .grade?:
                if let d = record["payload"] as? Data, let g = try? dec.decode(Grade.self, from: d) { gradeUps.append(g) }
            case .note?:
                if let d = record["payload"] as? Data, let n = try? dec.decode(Note.self, from: d) { noteUps.append(n) }
            case .schedule?:
                let deleted = (record["deleted"] as? Int ?? 0) == 1
                let modified = record["modifiedAt"] as? Date ?? .distantPast
                let data = (record["payloadAsset"] as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) }
                let s = data.flatMap { try? dec.decode(ScheduleData.self, from: $0) }
                scheduleStore?.applyRemote(schedule: s, remoteModifiedAt: modified, deleted: deleted)
            case nil:
                break
            }
        }
        for id in ids {
            systemFields[id.recordName] = nil
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
        for failure in e.failedRecordSaves {
            let record = failure.record
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { continue }
                remember(server)
                let local = record["modifiedAt"] as? Date
                let remote = server["modifiedAt"] as? Date ?? .distantPast
                if SyncMerge.remoteWins(local: local, remote: remote) { serverWinners.append(server) }
                else { retry.append(.saveRecord(record.recordID)) }
            case .zoneNotFound:
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                systemFields[record.recordID.recordName] = nil
                retry.append(.saveRecord(record.recordID))
            case .unknownItem:
                systemFields[record.recordID.recordName] = nil
                retry.append(.saveRecord(record.recordID))
            case .quotaExceeded:
                status = .quotaExceeded
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled, .requestRateLimited:
                break   // CKSyncEngine riprova da solo
            default:
                log.error("save \(record.recordID.recordName, privacy: .public): \(failure.error.localizedDescription, privacy: .public)")
            }
        }
        saveSystemFields()
        if !serverWinners.isEmpty { apply(modified: serverWinners, deleted: []) }
        if !retry.isEmpty { engine.state.add(pendingRecordZoneChanges: retry) }
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
