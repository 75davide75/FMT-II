import SwiftUI
import UIKit

private enum TagKind: Equatable { case subject, teacher, class_ }
private struct TagFilter: Equatable { let kind: TagKind; let value: String }

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
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return base }
        // Full-text find — matches note content, plus its time and day.
        return base.filter { n in
            let day = n.dayId.flatMap { dayLabels[$0] } ?? ""
            let hay = (n.attributedText.string + " " + (n.time ?? "") + " " + day).lowercased()
            return hay.contains(q)
        }
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

    private var notesByDay: [(label: String, dayId: DayId?, notes: [Note])] {
        var groups: [String: [Note]] = [:]
        var noDay: [Note] = []
        for note in displayNotes {
            if let d = note.day { groups[d, default: []].append(note) }
            else { noDay.append(note) }
        }
        var result: [(label: String, dayId: DayId?, notes: [Note])] = []
        for dayId in weekOrder {
            if let dayNotes = groups[dayId.rawValue], !dayNotes.isEmpty {
                let label = dayLabels[dayId] ?? dayId.rawValue
                result.append((label, dayId, dayNotes.sorted { ($0.time ?? "") < ($1.time ?? "") }))
            }
        }
        if !noDay.isEmpty { result.append(("Senza data", nil, noDay)) }
        return result
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color.indigo.opacity(0.10), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 220)
            .ignoresSafeArea()

                if displayNotes.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(notesByDay, id: \.label) { group in
                            Section(group.label) {
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
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            withAnimation { store.delete(ids: Set([note.id])) }
                                        } label: {
                                            Label("Elimina", systemImage: "trash")
                                        }
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
                                    .listRowBackground(Color(.tertiarySystemGroupedBackground))
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .animation(.default, value: displayNotes.count)
                }
            }
            .background(Color(.secondarySystemGroupedBackground).ignoresSafeArea())
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
                        ToolbarItem(id: "compose", placement: .topBarTrailing) {
                            if !showArchive {
                                Button { noteContext = NoteCreationContext() } label: {
                                    Image(systemName: "square.and.pencil")
                                }
                                .accessibilityLabel("Nuova voce di diario")
                            }
                        }
                        ToolbarItem(id: "menu", placement: .topBarTrailing) {
                            Menu {
                                Button {
                                    withAnimation { isSearching = true }
                                    searchFocused = true
                                } label: { Label("Cerca", systemImage: "magnifyingglass") }

                                if !availableSubjects.isEmpty || !availableTeachers.isEmpty || !availableClasses.isEmpty {
                                    Menu {
                                        Button { withAnimation { tagFilter = nil } } label: {
                                            if tagFilter == nil { Label("Mostra tutte", systemImage: "checkmark") }
                                            else { Text("Mostra tutte") }
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
                                        Label(tagFilter == nil ? "Filtra per tag" : "Filtro: \(tagFilter!.value)",
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
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting && !selectedIds.isEmpty {
                    selectionActionBar
                }
            }
        .sheet(item: $noteContext) { ctx in
            NoteEditorSheet(store: store, context: ctx, schedule: schedule, subjects: gradesStore?.subjects ?? [])
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: scheduleStore, notesStore: store, gradesStore: gradesStore, showFilePicker: $showFilePicker)
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
            } else {
                ZStack {
                    Circle().fill(Color.indigo.opacity(0.12)).frame(width: 110, height: 110)
                    Image(systemName: showArchive ? "archivebox" : "book.closed")
                        .font(.system(size: 44))
                        .foregroundStyle(.indigo)
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
                    if displayNotes.isEmpty { isSelecting = false }
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
                        if displayNotes.isEmpty { isSelecting = false }
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

    private var hasTags: Bool {
        note.time != nil || note.teacherTag != nil || note.classTag != nil || note.subjectTag != nil
    }

    /// True when the active search matches this note's time — used to highlight it green.
    private var timeMatches: Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty, let t = note.time else { return false }
        return t.lowercased().contains(q)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.displayTitle)
                .font(.body.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 5) {
                Text(note.createdAt, format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(.secondary)
                if !note.displayPreview.isEmpty {
                    Text(note.displayPreview)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .font(.caption)

            if hasTags {
                HStack(spacing: 6) {
                    if let time = note.time { TagChip(text: time, icon: "clock", tint: timeMatches ? .green : .secondary) }
                    if let subject = note.subjectTag { TagChip(text: subject, icon: "book.closed.fill", tint: .purple) }
                    if let teacher = note.teacherTag { TagChip(text: teacher, icon: "person.fill", tint: .blue) }
                    if let cls = note.classTag { TagChip(text: cls, icon: "graduationcap.fill", tint: .orange) }
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 3)
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
    @State private var day: String? = nil
    @State private var time: String? = nil
    @State private var teacherTag: String = ""
    @State private var classTag: String = ""
    @State private var subjectTag: String = ""
    @State private var reminder = false
    @State private var showMetadata = false

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

                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showMetadata.toggle() }
                    } label: {
                        HStack {
                            Label("Dettagli", systemImage: "tag")
                                .font(.caption.weight(.medium))
                            if day != nil || time != nil || !teacherTag.isEmpty || !classTag.isEmpty || !subjectTag.isEmpty {
                                Circle().fill(.blue).frame(width: 6, height: 6)
                            }
                            Spacer()
                            Image(systemName: showMetadata ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if showMetadata {
                        Divider()
                        metadataFields
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
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
        }
        .onAppear { setupInitialState() }
    }

    @ViewBuilder
    private var metadataFields: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Giorno", systemImage: "calendar").font(.callout)
                Spacer()
                Picker("", selection: Binding(get: { day }, set: { day = $0 })) {
                    Text("—").tag(String?.none)
                    ForEach(weekOrder, id: \.self) { d in
                        Text(dayLabels[d] ?? d.rawValue).tag(Optional(d.rawValue))
                    }
                }
                .pickerStyle(.menu)
                .tint(.secondary)
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

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $reminder) {
                    Label("Promemoria settimanale", systemImage: "bell")
                        .font(.callout)
                }
                .disabled(day == nil || time == nil)
                if day == nil || time == nil {
                    Text("Imposta giorno e ora per attivare il promemoria.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .onChange(of: reminder) { _, on in
                if on { Task { await NotificationManager.shared.requestAuthorization() } }
            }
        }
    }

    private func setupInitialState() {
        if let note = context.existingNote {
            attributedText = note.attributedText
            day = note.day
            time = note.time
            teacherTag = note.teacherTag ?? ""
            classTag = note.classTag ?? ""
            subjectTag = note.subjectTag ?? ""
            reminder = note.reminder
            // Keep "Dettagli" collapsed by default so the text area stays large;
            // the blue dot signals that details are present.
        } else {
            day = context.day?.rawValue
            time = context.time
            teacherTag = context.teacherTag ?? ""
            classTag = context.classTag ?? ""
        }
    }

    private func save() {
        var note = context.existingNote ?? Note()
        note.setAttributedText(attributedText)
        note.day = day
        note.time = time
        note.teacherTag = teacherTag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : teacherTag.trimmingCharacters(in: .whitespaces)
        note.classTag = classTag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : classTag.trimmingCharacters(in: .whitespaces)
        note.subjectTag = subjectTag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : subjectTag.trimmingCharacters(in: .whitespaces)
        note.reminder = reminder && note.day != nil && note.time != nil
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

        init(_ parent: RichTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.attributedText = textView.attributedText
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
