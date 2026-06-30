import SwiftUI

struct MainScheduleView: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var notesStore: NotesStore
    @Binding var targetMode: TargetMode
    @Binding var viewMode: ViewMode
    @Binding var selectedClass: String
    @Binding var teacherQuery: String
    @Binding var clock: Date
    @Binding var showFilePicker: Bool
    var isActive: Bool = true
    var gradesStore: GradesStore? = nil

    @AppStorage("useLiveTime") private var useLiveTime = true
    @AppStorage("manualDayRaw") private var manualDayRaw = "monday"
    @AppStorage("manualTime") private var manualTime = "08:10"

    let onLessonCountTap: () -> Void

    @State private var showTeacherMenu = false
    @State private var showSettings = false
    @State private var showQuickTimePicker = false
    @State private var showChangePDFConfirm = false
    @State private var noteContext: NoteCreationContext? = nil
    @State private var showDBDisclaimer = false
    @State private var showDBEditor = false
    @State private var dbEditTarget: String? = nil
    @FocusState private var teacherFieldFocused: Bool

    var schedule: ScheduleData { store.schedule ?? .empty }

    var manualDay: DayId {
        get { DayId(rawValue: manualDayRaw) ?? .monday }
        nonmutating set { manualDayRaw = newValue.rawValue }
    }

    var activeDay: DayId? {
        useLiveTime ? dayFromDate(clock) : DayId(rawValue: manualDayRaw)
    }

    var activeTime: String {
        useLiveTime ? timeFromDate(clock) : manualTime
    }

    var selectedTeacher: String? {
        resolveTeacher(schedule.teachers, query: teacherQuery)
    }

    var filteredTeachers: [String] {
        let q = teacherQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return schedule.teachers }
        return schedule.teachers.filter { $0.lowercased().contains(q) }
    }

    var targetLessons: [Lesson] {
        schedule.lessons.filter { lesson in
            targetMode == .class_
                ? lesson.className == selectedClass
                : selectedTeacher.map { lesson.teacher == $0 } ?? false
        }
    }

    var schoolTimes: [String] {
        guard let last = schedule.periods.last else { return [] }
        return schedule.periods.map { $0.startTime } + [last.endTime]
    }

    var currentLesson: Lesson? {
        findCurrentLesson(targetLessons, day: activeDay, time: activeTime)
    }

    var nextLesson: Lesson? {
        findNextLesson(targetLessons, day: activeDay, time: activeTime, current: currentLesson)
    }

    var dayForDayView: DayId { useLiveTime ? (activeDay ?? .monday) : manualDay }

    var dayPlan: [(period: Period, lessons: [Lesson])] {
        schedule.periods.map { period in
            let day = dayForDayView
            let ls = targetLessons
                .filter { $0.day == day && $0.startTime == period.startTime }
                .sorted { $0.className.compare($1.className, locale: Locale(identifier: "it")) == .orderedAscending }
            return (period, ls)
        }
    }

    var exportURL: URL? { store.exportScheduleURL() }

    var body: some View {
        ZStack(alignment: .top) {
                // Subtle gradient header
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.10), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 220)
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        statusStrip
                        controlPanel
                        if viewMode != .week { timeIndicator }

                        switch viewMode {
                        case .now:
                            NowView(
                                currentLesson: currentLesson,
                                nextLesson: nextLesson,
                                targetMode: targetMode,
                                activeDay: activeDay,
                                activeTime: activeTime,
                                schoolTimes: schoolTimes,
                                onOpenWeek: { withAnimation { viewMode = .week } },
                                onJumpToLesson: jumpToLessonTime,
                                onAddNote: { day, time, teacher, cls in addNoteContext(day: day, time: time, teacher: teacher, cls: cls) }
                            )
                        case .day:
                            DayView(
                                dayPlan: dayPlan,
                                dayLabel: schedule.days.first { $0.id == dayForDayView }?.label ?? "",
                                targetName: targetMode == .class_ ? selectedClass : (selectedTeacher ?? ""),
                                targetMode: targetMode,
                                dayId: dayForDayView,
                                onOpenCounterpart: openCounterpartDay,
                                onJumpToLesson: jumpToLessonTime,
                                onAddNote: { day, time, teacher, cls in addNoteContext(day: day, time: time, teacher: teacher, cls: cls) }
                            )
                        case .week:
                            WeekView(
                                schedule: schedule,
                                targetLessons: targetLessons,
                                targetMode: targetMode,
                                targetName: targetMode == .class_ ? selectedClass : (selectedTeacher ?? ""),
                                onOpenCounterpart: openCounterpartWeek,
                                onAddNote: { day, time, teacher, cls in addNoteContext(day: day, time: time, teacher: teacher, cls: cls) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(.secondarySystemGroupedBackground).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if isActive { toolbarContent } }
            .sensoryFeedback(.selection, trigger: viewMode)
            .sensoryFeedback(.selection, trigger: targetMode)
            .sensoryFeedback(.selection, trigger: selectedClass)
            .sensoryFeedback(.selection, trigger: selectedTeacher)
            .sheet(isPresented: $showSettings) {
                SettingsView(store: store, notesStore: notesStore, gradesStore: gradesStore, showFilePicker: $showFilePicker)
            }
            .sheet(item: $noteContext) { ctx in
                NoteEditorSheet(store: notesStore, context: ctx, schedule: schedule, subjects: gradesStore?.subjects ?? [])
            }
            .alert("Cambiare il PDF?", isPresented: $showChangePDFConfirm) {
                Button("Continua", role: .destructive) { showFilePicker = true }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("L'orario attuale verrà sostituito con il nuovo file.")
            }
            .alert("Modifica database", isPresented: $showDBDisclaimer) {
                Button("Annulla", role: .cancel) {}
                Button("Continua", role: .destructive) { showDBEditor = true }
            } message: {
                Text("Sei sicuro di voler modificare il database? Modifiche non corrette potrebbero impedire il corretto funzionamento dell'app.")
            }
            .sheet(isPresented: $showDBEditor) {
                NavigationStack {
                    DatabaseEditorView(store: store, scrollTarget: dbEditTarget)
                }
            }
            .sheet(isPresented: $showQuickTimePicker) {
                QuickTimePickerSheet(
                    useLiveTime: $useLiveTime,
                    manualDayRaw: $manualDayRaw,
                    manualTime: $manualTime,
                    schedule: schedule
                )
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let url = exportURL {
                ShareLink(
                    item: url,
                    preview: SharePreview(
                        "Orario \(schedule.sourceName)",
                        image: Image(systemName: "calendar.badge.clock")
                    )
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
        }
    }

    // MARK: - Status strip

    var statusStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: onLessonCountTap) {
                    StatPill(icon: "book.closed", value: "\(schedule.lessons.count)", label: "lezioni", color: .purple)
                }
                .buttonStyle(.plain)
                Button { dbEditTarget = "classi"; showDBDisclaimer = true } label: {
                    StatPill(icon: "graduationcap.fill", value: "\(schedule.classes.count)", label: "classi", color: .blue)
                }
                .buttonStyle(.plain)
                Button { dbEditTarget = "docenti"; showDBDisclaimer = true } label: {
                    StatPill(icon: "person.fill", value: "\(schedule.teachers.count)", label: "docenti", color: .orange)
                }
                .buttonStyle(.plain)

                Button {
                    showChangePDFConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(schedule.sourceName)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Control panel

    var panelAccent: Color { targetMode == .class_ ? .blue : .orange }

    var controlPanel: some View {
        VStack(spacing: 10) {
            Picker("Tipo", selection: $targetMode.animation()) {
                Label("Classe", systemImage: "graduationcap").tag(TargetMode.class_)
                Label("Docente", systemImage: "person").tag(TargetMode.teacher)
            }
            .pickerStyle(.segmented)

            if targetMode == .class_ {
                HStack {
                    Image(systemName: "graduationcap.fill")
                        .foregroundStyle(panelAccent)
                        .frame(width: 24)
                    Picker("Classe", selection: $selectedClass) {
                        ForEach(schedule.classes, id: \.self) { Text($0).tag($0) }
                    }
                    .tint(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(panelAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(panelAccent.opacity(0.25), lineWidth: 1))
            } else {
                TeacherPickerField(
                    query: $teacherQuery,
                    focused: _teacherFieldFocused,
                    showMenu: $showTeacherMenu,
                    filteredTeachers: filteredTeachers,
                    selectedTeacher: selectedTeacher,
                    onSelect: { teacher in teacherQuery = teacher; showTeacherMenu = false },
                    accentColor: panelAccent
                )
            }

            Picker("Vista", selection: $viewMode) {
                Label("Adesso", systemImage: "clock").tag(ViewMode.now)
                Label("Giorno", systemImage: "calendar.day.timeline.left").tag(ViewMode.day)
                Label("Settimana", systemImage: "calendar").tag(ViewMode.week)
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(.regularMaterial)
                .overlay {
                    LinearGradient(
                        colors: [panelAccent.opacity(0.10), panelAccent.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(panelAccent.opacity(0.20), lineWidth: 1)
                }
        }
        .animation(.easeInOut(duration: 0.25), value: targetMode)
    }

    // MARK: - Time indicator (compact)

    var timeIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: useLiveTime ? "clock.arrow.circlepath" : "clock.badge.xmark")
                .foregroundStyle(useLiveTime ? .green : .orange)
                .font(.subheadline)

            if viewMode == .day {
                let dayLabel = schedule.days.first { $0.id == manualDay }?.label ?? ""
                Text(dayLabel)
                    .font(.subheadline.weight(.medium))
            } else {
                let currentDayLabel = schedule.days.first { $0.id == activeDay }?.label ?? (useLiveTime ? "Weekend" : "—")
                if useLiveTime {
                    Text(currentDayLabel)
                        .font(.subheadline.weight(.medium))
                    Text("·")
                    Text(activeTime)
                        .font(.subheadline.monospacedDigit())
                } else {
                    Text(currentDayLabel)
                        .font(.subheadline.weight(.medium))
                    Text("·")
                    Text(activeTime)
                        .font(.subheadline.monospacedDigit())
                }
            }

            Spacer()

            Button {
                showQuickTimePicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: useLiveTime ? "clock.arrow.circlepath" : "pencil")
                        .font(.caption2)
                    Text(useLiveTime ? "Live" : "Manuale")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(useLiveTime ? .green : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((useLiveTime ? Color.green : Color.orange).opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    func addNoteContext(day: DayId? = nil, time: String? = nil, teacher: String? = nil, cls: String? = nil) {
        noteContext = NoteCreationContext(day: day, time: time, teacherTag: teacher, classTag: cls)
    }

    func jumpToLessonTime(day: DayId, time: String) {
        useLiveTime = false
        manualDayRaw = day.rawValue
        manualTime = time
        withAnimation { viewMode = .now }
    }

    func openCounterpartDay(_ lesson: Lesson) {
        manualDayRaw = lesson.day.rawValue
        withAnimation { viewMode = .day }
        if targetMode == .class_ { targetMode = .teacher; teacherQuery = lesson.teacher }
        else { targetMode = .class_; selectedClass = lesson.className }
    }

    func openCounterpartWeek(_ lesson: Lesson) {
        withAnimation { viewMode = .week }
        if targetMode == .class_ { targetMode = .teacher; teacherQuery = lesson.teacher }
        else { targetMode = .class_; selectedClass = lesson.className }
    }
}

// MARK: - Stat pill

struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
            Text(value)
                .fontWeight(.semibold)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - Teacher picker

struct TeacherPickerField: View {
    @Binding var query: String
    @FocusState var focused: Bool
    @Binding var showMenu: Bool
    let filteredTeachers: [String]
    let selectedTeacher: String?
    let onSelect: (String) -> Void
    var accentColor: Color = .orange

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(accentColor)
                    .frame(width: 24)
                TextField("Es. GRECO", text: $query)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.done)
                    .onSubmit {
                        if let first = filteredTeachers.first { onSelect(first) }
                    }
                    .onChange(of: focused) { _, f in showMenu = f }
                    .onChange(of: query) { _, _ in if focused { showMenu = true } }
                if !query.isEmpty {
                    Button { query = ""; showMenu = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accentColor.opacity(0.25), lineWidth: 1))

            if showMenu && focused && !filteredTeachers.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredTeachers, id: \.self) { teacher in
                            Button {
                                onSelect(teacher)
                                focused = false
                            } label: {
                                HStack {
                                    Text(teacher)
                                        .font(.callout)
                                        .foregroundColor(teacher == selectedTeacher ? .accentColor : .primary)
                                    Spacer()
                                    if teacher == selectedTeacher {
                                        Image(systemName: "checkmark").foregroundStyle(.tint).font(.caption)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if teacher != filteredTeachers.last {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .zIndex(10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Quick time picker sheet

struct QuickTimePickerSheet: View {
    @Binding var useLiveTime: Bool
    @Binding var manualDayRaw: String
    @Binding var manualTime: String
    let schedule: ScheduleData
    @Environment(\.dismiss) private var dismiss

    var manualDay: Binding<DayId> {
        Binding(
            get: { DayId(rawValue: manualDayRaw) ?? .monday },
            set: { manualDayRaw = $0.rawValue }
        )
    }

    var schoolTimes: [String] {
        guard let last = schedule.periods.last else { return [] }
        return schedule.periods.map { $0.startTime } + [last.endTime]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $useLiveTime) {
                        Label("Usa ora corrente", systemImage: "clock.arrow.circlepath")
                    }
                } footer: {
                    Text(useLiveTime ? "L'orario si aggiorna automaticamente ogni 30 secondi." : "Imposta un giorno e un'ora manualmente.")
                }

                if !useLiveTime {
                    Section("Giorno") {
                        Picker("Giorno", selection: manualDay) {
                            ForEach(schedule.days) { day in
                                Text(day.label).tag(day.id)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Ora") {
                        Picker("Ora", selection: $manualTime) {
                            ForEach(schoolTimes, id: \.self) { time in
                                Text(time).tag(time)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                    }
                }
            }
            .navigationTitle("Orario di consultazione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
