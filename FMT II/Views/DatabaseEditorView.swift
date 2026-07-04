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
            Section {
                AuroraTitle(
                    title: "Dati orario",
                    subtitle: "\(draft.sourceName.replacingOccurrences(of: ".pdf", with: "")) · \(draft.lessons.count) lezioni · \(draft.teachers.count) docenti · \(draft.classes.count) classi"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }
            timeSlotsSection
            teachersSection.id("docenti")
            classesSection.id("classi")
            lessonsSection
        }
        .scrollContentBackground(.hidden)
        .background { AuroraBackground(section: .orario) }
        .navigationTitle("")
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
            HStack {
                Text("Inizio 1ª ora").font(.system(size: 14.5, weight: .semibold))
                Spacer()
                DatePicker("", selection: $firstStartDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .onChange(of: firstStartDate) { _, _ in recomputePeriods() }
            }
            Stepper(value: $slotMinutes, in: 30...90, step: 5) {
                HStack {
                    Text("Durata lezione").font(.system(size: 14.5, weight: .semibold))
                    Spacer()
                    Text("\(slotMinutes) min")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color(hex: "#7CB3FF")!)
                }
            }
            .onChange(of: slotMinutes) { _, _ in recomputePeriods() }
            // Fasce calcolate, come chip (design 3e)
            ChipFlowLayout(spacing: 6) {
                ForEach(sortedPeriods) { p in
                    Text("\(p.number)ª · \(p.startTime)–\(p.endTime)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.06), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1))
                }
            }
            .padding(.vertical, 2)
        } header: {
            SettingsView.header("Fasce orarie")
        } footer: {
            Text("Calcolate da inizio e durata — nessun inserimento manuale.")
        }
        .listRowBackground(Color.sectionCard)
    }

    // MARK: Docenti

    private var teachersSection: some View {
        Section {
            entityChips(draft.teachers, kind: .teacher, addLabel: "Aggiungi")
        } header: {
            SettingsView.header("Docenti · \(draft.teachers.count)")
        } footer: {
            Text("Tocca un docente per rinominarlo ovunque nell'orario.")
        }
        .listRowBackground(Color.sectionCard)
    }

    /// Chip colorati per docenti/classi + chip "Aggiungi" tratteggiato (3e).
    private func entityChips(_ items: [String], kind: ItemKind, addLabel: String) -> some View {
        ChipFlowLayout(spacing: 7) {
            ForEach(items, id: \.self) { name in
                Button {
                    rename = RenameTarget(kind: kind, current: name)
                } label: {
                    Text(name)
                        .font(.system(size: 11.5, weight: .bold))
                        .kerning(0.3)
                        .foregroundStyle(entityTint(name).blended(with: .white, by: 0.45))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(entityTint(name).opacity(0.13), in: Capsule())
                        .overlay(Capsule().strokeBorder(entityTint(name).opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Button {
                rename = RenameTarget(kind: kind, current: "")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text(addLabel).font(.system(size: 11.5, weight: .bold))
                }
                .foregroundStyle(Color(hex: "#7DD3FC")!)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .overlay(Capsule().strokeBorder(Color(hex: "#7DD3FC")!.opacity(0.4),
                                                style: StrokeStyle(lineWidth: 1.4, dash: [4, 3])))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: Classi

    private var classesSection: some View {
        Section {
            entityChips(draft.classes, kind: .class_, addLabel: "Aggiungi")
        } header: {
            SettingsView.header("Classi · \(draft.classes.count)")
        } footer: {
            Text("Tocca una classe per rinominarla ovunque nell'orario.")
        }
        .listRowBackground(Color.sectionCard)
    }

    // MARK: Lezioni

    @ViewBuilder
    private var lessonsSection: some View {
        ForEach(dayOrder, id: \.self) { day in
            let lessons = draft.lessons
                .filter { $0.day == day }
                .sorted { minutesFromMidnight($0.startTime) < minutesFromMidnight($1.startTime) }
            if !lessons.isEmpty {
                Section {
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
                } header: {
                    SettingsView.header(dayLabels[day] ?? day.rawValue)
                }
                .listRowBackground(Color.sectionCard)
            }
        }
        Section {
            Button {
                lessonEdit = LessonEditTarget(lesson: nil)
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            LinearGradient(colors: [Color(hex: "#38BDF8")!, Color(hex: "#4E7CF6")!],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .shadow(color: Color(hex: "#3884F6")!.opacity(0.4), radius: 5, y: 2)
                    Text("Aggiungi lezione")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .listRowBackground(Color.sectionCard)
    }

    private func lessonRow(_ lesson: Lesson) -> some View {
        let display = lesson.subject.isEmpty ? lesson.teacher : lesson.subject
        return HStack(spacing: 10) {
            Text(lesson.startTime)
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(Color(hex: "#93C5FD")!)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(hex: "#60A5FA")!.opacity(0.13), in: Capsule())
            Text(lesson.className)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(entityTint(lesson.className).blended(with: .white, by: 0.45))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(entityTint(lesson.className).opacity(0.13), in: Capsule())
            Text(display)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
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
