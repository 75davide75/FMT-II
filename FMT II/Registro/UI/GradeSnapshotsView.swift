import SwiftUI

/// "Ripristina voti" (spec §6.2): copie dei voti con data e numero di voti.
/// Il ripristino chiede conferma e prima salva una copia dello stato attuale.
struct GradeSnapshotsView: View {
    @ObservedObject var grades: GradesStore
    let backups: GradeBackups

    @State private var snapshots: [GradeSnapshot] = []
    @State private var selected: GradeSnapshot?
    @State private var failure: String?
    @State private var restored = false

    var body: some View {
        Form {
            if snapshots.isEmpty {
                Section {
                    Text("Nessuna copia salvata finora. FMT ne crea una prima del collegamento al registro e prima di ogni sincronizzazione che cambia i voti.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.sectionCard)
            } else {
                Section {
                    ForEach(Array(snapshots.enumerated()), id: \.element.id) { i, s in
                        Button { selected = s } label: { row(s) }
                            .accessibilityIdentifier("registro.snapshot.\(i)")
                    }
                } header: {
                    SettingsView.header(L("Copie dei voti"))
                } footer: {
                    Text("Sono tenute le ultime 10 copie, più quella di prima del collegamento, che non viene mai eliminata. Le copie restano solo su questo dispositivo.")
                }
                .listRowBackground(Color.sectionCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background { AuroraBackground(section: .neutral) }
        .navigationTitle("Ripristina voti")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .alert("Ripristinare questa copia?",
               isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
               presenting: selected) { s in
            Button("Annulla", role: .cancel) {}
            Button("Ripristina", role: .destructive) { restore(s) }
        } message: { s in
            Text("I voti attuali verranno sostituiti con quelli della copia (\(gradesCountLabel(s.count))). Prima FMT salva una copia dello stato attuale, così puoi tornare indietro. I voti del registro assenti dalla copia non verranno reimportati.")
        }
        .alert("Errore", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        .alert("Voti ripristinati", isPresented: $restored) {
            Button("OK") {}
        }
    }

    private func row(_ s: GradeSnapshot) -> some View {
        HStack {
            SettingsView.row(RegistroText.snapshotKind(s.kind), icon: icon(s.kind), color(s.kind))
                .foregroundStyle(.primary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: gradesCountLabel(s.count))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(verbatim: s.date.appFormatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func icon(_ k: SnapshotKind) -> String {
        switch k {
        case .preLink: return "link"
        case .preSync: return "arrow.triangle.2.circlepath"
        case .preRestore: return "clock.arrow.2.circlepath"
        case .preUnlink: return "minus.circle.fill"
        }
    }

    private func color(_ k: SnapshotKind) -> String {
        switch k {
        case .preLink: return "#2DD4BF"
        case .preSync: return "#4E7CF6"
        case .preRestore: return "#38BDF8"
        case .preUnlink: return "#FB7185"
        }
    }

    private func reload() {
        snapshots = backups.list()
    }

    private func restore(_ s: GradeSnapshot) {
        if grades.restore(s) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            restored = true
        } else {
            failure = L("Impossibile ripristinare questa copia: i voti attuali non sono stati modificati.")
        }
        reload()
    }
}
