import SwiftUI

// MARK: - Manual schedule builder (weekly grid)

/// Create or edit a schedule by hand: pick the class(es), the time slots, then
/// tap cells in a weekly grid to fill them. Subjects are required, teachers are
/// optional and auto-filled from a learned subject→teacher map. Produces a
/// `ScheduleData` with `edited = true` (so custom times are preserved).
struct ScheduleBuilderView: View {
    let onSave: (ScheduleData) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduleData
    @State private var selectedClass: String
    @State private var firstStartDate: Date
    @State private var slotMinutes: Int
    @State private var periodCount: Int
    @State private var includeSaturday: Bool
    @State private var showSetup: Bool
    @State private var cell: CellTarget?
    @State private var addingClass = false
    @State private var newClassName = ""

    private let timeColWidth: CGFloat = 48
    private let dayColWidth: CGFloat = 96
    private let rowHeight: CGFloat = 58

    init(existing: ScheduleData?, onSave: @escaping (ScheduleData) -> Void) {
        self.onSave = onSave
        let base = existing ?? Self.blank()
        _draft = State(initialValue: base)
        _selectedClass = State(initialValue: base.classes.first ?? "")
        _includeSaturday = State(initialValue: base.days.contains { $0.id == .saturday })
        let periods = base.periods.sorted { $0.number < $1.number }
        _periodCount = State(initialValue: max(periods.count, 1))
        let firstStart = periods.first?.startTime ?? "08:00"
        var comp = DateComponents()
        let p = firstStart.split(separator: ":").compactMap { Int($0) }
        comp.hour = p.first ?? 8; comp.minute = p.count > 1 ? p[1] : 0
        _firstStartDate = State(initialValue: Calendar.current.date(from: comp) ?? Date())
        if periods.count >= 2 {
            _slotMinutes = State(initialValue: min(max(minutesFromMidnight(periods[1].startTime) - minutesFromMidnight(periods[0].startTime), 30), 90))
        } else {
            _slotMinutes = State(initialValue: 60)
        }
        // Open setup automatically when starting from scratch (no class yet).
        _showSetup = State(initialValue: (base.classes.first ?? "").isEmpty)
    }

    private var activeDays: [DayId] { includeSaturday ? dayOrder + [.saturday] : dayOrder }
    private var sortedPeriods: [Period] { draft.periods.sorted { $0.number < $1.number } }
    private var canSave: Bool { !selectedClass.trimmingCharacters(in: .whitespaces).isEmpty && !draft.lessons.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            setupBar
            Divider()
            grid
        }
        .navigationTitle("Crea orario")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Salva") {
                    onSave(applyManualEdits(draft))
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(!canSave)
            }
        }
        .onAppear(perform: rebuildPeriodsAndDays)
        .sheet(item: $cell) { target in
            CellEditorSheet(
                subject: lesson(for: target)?.subject ?? "",
                teacher: lesson(for: target)?.teacher ?? "",
                subjectPool: subjectPool,
                teacherPool: draft.teachers,
                subjectTeachers: draft.subjectTeachers
            ) { subject, teacher in
                setCell(target, subject: subject, teacher: teacher)
            }
        }
        .alert("Aggiungi classe", isPresented: $addingClass) {
            TextField("Es. 5GSA", text: $newClassName)
            Button("Annulla", role: .cancel) { newClassName = "" }
            Button("Aggiungi") { addClass() }
        } message: {
            Text("Crea l'orario anche per un'altra classe.")
        }
    }

    // MARK: Setup bar

    private var setupBar: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    ForEach(draft.classes, id: \.self) { c in
                        Button { selectedClass = c } label: {
                            if c == selectedClass { Label(c.isEmpty ? "(senza nome)" : c, systemImage: "checkmark") }
                            else { Text(c.isEmpty ? "(senza nome)" : c) }
                        }
                    }
                    Divider()
                    Button { addingClass = true } label: { Label("Aggiungi classe", systemImage: "plus") }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "graduationcap.fill")
                        Text(selectedClass.isEmpty ? "Nome classe" : selectedClass).fontWeight(.semibold)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .foregroundStyle(selectedClass.isEmpty ? .secondary : .primary)
                }

                if selectedClass.isEmpty {
                    TextField("Es. 5GSA", text: classNameBinding)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }

                Spacer()
                Button { withAnimation { showSetup.toggle() } } label: {
                    Image(systemName: showSetup ? "chevron.up" : "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            if showSetup {
                VStack(spacing: 10) {
                    DatePicker("Inizio 1ª ora", selection: $firstStartDate, displayedComponents: .hourAndMinute)
                        .onChange(of: firstStartDate) { _, _ in rebuildPeriodsAndDays() }
                    Stepper("Ore al giorno: \(periodCount)", value: $periodCount, in: 1...12)
                        .onChange(of: periodCount) { _, _ in rebuildPeriodsAndDays() }
                    Stepper("Durata ora: \(slotMinutes) min", value: $slotMinutes, in: 30...90, step: 5)
                        .onChange(of: slotMinutes) { _, _ in rebuildPeriodsAndDays() }
                    Toggle("Includi sabato", isOn: $includeSaturday)
                        .onChange(of: includeSaturday) { _, _ in rebuildPeriodsAndDays() }
                }
                .font(.callout)
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
    }

    private var classNameBinding: Binding<String> {
        Binding(
            get: { selectedClass },
            set: { newValue in
                let old = selectedClass
                selectedClass = newValue
                // Rename the (empty) placeholder class and its lessons.
                if let idx = draft.classes.firstIndex(of: old) { draft.classes[idx] = newValue }
                for i in draft.lessons.indices where draft.lessons[i].className == old {
                    draft.lessons[i].className = newValue
                }
            }
        )
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("").frame(width: timeColWidth)
                    ForEach(activeDays, id: \.self) { day in
                        Text(shortLabel(day)).font(.caption.bold())
                            .frame(width: dayColWidth, height: 34)
                    }
                }
                Divider()
                ForEach(sortedPeriods) { period in
                    HStack(spacing: 0) {
                        VStack(spacing: 1) {
                            Text(period.startTime).font(.caption2.monospacedDigit().weight(.medium))
                            Text(period.endTime).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .frame(width: timeColWidth, height: rowHeight)

                        ForEach(activeDays, id: \.self) { day in
                            cellView(day: day, period: period)
                        }
                    }
                    Divider().padding(.leading, timeColWidth)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func cellView(day: DayId, period: Period) -> some View {
        let target = CellTarget(day: day, period: period.number)
        let l = lesson(for: target)
        return Button {
            cell = target
        } label: {
            VStack(spacing: 1) {
                if let l, !l.subject.isEmpty {
                    Text(l.subject).font(.caption2.weight(.semibold)).lineLimit(1)
                    if !l.teacher.isEmpty {
                        Text(l.teacher).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Image(systemName: "plus").font(.caption2).foregroundStyle(.quaternary)
                }
            }
            .frame(width: dayColWidth, height: rowHeight)
            .background((l?.subject.isEmpty == false) ? Color.accentColor.opacity(0.12) : Color.clear)
            .overlay(alignment: .trailing) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortLabel(_ day: DayId) -> String {
        ["monday": "Lun", "tuesday": "Mar", "wednesday": "Mer", "thursday": "Gio", "friday": "Ven", "saturday": "Sab"][day.rawValue] ?? day.rawValue
    }

    // MARK: Data helpers

    private var subjectPool: [String] {
        var seen = Set<String>(); var out: [String] = []
        for l in draft.lessons where !l.subject.isEmpty && seen.insert(l.subject.lowercased()).inserted { out.append(l.subject) }
        return out
    }

    private func lesson(for t: CellTarget) -> Lesson? {
        draft.lessons.first { $0.className == selectedClass && $0.day == t.day && $0.period == t.period }
    }

    private func setCell(_ t: CellTarget, subject: String, teacher: String) {
        let subj = subject.trimmingCharacters(in: .whitespaces)
        let teach = teacher.trimmingCharacters(in: .whitespaces)
        // Remove any existing lesson in this cell.
        draft.lessons.removeAll { $0.className == selectedClass && $0.day == t.day && $0.period == t.period }
        guard !subj.isEmpty else { return }

        let p = sortedPeriods.first { $0.number == t.period }
        draft.lessons.append(Lesson(
            id: UUID().uuidString,
            className: selectedClass,
            teacher: teach,
            day: t.day,
            dayLabel: dayLabels[t.day] ?? t.day.rawValue,
            period: t.period,
            startTime: p?.startTime ?? "08:00",
            endTime: p?.endTime ?? "09:00",
            sourcePage: 0,
            subject: subj
        ))
        if !teach.isEmpty {
            if !draft.teachers.contains(teach) { draft.teachers.append(teach) }
            draft.subjectTeachers[subj] = teach   // learn the pairing
        }
    }

    private func addClass() {
        let name = newClassName.trimmingCharacters(in: .whitespaces)
        newClassName = ""
        guard !name.isEmpty, !draft.classes.contains(name) else { return }
        draft.classes.append(name)
        selectedClass = name
    }

    private func rebuildPeriodsAndDays() {
        let cal = Calendar.current
        let firstMins = cal.component(.hour, from: firstStartDate) * 60 + cal.component(.minute, from: firstStartDate)
        draft.periods = (1...periodCount).map { n in
            let start = firstMins + (n - 1) * slotMinutes
            return Period(number: n, startTime: hhmm(start), endTime: hhmm(start + slotMinutes))
        }
        draft.days = activeDays.map { DayInfo(id: $0, label: dayLabels[$0] ?? $0.rawValue) }
        // Drop lessons whose period no longer exists.
        let valid = Set(1...periodCount)
        draft.lessons.removeAll { !valid.contains($0.period) }
    }

    private func hhmm(_ mins: Int) -> String {
        String(format: "%02d:%02d", (mins / 60) % 24, mins % 60)
    }

    static func blank() -> ScheduleData {
        ScheduleData(
            id: UUID().uuidString,
            sourceName: "Orario personale",
            importedAt: ISO8601DateFormatter().string(from: Date()),
            startsFrom: nil,
            days: dayOrder.map { DayInfo(id: $0, label: dayLabels[$0] ?? $0.rawValue) },
            periods: (1...6).map { Period(number: $0, startTime: hhmmStatic(480 + ($0 - 1) * 60), endTime: hhmmStatic(480 + $0 * 60)) },
            classes: [""],
            teachers: [],
            lessons: [],
            warnings: [],
            edited: true,
            subjectTeachers: [:]
        )
    }

    private static func hhmmStatic(_ mins: Int) -> String {
        String(format: "%02d:%02d", (mins / 60) % 24, mins % 60)
    }
}

private struct CellTarget: Identifiable {
    let day: DayId
    let period: Int
    var id: String { "\(day.rawValue)-\(period)" }
}

// MARK: - Cell editor

private struct CellEditorSheet: View {
    @State var subject: String
    @State var teacher: String
    let subjectPool: [String]
    let teacherPool: [String]
    let subjectTeachers: [String: String]
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var subjectFocused: Bool

    private func suggest(_ text: String, from pool: [String]) -> [String] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return pool.filter { $0.lowercased().contains(q) && $0.lowercased() != q }.prefix(6).map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Materia") {
                    TextField("Es. Matematica", text: $subject)
                        .autocorrectionDisabled()
                        .focused($subjectFocused)
                        .submitLabel(.done)
                        .onSubmit { autocompleteSubject() }
                        .onChange(of: subject) { _, newValue in
                            // Auto-fill the teacher when the subject is already known.
                            if teacher.isEmpty, let t = subjectTeachers[newValue] { teacher = t }
                        }
                    ForEach(suggest(subject, from: subjectPool), id: \.self) { s in
                        Button {
                            subject = s
                            if teacher.isEmpty, let t = subjectTeachers[s] { teacher = t }
                        } label: {
                            Label(s, systemImage: "arrow.turn.down.right").font(.callout)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Docente (facoltativo)") {
                    TextField("Cognome", text: $teacher)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .submitLabel(.done)
                        .onSubmit { if let f = suggest(teacher, from: teacherPool).first { teacher = f } }
                    ForEach(suggest(teacher, from: teacherPool), id: \.self) { t in
                        Button { teacher = t } label: {
                            Label(t, systemImage: "arrow.turn.down.right").font(.callout)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !subject.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        Button(role: .destructive) {
                            onSave("", "")
                            dismiss()
                        } label: {
                            Label("Svuota cella", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Lezione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") { onSave(subject, teacher); dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { subjectFocused = true }
        }
    }

    private func autocompleteSubject() {
        if let f = suggest(subject, from: subjectPool).first {
            subject = f
            if teacher.isEmpty, let t = subjectTeachers[f] { teacher = t }
        }
    }
}
