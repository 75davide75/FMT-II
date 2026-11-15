import Foundation

/// Un voto manuale che potrebbe corrispondere a un voto del registro.
struct MatchCandidate: Equatable {
    var gradeID: UUID
    var score: Double
}

/// Soglie di corrispondenza (spec §5), in un solo punto per la taratura con dati reali.
enum MatchThresholds {
    /// Punteggio minimo del migliore candidato per il collegamento automatico.
    static let autoLink = 0.9
    /// Il secondo migliore deve restare sotto questa soglia.
    static let runnerUpMax = 0.5
    /// Distanza massima in giorni oltre la quale un voto non è candidato.
    static let maxDayDistance = 3
}

/// Calcolo puro (nessun I/O) del punteggio di corrispondenza fra un voto remoto
/// e i voti inseriti a mano.
enum GradeMatcher {
    private static let valueTolerance = 0.01

    /// Candidati per `r` fra i voti manuali non collegati (`origin == nil`),
    /// ordinati per punteggio decrescente.
    /// Parità di punteggio: prima la data più vicina, poi `id.uuidString` (ordine deterministico).
    /// Materia: `appSubject` è già la materia dell'app; si confronta con quella del voto
    /// tramite `SubjectMatcher.normalizedKey` (senza maiuscole, accenti, punteggiatura),
    /// così "matematica" scritto a mano coincide con "Matematica".
    static func candidates(for r: VotoRemoto, appSubject: String, among manual: [Grade], calendar: Calendar) -> [MatchCandidate] {
        let subjectKey = SubjectMatcher.normalizedKey(appSubject)
        var scored: [(candidate: MatchCandidate, distance: Int)] = []

        for g in manual where g.origin == nil {
            // filtri obbligatori: materia e valore
            guard SubjectMatcher.normalizedKey(g.subject) == subjectKey else { continue }
            guard valueMatches(r, g) else { continue }

            let distance = dayDistance(r.date, g.date, calendar: calendar)
            guard distance <= MatchThresholds.maxDayDistance else { continue }

            var score: Double
            switch distance {
            case 0: score = 1.0
            case 1: score = 0.7
            default: score = 0.4
            }

            if let remoteType = gradeType(of: r.kind) {
                score += remoteType == g.type ? 0.2 : -0.3
            }

            if let rt = r.teacher?.trimmingCharacters(in: .whitespacesAndNewlines), !rt.isEmpty {
                let gt = g.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
                if !gt.isEmpty, rt.caseInsensitiveCompare(gt) == .orderedSame { score += 0.1 }
            }

            scored.append((MatchCandidate(gradeID: g.id, score: score), distance))
        }

        return scored.sorted {
            if abs($0.candidate.score - $1.candidate.score) > 1e-9 { return $0.candidate.score > $1.candidate.score }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.candidate.gradeID.uuidString < $1.candidate.gradeID.uuidString
        }.map(\.candidate)
    }

    /// Collegamento automatico solo se il migliore ha punteggio >= `autoLink`
    /// e il secondo (se c'è) è < `runnerUpMax`. `c` deve essere ordinato come da `candidates`.
    static func isCertain(_ c: [MatchCandidate]) -> Bool {
        guard let best = c.first, best.score >= MatchThresholds.autoLink - 1e-9 else { return false }
        if c.count > 1, c[1].score >= MatchThresholds.runnerUpMax - 1e-9 { return false }
        return true
    }

    // MARK: - Helper

    /// Tipo noto del remoto; `nil` e `.other` sono "ignoto".
    private static func gradeType(of kind: RemoteGradeKind?) -> GradeType? {
        switch kind {
        case .written: return .written
        case .oral: return .oral
        case .practical: return .practical
        case .other, nil: return nil
        }
    }

    private static func valueMatches(_ r: VotoRemoto, _ g: Grade) -> Bool {
        if let n = r.numericValue {
            // un voto numerico non coincide mai con una giustifica
            return !g.isGiustifica && abs(g.value - n) <= valueTolerance + 1e-9
        }
        let raw = r.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = g.displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return !raw.isEmpty && raw.caseInsensitiveCompare(shown) == .orderedSame
    }

    private static func dayDistance(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
        let d = calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? Int.max
        return abs(d)
    }
}
