import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import MessageUI

struct SettingsView: View {
    @ObservedObject var store: ScheduleStore
    var notesStore: NotesStore? = nil
    var gradesStore: GradesStore? = nil
    @AppStorage("appearanceMode") private var appearanceMode = "auto"
    @AppStorage("useLiveTime") private var useLiveTime = true
    @AppStorage("manualDayRaw") private var manualDayRaw = "monday"
    @AppStorage("manualTime") private var manualTime = "08:10"
    @AppStorage("periodSystem") private var periodSystemRaw = PeriodSystem.quadrimestri.rawValue
    @AppStorage("period1EndTimestamp") private var period1EndTimestamp: Double = 0
    @AppStorage("dynamicTypeLevel") private var dynamicTypeLevel = 0
    @AppStorage("sufficientGrade") private var sufficientGrade: Double = 6
    @AppStorage("maxGrade") private var maxGrade: Double = 10
    @AppStorage("appSectionRaw") private var appSectionRaw = AppSection.notes.rawValue

    @Binding var showFilePicker: Bool
    @Environment(\.dismiss) private var dismiss

    /// Text-size override mirrored from the app root, re-applied here because a
    /// sheet doesn't always inherit it. Capped at "Enorme".
    private var overrideTypeSize: DynamicTypeSize? {
        switch dynamicTypeLevel {
        case 1: return .xLarge
        case 2: return .xxLarge
        case 3: return .xxxLarge
        default: return nil
        }
    }

    @State private var showPDFViewer = false
    @State private var showClearConfirmation = false
    @State private var showDBDisclaimer = false
    @State private var goToDBEditor = false
    @State private var showBuilder = false
    @State private var showOverwriteWarn = false
    @State private var showDeleteNotesConfirm = false
    @State private var showDeleteGradesConfirm = false
    @State private var backupURL: URL?
    @State private var showImporter = false
    @State private var showImportConfirm = false
    @State private var pendingBackup: BackupData?
    @State private var importError: String?

    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var manualDay: Binding<DayId> {
        Binding(
            get: { DayId(rawValue: manualDayRaw) ?? .monday },
            set: { manualDayRaw = $0.rawValue }
        )
    }

    var schoolTimes: [String] {
        guard let s = store.schedule, let last = s.periods.last else { return [] }
        return s.periods.map { $0.startTime } + [last.endTime]
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                accessibilitySection
                consultazioneSection
                importOrarioSection
                scheduleManagementSection
                valutazioneSection
                periodiSection
                backupSection
                infoSection
                supportSection
                dangerZoneSection
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showPDFViewer) {
                if let url = store.savedPDFURL {
                    PDFViewerSheet(url: url)
                }
            }
            .alert("Rimuovere l'orario?", isPresented: $showClearConfirmation) {
                Button("Rimuovi", role: .destructive) {
                    store.clearSchedule()
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    dismiss()
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("L'orario verrà eliminato. Potrai caricarne uno nuovo in qualsiasi momento.")
            }
            .alert("Cancellare tutto il diario?", isPresented: $showDeleteNotesConfirm) {
                Button("Annulla", role: .cancel) {}
                Button("Conferma", role: .destructive) {
                    notesStore?.deleteAll()
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    appSectionRaw = AppSection.notes.rawValue
                    dismiss()
                }
            } message: {
                Text("Tutte le voci del diario, archivio incluso, verranno eliminate. L'azione non è reversibile.")
            }
            .alert("Cancellare tutti i voti?", isPresented: $showDeleteGradesConfirm) {
                Button("Annulla", role: .cancel) {}
                Button("Conferma", role: .destructive) {
                    gradesStore?.deleteAll()
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    appSectionRaw = AppSection.grades.rawValue
                    dismiss()
                }
            } message: {
                Text("Tutti i voti verranno eliminati. L'azione non è reversibile.")
            }
            .onAppear { backupURL = makeBackupFile() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result {
                    loadBackup(from: url)
                } else {
                    importError = "Impossibile aprire il file."
                }
            }
            .alert("Ripristinare il backup?", isPresented: $showImportConfirm, presenting: pendingBackup) { backup in
                Button("Annulla", role: .cancel) {}
                Button("Ripristina", role: .destructive) {
                    notesStore?.replaceAll(backup.notes)
                    gradesStore?.replaceAll(backup.grades)
                    if let s = backup.schedule { store.restore(s) }
                }
            } message: { backup in
                let orario = backup.schedule != nil ? ", orario incluso" : ""
                Text("I dati attuali verranno sostituiti con il backup: \(backup.notes.count) voci di diario e \(backup.grades.count) voti\(orario). L'azione non è reversibile.")
            }
            .alert("Errore", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .alert("Modifica database", isPresented: $showDBDisclaimer) {
                Button("Annulla", role: .cancel) {}
                Button("Continua", role: .destructive) { goToDBEditor = true }
            } message: {
                Text("Sei sicuro di voler modificare il database? Modifiche non corrette potrebbero impedire il corretto funzionamento dell'app.")
            }
            .navigationDestination(isPresented: $goToDBEditor) {
                DatabaseEditorView(store: store)
            }
            .alert("Sostituire il tuo orario?", isPresented: $showOverwriteWarn) {
                Button("Annulla", role: .cancel) {}
                Button("Continua", role: .destructive) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showFilePicker = true }
                }
            } message: {
                Text("Hai creato il tuo orario a mano: importando un PDF verrà sostituito (solo se la lettura va a buon fine).")
            }
            .fullScreenCover(isPresented: $showBuilder) {
                NavigationStack {
                    ScheduleBuilderView(existing: store.schedule) { newSchedule in
                        store.update(newSchedule)
                    }
                }
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .modifier(FixedTypeSize(size: overrideTypeSize))
    }

    private var appearanceSection: some View {
        Section {
            Picker("Modalità", selection: $appearanceMode) {
                Label("Automatica", systemImage: "circle.lefthalf.filled").tag("auto")
                Label("Chiara", systemImage: "sun.max").tag("light")
                Label("Scura", systemImage: "moon.fill").tag("dark")
            }
            .pickerStyle(.inline)
        } header: {
            Text("Aspetto")
        }
    }

    private var accessibilitySection: some View {
        Section {
            Picker(selection: $dynamicTypeLevel) {
                Text("Automatica").tag(0)
                Text("Grande").tag(1)
                Text("Molto grande").tag(2)
                Text("Enorme").tag(3)
            } label: {
                Label("Dimensione testo", systemImage: "textformat.size")
            }
        } header: {
            Text("Accessibilità")
        } footer: {
            Text("Ingrandisce tutti i testi dell'app per una lettura più comoda.")
        }
    }

    @ViewBuilder
    private var consultazioneSection: some View {
        Section {
            Toggle(isOn: $useLiveTime) {
                Label("Usa ora corrente", systemImage: "clock.arrow.circlepath")
            }
            if !useLiveTime {
                if let schedule = store.schedule {
                    Picker(selection: manualDay) {
                        ForEach(schedule.days) { day in
                            Text(day.label).tag(day.id)
                        }
                    } label: {
                        Label("Giorno", systemImage: "calendar")
                    }
                }
                if !schoolTimes.isEmpty {
                    Picker(selection: $manualTime) {
                        ForEach(schoolTimes, id: \.self) { time in
                            Text(time).tag(time)
                        }
                    } label: {
                        Label("Ora", systemImage: "clock")
                    }
                    .pickerStyle(.menu)
                }
            }
        } header: {
            Text("Orario di consultazione")
        } footer: {
            Text(useLiveTime
                 ? "Viene usata l'ora del dispositivo, aggiornata ogni 30 secondi."
                 : "Imposta manualmente il giorno e l'ora per visualizzare le lezioni in un momento specifico.")
        }
    }

    @ViewBuilder
    private var importOrarioSection: some View {
        if store.schedule == nil {
            Section {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showFilePicker = true }
                } label: {
                    Label("Importa orario PDF", systemImage: "square.and.arrow.up")
                }
                Button { showBuilder = true } label: {
                    Label("Crea il mio orario", systemImage: "square.and.pencil")
                }
            } header: {
                Text("Orario scolastico")
            } footer: {
                Text("Importa il PDF dell'orario, oppure crealo a mano.")
            }
        }
    }

    private var valutazioneSection: some View {
        Section {
            Stepper(value: $sufficientGrade, in: 1...(max(maxGrade - 1, 2)), step: 0.5) {
                LabeledContent("Voto sufficiente", value: sufficientGrade.italianGrade)
            }
            Stepper(value: $maxGrade, in: (sufficientGrade + 1)...20, step: 1) {
                LabeledContent("Voto massimo", value: maxGrade.italianGrade)
            }
        } header: {
            Text("Valutazione")
        } footer: {
            Text("Personalizza la scala dei voti: la sufficienza minima e il voto massimo. Colori e obiettivi si adattano di conseguenza.")
        }
    }

    private var periodiSection: some View {
        Section {
            Picker("Sistema", selection: $periodSystemRaw) {
                Text("Quadrimestri").tag(PeriodSystem.quadrimestri.rawValue)
                Text("Trimestre + Pentamestre").tag(PeriodSystem.trimestre.rawValue)
            }
            MonthDayField(
                timestamp: $period1EndTimestamp,
                system: PeriodSystem(rawValue: periodSystemRaw) ?? .quadrimestri,
                label: "Fine \(period1Label)"
            )
        } header: {
            Text("Periodi scolastici")
        } footer: {
            Text("I voti vengono suddivisi in base alla data di fine del primo periodo (solo giorno e mese: l'anno è automatico).")
        }
    }

    private var infoSection: some View {
        Section("Informazioni") {
            LabeledContent("Versione", value: appVersion)
            LabeledContent("Sviluppatore", value: "Davide Sogos")
        }
    }

    private var supportSection: some View {
        Section("Supporto") {
            NavigationLink { TutorialView() } label: {
                Label("Tutorial", systemImage: "graduationcap")
            }
            NavigationLink { ManualView() } label: {
                Label("Manuale", systemImage: "book")
            }
            NavigationLink { BugReportView() } label: {
                Label("Segnala un problema", systemImage: "exclamationmark.bubble")
            }
            NavigationLink { AboutAppView() } label: {
                Label("Chi sono", systemImage: "person.circle")
            }
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        if notesStore != nil || gradesStore != nil {
            Section {
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("Esporta backup", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Importa backup", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Esporta diario e voti in un file, o importane uno per ripristinarli.")
            }
        }
    }

    @ViewBuilder
    private var scheduleManagementSection: some View {
        if let schedule = store.schedule {
            Section {
                LabeledContent("Sorgente", value: schedule.sourceName)
                LabeledContent("Lezioni", value: schedule.lessons.count.formatted())
                LabeledContent("Classi", value: schedule.classes.count.formatted())
                LabeledContent("Docenti", value: schedule.teachers.count.formatted())
                if let from = schedule.startsFrom {
                    LabeledContent("Valido dal", value: from)
                }
                LabeledContent("Importato il", value: formattedDate(schedule.importedAt))
            } header: {
                Text("Orario caricato")
            }

            Section {
                if store.schedule?.edited == true {
                    Button { showBuilder = true } label: {
                        Label("Modifica orario", systemImage: "square.and.pencil")
                    }
                }
                if store.savedPDFURL != nil {
                    Button { showPDFViewer = true } label: {
                        Label("Visualizza PDF originale", systemImage: "doc.text.magnifyingglass")
                    }
                }
                Button { showDBDisclaimer = true } label: {
                    Label("Modifica database", systemImage: "slider.horizontal.3")
                }
            } header: {
                Text("Azioni")
            }
        }
    }

    @ViewBuilder
    private var dangerZoneSection: some View {
        if store.schedule != nil || notesStore != nil || gradesStore != nil {
            Section {
                DangerZoneView(
                    onChangePDF: store.schedule != nil ? {
                        if store.schedule?.edited == true {
                            showOverwriteWarn = true
                        } else {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showFilePicker = true }
                        }
                    } : nil,
                    onRemove: store.schedule != nil ? { showClearConfirmation = true } : nil,
                    onDeleteNotes: notesStore != nil ? { showDeleteNotesConfirm = true } : nil,
                    onDeleteGrades: gradesStore != nil ? { showDeleteGradesConfirm = true } : nil
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            }
        }
    }

    private func makeBackupFile() -> URL? {
        let backup = BackupData(notes: notesStore?.notes ?? [], grades: gradesStore?.grades ?? [], schedule: store.schedule)
        guard let data = try? JSONEncoder().encode(backup) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FMT-backup.json")
        do { try data.write(to: url); return url } catch { return nil }
    }

    private func loadBackup(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let backup = try? JSONDecoder().decode(BackupData.self, from: data) else {
            importError = "File di backup non valido."
            return
        }
        pendingBackup = backup
        showImportConfirm = true
    }

    private var period1Label: String {
        periodSystemRaw == PeriodSystem.quadrimestri.rawValue ? "1° Quadrimestre" : "Trimestre"
    }

    private var period1EndBinding: Binding<Date> {
        Binding(
            get: {
                if period1EndTimestamp > 0 { return Date(timeIntervalSince1970: period1EndTimestamp) }
                var comps = Calendar.current.dateComponents([.year, .month], from: Date())
                if (comps.month ?? 1) >= 9 { comps.year = (comps.year ?? 2024) + 1 }
                comps.month = 1; comps.day = 31
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { period1EndTimestamp = $0.timeIntervalSince1970 }
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        display.locale = Locale(identifier: "it_IT")
        return display.string(from: date)
    }
}

// MARK: - Month/Day picker (year inferred)

/// Lets the user pick only a day + month; the year is inferred from the current
/// school year (so it stays the same every year, as the user expects).
private struct MonthDayField: View {
    @Binding var timestamp: Double
    let system: PeriodSystem
    let label: String

    private static let months = ["Gennaio", "Febbraio", "Marzo", "Aprile", "Maggio", "Giugno",
                                 "Luglio", "Agosto", "Settembre", "Ottobre", "Novembre", "Dicembre"]

    private var date: Date {
        timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : defaultPeriod1End(for: system)
    }
    private var month: Int { Calendar.current.component(.month, from: date) }
    private var day: Int { Calendar.current.component(.day, from: date) }
    private var daysInMonth: Int { daysIn(month: month, year: Calendar.current.component(.year, from: date)) }

    var body: some View {
        HStack {
            Label(label, systemImage: "calendar")
            Spacer()
            Menu {
                ForEach(1...daysInMonth, id: \.self) { d in
                    Button("\(d)") { set(month: month, day: d) }
                }
            } label: {
                Text("\(day)").fontWeight(.medium).foregroundStyle(.tint)
            }
            Menu {
                ForEach(1...12, id: \.self) { m in
                    Button(Self.months[m - 1]) { set(month: m, day: day) }
                }
            } label: {
                Text(Self.months[month - 1]).fontWeight(.medium).foregroundStyle(.tint)
            }
        }
    }

    private func set(month: Int, day: Int) {
        timestamp = schoolYearDate(month: month, day: day).timeIntervalSince1970
    }
}

// MARK: - Danger Zone

private struct DangerZoneView: View {
    var onChangePDF: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var onDeleteNotes: (() -> Void)? = nil
    var onDeleteGrades: (() -> Void)? = nil

    private struct Row: Identifiable {
        let id = UUID()
        let label: String
        let icon: String
        let destructive: Bool
        let action: () -> Void
    }

    private var rows: [Row] {
        var r: [Row] = []
        if let a = onChangePDF { r.append(Row(label: "Cambia PDF", icon: "arrow.triangle.2.circlepath", destructive: false, action: a)) }
        if let a = onRemove { r.append(Row(label: "Rimuovi orario", icon: "trash", destructive: true, action: a)) }
        if let a = onDeleteNotes { r.append(Row(label: "Cancella tutto il diario", icon: "trash", destructive: true, action: a)) }
        if let a = onDeleteGrades { r.append(Row(label: "Cancella tutti i voti", icon: "trash", destructive: true, action: a)) }
        return r
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text("ZONA DI RISCHIO")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.pink)
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.leading, 16) }
                    Button(action: row.action) {
                        HStack {
                            Label(row.label, systemImage: row.icon)
                                .foregroundStyle(row.destructive ? Color.red : Color.primary)
                            Spacer()
                            if !row.destructive {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        Color.pink.opacity(0.45),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 4])
                    )
            )
        }
    }
}

// MARK: - Chi sono

struct AboutAppView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer().frame(height: 20)
                Text("CIAO ☺️")
                    .font(.system(size: 64, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Innanzitutto grazie, perché stai leggendo questa sezione — cosa che non fa mai nessuno. Sono uno studente che ha appena finito di fare la maturità e ha tanto tempo libero. Una cosa che ho odiato durante gli anni delle superiori è non ricordarmi mai l'orario: volevo inventare un modo per consultare qualunque orario velocemente, senza impazzire a trovare la propria sezione. Questo è il mio miglior tentativo, almeno per ora. Grazie per aver provato la mia prima applicazione.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Chi sono")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Segnalazione problema

enum MailResult { case sent, cancelled, failed }

struct BugReportView: View {
    static let supportEmail = "davidesogos@gmail.com"

    @State private var messageText = ""
    @State private var userEmail = ""
    @State private var showMail = false
    @State private var showNoMailAlert = false
    @State private var result: MailResult? = nil

    private var mailBody: String {
        """
        Un utente ha segnalato un problema.

        Email: \(userEmail)

        Descrizione:
        \(messageText)
        """
    }

    private var canSubmit: Bool {
        !userEmail.trimmingCharacters(in: .whitespaces).isEmpty &&
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if result == .sent {
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.green)
                    Text("Segnalazione inviata!")
                        .font(.title2.bold())
                    Text("Grazie per il feedback.\nTi risponderò appena possibile.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                Form {
                    Section {
                        TextField("La tua email", text: $userEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("La tua email")
                    } footer: {
                        Text("Serve per poterti rispondere.")
                    }

                    Section {
                        TextEditor(text: $messageText)
                            .frame(minHeight: 160)
                    } header: {
                        Text("Descrivi il problema")
                    } footer: {
                        Text("Si aprirà l'app Mail con il messaggio già pronto, da inviare a \(Self.supportEmail).")
                    }

                    if result == .failed {
                        Section {
                            Text("Invio non riuscito dall'app Mail. Riprova.")
                                .foregroundStyle(.red).font(.callout)
                        }
                    }

                    Section {
                        Button {
                            if MFMailComposeViewController.canSendMail() {
                                showMail = true
                            } else {
                                showNoMailAlert = true
                            }
                        } label: {
                            Label("Invia segnalazione", systemImage: "paperplane.fill")
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
        }
        .navigationTitle("Segnala un problema")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMail) {
            MailComposeView(
                recipient: Self.supportEmail,
                subject: "SEGNALAZIONE FMT",
                body: mailBody
            ) { r in
                result = r
            }
            .ignoresSafeArea()
        }
        .alert("Mail non configurata", isPresented: $showNoMailAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Per inviare la segnalazione configura un account nell'app Mail, oppure scrivi a \(Self.supportEmail).")
        }
    }
}

struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onFinish: (MailResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MailResult) -> Void
        init(onFinish: @escaping (MailResult) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            controller.dismiss(animated: true)
            switch result {
            case .sent:   onFinish(.sent)
            case .failed: onFinish(.failed)
            default:      onFinish(.cancelled)
            }
        }
    }
}

// MARK: - PDF Viewer

struct PDFViewerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("PDF Orario")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: url, preview: SharePreview("PDF Orario", image: Image(systemName: "doc.fill")))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Chiudi") { dismiss() }
                    }
                }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
