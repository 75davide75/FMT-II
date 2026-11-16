import SwiftUI

/// Mapping "materia del registro → materia dell'app" (spec §5).
/// - `.firstLink`: dopo il primo download, prima di importare qualsiasi voto.
/// - `.settings`: modifica dalle Impostazioni (materie confermate e nuove in attesa).
/// Ogni riga è modificabile: una materia esistente, una nuova o un nome scritto a mano.
/// Le proposte da alias sono segnate "suggerito"; due materie del registro sulla
/// stessa materia dell'app vengono evidenziate.
struct SubjectMappingView: View {
    enum Mode { case firstLink, settings }

    @ObservedObject var registro: RegistroSyncCoordinator
    @ObservedObject var grades: GradesStore
    let mode: Mode
    /// Proposte del collegamento (solo `.firstLink`).
    var proposals: [(RemoteSubjectRef, SubjectProposal)] = []
    /// Fine del passo: true se confermato (solo `.firstLink`).
    var onFinish: ((Bool) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []
    @State private var loaded = false
    @State private var saving = false
    @State private var renaming: Row?
    @State private var customName = ""

    struct Row: Identifiable, Equatable {
        var id: String { ref.key }
        let ref: RemoteSubjectRef
        var target: String
        /// Proposta automatica da alias, non ancora cambiata dall'utente.
        var suggested: Bool
        /// Materia del registro non ancora confermata.
        let pending: Bool
        var edited = false
    }

    var body: some View {
        Form {
            if mode == .firstLink {
                Section {
                    Text("Controlla a quale materia dell'app va ogni materia del registro. Nessun voto viene importato finché non confermi.")
                        .font(.subheadline)
                }
                .listRowBackground(Color.sectionCard)
            }
            let pending = rows.filter(\.pending)
            let confirmed = rows.filter { !$0.pending }
            if !pending.isEmpty {
                Section {
                    ForEach(pending) { rowView($0) }
                } header: {
                    SettingsView.header(mode == .firstLink ? L("Materie del registro") : L("Da confermare"))
                } footer: {
                    Text("«Suggerito» indica un abbinamento probabile ma non certo: controllalo.")
                }
                .listRowBackground(Color.sectionCard)
            }
            if !confirmed.isEmpty {
                Section {
                    ForEach(confirmed) { rowView($0) }
                } header: {
                    SettingsView.header(L("Confermate"))
                } footer: {
                    Text("Cambiando una materia, i voti importati che non hai modificato passano alla nuova materia.")
                }
                .listRowBackground(Color.sectionCard)
            }
            if rows.isEmpty && loaded {
                Section {
                    Text("Nessuna materia del registro per ora.")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.sectionCard)
            }
            actionsSection
        }
        .disabled(saving)
        .scrollContentBackground(.hidden)
        .background { AuroraBackground(section: .neutral) }
        .navigationTitle("Materie")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .alert("Nome della materia", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("Materia"), text: $customName)
                .textInputAutocapitalization(.sentences)
            Button("Annulla", role: .cancel) { renaming = nil }
            Button("OK") {
                if let row = renaming { set(row.id, to: customName) }
                renaming = nil
            }
        } message: {
            Text("Scrivi il nome della materia dell'app per «\(renaming?.ref.name ?? "")».")
        }
    }

    // MARK: Righe

    private func rowView(_ row: Row) -> some View {
        let others = duplicates(of: row)
        return VStack(alignment: .leading, spacing: 7) {
            Text(verbatim: row.ref.name)
                .font(.system(size: 11.5, weight: .heavy))
                .kerning(0.4)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Menu {
                    menuContent(row)
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: row.target)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("registro.mapping.target.\(row.id)")
                Spacer(minLength: 4)
                if row.suggested && !row.edited {
                    tag(L("suggerito"), "#FB923C")
                } else if !appSubjects.contains(row.target) {
                    tag(L("nuova"), "#38BDF8")
                }
            }
            if !others.isEmpty {
                Label {
                    Text("Anche \(others.joined(separator: ", ")) va in questa materia: va bene solo se sono la stessa.")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(hex: "#FB923C")!)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("registro.mapping.duplicate")
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func menuContent(_ row: Row) -> some View {
        let readable = SubjectMatcher.readableName(row.ref.name)
        if !appSubjects.contains(readable) {
            Button { set(row.id, to: readable) } label: {
                Label(L("Nuova materia «\(readable)»"), systemImage: "plus")
            }
        }
        Section(L("Materie dell'app")) {
            ForEach(menuOptions, id: \.self) { name in
                Button { set(row.id, to: name) } label: {
                    if name == row.target {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: name)
                    }
                }
            }
        }
        Button {
            customName = row.target
            renaming = row
        } label: {
            Label(L("Altro nome…"), systemImage: "pencil")
        }
    }

    private func tag(_ text: String, _ hex: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .heavy))
            .foregroundStyle(Color(hex: hex)!)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(hex: hex)!.opacity(0.16), in: Capsule())
    }

    // MARK: Azioni

    private var actionsSection: some View {
        Section {
            Button { save() } label: {
                HStack {
                    Spacer()
                    if saving { ProgressView().padding(.trailing, 6) }
                    Text(mode == .firstLink ? L("Conferma e importa") : L("Salva"))
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(!canSave)
            .accessibilityIdentifier("registro.mapping.confirm")
            if mode == .firstLink {
                Button { onFinish?(false) } label: {
                    HStack {
                        Spacer()
                        Text("Più tardi")
                        Spacer()
                    }
                }
                .accessibilityIdentifier("registro.mapping.later")
            }
        } footer: {
            if mode == .firstLink {
                Text("Con «Più tardi» il registro resta collegato ma nessun voto viene importato: potrai confermare le materie dalle Impostazioni.")
            }
        }
        .listRowBackground(Color.sectionCard)
    }

    private var canSave: Bool {
        guard !saving, !rows.isEmpty else { return false }
        guard rows.allSatisfy({ !$0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return false }
        return mode == .firstLink || rows.contains { $0.pending || $0.edited }
    }

    private func save() {
        var table = registro.mapping
        for row in rows {
            table.entries[row.id] = row.target.trimmingCharacters(in: .whitespacesAndNewlines)
            table.confirmed.insert(row.id)
        }
        saving = true
        Task {
            await registro.confirmMapping(table)
            saving = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if mode == .firstLink { onFinish?(true) } else { dismiss() }
        }
    }

    private func set(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = rows.firstIndex(where: { $0.id == id }) else { return }
        guard rows[i].target != trimmed else { return }
        rows[i].target = trimmed
        rows[i].edited = true
    }

    // MARK: Dati

    /// Materie che hanno già voti nell'app.
    private var appSubjects: Set<String> { Set(grades.subjects) }

    /// Materie dell'app più quelle scelte nelle altre righe (anche nuove).
    private var menuOptions: [String] {
        Array(appSubjects.union(rows.map(\.target))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// Altre materie del registro che finiscono nella stessa materia dell'app.
    private func duplicates(of row: Row) -> [String] {
        let key = SubjectMatcher.normalizedKey(row.target)
        return rows.filter { $0.id != row.id && SubjectMatcher.normalizedKey($0.target) == key }
            .map { "«\($0.ref.name)»" }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .firstLink:
            rows = proposals.map(Self.row(pending: true))
        case .settings:
            let appSubjects = grades.subjects
            let pending = registro.pendingSubjects.map { ($0, SubjectMatcher.propose($0, appSubjects: appSubjects)) }
                .map(Self.row(pending: true))
            let pendingKeys = Set(pending.map(\.id))
            let table = registro.mapping
            let names = knownRemoteNames()
            let confirmed = table.confirmed.subtracting(pendingKeys).compactMap { key -> Row? in
                guard let target = table.entries[key] else { return nil }
                let ref = names[key] ?? RemoteSubjectRef(id: key, name: key)
                return Row(ref: ref, target: target, suggested: false, pending: false)
            }
            .sorted { $0.ref.name.localizedCaseInsensitiveCompare($1.ref.name) == .orderedAscending }
            rows = pending + confirmed
        }
    }

    private static func row(pending: Bool) -> ((RemoteSubjectRef, SubjectProposal)) -> Row {
        { pair in
            switch pair.1 {
            case .existing(let name, let viaAlias):
                return Row(ref: pair.0, target: name, suggested: viaAlias, pending: pending)
            case .new(let name):
                return Row(ref: pair.0, target: name, suggested: false, pending: pending)
            }
        }
    }

    /// Nomi delle materie del registro per chiave, dai voti collegati e dai conflitti
    /// (la tabella del mapping salva solo la chiave).
    private func knownRemoteNames() -> [String: RemoteSubjectRef] {
        var out: [String: RemoteSubjectRef] = [:]
        for g in grades.grades {
            guard let o = g.origin else { continue }
            let ref = RemoteSubjectRef(id: o.remoteSubjectId, name: o.remoteSubjectName)
            out[ref.key] = ref
        }
        for c in registro.pendingConflicts {
            let ref = RemoteSubjectRef(id: c.remote.subjectId, name: c.remote.subjectName)
            out[ref.key] = out[ref.key] ?? ref
        }
        return out
    }
}
