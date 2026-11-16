import Foundation

enum RegistroProviderID: String, Codable, CaseIterable {
    case classeviva, argo, axios, nuvola, mastercom, pronote
}

/// Tipo del voto come lo classifica il registro (non è `GradeType`: nessun nuovo caso lì).
enum RemoteGradeKind: String, Codable {
    case written, oral, practical, other
}

enum RemoteStatus: String, Codable {
    case active, removedFromRegistro
    /// Tolto dal registro e "tenuto" dall'utente: la sync non lo segna di nuovo
    /// come rimosso; se ricompare nel registro torna `.active`.
    case keptAfterRemoval
}

enum GradeField: String, Codable {
    case subject, teacher, value, date, type, weight, countsForAverage
}

/// I valori che l'ultima sync ha scritto nei campi del `Grade`. Un campo diverso
/// da questi è stato modificato dall'utente e la sync non lo tocca più.
struct AppliedValues: Codable, Equatable {
    var subject: String
    var teacher: String
    var value: Double
    var date: Date
    var type: GradeType
    var weight: Double
    var countsForAverage: Bool

    init(_ g: Grade) {
        subject = g.subject
        teacher = g.teacher
        value = g.value
        date = g.date
        type = g.type
        weight = g.weight
        countsForAverage = g.countsForAverage
    }

    /// Campi del voto che oggi differiscono dai valori applicati dalla sync.
    func editedFields(in g: Grade) -> Set<GradeField> {
        var s = Set<GradeField>()
        if g.subject != subject { s.insert(.subject) }
        if g.teacher != teacher { s.insert(.teacher) }
        if g.value != value { s.insert(.value) }
        if g.date != date { s.insert(.date) }
        if g.type != type { s.insert(.type) }
        if g.weight != weight { s.insert(.weight) }
        if g.countsForAverage != countsForAverage { s.insert(.countsForAverage) }
        return s
    }
}

/// Copia del voto manuale prima del collegamento (tutti i campi di `Grade`
/// tranne `origin`; non può contenere `Grade` perché sarebbe ricorsivo).
struct ManualGradeSnapshot: Codable, Equatable {
    var subject: String
    var teacher: String
    var value: Double
    var date: Date
    var note: String
    var type: GradeType
    var weight: Double
    var countsForAverage: Bool
    var modifiedAt: Date

    init(_ g: Grade) {
        subject = g.subject
        teacher = g.teacher
        value = g.value
        date = g.date
        note = g.note
        type = g.type
        weight = g.weight
        countsForAverage = g.countsForAverage
        modifiedAt = g.modifiedAt
    }

    /// Ricostruisce il voto manuale originale (senza `origin`) con l'id dato.
    func restored(id: UUID) -> Grade {
        Grade(id: id, subject: subject, teacher: teacher, value: value, date: date, note: note,
              type: type, weight: weight, countsForAverage: countsForAverage, modifiedAt: modifiedAt)
    }
}

struct RegistroOrigin: Codable, Equatable {
    var provider: RegistroProviderID
    var accountKey: String
    var remoteId: String
    var rawValue: String
    var numericValue: Double?
    var hasTime: Bool
    var remoteSubjectId: String?
    var remoteSubjectName: String
    var remoteTeacher: String?
    var remoteTypeRaw: String?
    var remoteKind: RemoteGradeKind?
    var remoteWeight: Double?
    var remotePeriod: String?
    var remoteComment: String?
    var notCounting: Bool
    var cancelled: Bool
    var remoteModifiedAt: Date?
    var fingerprint: String
    var applied: AppliedValues
    var manualSnapshot: ManualGradeSnapshot?
    var status: RemoteStatus

    /// Chiave stabile del voto remoto: `provider|accountKey|remoteId`.
    var remoteKey: String { "\(provider.rawValue)|\(accountKey)|\(remoteId)" }
}
