import XCTest
@testable import FMT_II

/// Motore di sync puro: nessun voto dell'utente perso o cambiato in silenzio,
/// nessuna cancellazione automatica, idempotenza.
final class RegistroSyncEngineTests: XCTestCase {

    // MARK: - Fixture

    private let account = "S1234567"

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    private func d(_ month: Int, _ day: Int, _ year: Int = 2026, hour: Int = 0) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Anno scolastico 2025/26 restituito dal registro.
    private var schoolYear: DateInterval { DateInterval(start: d(9, 1, 2025), end: d(9, 1, 2026)) }

    private let defaultMapping = SubjectMappingTable(
        entries: ["S1": "Matematica", "S2": "Storia", "S3": "Fisica"],
        confirmed: ["S1", "S2"])

    private func remote(_ id: String, subjectId: String? = "S1", subject: String = "MATEMATICA",
                        value: Double? = 7, raw: String = "7", date: Date? = nil,
                        kind: RemoteGradeKind? = .oral, teacher: String? = nil, weight: Double? = nil,
                        comment: String? = nil, notCounting: Bool = false, cancelled: Bool = false) -> VotoRemoto {
        VotoRemoto(provider: .classeviva, remoteId: id, date: date ?? d(3, 10), hasTime: false,
                   subjectId: subjectId, subjectName: subject, teacher: teacher, rawValue: raw,
                   numericValue: value, kind: kind, kindRaw: kind?.rawValue, weight: weight, period: "Q2",
                   comment: comment, notCounting: notCounting, cancelled: cancelled, remoteModifiedAt: nil)
    }

    private func manual(subject: String = "Matematica", value: Double = 7, date: Date? = nil,
                        type: GradeType = .oral, teacher: String = "", note: String = "",
                        weight: Double = 1, countsForAverage: Bool = true) -> Grade {
        Grade(subject: subject, teacher: teacher, value: value, date: date ?? d(3, 10, hour: 10), note: note,
              type: type, weight: weight, countsForAverage: countsForAverage,
              modifiedAt: d(3, 10, hour: 18))
    }

    private func input(_ local: [Grade], _ remotes: [VotoRemoto], range: DateInterval?? = .none,
                       mapping: SubjectMappingTable? = nil, ignored: Set<String> = [],
                       decisions: [String: ConflictDecision] = [:], maxGrade: Double = 10) -> RegistroSyncInput {
        let covered: DateInterval? = range ?? schoolYear
        return RegistroSyncInput(
            local: local, fetch: RemoteFetch(grades: remotes, skippedCount: 0, coveredRange: covered),
            provider: .classeviva, accountKey: account, mapping: mapping ?? defaultMapping,
            ignored: ignored, decisions: decisions, maxGrade: maxGrade, calendar: cal)
    }

    private func plan(_ local: [Grade], _ remotes: [VotoRemoto], range: DateInterval?? = .none,
                      mapping: SubjectMappingTable? = nil, ignored: Set<String> = [],
                      decisions: [String: ConflictDecision] = [:], maxGrade: Double = 10) -> SyncPlan {
        RegistroSyncEngine.plan(input(local, remotes, range: range, mapping: mapping, ignored: ignored,
                                      decisions: decisions, maxGrade: maxGrade))
    }

    /// Applica un piano come farà lo store: sostituisce per id aggiornamenti e
    /// collegamenti, aggiunge gli inserimenti. Non cancella mai nulla.
    private func apply(_ p: SyncPlan, to local: [Grade]) -> [Grade] {
        var result = local
        for g in p.updates + p.links {
            if let i = result.firstIndex(where: { $0.id == g.id }) { result[i] = g }
            else { XCTFail("il piano aggiorna un id che non esiste: \(g.id)") }
        }
        for g in p.inserts {
            XCTAssertFalse(result.contains { $0.id == g.id }, "inserimento con id già presente")
            result.append(g)
        }
        return result
    }

    private func key(_ id: String) -> String { "classeviva|\(account)|\(id)" }
    private func gid(_ id: String) -> UUID {
        RegistroIdentity.gradeID(provider: .classeviva, accountKey: account, remoteId: id)
    }

    /// Importa i remoti su un elenco vuoto e restituisce i voti risultanti.
    private func imported(_ remotes: [VotoRemoto], mapping: SubjectMappingTable? = nil) -> [Grade] {
        apply(plan([], remotes, mapping: mapping), to: [])
    }

    // MARK: - Importazione

    func testFirstImportCreatesDeterministicGrades() throws {
        let r1 = remote("101", teacher: "  Rossi ", comment: "bravo")
        let r2 = remote("102", value: 7.5, raw: " 7½ ", date: d(3, 12), kind: .written)
        let p = plan([], [r1, r2])

        XCTAssertEqual(p.inserts.map(\.id), [gid("101"), gid("102")])
        XCTAssertEqual(p.newGradeIDs, [gid("101"), gid("102")])
        XCTAssertTrue(p.updates.isEmpty)
        XCTAssertTrue(p.links.isEmpty)
        XCTAssertTrue(p.conflicts.isEmpty)
        XCTAssertFalse(p.isEmpty)

        let g1 = p.inserts[0]
        XCTAssertEqual(g1.subject, "Matematica")
        XCTAssertEqual(g1.teacher, "Rossi")
        XCTAssertEqual(g1.value, 7)
        XCTAssertEqual(g1.date, d(3, 10))
        XCTAssertEqual(g1.type, .oral)
        XCTAssertEqual(g1.weight, 1)
        XCTAssertTrue(g1.countsForAverage)
        XCTAssertEqual(g1.note, "")
        XCTAssertTrue(g1.isImported)
        let o1 = try XCTUnwrap(g1.origin)
        XCTAssertEqual(o1.remoteKey, key("101"))
        XCTAssertEqual(o1.fingerprint, r1.fingerprint())
        XCTAssertEqual(o1.applied, AppliedValues(g1))
        XCTAssertEqual(o1.remoteTeacher, "Rossi")
        XCTAssertEqual(o1.remoteComment, "bravo")
        XCTAssertEqual(o1.remoteSubjectName, "MATEMATICA")
        XCTAssertEqual(o1.remoteSubjectId, "S1")
        XCTAssertEqual(o1.status, .active)
        XCTAssertNil(o1.manualSnapshot)

        let g2 = p.inserts[1]
        XCTAssertEqual(g2.value, 7.5)
        XCTAssertEqual(g2.type, .written)
        XCTAssertEqual(g2.origin?.rawValue, "7½")
        XCTAssertEqual(g2.displayValue, "7½")

        // Deterministico: stesso input, stesso piano.
        XCTAssertEqual(plan([], [r1, r2]), p)
    }

    func testSecondIdenticalSyncIsEmpty() {
        let m = manual(subject: "matematica", note: "mia")              // collegato (materia in minuscolo)
        let other = manual(subject: "Storia", value: 4, date: d(2, 2))   // manuale estraneo
        let remotes = [
            remote("201", teacher: " Rossi "),                            // collega m
            remote("202", value: nil, raw: "buono", date: d(4, 1)),       // non numerico
            remote("203", subjectId: "S2", subject: "STORIA", value: 6, raw: "6", date: d(4, 2), weight: 0.5),
            remote("204", subjectId: "S3", subject: "FISICA", date: d(4, 3)),  // materia in attesa
        ]
        let local = [m, other]
        let first = plan(local, remotes)
        XCTAssertEqual(first.links.map(\.id), [m.id])
        XCTAssertEqual(first.inserts.count, 2)
        XCTAssertEqual(first.pendingSubjects.map(\.key), ["S3"])

        var after = apply(first, to: local)
        let second = plan(after, remotes)
        XCTAssertTrue(second.isEmpty, "seconda sync non vuota: \(second)")
        XCTAssertTrue(second.updates.isEmpty && second.inserts.isEmpty && second.links.isEmpty)

        // L'editor rifila materia e docente al salvataggio: nessun campo risulta modificato.
        after = after.map { var g = $0
            g.subject = g.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            g.teacher = g.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
            return g }
        for g in after { XCTAssertEqual(g.origin?.applied.editedFields(in: g) ?? [], []) }
        XCTAssertTrue(plan(after, remotes).isEmpty)
    }

    // MARK: - Aggiornamenti

    func testRemoteChangeUpdatesUneditedFields() throws {
        let local = imported([remote("301")])
        let changed = remote("301", value: 8, raw: "8", date: d(3, 11), kind: .written,
                             teacher: "Bianchi", weight: 0.5, comment: "ottimo")
        let p = plan(local, [changed])

        XCTAssertTrue(p.inserts.isEmpty)
        XCTAssertTrue(p.links.isEmpty)
        XCTAssertEqual(p.updates.count, 1)
        let g = p.updates[0]
        XCTAssertEqual(g.id, gid("301"))
        XCTAssertEqual(g.value, 8)
        XCTAssertEqual(g.teacher, "Bianchi")
        XCTAssertEqual(g.date, d(3, 11))
        XCTAssertEqual(g.type, .written)
        XCTAssertEqual(g.weight, 0.5)
        XCTAssertEqual(g.modifiedAt, local[0].modifiedAt, "il motore non tocca modifiedAt")
        let o = try XCTUnwrap(g.origin)
        XCTAssertEqual(o.rawValue, "8")
        XCTAssertEqual(o.remoteComment, "ottimo")
        XCTAssertEqual(o.remoteWeight, 0.5)
        XCTAssertEqual(o.fingerprint, changed.fingerprint())
        XCTAssertEqual(o.applied, AppliedValues(g))

        XCTAssertTrue(plan(apply(p, to: local), [changed]).isEmpty)
    }

    func testUserEditedFieldIsNotOverwritten() throws {
        var local = imported([remote("401", teacher: "Rossi")])
        // L'utente cambia il valore e aggiunge una nota.
        local[0].value = 9
        local[0].note = "corretto a mano"

        // Registro invariato: nessuna scrittura.
        XCTAssertTrue(plan(local, [remote("401", teacher: "Rossi")]).isEmpty)

        let changed = remote("401", value: 8, raw: "8", teacher: "Bianchi")
        let p = plan(local, [changed])
        XCTAssertEqual(p.updates.count, 1)
        let g = p.updates[0]
        XCTAssertEqual(g.value, 9, "il valore modificato dall'utente resta")
        XCTAssertEqual(g.note, "corretto a mano")
        XCTAssertEqual(g.teacher, "Bianchi", "i campi non modificati seguono il registro")
        let o = try XCTUnwrap(g.origin)
        XCTAssertEqual(o.applied.value, 7, "resta il vecchio valore applicato: il campo resta 'modificato'")
        XCTAssertEqual(o.applied.teacher, "Bianchi")
        XCTAssertEqual(o.applied.editedFields(in: g), [.value])
        XCTAssertEqual(o.rawValue, "8")

        let after = apply(p, to: local)
        XCTAssertTrue(plan(after, [changed]).isEmpty)
        // Anche un cambio successivo del registro non tocca il valore.
        let again = plan(after, [remote("401", value: 5, raw: "5", teacher: "Bianchi")])
        XCTAssertEqual(again.updates.first?.value, 9)
    }

    // MARK: - Collegamento ai voti manuali

    func testCertainMatchLinksManualKeepingIDAndNote() throws {
        let m = manual(note: "interrogazione su Euclide", weight: 0.5)
        let r = remote("501", teacher: "Rossi")
        let p = plan([m], [r])

        XCTAssertTrue(p.inserts.isEmpty)
        XCTAssertTrue(p.newGradeIDs.isEmpty)
        XCTAssertTrue(p.conflicts.isEmpty)
        XCTAssertEqual(p.links.count, 1)
        let g = p.links[0]
        XCTAssertEqual(g.id, m.id)
        XCTAssertEqual(g.note, "interrogazione su Euclide")
        XCTAssertEqual(g.subject, "Matematica")
        XCTAssertEqual(g.teacher, "Rossi")
        XCTAssertEqual(g.date, d(3, 10), "la data diventa quella del registro")
        XCTAssertEqual(g.weight, 0.5, "peso assente nel registro: resta quello manuale")
        XCTAssertEqual(g.modifiedAt, m.modifiedAt)
        XCTAssertFalse(g.isImported)
        let o = try XCTUnwrap(g.origin)
        XCTAssertEqual(o.remoteKey, key("501"))
        XCTAssertEqual(o.manualSnapshot, ManualGradeSnapshot(m))
        XCTAssertEqual(o.manualSnapshot?.restored(id: m.id), m)
        XCTAssertEqual(o.applied, AppliedValues(g))
    }

    /// Ruling 1: il registro diventa la fonte per i campi che fornisce, il resto resta manuale.
    func testCertainLinkTakesRegistroFieldsOnlyWhereProvided() throws {
        let m = manual(value: 7.005, type: .written, teacher: "Verdi", note: "n", weight: 0.3)
        let r = remote("502", kind: .other, teacher: nil, weight: 0.75, notCounting: true)
        let g = try XCTUnwrap(plan([m], [r]).links.first)
        XCTAssertEqual(g.value, 7, "valore numerico del registro (entro la tolleranza)")
        XCTAssertEqual(g.type, .written, "tipo 'altro' del registro: resta quello manuale")
        XCTAssertEqual(g.teacher, "Verdi", "docente assente nel registro: resta quello manuale")
        XCTAssertEqual(g.weight, 0.75)
        XCTAssertFalse(g.countsForAverage, "non fa media sul registro")
        XCTAssertEqual(g.note, "n")
        XCTAssertEqual(g.origin?.manualSnapshot?.value, 7.005)
        XCTAssertEqual(g.origin?.manualSnapshot?.teacher, "Verdi")
    }

    func testAmbiguousMatchBecomesConflict() {
        let a = manual(), b = manual()
        let r = remote("601")
        let p = plan([a, b], [r])
        XCTAssertTrue(p.inserts.isEmpty)
        XCTAssertTrue(p.links.isEmpty)
        XCTAssertTrue(p.isEmpty)
        XCTAssertEqual(p.conflicts.count, 1)
        XCTAssertEqual(p.conflicts[0].id, key("601"))
        XCTAssertEqual(p.conflicts[0].remote, r)
        XCTAssertEqual(Set(p.conflicts[0].candidateIDs), [a.id, b.id])

        // Un solo candidato ma debole (un giorno di distanza, tipo ignoto): conflitto.
        let near = manual(date: d(3, 11))
        let weak = plan([near], [remote("602", kind: nil)])
        XCTAssertEqual(weak.conflicts.map(\.candidateIDs), [[near.id]])
        XCTAssertTrue(weak.links.isEmpty && weak.inserts.isEmpty)
    }

    func testDecisionImportAsNewAndLinkTo() throws {
        let a = manual(note: "a"), b = manual(note: "b")
        let rA = remote("701"), rB = remote("702")
        let decisions: [String: ConflictDecision] = [key("701"): .linkTo(b.id), key("702"): .importAsNew]
        let p = plan([a, b], [rA, rB], decisions: decisions)

        XCTAssertTrue(p.conflicts.isEmpty)
        XCTAssertEqual(p.links.map(\.id), [b.id])
        XCTAssertEqual(p.links[0].origin?.remoteKey, key("701"))
        XCTAssertEqual(p.links[0].note, "b")
        XCTAssertEqual(p.links[0].origin?.manualSnapshot, ManualGradeSnapshot(b))
        XCTAssertEqual(p.inserts.map(\.id), [gid("702")])
        XCTAssertEqual(p.newGradeIDs, [gid("702")])

        let after = apply(p, to: [a, b])
        XCTAssertEqual(after.first { $0.id == a.id }, a, "il manuale non scelto resta intatto")
        XCTAssertTrue(plan(after, [rA, rB], decisions: decisions).isEmpty)
    }

    func testLaterDecisionKeepsConflictPendingWithoutImport() {
        let a = manual(), b = manual()
        let r = remote("801")
        let p = plan([a, b], [r], decisions: [key("801"): .later])
        XCTAssertTrue(p.isEmpty)
        XCTAssertEqual(p.conflicts.map(\.id), [key("801")])
        XCTAssertEqual(Set(p.conflicts[0].candidateIDs), [a.id, b.id])

        // "Decidi dopo" senza più candidati: resta in attesa, non si importa.
        let alone = plan([], [r], decisions: [key("801"): .later])
        XCTAssertTrue(alone.isEmpty)
        XCTAssertEqual(alone.conflicts.map(\.id), [key("801")])
    }

    /// Ruling 7: `linkTo` verso un id che non è un voto manuale non collegato → conflitto.
    func testLinkToInvalidIDFallsBackToConflict() {
        let a = manual(), b = manual()
        let importedGrade = imported([remote("901", subjectId: "S2", subject: "STORIA", date: d(1, 5))])[0]
        let local = [a, b, importedGrade]
        let remotes = [remote("901", subjectId: "S2", subject: "STORIA", date: d(1, 5)), remote("902"), remote("903")]
        let p = plan(local, remotes, decisions: [key("902"): .linkTo(UUID()), key("903"): .linkTo(importedGrade.id)])
        XCTAssertTrue(p.isEmpty, "\(p)")
        XCTAssertEqual(p.conflicts.map(\.id), [key("902"), key("903")])

        // Due decisioni verso lo stesso manuale: un solo collegamento.
        let twice = plan([a], [remote("904"), remote("905")],
                         decisions: [key("904"): .linkTo(a.id), key("905"): .linkTo(a.id)])
        XCTAssertEqual(twice.links.map(\.id), [a.id])
        XCTAssertEqual(twice.links[0].origin?.remoteKey, key("904"))
        XCTAssertEqual(twice.conflicts.map(\.id), [key("905")])
        XCTAssertTrue(twice.inserts.isEmpty)

        // Manuale con un valore diverso: collegarlo lo cambierebbe → conflitto.
        let eight = manual(value: 8)
        let wrongValue = plan([eight], [remote("906")], decisions: [key("906"): .linkTo(eight.id)])
        XCTAssertTrue(wrongValue.isEmpty)
        XCTAssertEqual(wrongValue.conflicts.map(\.id), [key("906")])

        // Un conflitto non elenca un manuale preso da un'altra decisione nella stessa sync.
        let mixed = plan([a, b], [remote("907"), remote("908")],
                         decisions: [key("907"): .later, key("908"): .linkTo(a.id)])
        XCTAssertEqual(mixed.links.map(\.id), [a.id])
        XCTAssertEqual(mixed.conflicts.map(\.candidateIDs), [[b.id]])
    }

    func testOneManualGradeLinksToOneRemoteOnly() {
        let m = manual()
        let p = plan([m], [remote("1002"), remote("1001")])
        XCTAssertEqual(p.links.count, 1, "mai due collegamenti allo stesso manuale")
        XCTAssertEqual(p.links[0].id, m.id)
        XCTAssertEqual(p.links.count + p.inserts.count + p.conflicts.count, 2)
        XCTAssertFalse(p.inserts.contains { $0.id == m.id })

        // Vince il remoto con la corrispondenza più forte, indipendentemente dall'ordine.
        let nextDay = remote("1003", date: d(3, 11))   // 0,9
        let sameDay = remote("1004")                    // 1,2
        for order in [[nextDay, sameDay], [sameDay, nextDay]] {
            let q = plan([m], order)
            XCTAssertEqual(q.links.map { $0.origin?.remoteKey }, [key("1004")])
            XCTAssertEqual(q.inserts.map(\.id), [gid("1003")])
        }
    }

    // MARK: - Materie

    func testUnconfirmedSubjectIsPending() {
        let p = plan([], [remote("1101", subjectId: "S3", subject: " FISICA "),
                          remote("1102", subjectId: "S3", subject: "FISICA", date: d(3, 12)),
                          remote("1103", subjectId: nil, subject: "Chimica organica"),
                          remote("1104")])
        XCTAssertEqual(p.pendingSubjects, [RemoteSubjectRef(id: "S3", name: "FISICA"),
                                           RemoteSubjectRef(id: nil, name: "Chimica organica")])
        XCTAssertEqual(p.inserts.map(\.id), [gid("1104")])
        XCTAssertTrue(p.conflicts.isEmpty)
    }

    /// Ruling 10: cambiando il mapping, i voti importati/collegati con materia non
    /// modificata dall'utente passano alla nuova materia, anche a fingerprint invariato.
    func testMappingChangeMovesUneditedImportedGrades() throws {
        let m = manual(subject: "Storia", value: 6, date: d(2, 3, hour: 9))
        let remotes = [remote("1201", subjectId: "S2", subject: "STORIA", value: 8, raw: "8", date: d(2, 1)),
                       remote("1202", subjectId: "S2", subject: "STORIA", value: 5, raw: "5", date: d(2, 10)),
                       remote("1203", subjectId: "S2", subject: "STORIA", value: 6, raw: "6", date: d(2, 3)),
                       remote("1204", date: d(2, 4))]
        var local = apply(plan([m], remotes), to: [m])
        XCTAssertEqual(local.first { $0.id == m.id }?.origin?.remoteKey, key("1203"))
        // L'utente sposta a mano uno dei voti importati.
        let edited = try XCTUnwrap(local.firstIndex { $0.id == gid("1202") })
        local[edited].subject = "Educazione civica"

        var newMapping = defaultMapping
        newMapping.entries["S2"] = "Storia e geografia"
        let p = plan(local, remotes, mapping: newMapping)
        XCTAssertEqual(Set(p.updates.map(\.id)), [gid("1201"), m.id])
        for g in p.updates {
            XCTAssertEqual(g.subject, "Storia e geografia")
            XCTAssertEqual(g.origin?.applied.subject, "Storia e geografia")
            XCTAssertEqual(g.origin?.applied.editedFields(in: g), [])
        }
        XCTAssertFalse(p.updates.contains { $0.id == gid("1202") }, "materia modificata dall'utente: intatta")
        XCTAssertTrue(plan(apply(p, to: local), remotes, mapping: newMapping).isEmpty)
    }

    // MARK: - Ignorati e annullati

    func testIgnoredRemoteIsNeverImported() {
        let m = manual()
        let p = plan([m], [remote("1301"), remote("1302", cancelled: true)], ignored: [key("1301")])
        XCTAssertTrue(p.isEmpty)
        XCTAssertTrue(p.conflicts.isEmpty)
        XCTAssertTrue(p.pendingSubjects.isEmpty)

        // Già importati: annullato o ignorato sul registro → nessuna modifica, nemmeno "rimosso".
        let local = imported([remote("1303", date: d(1, 10)), remote("1304", date: d(1, 11))])
        let q = plan(local, [remote("1303", value: 4, raw: "4", date: d(1, 10), cancelled: true),
                             remote("1304", value: 3, raw: "3", date: d(1, 11))],
                     ignored: [key("1304")])
        XCTAssertTrue(q.isEmpty, "\(q)")
        XCTAssertFalse(q.removalCheckSkipped)
    }

    // MARK: - Rimossi dal registro

    func testMissingRemoteIsMarkedRemovedNeverDeleted() throws {
        let remotes = [remote("1401", date: d(1, 10)), remote("1402", date: d(1, 11)), remote("1403", date: d(1, 12))]
        let local = imported(remotes)
        let p = plan(local, Array(remotes.prefix(2)))
        XCTAssertFalse(p.removalCheckSkipped)
        XCTAssertTrue(p.inserts.isEmpty && p.links.isEmpty)
        XCTAssertEqual(p.updates.count, 1)
        var expected = try XCTUnwrap(local.first { $0.id == gid("1403") })
        expected.origin?.status = .removedFromRegistro
        XCTAssertEqual(p.updates[0], expected, "cambia solo lo stato")

        let after = apply(p, to: local)
        XCTAssertEqual(after.count, 3, "nessun voto cancellato")
        XCTAssertTrue(plan(after, Array(remotes.prefix(2))).isEmpty)
    }

    func testRemovedGradeReappearingIsReactivated() {
        let remotes = [remote("1501", date: d(1, 10)), remote("1502", date: d(1, 11))]
        let local = imported(remotes)
        let removed = apply(plan(local, [remotes[0]]), to: local)
        XCTAssertEqual(removed.first { $0.id == gid("1502") }?.origin?.status, .removedFromRegistro)

        let p = plan(removed, remotes)
        XCTAssertEqual(p.updates, [local.first { $0.id == gid("1502") }!])
        XCTAssertEqual(p.updates.first?.origin?.status, .active)
    }

    func testEmptyFetchSkipsRemovalCheck() {
        let local = imported([remote("1601", date: d(1, 10)), remote("1602", date: d(1, 11))])
        let p = plan(local, [])
        XCTAssertTrue(p.isEmpty)
        XCTAssertTrue(p.removalCheckSkipped)

        // Senza voti collegati non c'è nulla da proteggere.
        XCTAssertFalse(plan([], []).removalCheckSkipped)
    }

    func testFewerThanHalfSkipsRemovalCheck() {
        let remotes = (1...5).map { remote("17\($0)", date: d(1, 10 + $0)) }
        let local = imported(remotes)
        let p = plan(local, Array(remotes.prefix(2)))   // 2 < 5/2
        XCTAssertTrue(p.isEmpty)
        XCTAssertTrue(p.removalCheckSkipped)

        // Esattamente la metà: il controllo si fa.
        let four = imported(Array(remotes.prefix(4)))
        let q = plan(four, Array(remotes.prefix(2)))
        XCTAssertFalse(q.removalCheckSkipped)
        XCTAssertEqual(Set(q.updates.map(\.id)), [gid("173"), gid("174")])
        XCTAssertTrue(q.updates.allSatisfy { $0.origin?.status == .removedFromRegistro })
    }

    func testLastYearGradesAreOutsideCoveredRange() {
        let lastYear = (1...4).map { remote("18\($0)", date: d(3, $0, 2025)) }
        let current = remote("1810", date: d(1, 10))
        let local = imported(lastYear + [current])
        // Il registro restituisce solo l'anno in corso: quelli dell'anno prima non sono
        // "rimossi" e non fanno scattare la protezione "pochi voti".
        let p = plan(local, [current])
        XCTAssertTrue(p.isEmpty, "\(p)")
        XCTAssertFalse(p.removalCheckSkipped)

        // Intervallo coperto sconosciuto: nessun controllo.
        let unknown = plan(local, [], range: .some(nil))
        XCTAssertTrue(unknown.isEmpty)
        XCTAssertFalse(unknown.removalCheckSkipped)
    }

    // MARK: - Valori

    func testNonNumericRemoteDoesNotCountForAverage() throws {
        let p = plan([], [remote("1901", value: nil, raw: "buono"),
                          remote("1902", value: 6, raw: "6", date: d(3, 11), notCounting: true),
                          remote("1903", value: 11, raw: "11", date: d(3, 12)),     // fuori scala
                          remote("1904", value: -1, raw: "-1", date: d(3, 13))])
        let byID = Dictionary(uniqueKeysWithValues: p.inserts.map { ($0.id, $0) })
        let judgement = try XCTUnwrap(byID[gid("1901")])
        XCTAssertEqual(judgement.value, 0)
        XCTAssertFalse(judgement.countsForAverage)
        XCTAssertEqual(judgement.origin?.rawValue, "buono")
        XCTAssertNil(judgement.origin?.numericValue)
        XCTAssertEqual(judgement.displayValue, "buono")

        let notCounting = try XCTUnwrap(byID[gid("1902")])
        XCTAssertEqual(notCounting.value, 6)
        XCTAssertFalse(notCounting.countsForAverage)

        for id in ["1903", "1904"] {
            let g = try XCTUnwrap(byID[gid(id)])
            XCTAssertNil(g.origin?.numericValue, "fuori da 0...maxGrade = non numerico")
            XCTAssertEqual(g.value, 0)
            XCTAssertFalse(g.countsForAverage)
        }

        // Un voto numerico che diventa non numerico tiene il valore già presente.
        let local = imported([remote("1905", value: 7, raw: "7")])
        let q = plan(local, [remote("1905", value: nil, raw: "N.C.")])
        XCTAssertEqual(q.updates.first?.value, 7)
        XCTAssertEqual(q.updates.first?.countsForAverage, false)
        XCTAssertEqual(q.updates.first?.origin?.rawValue, "N.C.")
    }

    func testMissingTimeTeacherWeightStayEmpty() throws {
        let p = plan([], [remote("2001", teacher: nil, weight: nil), remote("2002", date: d(3, 11), teacher: "   ")])
        for g in p.inserts {
            let o = try XCTUnwrap(g.origin)
            XCTAssertFalse(o.hasTime)
            XCTAssertEqual(g.teacher, "")
            XCTAssertNil(o.remoteTeacher)
            XCTAssertNil(o.remoteWeight)
            XCTAssertEqual(g.weight, 1)
        }
        XCTAssertEqual(p.inserts.count, 2)
    }

    // MARK: - Sicurezza

    /// Un voto con l'id deterministico ma senza `origin` non viene mai duplicato né toccato.
    func testDeterministicIDCollisionIsNeverDuplicatedOrTouched() {
        var g = manual(value: 3, date: d(2, 2))
        g.id = gid("2101")
        let p = plan([g], [remote("2101"), remote("2101")])
        XCTAssertTrue(p.isEmpty, "\(p)")
        XCTAssertTrue(p.conflicts.isEmpty)
    }
}
