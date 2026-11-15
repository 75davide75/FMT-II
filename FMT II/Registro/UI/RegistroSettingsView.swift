import SwiftUI

extension RegistroProviderID: Identifiable {
    var id: String { rawValue }
}

/// Riga "Registro elettronico" in Impostazioni, con il numero di voti da controllare.
struct RegistroSettingsRow: View {
    @ObservedObject var registro: RegistroSyncCoordinator

    var body: some View {
        HStack {
            SettingsView.row(L("Registro elettronico"), icon: "building.columns.fill", "#2DD4BF")
            Spacer()
            let pending = registro.pendingConflicts.count + registro.pendingSubjects.count
            if pending > 0 {
                RegistroBadge(count: pending)
            } else if let id = registro.connectedProvider {
                Text(verbatim: RegistroText.providerName(id))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Pallino arancione con un numero (cose da fare).
struct RegistroBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(hex: "#FB923C")!, in: Capsule())
    }
}

/// Impostazioni → Registro elettronico (spec §8): scelta del registro, stato,
/// sincronizzazione, conflitti, materie, notifiche, ripristino e scollegamento.
struct RegistroSettingsView: View {
    @ObservedObject var registro: RegistroSyncCoordinator
    @ObservedObject var grades: GradesStore
    @AppStorage(RegistroSyncCoordinator.Keys.notifyNewGrades) private var notifyNewGrades = false

    @State private var connecting: RegistroProviderID?
    @State private var showConflicts = false
    @State private var showUnlink = false

    private var connected: RegistroProviderID? { registro.connectedProvider }

    /// Voti collegati al registro (importati o manuali collegati).
    private var importedCount: Int {
        guard let connected else { return 0 }
        return grades.grades.filter { $0.origin?.provider == connected }.count
    }

    var body: some View {
        Form {
            if connected == nil {
                providersSection
            } else {
                statusSection
                if !registro.pendingConflicts.isEmpty { conflictsSection }
                subjectsSection
                notificationsSection
            }
            restoreSection
            if connected != nil { unlinkSection }
        }
        .scrollContentBackground(.hidden)
        .background { AuroraBackground(section: .neutral) }
        .navigationTitle("Registro elettronico")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $connecting) { id in
            RegistroConnectFlow(provider: id, registro: registro, grades: grades)
        }
        .sheet(isPresented: $showConflicts) {
            RegistroConflictView(registro: registro, grades: grades)
        }
        .sheet(isPresented: $showUnlink) {
            RegistroUnlinkSheet(registro: registro, grades: grades)
        }
    }

    // MARK: Scelta del registro

    private var providersSection: some View {
        Section {
            ForEach(RegistroText.providerOrder) { id in
                let available = registro.isAvailable(id)
                Button { connecting = id } label: {
                    HStack {
                        SettingsView.row(RegistroText.providerName(id), icon: "building.columns.fill",
                                         available ? "#2DD4BF" : "#64748B")
                            .foregroundStyle(.primary)
                        Spacer()
                        if available {
                            Text(verbatim: RegistroText.providerDetail(id))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        } else {
                            Text("Presto disponibile")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .opacity(available ? 1 : 0.55)
                }
                .disabled(!available)
                .accessibilityIdentifier("registro.provider.\(id.rawValue)")
            }
        } header: {
            SettingsView.header(L("Collega il registro"))
        } footer: {
            Text("I voti del registro arrivano nella tab Voti insieme a quelli che inserisci tu. Collegamento non ufficiale: tutto resta su questo dispositivo.")
        }
        .listRowBackground(Color.sectionCard)
    }

    // MARK: Stato

    private var statusSection: some View {
        Section {
            HStack {
                SettingsView.row(connected.map(RegistroText.providerName) ?? "", icon: "building.columns.fill", "#2DD4BF")
                Spacer()
                Text(RegistroText.status(registro.status))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusIsProblem ? Color(hex: "#FB923C")! : .secondary)
                    .accessibilityIdentifier("registro.status")
            }
            HStack {
                SettingsView.row(L("Ultima sincronizzazione"), icon: "clock.arrow.circlepath", "#4E7CF6")
                Spacer()
                Text(lastSyncText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            HStack {
                SettingsView.row(L("Voti importati"), icon: "tray.and.arrow.down.fill", "#34D399")
                Spacer()
                Text(verbatim: "\(importedCount)")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color(hex: "#6EE7B7")!)
                    .accessibilityIdentifier("registro.importedCount")
            }
            if registro.lastSkippedCount > 0 {
                HStack {
                    SettingsView.row(L("Voti non letti"), icon: "questionmark.circle.fill", "#FB923C")
                    Spacer()
                    Text(verbatim: "\(registro.lastSkippedCount)")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color(hex: "#FDBA74")!)
                        .accessibilityIdentifier("registro.skippedCount")
                }
            }
            if registro.lastRemovalCheckSkipped {
                Label {
                    Text("Il registro ha restituito molti meno voti del previsto: per sicurezza nessun voto è stato segnato come rimosso.")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "exclamationmark.shield.fill").foregroundStyle(Color(hex: "#FB923C")!)
                }
            }
            statusAction
            Button {
                Task { await registro.syncNow(.manual) }
            } label: {
                Self.syncLabel(syncing: registro.status == .syncing)
                    .opacity(canSync ? 1 : 0.4)
            }
            .disabled(!canSync)
            .accessibilityIdentifier("registro.syncNow")
        } header: {
            SettingsView.header(L("Stato"))
        } footer: {
            statusFooter
        }
        .listRowBackground(Color.sectionCard)
    }

    private static func syncLabel(syncing: Bool) -> some View {
        HStack {
            SettingsView.row(L("Sincronizza ora"), icon: "arrow.triangle.2.circlepath", "#4E7CF6")
                .foregroundStyle(.primary)
            Spacer()
            if syncing { ProgressView() }
        }
    }

    private var canSync: Bool {
        switch registro.status {
        case .syncing, .needsLogin, .disconnected: return false
        default: return true
        }
    }

    private var statusIsProblem: Bool {
        switch registro.status {
        case .needsLogin, .needsConfirmation, .error: return true
        default: return false
        }
    }

    private var lastSyncText: String {
        guard let date = registro.lastSync else { return L("Mai") }
        return date.appFormatted(date: .abbreviated, time: .shortened)
    }

    /// Azione richiesta dallo stato: nuovo accesso o conferma di un piano grande.
    @ViewBuilder
    private var statusAction: some View {
        switch registro.status {
        case .needsLogin:
            Button { connecting = connected } label: {
                SettingsView.row(L("Accedi di nuovo"), icon: "person.badge.key.fill", "#FB923C")
                    .foregroundStyle(.primary)
            }
            .accessibilityIdentifier("registro.relogin")
        case .needsConfirmation:
            Button {
                Task { await registro.confirmPendingPlan() }
            } label: {
                SettingsView.row(L("Applica le modifiche"), icon: "checkmark.circle.fill", "#FB923C")
                    .foregroundStyle(.primary)
            }
            .accessibilityIdentifier("registro.confirmPlan")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        switch registro.status {
        case .needsLogin:
            Text("Il registro ha rifiutato nome utente o password. Per evitare il blocco dell'account FMT non riprova da solo: accedi di nuovo.")
        case .needsConfirmation(let n):
            Text("Questa sincronizzazione modificherebbe \(n) voti inseriti da te. Per sicurezza viene applicata solo se confermi (prima viene salvata una copia dei voti).")
        case .error(let code):
            Text(RegistroText.message(forCode: code))
                .foregroundStyle(Color(hex: "#FB923C")!)
        default:
            Text("FMT legge i voti dal registro; non li modifica mai sul registro. I voti che inserisci tu non vengono mai cancellati.")
        }
    }

    // MARK: Conflitti

    private var conflictsSection: some View {
        Section {
            Button { showConflicts = true } label: {
                HStack {
                    SettingsView.row(L("Voti da controllare"), icon: "questionmark.square.dashed", "#FB923C")
                        .foregroundStyle(.primary)
                    Spacer()
                    RegistroBadge(count: registro.pendingConflicts.count)
                }
            }
            .accessibilityIdentifier("registro.conflicts")
        } footer: {
            Text("Voti del registro che potrebbero essere già nella tua lista: decidi tu se sono lo stesso voto.")
        }
        .listRowBackground(Color.sectionCard)
    }

    // MARK: Materie e notifiche

    private var subjectsSection: some View {
        Section {
            NavigationLink {
                SubjectMappingView(registro: registro, grades: grades, mode: .settings)
            } label: {
                HStack {
                    if registro.pendingSubjects.isEmpty {
                        SettingsView.row(L("Materie"), icon: "books.vertical.fill", "#8B5CF6")
                    } else {
                        SettingsView.row(L("Materie da confermare"), icon: "books.vertical.fill", "#8B5CF6")
                        Spacer()
                        RegistroBadge(count: registro.pendingSubjects.count)
                    }
                }
            }
            .accessibilityIdentifier(registro.pendingSubjects.isEmpty ? "registro.subjects" : "registro.pendingSubjects")
        } footer: {
            Text(registro.pendingSubjects.isEmpty
                 ? L("A quale materia dell'app corrisponde ogni materia del registro.")
                 : L("I voti delle materie non ancora confermate restano in attesa e non vengono importati."))
        }
        .listRowBackground(Color.sectionCard)
    }

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $notifyNewGrades) {
                SettingsView.row(L("Notifiche voti nuovi"), icon: "bell.badge.fill", "#F472B6")
            }
            .accessibilityIdentifier("registro.notify")
        } footer: {
            Text("Un avviso quando arrivano voti nuovi dal registro (mai per il primo import).")
        }
        .listRowBackground(Color.sectionCard)
    }

    // MARK: Ripristino e scollegamento

    private var restoreSection: some View {
        Section {
            NavigationLink {
                GradeSnapshotsView(grades: grades, backups: AppStores.gradeBackups)
            } label: {
                SettingsView.row(L("Ripristina voti"), icon: "clock.arrow.2.circlepath", "#38BDF8")
            }
            .accessibilityIdentifier("registro.restore")
        } header: {
            SettingsView.header(L("Copie di sicurezza"))
        } footer: {
            Text("Prima del collegamento e di ogni sincronizzazione che cambia qualcosa FMT salva una copia dei voti sul dispositivo.")
        }
        .listRowBackground(Color.sectionCard)
    }

    private var unlinkSection: some View {
        Section {
            Button(role: .destructive) { showUnlink = true } label: {
                SettingsView.row(L("Scollega"), icon: "minus.circle.fill", "#FB7185")
                    .foregroundStyle(.red)
            }
            .accessibilityIdentifier("registro.unlink")
        } footer: {
            Text("Scollegando, nome utente e password vengono cancellati dal Portachiavi.")
        }
        .listRowBackground(Color.sectionCard)
    }
}

// MARK: - Scollega

/// Scelta fra tenere o eliminare i voti importati (spec §6.5).
private struct RegistroUnlinkSheet: View {
    @ObservedObject var registro: RegistroSyncCoordinator
    @ObservedObject var grades: GradesStore
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var failure: String?

    /// Voti importati senza un valore numerico (giudizi come "N.C."): tenuti, perdono l'etichetta.
    private var nonNumericCount: Int {
        grades.grades.filter { $0.origin != nil && $0.origin?.manualSnapshot == nil && $0.origin?.numericValue == nil }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("I voti che hai inserito tu non vengono mai eliminati: quelli collegati al registro tornano come li avevi scritti, con le modifiche che hai fatto. Prima di scollegare FMT salva una copia di tutti i voti, ripristinabile da «Ripristina voti».")
                        .font(.subheadline)
                } header: {
                    SettingsView.header(L("Cosa succede"))
                }
                .listRowBackground(Color.sectionCard)

                Section {
                    Button { unlink(keep: true) } label: {
                        SettingsView.row(L("Tenere i voti importati"), icon: "tray.full.fill", "#34D399")
                            .foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("registro.unlink.keep")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Restano nella tab Voti come voti normali, senza collegamento al registro.")
                        if nonNumericCount > 0 {
                            Text("Attenzione: \(nonNumericCount) giudizi senza voto numerico (es. «N.C.») perdono l'etichetta del registro e restano come voti che non fanno media.")
                                .foregroundStyle(Color(hex: "#FB923C")!)
                        }
                    }
                }
                .listRowBackground(Color.sectionCard)

                Section {
                    Button(role: .destructive) { unlink(keep: false) } label: {
                        SettingsView.row(L("Eliminare i voti importati"), icon: "trash.fill", "#FB7185")
                            .foregroundStyle(.red)
                    }
                    .accessibilityIdentifier("registro.unlink.delete")
                } footer: {
                    Text("Vengono eliminati solo i voti arrivati dal registro che non hai modificato.")
                }
                .listRowBackground(Color.sectionCard)

                if let failure {
                    Section {
                        Text(failure).foregroundStyle(Color(hex: "#FB923C")!)
                    }
                    .listRowBackground(Color.sectionCard)
                }
            }
            .disabled(working)
            .scrollContentBackground(.hidden)
            .background { AuroraBackground(section: .neutral) }
            .navigationTitle("Scollega il registro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func unlink(keep: Bool) {
        working = true
        Task {
            await registro.unlink(keepImported: keep)
            working = false
            if registro.connectedProvider == nil {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } else if case .error(let code) = registro.status {
                failure = RegistroText.message(forCode: code)
            }
        }
    }
}
