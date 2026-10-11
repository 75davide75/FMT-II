import Foundation

/// Elemento sincronizzato. Il nome del record CloudKit è "<tipo>-<id>", così
/// il tipo si ricava dal nome senza consultare gli store.
enum SyncItem: Equatable, Hashable {
    case grade(UUID)
    case note(UUID)
    case schedule

    static let scheduleRecordName = "schedule-current"

    var recordName: String {
        switch self {
        case .grade(let id): return "grade-\(id.uuidString)"
        case .note(let id):  return "note-\(id.uuidString)"
        case .schedule:      return Self.scheduleRecordName
        }
    }

    var recordType: String {
        switch self {
        case .grade:    return "Grade"
        case .note:     return "Note"
        case .schedule: return "Schedule"
        }
    }

    init?(recordName: String) {
        if recordName == Self.scheduleRecordName { self = .schedule; return }
        let parts = recordName.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "grade": self = .grade(id)
        case "note":  self = .note(id)
        default:      return nil
        }
    }
}

/// Regole di merge (pure, testate): last-writer-wins su `modifiedAt`; a parità
/// vince il remoto, così tutti i dispositivi convergono sullo stesso valore.
enum SyncMerge {
    static func remoteWins(local: Date?, remote: Date) -> Bool {
        guard let local else { return true }
        return remote >= local
    }

    /// Conflitto all'invio: vince il locale se la copia attuale nello store
    /// (o, se non c'è, quella inviata) è più recente di quella sul server.
    static func conflictWinsLocally(storeModified: Date?, failedRecordModified: Date?,
                                    serverModified: Date) -> Bool {
        !remoteWins(local: storeModified ?? failedRecordModified, remote: serverModified)
    }

    /// Modifiche remote da applicare: esclusi gli elementi con una
    /// cancellazione locale ancora da inviare (non devono ricomparire).
    static func skippingPendingDeletes(_ recordNames: [String], pendingDeletes: Set<String>) -> [String] {
        recordNames.filter { !pendingDeletes.contains($0) }
    }

    /// JSON da inviare: i nostri campi più quelli sconosciuti (di versioni
    /// future dell'app) presenti nell'ultima copia ricevuta da iCloud.
    static func mergePayload(ours: Data, previousRemote: Data?) -> Data {
        guard let previousRemote,
              let remote = try? JSONSerialization.jsonObject(with: previousRemote) as? [String: Any],
              let mine = try? JSONSerialization.jsonObject(with: ours) as? [String: Any] else { return ours }
        let merged = remote.merging(mine) { _, own in own }
        return (try? JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])) ?? ours
    }

    /// La copia remota ha campi che questa versione non conosce?
    static func hasUnknownKeys(remote: Data, known: Data) -> Bool {
        guard let r = try? JSONSerialization.jsonObject(with: remote) as? [String: Any],
              let k = try? JSONSerialization.jsonObject(with: known) as? [String: Any] else { return false }
        return !Set(r.keys).subtracting(k.keys).isEmpty
    }

    /// Applica modifiche remote a una lista locale: unione per id, mai
    /// sostituzione totale.
    static func apply<T: Identifiable>(upserts: [T], deletions: Set<T.ID>, to local: [T],
                                       modifiedAt: (T) -> Date) -> [T] {
        var result = local.filter { !deletions.contains($0.id) }
        for item in upserts {
            if let idx = result.firstIndex(where: { $0.id == item.id }) {
                if remoteWins(local: modifiedAt(result[idx]), remote: modifiedAt(item)) {
                    result[idx] = item
                }
            } else {
                result.insert(item, at: 0)
            }
        }
        return result
    }
}
