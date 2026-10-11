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
    @Environment(\.deviceLayout) private var layout
    // Cambia quando l'utente personalizza i colori: forza il refresh delle tinte.
    @AppStorage("entityColorsVersion") private var entityColorsVersion = 0
    @AppStorage("manualDayRaw") private var manualDayRaw = "monday"
    @AppStorage("manualTime") private var manualTime = "08:10"

    let onLessonCountTap: () -> Void

    @State private var showTeacherMenu = false
    @State private var showSettings = false
    @State private var headerHeight: CGFloat = 64
    @Environment(\.colorScheme) private var scheme
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

    /// Materie distinte nell'orario (vista adattiva quando mancano i docenti).
    var scheduleSubjects: [String] {
        Array(Set(schedule.lessons.map { $0.subject }.filter { !$0.isEmpty }))
            .sorted { $0.compare($1, locale: Locale(identifier: "it")) == .orderedAscending }
    }

    /// Vista adattiva: docenti riconosciuti -> filtro classe/docente;
    /// solo materie riconosciute -> filtro materia/classe.
    var usesSubjectEntities: Bool { schedule.teachers.isEmpty && !scheduleSubjects.isEmpty }

    var entityList: [String] { usesSubjectEntities ? scheduleSubjects : schedule.teachers }

    var selectedTeacher: String? {
        resolveTeacher(entityList, query: teacherQuery)
    }

    var filteredTeachers: [String] {
        let q = teacherQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entityList }
        return entityList.filter { $0.lowercased().contains(q) }
    }

    var targetLessons: [Lesson] {
        schedule.lessons.filter { lesson in
            targetMode == .class_
                ? lesson.className == selectedClass
                : selectedTeacher.map { usesSubjectEntities ? lesson.subject == $0 : lesson.teacher == $0 } ?? false
        }
    }

    /// Classe di cui mostrare le fasce: quella selezionata in vista classe,
    /// nil in vista docente (unione degli orari di tutte le classi).
    var periodClass: String? { targetMode == .class_ ? selectedClass : nil }

    var schoolTimes: [String] {
        schedule.timeSlots(forClass: periodClass)
    }

    var currentLesson: Lesson? {
        findCurrentLesson(targetLessons, day: activeDay, time: activeTime)
    }

    var nextLesson: Lesson? {
        findNextLesson(targetLessons, day: activeDay, time: activeTime, current: currentLesson)
    }

    var dayForDayView: DayId { useLiveTime ? (activeDay ?? .monday) : manualDay }

    var dayPlan: [(period: Period, lessons: [Lesson])] {
        schedule.displayPeriods(forClass: periodClass).map { period in
            let day = dayForDayView
            let ls = targetLessons
                .filter { $0.day == day && $0.startTime == period.startTime }
                .sorted { $0.className.compare($1.className, locale: Locale(identifier: "it")) == .orderedAscending }
            return (period, ls)
        }
    }

    var exportURL: URL? { store.exportScheduleURL() }

    /// "5GSA · Giovedì · 13:00" — sottotitolo del titolo grande (design 3a).
    var orarioSubtitle: String {
        let target = targetMode == .class_ ? selectedClass : (selectedTeacher ?? "—")
        let day = schedule.days.first { $0.id == activeDay }?.label ?? "Weekend"
        return "\(target) · \(day) · \(activeTime)"
    }

    /// Adesso / Giorno / Settimana (uguale in tutti i layout).
    @ViewBuilder
    private var scheduleContent: some View {
        let _ = entityColorsVersion
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
                onAddNote: { day, time, teacher, cls, subject in addNoteContext(day: day, time: time, teacher: teacher, cls: cls, subject: subject) }
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
                onAddNote: { day, time, teacher, cls, subject in addNoteContext(day: day, time: time, teacher: teacher, cls: cls, subject: subject) }
            )
        case .week:
            WeekView(
                schedule: schedule,
                periods: schedule.displayPeriods(forClass: periodClass),
                targetLessons: targetLessons,
                targetMode: targetMode,
                targetName: targetMode == .class_ ? selectedClass : (selectedTeacher ?? ""),
                onOpenCounterpart: openCounterpartWeek,
                onAddNote: { day, time, teacher, cls, subject in addNoteContext(day: day, time: time, teacher: teacher, cls: cls, subject: subject) }
            )
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
                Group {
                    if layout == .wide {
                        // iPad in orizzontale: controlli a sinistra, contenuto a destra.
                        // Margini dentro le ScrollView: le ombre delle card non
                        // vengono tagliate ai bordi delle colonne.
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView {
                                VStack(spacing: 14) {
                                    statusStrip
                                    controlPanel
                                    if viewMode != .week { timeIndicator }
                                }
                                .padding(.leading, 16)
                                .padding(.trailing, 12)
                                .padding(.top, headerHeight + 6)
                                .padding(.bottom, 32)
                            }
                            .scrollIndicators(.hidden)
                            .frame(width: 368)
                            ScrollView {
                                scheduleContent
                                    .padding(.leading, 12)
                                    .padding(.trailing, 16)
                                    .padding(.top, headerHeight + 6)
                                    .padding(.bottom, 32)
                            }
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 14) {
                                statusStrip
                                controlPanel
                                if viewMode != .week { timeIndicator }
                                // iPad in verticale: Adesso/Giorno non si stirano.
                                scheduleContent
                                    .frame(maxWidth: layout == .regular && viewMode != .week ? 760 : .infinity)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, headerHeight + 6)
                            .padding(.bottom, 32)
                        }
                    }
                }
                // Il contenuto svanisce avvicinandosi al titolo (mask sulla
                // ScrollView): nessun velo dipinto sopra l'aurora, quindi
                // niente banda scura né sovrapposizioni.
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.5),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: headerHeight + 14)
                        Rectangle()
                    }
                }

                // «Orario» + sottotitolo restano fissi, senza sfondo.
                AuroraTitle(title: "Orario", subtitle: orarioSubtitle)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                    .background {
                        GeometryReader { g in
                            Color.clear
                                .onAppear { headerHeight = g.size.height }
                                .onChange(of: g.size.height) { _, h in headerHeight = h }
                        }
                    }
            }
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

    // Stesso bottone ⋯ in tutte e tre le sezioni: dentro, le azioni della
    // sezione più le Impostazioni condivise.
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let url = exportURL {
                    ShareLink(
                        item: url,
                        preview: SharePreview(
                            "Orario \(schedule.sourceName)",
                            image: Image(systemName: "calendar.badge.clock")
                        )
                    ) {
                        Label("Condividi orario", systemImage: "square.and.arrow.up")
                    }
                }
                Button { dbEditTarget = nil; showDBDisclaimer = true } label: {
                    Label("Dati orario", systemImage: "slider.horizontal.3")
                }
                Button { showSettings = true } label: {
                    Label("Impostazioni", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Altre azioni")
        }
    }

    // MARK: - Status strip

    var statusStrip: some View {
        Group {
            if layout == .wide {
                // Colonna laterale iPad: le pillole vanno a capo invece di scorrere.
                ChipFlowLayout(spacing: 8) { statusPills }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { statusPills }
                        .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var statusPills: some View {
        Button(action: onLessonCountTap) {
            StatPill(icon: "book.closed", value: "\(schedule.lessons.count)", label: "lezioni", color: .purple)
        }
        .buttonStyle(.plain)
        Button { dbEditTarget = "classi"; showDBDisclaimer = true } label: {
            StatPill(icon: "graduationcap.fill", value: "\(schedule.classes.count)", label: "classi", color: .blue)
        }
        .buttonStyle(.plain)
        Button { dbEditTarget = "docenti"; showDBDisclaimer = true } label: {
            StatPill(icon: usesSubjectEntities ? "book.closed.fill" : "person.fill",
                     value: usesSubjectEntities ? "\(scheduleSubjects.count)" : "\(schedule.teachers.count)",
                     label: usesSubjectEntities ? "materie" : "docenti",
                     color: .orange)
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
            .auroraCard(radius: 999)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Control panel

    var panelAccent: Color { targetMode == .class_ ? AuroraSection.orario.tintB : AuroraSection.orario.tintA }

    var controlPanel: some View {
        VStack(spacing: 10) {
            AuroraSegmented(
                options: [(TargetMode.class_, "Classe"),
                          (TargetMode.teacher, usesSubjectEntities ? "Materia" : "Docente")],
                selection: $targetMode.animation()
            )

            // Altezza identica nei due stati e dissolvenza incrociata:
            // niente "scalino" quando si passa da classe a docente.
            ZStack {
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
                    .frame(height: 26)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(panelAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(panelAccent.opacity(0.25), lineWidth: 1))
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    TeacherPickerField(
                        query: $teacherQuery,
                        focused: _teacherFieldFocused,
                        showMenu: $showTeacherMenu,
                        filteredTeachers: filteredTeachers,
                        selectedTeacher: selectedTeacher,
                        onSelect: { teacher in teacherQuery = teacher; showTeacherMenu = false },
                        accentColor: panelAccent,
                        placeholder: usesSubjectEntities ? "Es. MATEMATICA" : "Es. GRECO"
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: targetMode)

            AuroraSegmented(
                options: [(ViewMode.now, "Adesso"), (ViewMode.day, "Giorno"), (ViewMode.week, "Settimana")],
                selection: $viewMode
            )
        }
        .padding(14)
        .auroraCard(radius: 18, strokeTint: panelAccent)
        .animation(.easeInOut(duration: 0.25), value: targetMode)
    }

    // MARK: - Time indicator (compact)

    var timeIndicator: some View {
        let dayLabel = viewMode == .day
            ? (schedule.days.first { $0.id == dayForDayView }?.label ?? "")
            : (schedule.days.first { $0.id == activeDay }?.label ?? (useLiveTime ? "Weekend" : "—"))
        return HStack(spacing: 8) {
            Text("\(dayLabel) · \(activeTime)")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                showQuickTimePicker = true
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(useLiveTime ? Color(hex: "#34D399")! : .orange)
                        .frame(width: 5, height: 5)
                        .shadow(color: (useLiveTime ? Color(hex: "#34D399")! : .orange).opacity(0.9), radius: 3.5)
                    Text(useLiveTime ? "Live" : "Manuale")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(useLiveTime ? Color(hex: "#6EE7B7")! : .orange)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background((useLiveTime ? Color(hex: "#34D399")! : .orange).opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder((useLiveTime ? Color(hex: "#34D399")! : .orange).opacity(0.28), lineWidth: 1))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    // MARK: - Actions

    func addNoteContext(day: DayId? = nil, time: String? = nil, teacher: String? = nil, cls: String? = nil, subject: String? = nil) {
        noteContext = NoteCreationContext(day: day, time: time, teacherTag: teacher, classTag: cls, subjectTag: subject)
    }

    func jumpToLessonTime(day: DayId, time: String) {
        useLiveTime = false
        manualDayRaw = day.rawValue
        manualTime = time
        withAnimation { viewMode = .now }
    }

    func openCounterpartDay(_ lesson: Lesson) {
        manualDayRaw = lesson.day.rawValue
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            viewMode = .day
            if targetMode == .class_ { targetMode = .teacher; teacherQuery = usesSubjectEntities ? lesson.subject : lesson.teacher }
            else { targetMode = .class_; selectedClass = lesson.className }
        }
    }

    func openCounterpartWeek(_ lesson: Lesson) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            viewMode = .week
            if targetMode == .class_ { targetMode = .teacher; teacherQuery = usesSubjectEntities ? lesson.subject : lesson.teacher }
            else { targetMode = .class_; selectedClass = lesson.className }
        }
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
        .auroraCard(radius: 999)
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
    var placeholder: String = "Es. GRECO"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(accentColor)
                    .frame(width: 24)
                TextField(placeholder, text: $query)
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
        schedule.timeSlots(forClass: nil)
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
