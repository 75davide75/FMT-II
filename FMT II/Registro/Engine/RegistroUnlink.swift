import Foundation

/// Scollegamento del registro (spec §6.5). Funzione pura: l'istantanea `.preUnlink`
/// e la scrittura sono compito di chi la chiama.
enum RegistroUnlink {
    /// - Voti manuali collegati: perdono `origin`; i campi che l'utente non ha
    ///   modificato tornano ai valori del `manualSnapshot`, quelli modificati restano.
    ///   Mai eliminati.
    /// - Voti importati modificati dall'utente (campi o nota): tenuti senza `origin`.
    /// - Voti importati non modificati: tenuti senza `origin` se `keepImported`,
    ///   altrimenti eliminati (`removedIDs`).
    /// - Voti manuali: invariati.
    /// `modifiedAt` non viene toccato qui (lo aggiorna lo store per i voti cambiati).
    static func apply(_ grades: [Grade], keepImported: Bool) -> (grades: [Grade], removedIDs: Set<UUID>) {
        var out: [Grade] = []
        var removed = Set<UUID>()
        for g in grades {
            guard let o = g.origin else { out.append(g); continue }
            let edited = o.applied.editedFields(in: g)
            var r = g
            r.origin = nil
            if let snap = o.manualSnapshot {
                if !edited.contains(.subject) { r.subject = snap.subject }
                if !edited.contains(.teacher) { r.teacher = snap.teacher }
                if !edited.contains(.value) { r.value = snap.value }
                if !edited.contains(.date) { r.date = snap.date }
                if !edited.contains(.type) { r.type = snap.type }
                if !edited.contains(.weight) { r.weight = snap.weight }
                if !edited.contains(.countsForAverage) { r.countsForAverage = snap.countsForAverage }
                out.append(r)
            } else if keepImported || !edited.isEmpty
                        || !g.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(r)
            } else {
                removed.insert(g.id)
            }
        }
        return (out, removed)
    }
}
