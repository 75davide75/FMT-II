import Foundation

/// Risposta dell'utente a un conflitto "È questo il voto che hai già inserito?".
enum ConflictDecision: Codable, Equatable {
    /// "Sì, è questo": collega il remoto al voto manuale con questo id.
    case linkTo(UUID)
    /// "No, è un voto diverso": importa il remoto come voto nuovo.
    case importAsNew
    /// "Decidi dopo": il remoto resta in attesa e non viene importato.
    case later
}

/// Voto remoto in attesa di una decisione dell'utente.
struct PendingConflict: Codable, Identifiable, Equatable {
    /// `remoteKey` del voto remoto (`provider|accountKey|remoteId`).
    var id: String
    var remote: VotoRemoto
    /// Voti manuali non collegati che potrebbero corrispondere (ordinati per punteggio).
    var candidateIDs: [UUID]
}

/// Tutto ciò che serve al motore: nessun I/O, nessuno stato globale.
struct RegistroSyncInput {
    var local: [Grade]
    var fetch: RemoteFetch
    var provider: RegistroProviderID
    var accountKey: String
    var mapping: SubjectMappingTable
    /// `remoteKey` dei voti che l'utente ha eliminato: non si reimportano mai.
    var ignored: Set<String>
    /// Decisioni sui conflitti, per `remoteKey`.
    var decisions: [String: ConflictDecision]
    var maxGrade: Double
    var calendar: Calendar
}

/// Esito puro di una sync: cosa scrivere (inserimenti, aggiornamenti, collegamenti)
/// e cosa chiedere all'utente (conflitti, materie da mappare).
/// Il motore non imposta mai `modifiedAt` sugli aggiornamenti: lo fa lo store (Task 9).
struct SyncPlan: Equatable {
    /// Voti nuovi importati dal registro (id deterministico).
    var inserts: [Grade] = []
    /// Voti già collegati/importati che cambiano, compresi quelli segnati come
    /// rimossi dal registro o tornati attivi.
    var updates: [Grade] = []
    /// Voti manuali collegati a un voto remoto (stesso id, `manualSnapshot` salvato).
    var links: [Grade] = []
    /// Remoti con candidati incerti o rimandati ("Decidi dopo"): nulla importato.
    var conflicts: [PendingConflict] = []
    /// Materie del registro non ancora confermate: i loro voti restano in attesa.
    var pendingSubjects: [RemoteSubjectRef] = []
    /// Id dei soli voti inseriti.
    var newGradeIDs: [UUID] = []
    /// Il controllo "rimossi dal registro" è stato saltato per protezione
    /// (download vuoto o con meno della metà dei voti collegati attesi).
    var removalCheckSkipped = false

    /// Vero se il piano non scrive nulla (conflitti e materie in attesa non sono scritture).
    var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && links.isEmpty }
}
