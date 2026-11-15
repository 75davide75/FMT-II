import SwiftUI

/// Collegamento di un registro (spec §5, §7, §8): disclaimer da accettare →
/// accesso → conferma delle materie → primo import. Nessun voto viene scritto
/// prima della conferma delle materie. Per un nuovo accesso (credenziali
/// rifiutate) il disclaimer, già accettato, non si ripete.
struct RegistroConnectFlow: View {
    let provider: RegistroProviderID
    @ObservedObject var registro: RegistroSyncCoordinator
    @ObservedObject var grades: GradesStore

    @Environment(\.dismiss) private var dismiss

    private enum Step { case disclaimer, login, mapping }

    @State private var step: Step
    @State private var accepted = false
    @State private var username = ""
    @State private var password = ""
    @State private var schoolCode = ""
    @State private var working = false
    @State private var failure: String?
    @State private var proposals: [(RemoteSubjectRef, SubjectProposal)] = []

    init(provider: RegistroProviderID, registro: RegistroSyncCoordinator, grades: GradesStore) {
        self.provider = provider
        self.registro = registro
        self.grades = grades
        _step = State(initialValue: registro.connectedProvider == provider ? .login : .disclaimer)
    }

    private var name: String { RegistroText.providerName(provider) }
    private var fields: [LoginField] { registro.loginFields(for: provider) }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .disclaimer: disclaimer
                case .login: login
                case .mapping:
                    SubjectMappingView(registro: registro, grades: grades, mode: .firstLink,
                                       proposals: proposals) { _ in dismiss() }
                }
            }
            .toolbar {
                if step != .mapping {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { dismiss() }
                            .disabled(working)
                    }
                }
            }
        }
        .interactiveDismissDisabled(working || step == .mapping)
    }

    // MARK: Disclaimer

    private var disclaimer: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color(hex: "#2DD4BF")!)
                    Text("Prima di collegare \(name)")
                        .font(.title3.weight(.bold))
                    Text("Leggi con attenzione: per continuare devi accettare.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.sectionCard)

            Section {
                point("exclamationmark.triangle.fill", "#FB923C",
                      L("Collegamento non ufficiale: FMT non è affiliato né approvato da Spaggiari o da Argo."))
                point("bolt.horizontal.circle.fill", "#FBBF24",
                      L("FMT usa lo stesso accesso dell'app ufficiale: se il registro cambia, il collegamento può smettere di funzionare in qualsiasi momento."))
                point("lock.trianglebadge.exclamationmark.fill", "#FB7185",
                      L("Il registro potrebbe limitare o bloccare l'account se nota accessi insoliti. FMT sincronizza di rado e non riprova mai dopo una password rifiutata."))
                point("iphone", "#38BDF8",
                      L("I dati restano sul dispositivo: FMT parla solo con il registro, senza server propri. I voti importati vanno sui tuoi dispositivi via iCloud, come quelli che inserisci tu."))
                point("key.fill", "#34D399",
                      L("Nome utente e password vengono salvati nel Portachiavi di questo dispositivo (non su iCloud), solo per rinnovare l'accesso quando scade. Scollegando vengono cancellati."))
            } header: {
                SettingsView.header(L("Da sapere"))
            }
            .listRowBackground(Color.sectionCard)

            Section {
                Toggle(isOn: $accepted) {
                    Text("Ho letto e accetto")
                        .fontWeight(.semibold)
                }
                .accessibilityIdentifier("registro.disclaimer.accept")
                Button {
                    withAnimation { step = .login }
                } label: {
                    HStack {
                        Spacer()
                        Text("Continua").fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!accepted)
                .accessibilityIdentifier("registro.disclaimer.continue")
            }
            .listRowBackground(Color.sectionCard)
        }
        .scrollContentBackground(.hidden)
        .background { AuroraBackground(section: .neutral) }
        .navigationTitle(Text("Collega \(name)"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func point(_ icon: String, _ hex: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundStyle(Color(hex: hex)!)
        }
    }

    // MARK: Accesso

    private var login: some View {
        Form {
            Section {
                if fields.contains(.schoolCode) {
                    TextField(L("Codice scuola"), text: $schoolCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("registro.login.school")
                }
                TextField(L("Nome utente"), text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .accessibilityIdentifier("registro.login.username")
                SecureField(L("Password"), text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("registro.login.password")
            } header: {
                SettingsView.header(L("Accesso a \(name)"))
            } footer: {
                Text("Le stesse credenziali dell'app ufficiale dello studente. La password viene inviata solo al registro e salvata nel Portachiavi di questo dispositivo per rinnovare l'accesso quando la sessione scade.")
            }
            .listRowBackground(Color.sectionCard)

            if let failure {
                Section {
                    Label {
                        Text(failure).font(.subheadline)
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color(hex: "#FB923C")!)
                    }
                    .accessibilityIdentifier("registro.login.error")
                }
                .listRowBackground(Color.sectionCard)
            }

            Section {
                Button { submit() } label: {
                    HStack {
                        Spacer()
                        if working { ProgressView().padding(.trailing, 6) }
                        Text(working ? L("Accesso in corso…") : L("Accedi")).fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
                .accessibilityIdentifier("registro.login.submit")
            } footer: {
                Text("Dopo l'accesso controllerai le materie: nessun voto viene importato prima.")
            }
            .listRowBackground(Color.sectionCard)
        }
        .disabled(working)
        .scrollContentBackground(.hidden)
        .background { AuroraBackground(section: .neutral) }
        .navigationTitle(Text("Accedi a \(name)"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canSubmit: Bool {
        guard !working else { return false }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let school = schoolCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return !user.isEmpty && !password.isEmpty && (!fields.contains(.schoolCode) || !school.isEmpty)
    }

    /// Accesso e primo download (nessuna scrittura dei voti). Le credenziali non
    /// vengono mai mostrate né registrate nei log.
    private func submit() {
        let school = schoolCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let credentials = RegistroCredentials(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password,
            schoolCode: fields.contains(.schoolCode) ? school : nil)
        working = true
        failure = nil
        Task {
            do {
                let result = try await registro.connect(provider, credentials: credentials)
                password = ""
                if result.isEmpty {
                    // Nessuna materia nuova (es. nuovo accesso): sync col mapping già confermato.
                    await registro.confirmMapping(registro.mapping)
                    working = false
                    dismiss()
                } else {
                    proposals = result
                    working = false
                    withAnimation { step = .mapping }
                }
            } catch {
                working = false
                failure = RegistroText.message(for: error)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}
