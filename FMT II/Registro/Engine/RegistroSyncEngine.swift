import Foundation

/// Motore di sincronizzazione puro (spec §1, §2, §5): (voti locali, voti remoti,
/// mapping materie, decisioni) -> `SyncPlan`. Nessun I/O.
///
/// Regole fisse: nessun voto viene mai cancellato; i campi modificati dall'utente
/// non vengono mai sovrascritti; `note` e `modifiedAt` non vengono mai toccati;
/// due sync identiche di fila producono un piano vuoto.
enum RegistroSyncEngine {

    static func plan(_ input: RegistroSyncInput) -> SyncPlan {
        var builder = PlanBuilder(input: input)
        builder.run()
        return builder.plan
    }
}

// MARK: - Costruzione del piano

private struct PlanBuilder {
    let input: RegistroSyncInput
    var plan = SyncPlan()

    /// Voti locali collegati a questo account, per `remoteKey`.
    private var linkedByKey: [String: [Grade]] = [:]
    private var localByID: [UUID: Grade] = [:]
    /// Voti manuali già collegati in questa sync (ogni manuale a un solo remoto).
    private var claimed = Set<UUID>()
    /// `remoteKey` dei remoti presenti nel download.
    private var seenKeys = Set<String>()
    private var pendingKeys = Set<String>()

    init(input: RegistroSyncInput) {
        self.input = input
        for g in input.local {
            localByID[g.id] = g
            if let o = g.origin, belongsToAccount(o) {
                linkedByKey[o.remoteKey, default: []].append(g)
            }
        }
    }

    private func belongsToAccount(_ o: RegistroOrigin) -> Bool {
        o.provider == input.provider && o.accountKey == input.accountKey
    }

    private func remoteKey(_ r: VotoRemoto) -> String {
        "\(input.provider.rawValue)|\(input.accountKey)|\(r.remoteId)"
    }

    private func gradeID(_ r: VotoRemoto) -> UUID {
        RegistroIdentity.gradeID(provider: input.provider, accountKey: input.accountKey, remoteId: r.remoteId)
    }

    // MARK: Passi

    mutating func run() {
        // Remoti nuovi (né già presenti né saltati) con la materia confermata.
        var fresh: [(remote: RemoteValues, appSubject: String)] = []

        for raw in input.fetch.grades {
            let key = remoteKey(raw)
            // Un remoto ripetuto nello stesso download si considera una volta sola.
            guard seenKeys.insert(key).inserted else { continue }
            let r = RemoteValues(raw, maxGrade: input.maxGrade)
            let appSubject = input.mapping.appSubject(for: r.subjectRef)

            // 1. Già presente (stessa remoteKey o id deterministico) → mai un voto nuovo.
            let existing = linkedByKey[key] ?? []
            if !existing.isEmpty || localByID[gradeID(raw)] != nil {
                // Annullato o ignorato: nessuna modifica al voto collegato.
                guard !raw.cancelled, !input.ignored.contains(key) else { continue }
                for g in existing {
                    if let updated = refreshed(g, with: r, appSubject: appSubject) { plan.updates.append(updated) }
                }
                if appSubject == nil { addPending(r.subjectRef) }
                continue
            }

            // 2. Annullato o ignorato: mai importato.
            if raw.cancelled || input.ignored.contains(key) { continue }

            // 3. Materia non confermata: in attesa, nulla importato.
            guard let appSubject else { addPending(r.subjectRef); continue }
            fresh.append((r, appSubject))
        }

        resolveFresh(fresh)
        markRemoved()
        plan.newGradeIDs = plan.inserts.map(\.id)
    }

    private mutating func addPending(_ ref: RemoteSubjectRef) {
        if pendingKeys.insert(ref.key).inserted { plan.pendingSubjects.append(ref) }
    }

    /// Decisioni dell'utente, poi collegamenti certi (il più forte vince), poi
    /// conflitti e nuovi voti. I candidati dei conflitti si calcolano alla fine,
    /// così non elencano manuali già collegati ad altri remoti in questa sync.
    private mutating func resolveFresh(_ fresh: [(remote: RemoteValues, appSubject: String)]) {
        typealias Item = (remote: RemoteValues, appSubject: String)
        var forcedConflicts = Set<String>()   // "Decidi dopo" o "Sì, è questo" non più valido
        var automatic: [Item] = []

        // 1. Decisioni dell'utente (hanno la precedenza sui collegamenti automatici).
        for item in fresh {
            let key = remoteKey(item.remote.original)
            switch input.decisions[key] {
            case .importAsNew?:
                insert(item.remote, appSubject: item.appSubject)
            case .linkTo(let id)?:
                if let m = linkableManual(id, for: item.remote) { link(m, to: item.remote) }
                else { forcedConflicts.insert(key) }
            case .later?:
                forcedConflicts.insert(key)
            case nil:
                automatic.append(item)
            }
        }

        // 2. Collegamenti certi: prima la corrispondenza più forte, a parità la remoteKey.
        let scored = automatic.map { (item: $0, candidates: candidates(for: $0.remote, appSubject: $0.appSubject)) }
        let ordered = scored.sorted {
            let a = $0.candidates.first?.score ?? -1, b = $1.candidates.first?.score ?? -1
            if abs(a - b) > 1e-9 { return a > b }
            return remoteKey($0.item.remote.original) < remoteKey($1.item.remote.original)
        }
        var linked = Set<String>()
        for entry in ordered {
            if GradeMatcher.isCertain(entry.candidates), let best = entry.candidates.first,
               !claimed.contains(best.gradeID), let m = localByID[best.gradeID] {
                link(m, to: entry.item.remote)
                linked.insert(remoteKey(entry.item.remote.original))
            }
        }

        // 3. Il resto, nell'ordine del download. Candidati ricalcolati: solo manuali
        //    ancora liberi. Con candidati → conflitto (mai un collegamento automatico
        //    qui); senza → voto nuovo, salvo "Decidi dopo"/scelta non valida, che
        //    resta in attesa e non importa nulla.
        let automaticKeys = Set(automatic.map { remoteKey($0.remote.original) })
        for item in fresh {
            let key = remoteKey(item.remote.original)
            let forced = forcedConflicts.contains(key)
            guard forced || (automaticKeys.contains(key) && !linked.contains(key)) else { continue }
            let free = candidates(for: item.remote, appSubject: item.appSubject)
            if free.isEmpty && !forced {
                insert(item.remote, appSubject: item.appSubject)
            } else {
                plan.conflicts.append(PendingConflict(id: key, remote: item.remote.original,
                                                      candidateIDs: free.map(\.gradeID)))
            }
        }
    }

    // MARK: Matching

    /// Candidati fra i voti manuali non collegati e non ancora presi in questa sync.
    private func candidates(for r: RemoteValues, appSubject: String) -> [MatchCandidate] {
        let manual = input.local.filter { $0.origin == nil && !claimed.contains($0.id) }
        return GradeMatcher.candidates(for: r.matchable, appSubject: appSubject, among: manual, calendar: input.calendar)
    }

    /// Il voto scelto con "Sì, è questo", se è ancora un voto manuale libero e
    /// collegarlo non ne cambia il valore (oltre la tolleranza del matcher).
    private func linkableManual(_ id: UUID, for r: RemoteValues) -> Grade? {
        guard let m = localByID[id], m.origin == nil, !claimed.contains(id) else { return nil }
        if let n = r.numeric, abs(m.value - n) > 0.01 + 1e-9 { return nil }
        return m
    }

    // MARK: Scritture

    private mutating func insert(_ r: RemoteValues, appSubject: String) {
        var g = Grade(id: gradeID(r.original), subject: appSubject, teacher: r.teacher ?? "",
                      value: r.numeric ?? 0, date: r.original.date, note: "",
                      type: r.gradeType ?? .oral, weight: r.weight ?? 1.0,
                      countsForAverage: r.counts,
                      // valore deterministico: lo store lo aggiorna quando applica il piano
                      modifiedAt: r.original.date)
        g.origin = origin(for: r, applied: AppliedValues(g), manualSnapshot: nil)
        plan.inserts.append(g)
    }

    /// Collegamento: il voto manuale tiene id e nota; il registro diventa la fonte
    /// dei campi che fornisce (data, docente, tipo, peso, "fa media", valore).
    private mutating func link(_ manual: Grade, to r: RemoteValues) {
        claimed.insert(manual.id)
        var g = manual
        g.date = r.original.date
        if let t = r.teacher { g.teacher = t }
        if let t = r.gradeType { g.type = t }
        if let w = r.weight { g.weight = w }
        if let n = r.numeric { g.value = n }
        g.countsForAverage = r.counts
        g.origin = origin(for: r, applied: AppliedValues(g), manualSnapshot: ManualGradeSnapshot(manual))
        plan.links.append(g)
    }

    /// Voto già collegato/importato: nil se non cambia nulla.
    private func refreshed(_ g: Grade, with r: RemoteValues, appSubject: String?) -> Grade? {
        guard let o = g.origin else { return nil }
        let remoteChanged = o.fingerprint != r.fingerprint || o.status != .active
        let edited = o.applied.editedFields(in: g)
        var out = g
        var applied = o.applied

        // Materia: segue il mapping se l'utente non l'ha cambiata (anche a fingerprint invariato).
        if let appSubject, !edited.contains(.subject),
           SubjectMatcher.normalizedKey(g.subject) != SubjectMatcher.normalizedKey(appSubject) {
            out.subject = appSubject
            applied.subject = appSubject
        }

        if remoteChanged {
            let linked = o.manualSnapshot != nil
            func set<T>(_ field: GradeField, _ path: WritableKeyPath<Grade, T>, _ appliedPath: WritableKeyPath<AppliedValues, T>, _ value: T) {
                guard !edited.contains(field) else { return } // campo dell'utente: resta, e resta "modificato"
                out[keyPath: path] = value
                applied[keyPath: appliedPath] = value
            }
            set(.teacher, \.teacher, \.teacher, r.teacher ?? (linked ? g.teacher : ""))
            set(.value, \.value, \.value, r.numeric ?? g.value)
            set(.date, \.date, \.date, r.original.date)
            set(.type, \.type, \.type, r.gradeType ?? g.type)
            set(.weight, \.weight, \.weight, r.weight ?? (linked ? g.weight : 1.0))
            set(.countsForAverage, \.countsForAverage, \.countsForAverage, r.counts)
            out.origin = origin(for: r, applied: applied, manualSnapshot: o.manualSnapshot)
        } else {
            out.origin?.applied = applied
        }
        return out == g ? nil : out
    }

    /// Voti collegati spariti dal registro: segnati "rimossi", mai cancellati.
    /// Solo voti attivi (non quelli già rimossi o "tenuti" dall'utente) con data
    /// nell'intervallo coperto dal download; controllo saltato (e segnalato) se il
    /// download sembra incompleto.
    private mutating func markRemoved() {
        guard let range = input.fetch.coveredRange else { return }
        let activeInRange = linkedByKey.values.joined().filter {
            $0.origin?.status == .active && range.contains($0.date)
        }
        guard !activeInRange.isEmpty else { return }
        let remoteInRange = input.fetch.grades.filter { range.contains($0.date) }.count
        if remoteInRange == 0 || remoteInRange * 2 < activeInRange.count {
            plan.removalCheckSkipped = true
            return
        }
        let candidates = Set(activeInRange.map(\.id))
        for g in input.local where candidates.contains(g.id) {
            guard let key = g.origin?.remoteKey, !seenKeys.contains(key) else { continue }
            var removed = g
            removed.origin?.status = .removedFromRegistro
            plan.updates.append(removed)
        }
    }

    private func origin(for r: RemoteValues, applied: AppliedValues, manualSnapshot: ManualGradeSnapshot?) -> RegistroOrigin {
        let raw = r.original
        return RegistroOrigin(
            provider: input.provider, accountKey: input.accountKey, remoteId: raw.remoteId,
            rawValue: r.rawValue, numericValue: r.numeric, hasTime: raw.hasTime,
            remoteSubjectId: raw.subjectId, remoteSubjectName: r.subjectRef.name,
            remoteTeacher: r.teacher, remoteTypeRaw: raw.kindRaw, remoteKind: raw.kind,
            remoteWeight: raw.weight, remotePeriod: raw.period, remoteComment: raw.comment,
            notCounting: raw.notCounting, cancelled: raw.cancelled,
            remoteModifiedAt: raw.remoteModifiedAt, fingerprint: r.fingerprint,
            applied: applied, manualSnapshot: manualSnapshot, status: .active)
    }
}

// MARK: - Valori remoti ripuliti

/// Il voto remoto con i valori pronti da scrivere: stringhe rifilate (l'editor
/// rifila al salvataggio, altrimenti sembrerebbero modifiche dell'utente) e
/// numeri fuori scala considerati non numerici.
private struct RemoteValues {
    let original: VotoRemoto
    let fingerprint: String
    let rawValue: String
    let numeric: Double?
    let teacher: String?
    let weight: Double?
    let subjectRef: RemoteSubjectRef

    init(_ r: VotoRemoto, maxGrade: Double) {
        original = r
        fingerprint = r.fingerprint()
        rawValue = r.rawValue.trimmed
        if let n = r.numericValue, n.isFinite, n >= 0, n <= maxGrade { numeric = n } else { numeric = nil }
        let t = r.teacher?.trimmed ?? ""
        teacher = t.isEmpty ? nil : t
        if let w = r.weight, w.isFinite, w >= 0, w <= 1 { weight = w } else { weight = nil }
        subjectRef = RemoteSubjectRef(id: r.subjectId, name: r.subjectName.trimmed)
    }

    /// Fa media solo se numerico e non escluso dal registro.
    var counts: Bool { numeric != nil && !original.notCounting }

    /// Tipo dell'app, solo per scritto/orale/pratico (nessun nuovo caso in `GradeType`).
    var gradeType: GradeType? {
        switch original.kind {
        case .written: return .written
        case .oral: return .oral
        case .practical: return .practical
        case .other, nil: return nil
        }
    }

    /// Copia per il matcher con i valori ripuliti.
    var matchable: VotoRemoto {
        var r = original
        r.numericValue = numeric
        r.rawValue = rawValue
        r.teacher = teacher
        return r
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
