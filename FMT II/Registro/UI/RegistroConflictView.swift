import SwiftUI

/// "È questo il voto che hai già inserito?" (spec §5): un conflitto alla volta.
/// Le risposte si salvano subito (`sync: false`); alla chiusura parte una sola
/// sync (`applyDecisions`), che non parte se il registro ha rifiutato la password.
struct RegistroConflictView: View {
    @ObservedObject var registro: RegistroSyncCoordinator
    @ObservedObject var grades: GradesStore
    @Environment(\.dismiss) private var dismiss

    /// Conflitti rimandati in questa sessione ("Decidi dopo"): si passa al successivo.
    @State private var postponed: Set<String> = []
    @State private var answered = 0
    @State private var working = false
    @State private var total = 0

    private var queue: [PendingConflict] {
        registro.pendingConflicts.filter { !postponed.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let conflict = queue.first {
                    card(conflict)
                } else {
                    Color.clear.onAppear { dismiss() }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuroraBackground(section: .neutral) }
            .navigationTitle("Voti da controllare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear { total = registro.pendingConflicts.count }
        .onDisappear {
            guard answered > 0 else { return }
            answered = 0
            Task { await registro.applyDecisions() }
        }
    }

    // MARK: Conflitto

    private func card(_ c: PendingConflict) -> some View {
        let candidates = c.candidateIDs.compactMap { id in grades.grades.first { $0.id == id && $0.origin == nil } }
        let position = max(total - queue.count + 1, 1)
        return Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if total > 1 {
                        Text("\(position) di \(total)")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.secondary)
                    }
                    Text("È questo il voto che hai già inserito?")
                        .font(.title3.weight(.bold))
                    Text("Il registro ha un voto simile a uno dei tuoi: scegli tu, così non compare due volte.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.sectionCard)

            Section {
                remoteRow(c.remote)
            } header: {
                SettingsView.header(L("Dal registro"))
            }
            .listRowBackground(Color.sectionCard)

            if !candidates.isEmpty {
                Section {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { i, g in
                        candidateRow(g, index: i, conflict: c)
                    }
                } header: {
                    SettingsView.header(L("I tuoi voti"))
                }
                .listRowBackground(Color.sectionCard)
            }

            Section {
                Button { decide(c, .importAsNew) } label: {
                    SettingsView.row(L("No, è un voto diverso"), icon: "plus.circle.fill", "#4E7CF6")
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("registro.conflict.new")
                Button { decide(c, .later) } label: {
                    SettingsView.row(L("Decidi dopo"), icon: "clock.fill", "#64748B")
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("registro.conflict.later")
            } footer: {
                Text("«No, è un voto diverso» importa il voto del registro come nuovo. «Decidi dopo» lo lascia in attesa senza importarlo.")
            }
            .listRowBackground(Color.sectionCard)
        }
        .disabled(working)
    }

    private func remoteRow(_ r: VotoRemoto) -> some View {
        HStack(spacing: 12) {
            valueBadge(r.rawValue, "#2DD4BF")
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: SubjectMatcher.readableName(r.subjectName))
                    .font(.system(size: 15, weight: .semibold))
                Text(verbatim: details(date: r.date, type: kindLabel(r.kind), teacher: r.teacher ?? ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func candidateRow(_ g: Grade, index: Int, conflict: PendingConflict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                valueBadge(g.value.italianGrade, "#A78BFA")
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: g.subject)
                        .font(.system(size: 15, weight: .semibold))
                    Text(verbatim: details(date: g.date, type: g.type.label, teacher: g.teacher))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !g.note.isEmpty {
                        Text(verbatim: g.note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            Button { decide(conflict, .linkTo(g.id)) } label: {
                Label(L("Sì, è questo"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("registro.conflict.link.\(index)")
        }
        .padding(.vertical, 2)
    }

    private func valueBadge(_ text: String, _ hex: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(.white)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 4)
            .background(Color(hex: hex)!.opacity(0.85), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func details(date: Date, type: String, teacher: String) -> String {
        [date.appFormatted(date: .abbreviated, time: .omitted), type, teacher]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func kindLabel(_ k: RemoteGradeKind?) -> String {
        switch k {
        case .written: return GradeType.written.label
        case .oral: return GradeType.oral.label
        case .practical: return GradeType.practical.label
        case .other, nil: return ""
        }
    }

    // MARK: Decisione

    private func decide(_ c: PendingConflict, _ decision: ConflictDecision) {
        working = true
        Task {
            await registro.resolve(c.id, decision, sync: false)
            if decision == .later { postponed.insert(c.id) }
            answered += 1
            working = false
        }
    }
}
