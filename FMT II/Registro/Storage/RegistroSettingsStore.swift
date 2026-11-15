import Foundation

/// Mapping materie e voti ignorati del registro, come JSON in UserDefaults.
/// Le due chiavi sono in `SettingsSync.syncedKeys` (iCloud key-value store).
/// Si scrive sempre un valore (mai `removeObject`): la sync non propaga le
/// rimozioni, quindi anche l'azzeramento è un valore vuoto codificato.
final class RegistroSettingsStore {
    static let mappingKey = "registroSubjectMap"
    static let ignoredKey = "registroIgnored"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Dati assenti o non decodificabili: tabella vuota, mai un crash.
    var mapping: SubjectMappingTable {
        get {
            guard let data = defaults.data(forKey: Self.mappingKey),
                  let table = try? JSONDecoder().decode(SubjectMappingTable.self, from: data)
            else { return SubjectMappingTable(entries: [:], confirmed: []) }
            return table
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.mappingKey)
        }
    }

    /// Chiavi dei voti importati eliminati dall'utente (coppia provider + remoteId).
    var ignored: Set<String> {
        get {
            guard let data = defaults.data(forKey: Self.ignoredKey),
                  let set = try? JSONDecoder().decode(Set<String>.self, from: data)
            else { return [] }
            return set
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.ignoredKey)
        }
    }

    func ignore(_ remoteKey: String) {
        var current = ignored
        guard current.insert(remoteKey).inserted else { return }
        ignored = current
    }

    /// Più chiavi con una sola scrittura.
    func ignore<S: Sequence>(contentsOf keys: S) where S.Element == String {
        var current = ignored
        let before = current.count
        current.formUnion(keys)
        guard current.count != before else { return }
        ignored = current
    }

    /// Azzera l'elenco scrivendo un insieme vuoto (non rimuove la chiave, altrimenti
    /// il valore vecchio tornerebbe da iCloud).
    func clearIgnored() {
        ignored = []
    }
}
