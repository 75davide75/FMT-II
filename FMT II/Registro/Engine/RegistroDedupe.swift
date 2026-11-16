import Foundation

/// Rete di sicurezza (spec §2): se esistono più voti con la stessa `remoteKey`
/// (es. due dispositivi hanno importato/collegato lo stesso voto in contemporanea)
/// ne resta collegato uno solo. Funzione pura: chi la usa salva i voti in
/// un'istantanea prima di scrivere.
///
/// Un voto manuale collegato non viene mai scartato: se non è quello tenuto
/// torna un voto manuale normale (`RegistroUnlink.restoredManual`, stesso id,
/// valori originali più le modifiche dell'utente). Solo i voti importati (senza
/// `manualSnapshot`) possono essere scartati come doppioni.
enum RegistroDedupe {
    /// Preferenza: il voto manuale collegato (fra più manuali collegati, l'id più
    /// basso: la scelta non dipende da `modifiedAt` né dalle modifiche, così ogni
    /// dispositivo arriva allo stesso esito), poi quello con campi modificati
    /// dall'utente, poi il più recente (a parità, l'id). Il voto tenuto conserva il
    /// suo id; le note distinte non vuote dei voti importati scartati vengono unite
    /// alla sua con "\n" nell'ordine di preferenza (quelle dei manuali ripristinati
    /// restano sul loro voto). L'ordine dei voti resta quello di ingresso.
    /// `grades` contiene anche i manuali ripristinati; `dropped` solo voti importati.
    static func resolve(_ grades: [Grade]) -> (grades: [Grade], dropped: [Grade]) {
        var groups: [String: [Int]] = [:]
        for (i, g) in grades.enumerated() {
            if let key = g.origin?.remoteKey { groups[key, default: []].append(i) }
        }

        var dropIndexes = Set<Int>()
        var replaced: [Int: Grade] = [:]
        for indexes in groups.values where indexes.count > 1 {
            let ordered = indexes.sorted { preferred(grades[$0], over: grades[$1]) }
            let keeperIndex = ordered[0]
            var keeper = grades[keeperIndex]
            var notes: [String] = []
            for i in ordered {
                let restored = i == keeperIndex ? nil : RegistroUnlink.restoredManual(grades[i])
                if let restored {
                    replaced[i] = restored
                    continue
                }
                if i != keeperIndex { dropIndexes.insert(i) }
                let note = grades[i].note
                guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !notes.contains(note) else { continue }
                notes.append(note)
            }
            keeper.note = notes.joined(separator: "\n")
            replaced[keeperIndex] = keeper
        }

        guard !replaced.isEmpty else { return (grades, []) }
        var kept: [Grade] = []
        var dropped: [Grade] = []
        for (i, g) in grades.enumerated() {
            if dropIndexes.contains(i) { dropped.append(g) } else { kept.append(replaced[i] ?? g) }
        }
        return (kept, dropped)
    }

    private static func preferred(_ a: Grade, over b: Grade) -> Bool {
        let aLinked = a.origin?.manualSnapshot != nil, bLinked = b.origin?.manualSnapshot != nil
        if aLinked != bLinked { return aLinked }
        if aLinked { return a.id.uuidString < b.id.uuidString }
        let aEdited = isEdited(a), bEdited = isEdited(b)
        if aEdited != bEdited { return aEdited }
        if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt }
        return a.id.uuidString < b.id.uuidString
    }

    private static func isEdited(_ g: Grade) -> Bool {
        guard let o = g.origin else { return false }
        return !o.applied.editedFields(in: g).isEmpty
    }
}
