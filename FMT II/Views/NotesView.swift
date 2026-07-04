import SwiftUI
import UIKit

private enum TagKind: Equatable { case subject, teacher, class_ }
private struct TagFilter: Equatable { let kind: TagKind; let value: String }

/// Gruppo di note di una stessa data di calendario (o senza data).
private struct NoteDateGroup {
    let id: String
    let label: String
    let date: Date?
    let notes: [Note]
}

extension NoteTaskType {
    var color: Color {
        switch self {
        case .compito:        return .yellow
        case .verifica:       return .red
        case .interrogazione: return .orange
        }
    }
    var icon: String {
        switch self {
        case .compito:        return "pencil.and.list.clipboard"
        case .verifica:       return "doc.text.magnifyingglass"
        case .interrogazione: return "person.wave.2"
        }
    }
}

// MARK: - Notes List

struct NotesListView: View {
    @ObservedObject var store: NotesStore
    var schedule: ScheduleData?
    @ObservedObject var scheduleStore: ScheduleStore
    @Binding var showFilePicker: Bool
    var isActive: Bool = true
    var gradesStore: GradesStore? = nil

    @State private var noteContext: NoteCreationContext? = nil
    @State private var isSelecting = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showArchive = false
    @State private var showSettings = false
    @State private var searchQuery = ""
    @State private var tagFilter: TagFilter? = nil
    @State private var taskFilter: NoteTaskType? = nil
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    private var allSelected: Bool {
        !displayNotes.isEmpty && selectedIds.count == displayNotes.count
    }

    private var visibleBase: [Note] {
        store.notes.filter { showArchive ? $0.isArchived : !$0.isArchived }
    }

    private func distinctTags(_ keyPath: KeyPath<Note, String?>) -> [String] {
        var seen = Set<String>(); var result: [String] = []
        for n in visibleBase {
            if let t = n[keyPath: keyPath], seen.insert(t).inserted { result.append(t) }
        }
        return result.sorted()
    }
    private var availableSubjects: [String] { distinctTags(\.subjectTag) }
    private var availableTeachers: [String] { distinctTags(\.teacherTag) }
    private var availableClasses: [String] { distinctTags(\.classTag) }

    private var displayNotes: [Note] {
        var base = visibleBase
        if let f = tagFilter {
            base = base.filter { n in
                switch f.kind {
                case .subject: return n.subjectTag == f.value
                case .teacher: return n.teacherTag == f.value
                case .class_:  return n.classTag == f.value
                }
            }
        }
        if let task = taskFilter {
            base = base.filter { $0.taskType == task.rawValue }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return base }
        // Full-text find — matches note content, plus its time and day.
        return base.filter { n in
            let day = n.dayId.flatMap { dayLabels[$0] } ?? ""
            let created = n.createdAt.formatted(date: .abbreviated, time: .omitted)
            let dated = n.date?.formatted(date: .abbreviated, time: .omitted) ?? ""
            let hay = (n.attributedText.string + " " + (n.time ?? "") + " " + day + " " + created + " " + dated).lowercased()
            return hay.contains(q)
        }
    }

    @State private var jumpToDate: Date? = nil
    @State private var selectedStripDate: Date? = nil

    /// Sottotitolo del titolo grande: "5 impegni · 1 verifica".
    private var diarioSubtitle: String {
        let n = displayNotes.count
        let verifiche = displayNotes.filter { $0.taskType == NoteTaskType.verifica.rawValue }.count
        var parts = ["\(n) impegn\(n == 1 ? "o" : "i")"]
        if verifiche > 0 { parts.append("\(verifiche) verific\(verifiche == 1 ? "a" : "he")") }
        return parts.joined(separator: " · ")
    }

    /// Il gruppo del giorno esatto se ha note, altrimenti il primo gruppo con
    /// data successiva, altrimenti l'ultimo precedente.
    private func targetGroup(for date: Date) -> NoteDateGroup? {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let dated = notesByDate.filter { $0.date != nil }
        if let exact = dated.first(where: { cal.isDate($0.date!, inSameDayAs: day) }) { return exact }
        if let next = dated.first(where: { $0.date! > day }) { return next }
        if let previous = dated.last(where: { $0.date! < day }) { return previous }
        return notesByDate.first
    }

    /// Tipi presenti in una data (puntini della striscia giorni, max 3).
    private func dayDots(_ date: Date) -> [Color] {
        let cal = Calendar.current
        var seen = Set<String>()
        var colors: [Color] = []
        for n in visibleBase where n.date.map({ cal.isDate($0, inSameDayAs: date) }) == true {
            let key = n.taskType ?? "nota"
            guard seen.insert(key).inserted else { continue }
            colors.append(n.taskType.flatMap(NoteTaskType.init(rawValue:))?.auroraColor ?? plainNoteColor)
        }
        return Array(colors.prefix(3))
    }

    /// Header del Diario (design 1a): titolo grande, striscia settimana con
    /// puntini per tipo, filtri rapidi sempre visibili.
    private var diarioHeader: some View {
        VStack(alignment: .leading, spacing: 13) {
            AuroraTitle(title: showArchive ? "Archivio" : "Diario",
                        subtitle: diarioSubtitle)
                .padding(.top, 2)

            // Striscia dei giorni, infinita in entrambe le direzioni: tocca
            // una data per saltare alle sue note. (La finestra è così ampia
            // che il pan non raggiunge mai un bordo, quindi lo scorrimento
            // non "scappa" più verso il pager delle sezioni.)
            ScrollViewReader { stripProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 7) {
                        ForEach(stripDates, id: \.self) { date in
                            dayTile(date)
                                .id(date)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .onAppear {
                    stripProxy.scrollTo(Calendar.current.startOfDay(for: Date()), anchor: .center)
                }
                .onChange(of: selectedStripDate) { _, date in
                    guard let date else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        stripProxy.scrollTo(date, anchor: .center)
                    }
                }
            }
            .frame(height: 74)

            // Filtri rapidi Verifiche / Compiti / Interrogazioni.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    quickFilter(nil, label: "Tutti")
                    ForEach(NoteTaskType.allCases) { t in
                        quickFilter(t, label: t.label == "Compito" ? "Compiti"
                                              : t.label == "Verifica" ? "Verifiche"
                                              : "Interrogazioni")
                    }
                }
            }
        }
    }

    /// Le date della striscia: ±2 anni intorno a oggi. La LazyHStack
    /// materializza solo le celle visibili.
    private var stripDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-730...730).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    private func dayTile(_ date: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        // Evidenziata è la data selezionata; in assenza di selezione, oggi.
        let isActiveTile = cal.isDate(selectedStripDate ?? cal.startOfDay(for: Date()), inSameDayAs: date)
        let day = todayDayId(date)
        let dots = dayDots(date)

        return Button {
            selectedStripDate = date
            jumpToDate = date
        } label: {
            VStack(spacing: 2) {
                Text(String((dayLabels[day] ?? "").prefix(3)).uppercased())
                    .font(.system(size: 10, weight: isActiveTile ? .heavy : .bold))
                    .kerning(0.8)
                    .foregroundStyle(isActiveTile ? .white.opacity(0.85) : Color.secondary)
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 16, weight: isActiveTile ? .heavy : .bold))
                    .foregroundStyle(isActiveTile ? .white : .primary)
                HStack(spacing: 3) {
                    if dots.isEmpty {
                        Circle().fill(.clear).frame(width: 4, height: 4)
                    } else {
                        ForEach(dots.indices, id: \.self) { i in
                            Circle().fill(dots[i]).frame(width: 4, height: 4)
                        }
                    }
                }
                .frame(height: 4)
            }
            .frame(width: 52)
            .padding(.vertical, 8)
            .background {
                if isActiveTile {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: "#4E7CF6")!, Color(hex: "#8B5CF6")!],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: Color(hex: "#685CF6")!.opacity(0.5), radius: 10, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(.white.opacity(0.05))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(
                    // Oggi resta riconoscibile anche quando è selezionata
                    // un'altra data.
                    isActiveTile ? .white.opacity(0.28)
                        : (isToday ? Color(hex: "#8B5CF6")!.opacity(0.55) : .white.opacity(0.08)),
                    lineWidth: isToday && !isActiveTile ? 1.4 : 1))
        }
        .buttonStyle(.plain)
    }

    private func quickFilter(_ type: NoteTaskType?, label: String) -> some View {
        let active = taskFilter == type
        return Button {
            withAnimation { taskFilter = type }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: active ? .bold : .semibold))
                .foregroundStyle(
                    type == nil
                        ? (active ? Color(hex: "#0B1024")! : Color.primary.opacity(0.75))
                        : type!.auroraColor.blended(with: .white, by: active ? 0 : 0.35)
                )
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background {
                    if type == nil && active {
                        Capsule().fill(Color(hex: "#F0F4FF")!.opacity(0.92))
                    } else if let t = type {
                        Capsule().fill(t.auroraColor.opacity(active ? 0.30 : 0.12))
                    } else {
                        Capsule().fill(.white.opacity(0.06))
                    }
                }
                .overlay(Capsule().strokeBorder(
                    type == nil
                        ? .white.opacity(active ? 0.6 : 0.10)
                        : type!.auroraColor.opacity(active ? 0.55 : 0.26),
                    lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Header di giorno: pill OGGI sfumata + nome + conteggio (design 1a).
    private func dayHeader(_ group: NoteDateGroup) -> some View {
        HStack(spacing: 8) {
            if group.date.map({ Calendar.current.isDateInToday($0) }) == true {
                Text("OGGI")
                    .font(.system(size: 10.5, weight: .heavy))
                    .kerning(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(colors: [Color(hex: "#4E7CF6")!, Color(hex: "#8B5CF6")!],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                    .shadow(color: Color(hex: "#6D5EF6")!.opacity(0.45), radius: 6, y: 2)
            }
            Text(group.label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(group.notes.count) impegn\(group.notes.count == 1 ? "o" : "i")")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.white.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1))
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 1)
        .textCase(nil)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Cerca nel testo delle note", text: $searchQuery)
                    .focused($searchFocused)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            Button("Annulla") {
                searchQuery = ""
                searchFocused = false
                withAnimation { isSearching = false }
            }
            .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Gruppi per data di calendario in ordine cronologico; le note senza data
    /// chiudono l'elenco.
    private var notesByDate: [NoteDateGroup] {
        let cal = Calendar.current
        var groups: [Date: [Note]] = [:]
        var noDate: [Note] = []
        for note in displayNotes {
            if let d = note.date { groups[cal.startOfDay(for: d), default: []].append(note) }
            else { noDate.append(note) }
        }
        var result: [NoteDateGroup] = groups.keys.sorted().map { day in
            NoteDateGroup(id: "d-\(Int(day.timeIntervalSince1970))",
                          label: dateGroupLabel(day),
                          date: day,
                          notes: groups[day]!.sorted { ($0.time ?? "") < ($1.time ?? "") })
        }
        if !noDate.isEmpty {
            result.append(NoteDateGroup(id: "nodate", label: "Senza data", date: nil, notes: noDate))
        }
        return result
    }

    private func dateGroupLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Oggi" }
        if cal.isDateInTomorrow(day) { return "Domani" }
        if cal.isDateInYesterday(day) { return "Ieri" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = cal.component(.year, from: day) == cal.component(.year, from: Date())
            ? "EEEE d MMMM" : "EEEE d MMMM yyyy"
        return f.string(from: day).capitalized
    }

    var body: some View {
        ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    // Header fisso: titolo, striscia date e filtri restano
                    // sempre visibili; sotto scorre solo l'elenco.
                    diarioHeader
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    if displayNotes.isEmpty {
                        emptyState
                    } else {
                    ScrollViewReader { proxy in
                    List {
                        ForEach(notesByDate, id: \.id) { group in
                            Section {
                                ForEach(group.notes) { note in
                                    NoteRowSelectable(
                                        note: note,
                                        isSelecting: isSelecting,
                                        isSelected: selectedIds.contains(note.id),
                                        searchQuery: searchQuery
                                    ) {
                                        if isSelecting {
                                            toggleSelection(note.id)
                                        } else {
                                            noteContext = NoteCreationContext(existingNote: note)
                                        }
                                    }
                                    // Niente eliminazione con lo swipe: si
                                    // elimina dal menu (pressione prolungata)
                                    // o dalla selezione multipla.
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if showArchive {
                                            Button {
                                                withAnimation { store.unarchive(ids: Set([note.id])) }
                                            } label: {
                                                Label("Ripristina", systemImage: "arrow.uturn.up")
                                            }
                                            .tint(.blue)
                                        } else {
                                            Button {
                                                withAnimation { store.archive(ids: Set([note.id])) }
                                            } label: {
                                                Label("Archivia", systemImage: "archivebox.fill")
                                            }
                                            .tint(.orange)
                                        }
                                    }
                                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .contextMenu {
                                        Button {
                                            noteContext = NoteCreationContext(existingNote: note)
                                        } label: { Label("Modifica", systemImage: "pencil") }

                                        if showArchive {
                                            Button {
                                                withAnimation { store.unarchive(ids: [note.id]) }
                                            } label: { Label("Ripristina", systemImage: "arrow.uturn.up") }
                                        } else {
                                            Button {
                                                withAnimation { store.archive(ids: [note.id]) }
                                            } label: { Label("Archivia", systemImage: "archivebox.fill") }
                                        }

                                        Button(role: .destructive) {
                                            withAnimation { store.delete(ids: [note.id]) }
                                        } label: { Label("Elimina", systemImage: "trash") }
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                }
                            } header: {
                                dayHeader(group)
                            }
                            .id(group.id)
                        }
                        Color.clear.frame(height: 80)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .animation(.default, value: displayNotes.count)
                    .onChange(of: jumpToDate) { _, date in
                        guard let date else { return }
                        // Data esatta se ha note, altrimenti la prima data
                        // successiva con note (poi la precedente).
                        if let target = targetGroup(for: date) {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) {
                                proxy.scrollTo(target.id, anchor: .top)
                            }
                        }
                        jumpToDate = nil
                    }
                    }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isActive {
                    if isSelecting {
                        ToolbarItem(id: "selectAll", placement: .topBarTrailing) {
                            Button {
                                withAnimation {
                                    if selectedIds.count == displayNotes.count {
                                        selectedIds.removeAll()
                                    } else {
                                        selectedIds = Set(displayNotes.map(\.id))
                                    }
                                }
                            } label: {
                                Image(systemName: allSelected ? "xmark.circle" : "checkmark.circle")
                            }
                            .accessibilityLabel(allSelected ? "Deseleziona tutto" : "Seleziona tutto")
                        }
                        ToolbarItem(id: "endSelect", placement: .topBarTrailing) {
                            Button("Fine") {
                                withAnimation { isSelecting = false; selectedIds.removeAll() }
                            }
                            .fontWeight(.semibold)
                        }
                    } else {
                        ToolbarItem(id: "menu", placement: .topBarTrailing) {
                            Menu {
                                Button {
                                    withAnimation { isSearching = true }
                                    searchFocused = true
                                } label: { Label("Cerca", systemImage: "magnifyingglass") }

                                if !visibleBase.isEmpty {
                                    Menu {
                                        Button { withAnimation { tagFilter = nil; taskFilter = nil } } label: {
                                            if tagFilter == nil && taskFilter == nil { Label("Mostra tutte", systemImage: "checkmark") }
                                            else { Text("Mostra tutte") }
                                        }
                                        Menu("Tipo") {
                                            ForEach(NoteTaskType.allCases) { t in
                                                Button { withAnimation { taskFilter = (taskFilter == t ? nil : t) } } label: {
                                                    if taskFilter == t { Label(t.label, systemImage: "checkmark") }
                                                    else { Label(t.label, systemImage: t.icon) }
                                                }
                                            }
                                        }
                                        if !availableSubjects.isEmpty {
                                            Menu("Materie") { tagButtons(.subject, availableSubjects) }
                                        }
                                        if !availableTeachers.isEmpty {
                                            Menu("Docenti") { tagButtons(.teacher, availableTeachers) }
                                        }
                                        if !availableClasses.isEmpty {
                                            Menu("Classi") { tagButtons(.class_, availableClasses) }
                                        }
                                    } label: {
                                        Label((tagFilter == nil && taskFilter == nil) ? "Filtra" : "Filtro attivo",
                                              systemImage: "line.3.horizontal.decrease.circle")
                                    }
                                }

                                if !displayNotes.isEmpty {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) { isSelecting = true }
                                    } label: { Label("Seleziona", systemImage: "checklist") }
                                }
                                Button {
                                    withAnimation { showArchive.toggle() }
                                } label: {
                                    Label(showArchive ? "Mostra il diario" : "Mostra l'archivio",
                                          systemImage: showArchive ? "book.closed" : "archivebox")
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
                }
            }
            .safeAreaInset(edge: .top) {
                if isActive && isSearching {
                    searchBar
                }
            }
            .sensoryFeedback(.selection, trigger: isSelecting)
            .sensoryFeedback(.impact(weight: .light), trigger: selectedStripDate)
            .sensoryFeedback(.selection, trigger: tagFilter)
            .sensoryFeedback(.impact(weight: .light), trigger: selectedIds)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: displayNotes.count)
            .onChange(of: showArchive) { _, _ in
                isSelecting = false
                selectedIds.removeAll()
            }
            .onChange(of: isActive) { _, active in
                // Leaving the Diary resets it to its home (no archive/selection/search/filter).
                if !active {
                    showArchive = false
                    isSelecting = false
                    selectedIds.removeAll()
                    isSearching = false
                    searchQuery = ""
                    tagFilter = nil
                    taskFilter = nil
                    selectedStripDate = nil
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting && !selectedIds.isEmpty {
                    selectionActionBar
                }
            }
        .overlay(alignment: .bottomTrailing) {
            // FAB "+" con gradiente (design 1a).
            if isActive && !showArchive && !isSelecting {
                Button { noteContext = NoteCreationContext() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(
                            LinearGradient(colors: [Color(hex: "#4E7CF6")!, Color(hex: "#8B5CF6")!, Color(hex: "#A78BFA")!],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle()
                        )
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        .shadow(color: Color(hex: "#685CF6")!.opacity(0.55), radius: 15, y: 7)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 26)
                .accessibilityLabel("Nuova voce di diario")
            }
        }
        .sheet(item: $noteContext) { ctx in
            NoteEditorSheet(store: store, context: ctx, schedule: schedule, subjects: gradesStore?.subjects ?? [])
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: scheduleStore, notesStore: store, gradesStore: gradesStore, showFilePicker: $showFilePicker)
        }
    }

    /// Row background: a coloured, bordered card for special task types
    /// (compito/verifica/interrogazione), otherwise a neutral card.
    @ViewBuilder
    private func rowBackground(for note: Note) -> some View {
        if let tc = note.taskType.flatMap(NoteTaskType.init(rawValue:))?.color {
            RoundedRectangle(cornerRadius: 10)
                .fill(tc.opacity(0.13))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tc.opacity(0.55), lineWidth: 1.5))
                .padding(.vertical, 2)
        } else {
            Color.sectionCard
        }
    }

    @ViewBuilder
    private func tagButtons(_ kind: TagKind, _ values: [String]) -> some View {
        ForEach(values, id: \.self) { v in
            Button { withAnimation { tagFilter = TagFilter(kind: kind, value: v) } } label: {
                if tagFilter == TagFilter(kind: kind, value: v) { Label(v, systemImage: "checkmark") }
                else { Text(v) }
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIds.contains(id) { selectedIds.remove(id) }
        else { selectedIds.insert(id) }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundStyle(.quaternary)
                Text("Nessun risultato")
                    .font(.title3.bold())
                Text("Nessuna voce del diario per «\(searchQuery)».")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else if let t = taskFilter {
                // Filtro tipo attivo ma senza note: il messaggio dice cosa
                // manca, non "Diario vuoto".
                Image(systemName: t.icon)
                    .font(.system(size: 56))
                    .foregroundStyle(.quaternary)
                Text(t == .verifica ? "Nessuna verifica in programma"
                     : t == .compito ? "Nessun compito in programma"
                     : "Nessuna interrogazione in programma")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text("Le note con questa etichetta compariranno qui.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else if let f = tagFilter {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.quaternary)
                Text("Nessuna corrispondenza")
                    .font(.title3.bold())
                Text("Non ci sono note per «\(f.value)».")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                ZStack {
                    Circle().fill(AuroraSection.diario.gradient).opacity(0.22).frame(width: 110, height: 110)
                    Image(systemName: showArchive ? "archivebox" : "book.closed")
                        .font(.system(size: 44))
                        .foregroundStyle(AuroraSection.diario.accent)
                }
                Text(showArchive ? "Archivio vuoto" : "Diario vuoto")
                    .font(.title3.bold())
                if !showArchive {
                    Text("Tieni premuto su un docente o una classe per aggiungere una voce al diario.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var selectionActionBar: some View {
        HStack(spacing: 0) {
            Button(role: .destructive) {
                withAnimation {
                    store.delete(ids: selectedIds)
                    selectedIds.removeAll()
                    isSelecting = false
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "trash").font(.title3)
                    Text("Elimina").font(.caption)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }

            Divider().frame(height: 44)

            if showArchive {
                Button {
                    withAnimation {
                        store.unarchive(ids: selectedIds)
                        selectedIds.removeAll()
                        isSelecting = false
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.up").font(.title3)
                        Text("Ripristina").font(.caption)
                    }
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            } else {
                Button {
                    withAnimation {
                        store.archive(ids: selectedIds)
                        selectedIds.removeAll()
                        isSelecting = false
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "archivebox").font(.title3)
                        Text("Archivia").font(.caption)
                    }
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Note row with selection

private struct NoteRowSelectable: View {
    let note: Note
    let isSelecting: Bool
    let isSelected: Bool
    var searchQuery: String = ""
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : Color(.tertiaryLabel))
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
            NoteRowView(note: note, searchQuery: searchQuery)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Note row

private struct NoteRowView: View {
    let note: Note
    var searchQuery: String = ""

    private var taskType: NoteTaskType? { note.taskType.flatMap(NoteTaskType.init(rawValue:)) }

    private var hasTags: Bool {
        taskType != nil || note.time != nil || note.teacherTag != nil || note.classTag != nil || note.subjectTag != nil
    }

    /// True when the active search matches this note's time — used to highlight it green.
    private var timeMatches: Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty, let t = note.time else { return false }
        return t.lowercased().contains(q)
    }

    /// True when the active search matches this note's date — highlights it green.
    private var dateMatches: Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return false }
        return note.createdAt.formatted(date: .abbreviated, time: .omitted).lowercased().contains(q)
    }

    private var barGradient: LinearGradient {
        taskType?.auroraGradient ?? plainNoteGradient
    }

    private var isVerifica: Bool { taskType == .verifica }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Barra laterale sfumata per tipo (design 1a)
            RoundedRectangle(cornerRadius: 4)
                .fill(barGradient)
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(note.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .kerning(-0.2)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(note.createdAt, format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 10.5, weight: .heavy))
                        .kerning(0.6)
                        .foregroundStyle(dateMatches ? Color(hex: "#6EE7B7")! : (isVerifica ? Color(hex: "#FDA4AF")! : .secondary))
                }
                if !note.displayPreview.isEmpty {
                    Text(note.displayPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if hasTags {
                    ChipFlowLayout(spacing: 6) {
                        if let tt = taskType {
                            AuroraChip(text: tt.label, color: tt.auroraColor)
                        }
                        if let subject = note.subjectTag {
                            AuroraChip(text: subject, color: subjectColor(subject))
                        }
                        if let time = note.time {
                            AuroraChip(text: time, color: timeMatches ? Color(hex: "#34D399")! : Color(hex: "#94A3C8")!, icon: "clock")
                        }
                        if let teacher = note.teacherTag {
                            AuroraChip(text: teacher, color: Color(hex: "#60A5FA")!, icon: "person.fill")
                        }
                        if let cls = note.classTag {
                            AuroraChip(text: cls, color: Color(hex: "#FB923C")!, icon: "graduationcap.fill")
                        }
                        if !note.reminders.isEmpty || note.reminder {
                            AuroraChip(text: "Promemoria", color: Color(hex: "#34D399")!, icon: "bell.fill")
                        }
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 13, leading: 12, bottom: 13, trailing: 14))
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardFill)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isVerifica ? Color(hex: "#FB7185")!.opacity(0.32) : .white.opacity(0.13), lineWidth: 1)
        )
        .shadow(color: isVerifica ? Color(red: 0.47, green: 0.08, blue: 0.16).opacity(0.22) : .black.opacity(0.20),
                radius: 14, y: 6)
    }

    @Environment(\.colorScheme) private var scheme

    private var cardFill: LinearGradient {
        if isVerifica {
            return LinearGradient(colors: [Color(hex: "#FB7185")!.opacity(scheme == .dark ? 0.13 : 0.16),
                                           .white.opacity(scheme == .dark ? 0.05 : 0.7)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: scheme == .dark
                                ? [.white.opacity(0.10), .white.opacity(0.045)]
                                : [.white.opacity(0.92), .white.opacity(0.65)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct TagChip: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Note Editor Sheet

struct NoteEditorSheet: View {
    @ObservedObject var store: NotesStore
    let context: NoteCreationContext
    var schedule: ScheduleData?
    var subjects: [String] = []

    @Environment(\.dismiss) private var dismiss
    @State private var attributedText: NSAttributedString = NSAttributedString(string: "")
    @State private var noteDate: Date? = nil
    @State private var time: String? = nil
    @State private var teacherTag: String = ""
    @State private var classTag: String = ""
    @State private var subjectTag: String = ""
    @State private var reminders: [NoteReminder] = []
    @State private var taskType: NoteTaskType? = nil
    @State private var showDetailsSheet = false

    private var hasDetails: Bool {
        noteDate != nil || time != nil || !teacherTag.isEmpty || !classTag.isEmpty || !subjectTag.isEmpty || !reminders.isEmpty || taskType != nil
    }

    private var isNew: Bool { context.existingNote == nil }

    var schoolDays: [DayInfo] { schedule?.days ?? [] }
    var schoolTimes: [String] {
        guard let s = schedule, let last = s.periods.last else { return [] }
        return s.periods.map { $0.startTime } + [last.endTime]
    }

    /// Bridges the optional "HH:mm" string to a Date for a full 24h picker.
    private var timeDateBinding: Binding<Date> {
        Binding(
            get: {
                let parts = (time ?? "08:00").split(separator: ":").compactMap { Int($0) }
                var c = DateComponents()
                c.hour = parts.first ?? 8
                c.minute = parts.count > 1 ? parts[1] : 0
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newDate in
                let h = Calendar.current.component(.hour, from: newDate)
                let m = Calendar.current.component(.minute, from: newDate)
                time = String(format: "%02d:%02d", h, m)
            }
        )
    }

    private func currentHHmm() -> String {
        let now = Date()
        return String(format: "%02d:%02d",
                      Calendar.current.component(.hour, from: now),
                      Calendar.current.component(.minute, from: now))
    }

    private func reminderTime(_ binding: Binding<NoteReminder>) -> Binding<Date> {
        Binding(
            get: {
                let parts = binding.wrappedValue.time.split(separator: ":").compactMap { Int($0) }
                var c = DateComponents()
                c.hour = parts.first ?? 8
                c.minute = parts.count > 1 ? parts[1] : 0
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newDate in
                let h = Calendar.current.component(.hour, from: newDate)
                let m = Calendar.current.component(.minute, from: newDate)
                binding.wrappedValue.time = String(format: "%02d:%02d", h, m)
            }
        )
    }

    private func addReminder() {
        let d = noteDate.map { todayDayId($0).rawValue } ?? DayId.monday.rawValue
        let t = time ?? currentHHmm()
        reminders.append(NoteReminder(day: d, time: t))
        Task { await NotificationManager.shared.requestAuthorization() }
    }

    // MARK: Autocomplete

    private static let commonSubjects = [
        "Italiano", "Matematica", "Storia", "Geografia", "Geostoria",
        "Inglese", "Francese", "Spagnolo", "Tedesco", "Latino", "Greco",
        "Scienze", "Scienze naturali", "Biologia", "Chimica", "Fisica",
        "Filosofia", "Storia dell'arte", "Disegno e storia dell'arte",
        "Diritto", "Economia", "Informatica", "Tecnologia",
        "Scienze motorie", "Educazione fisica", "Educazione civica",
        "Religione", "Musica", "Arte e immagine"
    ]

    private func suggest(_ text: String, from pool: [String]) -> [String] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var seen = Set<String>(); var dedup: [String] = []
        for s in pool where seen.insert(s.lowercased()).inserted { dedup.append(s) }
        return dedup.filter { $0.lowercased().contains(q) && $0.lowercased() != q }.prefix(6).map { $0 }
    }

    private var subjectSuggestions: [String] { suggest(subjectTag, from: subjects + Self.commonSubjects) }
    private var teacherSuggestions: [String] { suggest(teacherTag, from: schedule?.teachers ?? []) }
    private var classSuggestions: [String] { suggest(classTag, from: schedule?.classes ?? []) }

    @ViewBuilder
    private func suggestionsRow(_ items: [String], onPick: @escaping (String) -> Void) -> some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items, id: \.self) { s in
                        Button { onPick(s) } label: {
                            Text(s)
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RichTextEditor(attributedText: $attributedText)
                    .frame(maxHeight: .infinity)

                Divider()

                Button {
                    showDetailsSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Label("Dettagli", systemImage: "tag")
                            .font(.callout)
                        if hasDetails {
                            Circle().fill(.blue).frame(width: 6, height: 6)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color(.secondarySystemGroupedBackground))
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle(isNew ? "Nuova nota" : "Modifica nota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") { save() }
                        .fontWeight(.semibold)
                        .disabled(attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showDetailsSheet) {
                NavigationStack {
                    ScrollView { metadataFields.padding(.vertical, 4) }
                        .background(Color(.systemGroupedBackground))
                        .navigationTitle("Dettagli")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) { Button("Fine") { showDetailsSheet = false } }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear { setupInitialState() }
    }

    @ViewBuilder
    private var metadataFields: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Tipo", systemImage: "flag.fill").font(.callout)
                Spacer()
                Picker("", selection: $taskType) {
                    Text("Nessuno").tag(NoteTaskType?.none)
                    ForEach(NoteTaskType.allCases) { t in
                        Text(t.label).tag(NoteTaskType?.some(t))
                    }
                }
                .pickerStyle(.menu)
                .tint(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            Divider().padding(.leading, 16)

            HStack {
                Label("Giorno", systemImage: "calendar").font(.callout)
                Spacer()
                if let binding = Binding($noteDate) {
                    // Data completa (giorno, mese e anno), non solo il giorno
                    // della settimana.
                    DatePicker("", selection: binding, displayedComponents: .date)
                        .labelsHidden()
                    Button { noteDate = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Aggiungi") { noteDate = Calendar.current.startOfDay(for: Date()) }
                        .font(.callout)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            Divider().padding(.leading, 16)

            HStack {
                Label("Ora", systemImage: "clock").font(.callout)
                Spacer()
                if time != nil {
                    DatePicker("", selection: timeDateBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Button { time = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Aggiungi") { time = currentHHmm() }
                        .font(.callout)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            Divider().padding(.leading, 16)

            HStack {
                Label("Docente", systemImage: "person.fill").font(.callout)
                Spacer()
                TextField("Cognome", text: $teacherTag)
                    .multilineTextAlignment(.trailing).font(.callout)
                    .foregroundStyle(.secondary).autocorrectionDisabled()
                    .textInputAutocapitalization(.characters).frame(maxWidth: 150)
                    .submitLabel(.done)
                    .onSubmit { if let f = teacherSuggestions.first { teacherTag = f } }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            suggestionsRow(teacherSuggestions) { teacherTag = $0 }

            Divider().padding(.leading, 16)

            HStack {
                Label("Classe", systemImage: "graduationcap.fill").font(.callout)
                Spacer()
                TextField("Es. 5GSA", text: $classTag)
                    .multilineTextAlignment(.trailing).font(.callout)
                    .foregroundStyle(.secondary).autocorrectionDisabled()
                    .textInputAutocapitalization(.characters).frame(maxWidth: 150)
                    .submitLabel(.done)
                    .onSubmit { if let f = classSuggestions.first { classTag = f } }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            suggestionsRow(classSuggestions) { classTag = $0 }

            Divider().padding(.leading, 16)

            HStack {
                Label("Materia", systemImage: "book.closed.fill").font(.callout)
                Spacer()
                TextField("Es. Matematica", text: $subjectTag)
                    .multilineTextAlignment(.trailing).font(.callout)
                    .foregroundStyle(.secondary).autocorrectionDisabled()
                    .frame(maxWidth: 150)
                    .submitLabel(.done)
                    .onSubmit { if let f = subjectSuggestions.first { subjectTag = f } }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            suggestionsRow(subjectSuggestions) { subjectTag = $0 }

            Divider().padding(.leading, 16)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Promemoria", systemImage: "bell").font(.callout)
                    Spacer()
                    Button { addReminder() } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                }
                ForEach($reminders) { $r in
                    HStack {
                        Menu {
                            ForEach(weekOrder, id: \.self) { d in
                                Button(dayLabels[d] ?? d.rawValue) { $r.day.wrappedValue = d.rawValue }
                            }
                        } label: {
                            Text(dayLabels[r.dayId ?? .monday] ?? "Giorno")
                                .font(.callout)
                        }
                        Spacer()
                        DatePicker("", selection: reminderTime($r), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Button { reminders.removeAll { $0.id == r.id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if reminders.isEmpty {
                    Text("Aggiungi uno o più avvisi settimanali, ciascuno con giorno e ora.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private func setupInitialState() {
        if let note = context.existingNote {
            attributedText = note.attributedText
            noteDate = note.date
            time = note.time
            teacherTag = note.teacherTag ?? ""
            classTag = note.classTag ?? ""
            subjectTag = note.subjectTag ?? ""
            taskType = note.taskType.flatMap(NoteTaskType.init(rawValue:))
            reminders = note.reminders
            // Keep "Dettagli" collapsed by default so the text area stays large;
            // the blue dot signals that details are present.
        } else {
            // Dalle viste orario arriva il giorno settimanale: diventa la
            // prossima occorrenza di quel giorno.
            noteDate = context.date ?? context.day.map { nextOccurrence(of: $0) }
            time = context.time
            teacherTag = context.teacherTag ?? ""
            classTag = context.classTag ?? ""
            subjectTag = context.subjectTag ?? ""
        }
    }

    private func save() {
        var note = context.existingNote ?? Note()
        note.setAttributedText(attributedText)
        note.date = noteDate.map { Calendar.current.startOfDay(for: $0) }
        note.day = noteDate.map { todayDayId($0).rawValue }
        note.time = time
        note.teacherTag = teacherTag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : teacherTag.trimmingCharacters(in: .whitespaces)
        note.classTag = classTag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : classTag.trimmingCharacters(in: .whitespaces)
        note.subjectTag = subjectTag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : subjectTag.trimmingCharacters(in: .whitespaces)
        note.taskType = taskType?.rawValue
        note.reminders = reminders
        note.reminder = !reminders.isEmpty
        if isNew { store.add(note) } else { store.update(note) }
        NotificationManager.shared.schedule(note: note)
        dismiss()
    }
}

// MARK: - Rich Text Editor

struct RichTextEditor: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .systemBackground
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        tv.inputAccessoryView = context.coordinator.makeFormattingBar(for: tv)
        if !attributedText.string.isEmpty { tv.attributedText = attributedText }
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard !uiView.attributedText.isEqual(to: attributedText) else { return }
        let sel = uiView.selectedRange
        uiView.attributedText = attributedText
        let safeLoc = min(sel.location, uiView.attributedText.length)
        uiView.selectedRange = NSRange(location: safeLoc, length: 0)
    }

    // MARK: Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor
        weak var textView: UITextView?
        weak var boldBtn: UIButton?
        weak var italicBtn: UIButton?
        weak var underlineBtn: UIButton?
        weak var strikeBtn: UIButton?

        init(_ parent: RichTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.attributedText = textView.attributedText
            updateFormatButtons()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateFormatButtons()
        }

        // MARK: Active-state feedback

        /// Highlights the B/I/U/S buttons that are active for the current
        /// selection (or the cursor's typing attributes when nothing is selected).
        func updateFormatButtons() {
            guard let tv = textView else { return }
            setActive(boldBtn,      traitActive(.traitBold, in: tv))
            setActive(italicBtn,    traitActive(.traitItalic, in: tv))
            setActive(underlineBtn, attrActive(.underlineStyle, in: tv))
            setActive(strikeBtn,    attrActive(.strikethroughStyle, in: tv))
        }

        private func setActive(_ btn: UIButton?, _ active: Bool) {
            guard let btn else { return }
            btn.tintColor = active ? .tintColor : .label
            var cfg = btn.configuration
            cfg?.background.backgroundColor = active ? UIColor.tintColor.withAlphaComponent(0.16) : .clear
            cfg?.background.cornerRadius = 7
            btn.configuration = cfg
        }

        private func traitActive(_ trait: UIFontDescriptor.SymbolicTraits, in tv: UITextView) -> Bool {
            let range = tv.selectedRange
            if range.length == 0 {
                let f = (tv.typingAttributes[.font] as? UIFont) ?? tv.font ?? UIFont.preferredFont(forTextStyle: .body)
                return f.fontDescriptor.symbolicTraits.contains(trait)
            }
            var all = true
            tv.attributedText.enumerateAttribute(.font, in: range) { v, _, stop in
                let f = (v as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
                if !f.fontDescriptor.symbolicTraits.contains(trait) { all = false; stop.pointee = true }
            }
            return all
        }

        private func attrActive(_ key: NSAttributedString.Key, in tv: UITextView) -> Bool {
            let range = tv.selectedRange
            if range.length == 0 {
                return (tv.typingAttributes[key] as? Int) == NSUnderlineStyle.single.rawValue
            }
            var all = true
            tv.attributedText.enumerateAttribute(key, in: range) { v, _, stop in
                if (v as? Int) != NSUnderlineStyle.single.rawValue { all = false; stop.pointee = true }
            }
            return all
        }

        func makeFormattingBar(for tv: UITextView) -> UIView {
            self.textView = tv

            let bar = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 46))
            bar.backgroundColor = UIColor.secondarySystemBackground
            bar.autoresizingMask = .flexibleWidth

            let hairline = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 0.5))
            hairline.backgroundColor = UIColor.separator
            hairline.autoresizingMask = .flexibleWidth
            bar.addSubview(hairline)

            let symCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

            func makeImgBtn(_ symbol: String, action: Selector) -> UIButton {
                var cfg = UIButton.Configuration.plain()
                cfg.image = UIImage(systemName: symbol, withConfiguration: symCfg)
                cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
                let btn = UIButton(configuration: cfg)
                btn.tintColor = .label
                btn.addTarget(self, action: action, for: .touchUpInside)
                return btn
            }

            var formatCfg = UIButton.Configuration.plain()
            formatCfg.image = UIImage(systemName: "textformat", withConfiguration: symCfg)
            formatCfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
            let formatBtn = UIButton(configuration: formatCfg)
            formatBtn.tintColor = .label
            formatBtn.showsMenuAsPrimaryAction = true
            formatBtn.menu = UIMenu(title: "Stile del paragrafo", children: [
                UIAction(title: "Titolo", image: UIImage(systemName: "textformat.size.larger")) { [weak self] _ in self?.applyParagraph(.title) },
                UIAction(title: "Intestazione", image: UIImage(systemName: "textformat")) { [weak self] _ in self?.applyParagraph(.heading) },
                UIAction(title: "Sottotitolo", image: UIImage(systemName: "textformat.size.smaller")) { [weak self] _ in self?.applyParagraph(.subheading) },
                UIAction(title: "Corpo", image: UIImage(systemName: "text.alignleft")) { [weak self] _ in self?.applyParagraph(.body) }
            ])

            let boldBtn      = makeImgBtn("bold",          action: #selector(toggleBold))
            let italicBtn    = makeImgBtn("italic",        action: #selector(toggleItalic))
            let underlineBtn = makeImgBtn("underline",     action: #selector(toggleUnderline))
            let strikeBtn    = makeImgBtn("strikethrough", action: #selector(toggleStrikethrough))
            self.boldBtn = boldBtn
            self.italicBtn = italicBtn
            self.underlineBtn = underlineBtn
            self.strikeBtn = strikeBtn

            let vsep = UIView()
            vsep.backgroundColor = UIColor.separator
            vsep.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                vsep.widthAnchor.constraint(equalToConstant: 0.5),
                vsep.heightAnchor.constraint(equalToConstant: 20)
            ])

            var doneCfg = UIButton.Configuration.plain()
            doneCfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 8)
            let doneBtn = UIButton(configuration: doneCfg)
            doneBtn.setTitle("Fine", for: .normal)
            doneBtn.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            doneBtn.setTitleColor(UIColor.tintColor, for: .normal)
            doneBtn.addTarget(self, action: #selector(done), for: .touchUpInside)

            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let mainStack = UIStackView(arrangedSubviews: [formatBtn, vsep, boldBtn, italicBtn, underlineBtn, strikeBtn, spacer, doneBtn])
            mainStack.axis = .horizontal; mainStack.spacing = 0; mainStack.alignment = .center
            mainStack.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(mainStack)

            NSLayoutConstraint.activate([
                mainStack.leadingAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.leadingAnchor),
                mainStack.trailingAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.trailingAnchor),
                mainStack.topAnchor.constraint(equalTo: bar.topAnchor, constant: 0.5),
                mainStack.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
            ])

            return bar
        }

        @objc func toggleBold()    { toggleTrait(.traitBold) }
        @objc func toggleItalic()  { toggleTrait(.traitItalic) }

        private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
            guard let tv = textView, tv.selectedRange.length > 0 else { return }
            let range = tv.selectedRange
            let m = NSMutableAttributedString(attributedString: tv.attributedText)
            var allHave = true
            m.enumerateAttribute(.font, in: range) { v, _, _ in
                guard let f = v as? UIFont else { allHave = false; return }
                if !f.fontDescriptor.symbolicTraits.contains(trait) { allHave = false }
            }
            m.enumerateAttribute(.font, in: range) { v, r, _ in
                let f = (v as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
                var traits = f.fontDescriptor.symbolicTraits
                if allHave { traits.remove(trait) } else { traits.insert(trait) }
                if let d = f.fontDescriptor.withSymbolicTraits(traits) {
                    m.addAttribute(.font, value: UIFont(descriptor: d, size: f.pointSize), range: r)
                }
            }
            tv.attributedText = m; tv.selectedRange = range
            parent.attributedText = m
            updateFormatButtons()
        }

        @objc func toggleUnderline() {
            guard let tv = textView, tv.selectedRange.length > 0 else { return }
            let range = tv.selectedRange
            let m = NSMutableAttributedString(attributedString: tv.attributedText)
            var allHave = true
            m.enumerateAttribute(.underlineStyle, in: range) { v, _, _ in
                if (v as? Int) != NSUnderlineStyle.single.rawValue { allHave = false }
            }
            if allHave { m.removeAttribute(.underlineStyle, range: range) }
            else { m.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            tv.attributedText = m; tv.selectedRange = range
            parent.attributedText = m
            updateFormatButtons()
        }

        @objc func toggleStrikethrough() {
            guard let tv = textView, tv.selectedRange.length > 0 else { return }
            let range = tv.selectedRange
            let m = NSMutableAttributedString(attributedString: tv.attributedText)
            var allHave = true
            m.enumerateAttribute(.strikethroughStyle, in: range) { v, _, _ in
                if (v as? Int) != NSUnderlineStyle.single.rawValue { allHave = false }
            }
            if allHave { m.removeAttribute(.strikethroughStyle, range: range) }
            else { m.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            tv.attributedText = m; tv.selectedRange = range
            parent.attributedText = m
            updateFormatButtons()
        }

        enum ParaStyle { case title, heading, subheading, body }

        /// Applies an Apple-Notes-style paragraph font to the whole paragraph(s)
        /// touched by the selection (or the current line when nothing is selected).
        func applyParagraph(_ style: ParaStyle) {
            guard let tv = textView else { return }
            let font: UIFont
            switch style {
            case .title:      font = .systemFont(ofSize: 28, weight: .bold)
            case .heading:    font = .systemFont(ofSize: 22, weight: .bold)
            case .subheading: font = .systemFont(ofSize: 18, weight: .semibold)
            case .body:       font = .preferredFont(forTextStyle: .body)
            }
            let ns = tv.attributedText.string as NSString
            let paraRange = ns.paragraphRange(for: tv.selectedRange)
            let m = NSMutableAttributedString(attributedString: tv.attributedText)
            if paraRange.length > 0 {
                m.addAttribute(.font, value: font, range: paraRange)
            }
            let sel = tv.selectedRange
            tv.attributedText = m
            tv.selectedRange = NSRange(location: min(sel.location, m.length), length: min(sel.length, m.length - min(sel.location, m.length)))
            tv.typingAttributes[.font] = font
            parent.attributedText = m
        }

        @objc func done() { textView?.resignFirstResponder() }
    }
}
