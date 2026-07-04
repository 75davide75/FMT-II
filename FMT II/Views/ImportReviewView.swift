import SwiftUI

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
                } else {
                    Section(cls) {
                        ForEach(lessons(for: cls)) { lesson in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(lesson.dayLabel) · \(lesson.startTime)")
                                        .font(.callout)
                                    Text(missing == .teacher ? lesson.subject : lesson.teacher)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                TextField(missing == .teacher ? "Docente" : "Materia", text: Binding(
                                    get: { edits[lesson.id] ?? "" },
                                    set: { edits[lesson.id] = $0 }
                                ))
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(missing == .teacher ? .characters : .words)
                                .frame(maxWidth: 150)
                            }
                        }
                    }
                    .listRowBackground(Color.sectionCard)
                }
            }
        }
        .scrollContentBackground(.hidden)
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
private struct FlowLayoutChips: View {
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
