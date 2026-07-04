import SwiftUI

/// Propaga la materia inserita per una lezione a tutte le altre lezioni dello
/// stesso docente, senza toccare i campi modificati a mano dall'utente
/// (riempie solo i campi vuoti o quelli già auto-compilati).
func propagateSubject(edits: [String: String], autoFilled: Set<String>, lessons: [Lesson],
                      teacher: String, subject: String, sourceId: String)
    -> (edits: [String: String], autoFilled: Set<String>) {
    var edits = edits
    var auto = autoFilled
    for l in lessons where l.teacher == teacher && l.id != sourceId {
        let current = edits[l.id] ?? ""
        if current.isEmpty || auto.contains(l.id) {
            edits[l.id] = subject
            auto.insert(l.id)
        }
    }
    auto.remove(sourceId)
    return (edits, auto)
}

/// Modifica in sospeso di un campo auto-compilato: chiede conferma prima di
/// differenziare la materia di un docente.
struct PendingSubjectEdit: Identifiable {
    let id = UUID()
    let lessonId: String
    let teacher: String
    let oldValue: String
}

/// Materie comuni alla maggior parte delle scuole italiane, proposte come
/// suggerimenti nel completamento/modifica delle materie.
let commonItalianSubjects = [
    "Italiano", "Matematica", "Storia", "Geografia", "Geostoria",
    "Inglese", "Francese", "Spagnolo", "Tedesco", "Latino", "Greco",
    "Scienze", "Scienze naturali", "Biologia", "Chimica", "Fisica",
    "Filosofia", "Storia dell'arte", "Disegno e storia dell'arte",
    "Diritto", "Economia", "Informatica", "Tecnologia",
    "Scienze motorie", "Educazione fisica", "Educazione civica",
    "Religione", "Musica", "Arte e immagine"
]

/// Sezione (una classe) di campi materia: suggerimenti, invio che accetta il
/// primo, propagazione per docente e conferma multi-materia. Riusata dal
/// completamento import e dall'editor «Dati orario».
struct SubjectCompletionSection: View {
    let className: String
    let lessons: [Lesson]              // lezioni della classe, ordinate
    let allLessons: [Lesson]           // tutte, per propagare tra le classi
    @Binding var edits: [String: String]
    @Binding var autoFilled: Set<String>
    @Binding var multiSubjectTeachers: Set<String>
    @Binding var pendingEdit: PendingSubjectEdit?
    @FocusState.Binding var focusedLesson: String?

    var body: some View {
        Section(className) {
            ForEach(lessons) { lesson in
                row(lesson)
            }
        }
        .listRowBackground(Color.sectionCard)
    }

    @ViewBuilder
    private func row(_ lesson: Lesson) -> some View {
        let text = Binding(
            get: { edits[lesson.id] ?? "" },
            set: { edits[lesson.id] = $0 }
        )
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(lesson.dayLabel) · \(lesson.startTime)")
                        .font(.callout)
                    Text(lesson.teacher)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Materia", text: text)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .frame(maxWidth: 150)
                    .focused($focusedLesson, equals: lesson.id)
                    .submitLabel(.done)
                    // Il campo auto-compilato resta attenuato finché non viene
                    // confermato o modificato dall'utente.
                    .foregroundStyle(autoFilled.contains(lesson.id) ? .secondary : .primary)
                    .onSubmit {
                        var value = text.wrappedValue
                        if let first = suggestions(for: value).first {
                            value = first
                            edits[lesson.id] = first
                        }
                        commit(value, for: lesson)
                    }
                    .onChange(of: edits[lesson.id] ?? "") { old, new in
                        // Cambiare a mano un campo propagato chiede se il
                        // docente insegna più di una materia.
                        guard autoFilled.contains(lesson.id),
                              new != old,
                              focusedLesson == lesson.id,
                              !multiSubjectTeachers.contains(lesson.teacher),
                              pendingEdit == nil else { return }
                        pendingEdit = PendingSubjectEdit(lessonId: lesson.id,
                                                         teacher: lesson.teacher,
                                                         oldValue: old)
                    }
            }
            if focusedLesson == lesson.id {
                let items = suggestions(for: edits[lesson.id] ?? "")
                if !items.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(items, id: \.self) { s in
                                Button {
                                    edits[lesson.id] = s
                                    commit(s, for: lesson)
                                } label: {
                                    Text(s)
                                        .font(.caption)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Suggerimenti: materie già inserite + materie comuni italiane.
    private func suggestions(for text: String) -> [String] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        var pool: [String] = []
        for s in edits.values.sorted() + commonItalianSubjects
            where !s.isEmpty && seen.insert(s.lowercased()).inserted { pool.append(s) }
        return pool.filter { $0.lowercased().contains(q) && $0.lowercased() != q }.prefix(6).map { $0 }
    }

    /// Conferma la materia di una lezione e la propaga alle altre ore dello
    /// stesso docente.
    private func commit(_ value: String, for lesson: Lesson) {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        autoFilled.remove(lesson.id)
        guard !lesson.teacher.isEmpty else { return }
        let out = propagateSubject(edits: edits, autoFilled: autoFilled, lessons: allLessons,
                                   teacher: lesson.teacher, subject: v, sourceId: lesson.id)
        edits = out.edits
        autoFilled = out.autoFilled
    }
}

/// Alert condiviso «insegna più di una materia?» per l'editor materie.
struct MultiSubjectAlert: ViewModifier {
    @Binding var pendingEdit: PendingSubjectEdit?
    @Binding var edits: [String: String]
    @Binding var autoFilled: Set<String>
    @Binding var multiSubjectTeachers: Set<String>

    func body(content: Content) -> some View {
        content.alert(item: $pendingEdit) { p in
            Alert(
                title: Text("\(p.teacher) insegna più di una materia?"),
                message: Text("Se sì, questa ora può avere una materia diversa; le altre ore del docente restano invariate."),
                primaryButton: .default(Text("Sì")) {
                    multiSubjectTeachers.insert(p.teacher)
                    autoFilled.remove(p.lessonId)
                },
                secondaryButton: .cancel(Text("No")) {
                    edits[p.lessonId] = p.oldValue
                }
            )
        }
    }
}

/// Presentata dopo un import parziale: spiega quale elemento manca e lascia
/// scegliere all'utente per quali classi completare i dati a mano.
struct ImportReviewView: View {
    @ObservedObject var store: ScheduleStore
    let missing: ScheduleField
    var onOpenBuilder: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selectedClasses: Set<String> = []
    @State private var editing = false
    @State private var edits: [String: String] = [:]      // lesson id -> valore
    @State private var classRenames: [String: String] = [:]
    // Materie: campi auto-compilati dalla propagazione per docente, docenti
    // confermati "multi-materia" e modifica in attesa di conferma.
    @State private var autoFilled: Set<String> = []
    @State private var multiSubjectTeachers: Set<String> = []
    @State private var pendingEdit: PendingSubjectEdit? = nil
    @FocusState private var focusedLesson: String?

    private var schedule: ScheduleData { store.schedule ?? .empty }

    private var missingDescription: String {
        switch missing {
        case .teacher: return "Nel PDF non sono indicati i docenti."
        case .subject: return "Nel PDF non sono indicate le materie."
        case .classes: return "Nel PDF non è indicato il nome della classe."
        case .dayTime: return "Nel PDF mancano giorni e ore delle lezioni."
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground(section: .orario)
                if editing {
                    completionEditor
                } else {
                    classPicker
                }
            }
            .navigationTitle("Import parziale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Più tardi") { close() }
                }
            }
        }
    }

    // MARK: Step 1 — scelta delle classi

    private var classPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Orario importato", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(AuroraSection.orario.accent)
                    Text(missingDescription)
                        .font(.subheadline)
                    Text(missing == .dayTime
                         ? "Puoi assegnare giorni e ore con la creazione manuale."
                         : "Scegli tu per quali classi completare i dati: le altre restano come nel PDF.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .auroraCard()

                if missing == .dayTime {
                    Button {
                        close()
                        onOpenBuilder?()
                    } label: {
                        Label("Apri la creazione manuale", systemImage: "square.and.pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .auroraProminent(.orario)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Classi da completare")
                            .font(.subheadline.weight(.semibold))
                        FlowLayoutChips(items: schedule.classes,
                                        selected: $selectedClasses)
                        HStack {
                            Button(selectedClasses.count == schedule.classes.count ? "Nessuna" : "Tutte") {
                                if selectedClasses.count == schedule.classes.count {
                                    selectedClasses.removeAll()
                                } else {
                                    selectedClasses = Set(schedule.classes)
                                }
                            }
                            .font(.footnote.weight(.medium))
                            Spacer()
                        }
                    }
                    .padding(18)
                    .auroraCard()

                    Button {
                        editing = true
                    } label: {
                        Label("Completa \(selectedClasses.count) class\(selectedClasses.count == 1 ? "e" : "i")",
                              systemImage: "pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .auroraProminent(.orario)
                    .disabled(selectedClasses.isEmpty)
                    .opacity(selectedClasses.isEmpty ? 0.45 : 1)
                }
            }
            .padding(16)
        }
    }

    // MARK: Step 2 — completamento dei dati

    private var completionEditor: some View {
        List {
            ForEach(schedule.classes.filter { selectedClasses.contains($0) }, id: \.self) { cls in
                if missing == .classes {
                    Section("Nome della classe") {
                        TextField("Es. 5GSA", text: Binding(
                            get: { classRenames[cls] ?? "" },
                            set: { classRenames[cls] = $0 }
                        ))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    }
                    .listRowBackground(Color.sectionCard)
                } else if missing == .subject {
                    SubjectCompletionSection(
                        className: cls,
                        lessons: lessons(for: cls),
                        allLessons: schedule.lessons,
                        edits: $edits,
                        autoFilled: $autoFilled,
                        multiSubjectTeachers: $multiSubjectTeachers,
                        pendingEdit: $pendingEdit,
                        focusedLesson: $focusedLesson
                    )
                } else {
                    Section(cls) {
                        ForEach(lessons(for: cls)) { lesson in
                            teacherRow(lesson)
                        }
                    }
                    .listRowBackground(Color.sectionCard)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .modifier(MultiSubjectAlert(pendingEdit: $pendingEdit,
                                    edits: $edits,
                                    autoFilled: $autoFilled,
                                    multiSubjectTeachers: $multiSubjectTeachers))
        .safeAreaInset(edge: .bottom) {
            Button {
                apply()
            } label: {
                Label("Salva", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .auroraProminent(.orario)
            .padding(16)
        }
    }

    /// Riga semplice per il completamento dei docenti mancanti.
    private func teacherRow(_ lesson: Lesson) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(lesson.dayLabel) · \(lesson.startTime)")
                    .font(.callout)
                Text(lesson.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Docente", text: Binding(
                get: { edits[lesson.id] ?? "" },
                set: { edits[lesson.id] = $0 }
            ))
            .multilineTextAlignment(.trailing)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.characters)
            .frame(maxWidth: 150)
        }
    }

    private func lessons(for cls: String) -> [Lesson] {
        schedule.lessons
            .filter { $0.className == cls }
            .sorted {
                let d0 = weekOrder.firstIndex(of: $0.day) ?? 0
                let d1 = weekOrder.firstIndex(of: $1.day) ?? 0
                return d0 != d1 ? d0 < d1 : $0.period < $1.period
            }
    }

    private func apply() {
        var s = schedule
        if missing == .classes {
            var renames: [String: String] = [:]
            for (old, new) in classRenames {
                let cleaned = new.trimmingCharacters(in: .whitespaces).uppercased()
                if !cleaned.isEmpty { renames[old] = cleaned }
            }
            s.lessons = s.lessons.map { l in
                var l = l
                if let n = renames[l.className] { l.className = n }
                return l
            }
            s.classes = s.classes.map { renames[$0] ?? $0 }
        } else {
            s.lessons = s.lessons.map { l in
                var l = l
                if let v = edits[l.id]?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
                    if missing == .teacher { l.teacher = v.uppercased() } else { l.subject = v }
                }
                return l
            }
            let teachers = Set(s.lessons.map { $0.teacher }.filter { !$0.isEmpty })
            s.teachers = teachers.sorted { $0.compare($1, locale: Locale(identifier: "it")) == .orderedAscending }
        }
        store.update(applyManualEdits(s))
        close()
    }

    private func close() {
        store.pendingCompletion = nil
        dismiss()
    }
}

/// Chips selezionabili disposti a bandiera.
struct FlowLayoutChips: View {
    let items: [String]
    @Binding var selected: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                let isOn = selected.contains(item)
                Button {
                    if isOn { selected.remove(item) } else { selected.insert(item) }
                } label: {
                    Text(item)
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            isOn ? AnyShapeStyle(AuroraSection.orario.gradient)
                                 : AnyShapeStyle(Color.primary.opacity(0.06)),
                            in: Capsule()
                        )
                        .foregroundStyle(isOn ? .white : .primary)
                        .overlay(Capsule().strokeBorder(.white.opacity(isOn ? 0.25 : 0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
