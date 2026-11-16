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
            if let manual = restoredManual(g) { out.append(manual); continue }
            let edited = o.applied.editedFields(in: g)
            var r = g
            r.origin = nil
            if keepImported || !edited.isEmpty
                        || !g.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(r)
            } else {
                removed.insert(g.id)
            }
        }
        return (out, removed)
    }

    /// Un voto manuale collegato tornato voto manuale normale: stesso id, nessun
    /// `origin`; i campi che l'utente non ha modificato tornano ai valori del
    /// `manualSnapshot`, quelli modificati e la nota restano. nil se il voto non è
    /// un manuale collegato. `modifiedAt` non viene toccato.
    static func restoredManual(_ g: Grade) -> Grade? {
        guard let o = g.origin, let snap = o.manualSnapshot else { return nil }
        let edited = o.applied.editedFields(in: g)
        var r = snap.restored(id: g.id)
        if edited.contains(.subject) { r.subject = g.subject }
        if edited.contains(.teacher) { r.teacher = g.teacher }
        if edited.contains(.value) { r.value = g.value }
        if edited.contains(.date) { r.date = g.date }
        if edited.contains(.type) { r.type = g.type }
        if edited.contains(.weight) { r.weight = g.weight }
        if edited.contains(.countsForAverage) { r.countsForAverage = g.countsForAverage }
        r.note = g.note
        r.modifiedAt = g.modifiedAt
        return r
    }
}
