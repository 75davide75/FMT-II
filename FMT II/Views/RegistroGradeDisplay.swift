import Foundation

/// Come la tab Voti mostra i voti che arrivano dal registro: funzioni pure
/// (testabili) usate da righe, grafico e foglio di modifica.
enum RegistroGradeDisplay {
    /// Il voto è stato tolto dal registro (resta nell'app finché l'utente non decide).
    static func isRemoved(_ g: Grade) -> Bool { g.origin?.status == .removedFromRegistro }

    /// Etichetta "Rimosso dal registro", solo per i voti segnati come rimossi.
    static func removedLabel(for g: Grade) -> String? {
        isRemoved(g) ? L("Rimosso dal registro") : nil
    }

    /// Punti del grafico: niente giustifiche né giudizi non numerici del registro
    /// ("N.C.", "buono"...: `numericValue == nil`), che non hanno un valore sul grafico.
    static func chartPoints(_ grades: [Grade]) -> [Grade] {
        grades.filter { g in
            guard !g.isGiustifica else { return false }
            if let o = g.origin, o.numericValue == nil { return false }
            return true
        }
    }

    /// "Tieni": toglie lo stato "rimosso" e nient'altro. Se il voto manca ancora
    /// dal registro, la sync successiva potrà segnarlo di nuovo come rimosso.
    static func keeping(_ g: Grade) -> Grade {
        var kept = g
        kept.origin?.status = .active
        return kept
    }

    /// Ora del voto, solo se il registro l'ha fornita (mai inventata).
    static func timeText(for g: Grade) -> String? {
        guard g.origin?.hasTime == true else { return nil }
        return g.date.formatted(date: .omitted, time: .shortened)
    }

    /// Voce del registro nel dettaglio: valori originali, tutti opzionali tranne il voto.
    struct Detail: Equatable {
        var rawValue: String
        var time: String?
        var period: String?
        var comment: String?
        var teacher: String?
        var typeLabel: String?
    }

    /// Dati della sezione "Dal registro" (nil per i voti manuali).
    static func detail(for g: Grade) -> Detail? {
        guard let o = g.origin else { return nil }
        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }
        return Detail(rawValue: o.rawValue, time: timeText(for: g), period: clean(o.remotePeriod),
                      comment: clean(o.remoteComment), teacher: clean(o.remoteTeacher),
                      typeLabel: o.remoteKind.map(kindLabel))
    }

    static func kindLabel(_ k: RemoteGradeKind) -> String {
        switch k {
        case .written: return GradeType.written.label
        case .oral: return GradeType.oral.label
        case .practical: return GradeType.practical.label
        case .other: return L("Altro")
        }
    }

    /// Etichetta VoiceOver: il valore completo (il badge lo abbrevia a vista) più
    /// origine e stato.
    static func accessibilityLabel(for g: Grade) -> String {
        var parts = [g.displayValue]
        if g.origin != nil { parts.append(L("Dal registro")) }
        if let removed = removedLabel(for: g) { parts.append(removed) }
        return parts.joined(separator: ", ")
    }
}
