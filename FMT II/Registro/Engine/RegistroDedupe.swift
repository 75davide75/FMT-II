import Foundation

/// Rete di sicurezza (spec §2): se esistono più voti con la stessa `remoteKey`
/// (es. due dispositivi hanno importato/collegato lo stesso voto in contemporanea)
/// se ne tiene uno solo. Funzione pura: chi la usa salva i voti scartati in
/// un'istantanea prima di rimuoverli.
enum RegistroDedupe {
    /// Preferenza: il voto manuale collegato, poi quello con campi modificati
    /// dall'utente, poi il più recente (a parità, l'id: deterministico su ogni
    /// dispositivo). Il voto tenuto conserva il suo id; le note distinte non vuote
    /// vengono unite con "\n" nell'ordine di preferenza. L'ordine dei voti resta
    /// quello di ingresso.
    static func resolve(_ grades: [Grade]) -> (grades: [Grade], dropped: [Grade]) {
        var groups: [String: [Int]] = [:]
        for (i, g) in grades.enumerated() {
            if let key = g.origin?.remoteKey { groups[key, default: []].append(i) }
        }

        var dropIndexes = Set<Int>()
        var replaced: [Int: Grade] = [:]
        for indexes in groups.values where indexes.count > 1 {
            let ordered = indexes.sorted { preferred(grades[$0], over: grades[$1]) }
            var keeper = grades[ordered[0]]
            var notes: [String] = []
            for i in ordered {
                let note = grades[i].note
                guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !notes.contains(note) else { continue }
                notes.append(note)
            }
            keeper.note = notes.joined(separator: "\n")
            replaced[ordered[0]] = keeper
            dropIndexes.formUnion(ordered.dropFirst())
        }

        guard !dropIndexes.isEmpty else { return (grades, []) }
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
