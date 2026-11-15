import Foundation

/// Esito della validazione di un piano prima di applicarlo (spec §6.3).
enum PlanValidation: Equatable {
    case ok
    /// Il piano tocca troppi voti manuali in una volta: serve la conferma dell'utente.
    case needsConfirmation(manualTouched: Int)
    /// Il piano viola una regola di protezione: non si applica nulla.
    /// Il motivo è un codice tecnico (non mostrato così com'è all'utente).
    case rejected(String)
}

/// Seconda fase della sync: controlla il piano calcolato dal motore contro i voti
/// locali attuali. Rete di sicurezza indipendente dal motore.
enum SyncPlanValidator {
    /// Oltre questo numero di voti manuali toccati si chiede conferma.
    static let manualConfirmationThreshold = 20
    /// Un collegamento può cambiare il valore di un voto manuale al massimo di
    /// questa tolleranza (la stessa del matcher: 7.005 → 7 è ammesso).
    static let linkValueTolerance = 0.01

    static func validate(_ p: SyncPlan, local: [Grade]) -> PlanValidation {
        let byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Ogni id compare al più una volta nel piano.
        var seen = Set<UUID>()
        for g in p.inserts + p.updates + p.links where !seen.insert(g.id).inserted {
            return .rejected("duplicateID")
        }

        for g in p.inserts {
            if byID[g.id] != nil { return .rejected("insertExists") }
            if g.origin == nil { return .rejected("insertWithoutOrigin") }
        }

        for g in p.updates {
            guard let old = byID[g.id] else { return .rejected("updateMissing") }
            // Un voto manuale si cambia solo collegandolo, mai con un aggiornamento.
            if old.origin == nil || g.origin == nil { return .rejected("updateOnManual") }
            if g.note != old.note { return .rejected("noteChanged") }
        }

        for g in p.links {
            guard let old = byID[g.id] else { return .rejected("linkMissing") }
            if old.origin != nil { return .rejected("linkOnLinked") }
            if g.origin?.manualSnapshot == nil { return .rejected("linkWithoutSnapshot") }
            if abs(g.value - old.value) > linkValueTolerance + 1e-9 { return .rejected("linkChangesValue") }
            if g.note != old.note { return .rejected("noteChanged") }
        }

        // Voti manuali toccati: quelli che vengono collegati e i manuali già collegati che cambiano.
        let touched = p.links.count + p.updates.filter { byID[$0.id]?.origin?.manualSnapshot != nil }.count
        return touched > manualConfirmationThreshold ? .needsConfirmation(manualTouched: touched) : .ok
    }
}
