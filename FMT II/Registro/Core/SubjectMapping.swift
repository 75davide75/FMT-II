import Foundation

/// Materia come la espone il registro: id (se il provider ne ha uno) + nome.
struct RemoteSubjectRef: Codable, Hashable {
    var id: String?
    var name: String

    /// Chiave stabile del mapping: l'id se presente, altrimenti il nome normalizzato.
    var key: String {
        if let id, !id.isEmpty { return id }
        return SubjectMatcher.normalizedKey(name)
    }
}

/// Tabella "materia del registro -> materia dell'app".
struct SubjectMappingTable: Codable, Equatable {
    /// chiave remota -> materia dell'app
    var entries: [String: String]
    /// chiavi remote la cui associazione è stata confermata dall'utente (o accettata)
    var confirmed: Set<String>

    /// La materia dell'app, solo se l'associazione è confermata.
    func appSubject(for r: RemoteSubjectRef) -> String? {
        guard confirmed.contains(r.key) else { return nil }
        return entries[r.key]
    }
}

enum SubjectProposal: Equatable {
    case existing(String, viaAlias: Bool)
    case new(String)
}

enum SubjectMatcher {
    /// Minuscolo, senza accenti né punteggiatura, spazi compressi e rifilati.
    static func normalizedKey(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
        let cleaned = folded.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return " " // punteggiatura e spazi vari diventano separatori
        }
        return String(cleaned).lowercased()
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
    }

    /// Nome leggibile: prima lettera maiuscola, resto minuscolo, spazi compressi.
    static func readableName(_ s: String) -> String {
        let collapsed = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        guard let first = collapsed.first else { return "" }
        return first.uppercased() + collapsed.dropFirst()
    }

    /// Gruppi di nomi equivalenti (chiavi normalizzate).
    private static let aliasGroups: [Set<String>] = [
        ["italiano", "lingua e letteratura italiana", "lingua italiana"],
        ["matematica", "matematica e complementi di matematica"],
        ["inglese", "lingua inglese", "lingua e cultura inglese", "lingua e letteratura inglese"],
        ["scienze motorie", "scienze motorie e sportive", "educazione fisica", "ed fisica"],
        ["religione", "religione cattolica", "irc"],
        ["storia", "storia e geografia", "geostoria"],
        ["scienze", "scienze naturali", "scienze integrate"],
    ]

    /// Proposta: corrispondenza esatta normalizzata, poi alias, altrimenti materia nuova.
    /// Con più materie dell'app candidate si sceglie in modo deterministico la prima
    /// in ordine (chiave normalizzata, poi nome grezzo), indipendente dall'ordine di `appSubjects`.
    static func propose(_ r: RemoteSubjectRef, appSubjects: [String]) -> SubjectProposal {
        let target = normalizedKey(r.name)
        let candidates = appSubjects
            .map { (key: normalizedKey($0), name: $0) }
            .filter { !$0.key.isEmpty }
            .sorted { ($0.key, $0.name) < ($1.key, $1.name) }

        if let exact = candidates.first(where: { $0.key == target }) {
            return .existing(exact.name, viaAlias: false)
        }
        if let group = aliasGroups.first(where: { $0.contains(target) }),
           let alias = candidates.first(where: { group.contains($0.key) }) {
            return .existing(alias.name, viaAlias: true)
        }
        return .new(readableName(r.name))
    }
}
