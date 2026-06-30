import SwiftUI

// MARK: - Database editor

/// Lets the user fix the parsed schedule: rename/add teachers & classes, change
/// the time slots (start + duration), and full CRUD on individual lessons.
/// Works on a draft copy; on Save it's persisted via `store.update(applyManualEdits(...))`
/// which keeps custom times (skips the fixed-time normalization).
struct DatabaseEditorView: View {
    @ObservedObject var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ScheduleData
    @State private var firstStartDate = Date()
    @State private var slotMinutes = 60
    @State private var showResetConfirm = false

    private let original: ScheduleData
    private let scrollTarget: String?

    // Sheets
    @State private var rename: RenameTarget?
    @State private var lessonEdit: LessonEditTarget?

    init(store: ScheduleStore, scrollTarget: String? = nil) {
        _store = ObservedObject(initialValue: store)
        let current = store.schedule ?? .empty
        _draft = State(initialValue: current)
        original = current
        self.scrollTarget = scrollTarget
    }

    private var sortedPeriods: [Period] { draft.periods.sorted { $0.number < $1.number } }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            timeSlotsSection
            teachersSection.id("docenti")
            classesSection.id("classi")
            lessonsSection
        }
        .navigationTitle("Modifica database")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Annulla") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Salva") {
                    store.update(applyManualEdits(draft))
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) { showResetConfirm = true } label: {
                    Label("Ripristina modifiche", systemImage: "arrow.uturn.backward")
                }
            }
        }
        .onAppear {
            loadTimeState()
            if let t = scrollTarget {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation { proxy.scrollTo(t, anchor: .top) }
                }
            }
        }
        .alert("Ripristinare le modifiche?", isPresented: $showResetConfirm) {
            Button("Annulla", role: .cancel) {}
            Button("Ripristina", role: .destructive) {
                draft = original
                loadTimeState()
            }
        } message: {
            Text("Tutte le modifiche fatte in questa schermata verranno annullate.")
        }
        .sheet(item: $rename) { target in
            TextEditSheet(title: target.title, initial: target.current) { newValue in
                applyRename(target, to: newValue)
            }
        }
        .sheet(item: $lessonEdit) { target in
            LessonEditorSheet(
                lesson: target.lesson,
                days: dayOrder,
                periods: sortedPeriods,
                classes: draft.classes,
                teachers: draft.teachers
            ) { saved in
                applyLesson(saved, replacing: target.lesson)
            }
        }
        }
    }

    // MARK: Fasce orarie

    private var timeSlotsSection: some View {
        Section {
            DatePicker("Inizio 1ª ora", selection: $firstStartDate, displayedComponents: .hourAndMinute)
                .onChange(of: firstStartDate) { _, _ in recomputePeriods() }
            Stepper("Durata: \(slotMinutes) min", value: $slotMinutes, in: 30...90, step: 5)
                .onChange(of: slotMinutes) { _, _ in recomputePeriods() }
            ForEach(sortedPeriods) { p in
                HStack {
                    Text("\(p.number)ª ora").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(p.startTime)–\(p.endTime)").monospacedDigit()
                }
                .font(.callout)
            }
        } header: {
            Text("Fasce orarie")
        } footer: {
            Text("Le ore vengono calcolate a partire dall'inizio e dalla durata.")
        }
    }

    // MARK: Docenti

    private var teachersSection: some View {
        Section {
            ForEach(draft.teachers, id: \.self) { teacher in
                Button {
                    rename = RenameTarget(kind: .teacher, current: teacher)
                } label: {
                    HStack {
                        Text(teacher).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            Button {
                rename = RenameTarget(kind: .teacher, current: "")
            } label: {
                Label("Aggiungi docente", systemImage: "plus")
            }
        } header: {
            Text("Docenti (\(draft.teachers.count))")
        }
    }

    // MARK: Classi

    private var classesSection: some View {
        Section {
            ForEach(draft.classes, id: \.self) { cls in
                Button {
                    rename = RenameTarget(kind: .class_, current: cls)
                } label: {
                    HStack {
                        Text(cls).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            Button {
                rename = RenameTarget(kind: .class_, current: "")
            } label: {
                Label("Aggiungi classe", systemImage: "plus")
            }
        } header: {
            Text("Classi (\(draft.classes.count))")
        }
    }

    // MARK: Lezioni

    @ViewBuilder
    private var lessonsSection: some View {
        ForEach(dayOrder, id: \.self) { day in
            let lessons = draft.lessons
                .filter { $0.day == day }
                .sorted { minutesFromMidnight($0.startTime) < minutesFromMidnight($1.startTime) }
            if !lessons.isEmpty {
                Section(dayLabels[day] ?? day.rawValue) {
                    ForEach(lessons) { lesson in
                        Button {
                            lessonEdit = LessonEditTarget(lesson: lesson)
                        } label: {
                            lessonRow(lesson)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { lessons[$0].id }
                        draft.lessons.removeAll { ids.contains($0.id) }
                    }
                }
            }
        }
        Section {
            Button {
                lessonEdit = LessonEditTarget(lesson: nil)
            } label: {
                Label("Aggiungi lezione", systemImage: "plus")
            }
        }
    }

    private func lessonRow(_ lesson: Lesson) -> some View {
        HStack(spacing: 10) {
            Text(lesson.startTime).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.className).font(.callout.weight(.medium)).foregroundStyle(.primary)
                Text(lesson.teacher).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Logic

    private func loadTimeState() {
        let periods = sortedPeriods
        guard let first = periods.first else { return }
        firstStartDate = dateFrom(first.startTime)
        if periods.count >= 2 {
            let diff = minutesFromMidnight(periods[1].startTime) - minutesFromMidnight(periods[0].startTime)
            slotMinutes = min(max(diff, 30), 90)
        } else {
            let diff = minutesFromMidnight(first.endTime) - minutesFromMidnight(first.startTime)
            slotMinutes = min(max(diff, 30), 90)
        }
    }

    private func recomputePeriods() {
        let cal = Calendar.current
        let firstMins = cal.component(.hour, from: firstStartDate) * 60 + cal.component(.minute, from: firstStartDate)
        let ordered = sortedPeriods
        var updated: [Period] = []
        for (i, p) in ordered.enumerated() {
            let start = firstMins + i * slotMinutes
            updated.append(Period(number: p.number, startTime: hhmm(start), endTime: hhmm(start + slotMinutes)))
        }
        draft.periods = updated
    }

    private func applyRename(_ target: RenameTarget, to raw: String) {
        let new = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty else { return }
        switch target.kind {
        case .teacher:
            if target.current.isEmpty {
                if !draft.teachers.contains(new) { draft.teachers.append(new) }
            } else {
                for i in draft.lessons.indices where draft.lessons[i].teacher == target.current {
                    draft.lessons[i].teacher = new
                }
                draft.teachers = dedup(draft.teachers.map { $0 == target.current ? new : $0 })
            }
        case .class_:
            if target.current.isEmpty {
                if !draft.classes.contains(new) { draft.classes.append(new) }
            } else {
                for i in draft.lessons.indices where draft.lessons[i].className == target.current {
                    draft.lessons[i].className = new
                }
                draft.classes = dedup(draft.classes.map { $0 == target.current ? new : $0 })
            }
        }
    }

    private func applyLesson(_ saved: Lesson, replacing original: Lesson?) {
        var lesson = saved
        // Align times to the chosen period; keep ids consistent.
        if let p = sortedPeriods.first(where: { $0.number == lesson.period }) {
            lesson.startTime = p.startTime
            lesson.endTime = p.endTime
        }
        lesson.dayLabel = dayLabels[lesson.day] ?? lesson.dayLabel
        if let original, let idx = draft.lessons.firstIndex(where: { $0.id == original.id }) {
            draft.lessons[idx] = lesson
        } else {
            draft.lessons.append(lesson)
        }
        if !lesson.className.isEmpty && !draft.classes.contains(lesson.className) {
            draft.classes.append(lesson.className)
        }
        if !lesson.teacher.isEmpty && !draft.teachers.contains(lesson.teacher) {
            draft.teachers.append(lesson.teacher)
        }
    }

    private func dedup(_ arr: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for x in arr where seen.insert(x).inserted { out.append(x) }
        return out.sorted()
    }

    private func hhmm(_ mins: Int) -> String {
        String(format: "%02d:%02d", (mins / 60) % 24, mins % 60)
    }

    private func dateFrom(_ hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var c = DateComponents()
        c.hour = parts.first ?? 8
        c.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: c) ?? Date()
    }
}

// MARK: - Rename sheet

private enum ItemKind { case teacher, class_ }

private struct RenameTarget: Identifiable {
    let id = UUID()
    let kind: ItemKind
    let current: String
    var title: String {
        let adding = current.isEmpty
        switch kind {
        case .teacher: return adding ? "Nuovo docente" : "Modifica docente"
        case .class_:  return adding ? "Nuova classe" : "Modifica classe"
        }
    }
}

private struct TextEditSheet: View {
    let title: String
    let initial: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $text)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") { onSave(text); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { text = initial }
        }
    }
}

// MARK: - Lesson editor sheet

private struct LessonEditTarget: Identifiable {
    let id = UUID()
    let lesson: Lesson?
}

private struct LessonEditorSheet: View {
    let lesson: Lesson?
    let days: [DayId]
    let periods: [Period]
    let classes: [String]
    let teachers: [String]
    let onSave: (Lesson) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var day: DayId = .monday
    @State private var period: Int = 1
    @State private var className = ""
    @State private var teacher = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Giorno", selection: $day) {
                    ForEach(days, id: \.self) { d in
                        Text(dayLabels[d] ?? d.rawValue).tag(d)
                    }
                }
                Picker("Ora", selection: $period) {
                    ForEach(periods) { p in
                        Text("\(p.number)ª (\(p.startTime))").tag(p.number)
                    }
                }
                Section("Classe") {
                    TextField("Es. 5GSA", text: $className)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    pickRow(classes, onPick: { className = $0 })
                }
                Section("Docente") {
                    TextField("Cognome", text: $teacher)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    pickRow(teachers, onPick: { teacher = $0 })
                }
            }
            .navigationTitle(lesson == nil ? "Nuova lezione" : "Modifica lezione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") { save() }
                        .fontWeight(.semibold)
                        .disabled(className.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: setup)
        }
    }

    @ViewBuilder
    private func pickRow(_ items: [String], onPick: @escaping (String) -> Void) -> some View {
        if !items.isEmpty {
            Menu {
                ForEach(items, id: \.self) { item in
                    Button(item) { onPick(item) }
                }
            } label: {
                Label("Scegli esistente", systemImage: "list.bullet")
                    .font(.caption)
            }
        }
    }

    private func setup() {
        if let lesson {
            day = lesson.day
            period = lesson.period
            className = lesson.className
            teacher = lesson.teacher
        } else {
            day = days.first ?? .monday
            period = periods.first?.number ?? 1
        }
    }

    private func save() {
        let p = periods.first { $0.number == period }
        let new = Lesson(
            id: lesson?.id ?? UUID().uuidString,
            className: className.trimmingCharacters(in: .whitespaces),
            teacher: teacher.trimmingCharacters(in: .whitespaces),
            day: day,
            dayLabel: dayLabels[day] ?? day.rawValue,
            period: period,
            startTime: p?.startTime ?? "08:00",
            endTime: p?.endTime ?? "09:00",
            sourcePage: lesson?.sourcePage ?? 0
        )
        onSave(new)
        dismiss()
    }
}
