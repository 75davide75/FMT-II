import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import MessageUI

struct SettingsView: View {
    @ObservedObject var store: ScheduleStore
    var notesStore: NotesStore? = nil
    var gradesStore: GradesStore? = nil
    @AppStorage("appearanceMode") private var appearanceMode = "dark"   // scuro di default al primo avvio
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
                orarioSection
                importOrarioSection
                valutazioneSection
                backupSection
                supportSection
                infoSection
                dangerZoneSection
            }
            .scrollContentBackground(.hidden)
            .background { AuroraBackground(section: .neutral) }
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
        .modifier(FixedTypeSize(size: overrideTypeSize))
    }

    /// Header di sezione in maiuscoletto indaco (design 3e).
    static func header(_ text: String, tint: Color = Color(hex: "#A5B4FC")!) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .heavy))
            .kerning(1)
            .foregroundStyle(tint)
            .textCase(nil)
    }

    /// Etichetta con icona su badge sfumato, stile Impostazioni iOS.
    static func row(_ title: String, icon: String, _ hexColor: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(colors: [Color(hex: hexColor)!.blended(with: .white, by: 0.18), Color(hex: hexColor)!],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            Text(title)
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(selection: $appearanceMode) {
                Text("Automatico").tag("auto")
                Text("Chiaro").tag("light")
                Text("Scuro").tag("dark")
            } label: {
                Self.row("Tema", icon: "circle.lefthalf.filled", "#8B5CF6")
            }
            Picker(selection: $dynamicTypeLevel) {
                Text("Automatica").tag(0)
                Text("Grande").tag(1)
                Text("Molto grande").tag(2)
                Text("Enorme").tag(3)
            } label: {
                Self.row("Dimensione testo", icon: "textformat.size", "#4E7CF6")
            }
            if let schedule = store.schedule {
                NavigationLink {
                    EntityColorsView(schedule: schedule)
                } label: {
                    Self.row("Colori di classi e docenti", icon: "paintpalette.fill", "#F472B6")
                }
            }
        } header: {
            Self.header("Aspetto")
        } footer: {
            Text(store.schedule != nil
                 ? "Scegli un colore per ogni classe, docente o materia: lo ritrovi nella settimana, nel giorno e nel builder."
                 : "")
        }
        .listRowBackground(Color.sectionCard)
    }

    @ViewBuilder
    private var orarioSection: some View {
        if let schedule = store.schedule {
            Section {
                LabeledContent {
                    Text(schedule.sourceName).lineLimit(1).truncationMode(.middle)
                } label: {
                    Self.row("Sorgente", icon: "doc.fill", "#38BDF8")
                }
                LabeledContent {
                    Text("\(schedule.lessons.count) lezioni · \(schedule.classes.count) classi · \(schedule.teachers.count) docenti")
                } label: {
                    Self.row("Contenuto", icon: "square.grid.3x3.fill", "#4E7CF6")
                }
                Toggle(isOn: $useLiveTime) {
                    Self.row("Usa ora corrente", icon: "clock.arrow.circlepath", "#34D399")
                }
                if !useLiveTime {
                    Picker(selection: manualDay) {
                        ForEach(schedule.days) { day in
                            Text(day.label).tag(day.id)
                        }
                    } label: {
                        Self.row("Giorno", icon: "calendar", "#2DD4BF")
                    }
                    if !schoolTimes.isEmpty {
                        Picker(selection: $manualTime) {
                            ForEach(schoolTimes, id: \.self) { time in
                                Text(time).tag(time)
                            }
                        } label: {
                            Self.row("Ora", icon: "clock", "#60A5FA")
                        }
                        .pickerStyle(.menu)
                    }
                }
                if store.schedule?.edited == true {
                    Button { showBuilder = true } label: {
                        Self.row("Modifica orario", icon: "square.and.pencil", "#FB923C")
                            .foregroundStyle(.primary)
                    }
                }
                if store.savedPDFURL != nil {
                    Button { showPDFViewer = true } label: {
                        Self.row("PDF originale", icon: "doc.text.magnifyingglass", "#A78BFA")
                            .foregroundStyle(.primary)
                    }
                }
                Button { showDBDisclaimer = true } label: {
                    Self.row("Dati orario", icon: "slider.horizontal.3", "#F59E0B")
                        .foregroundStyle(.primary)
                }
            } header: {
                Self.header("Orario")
            } footer: {
                Text(useLiveTime
                     ? "Con l'ora corrente attiva, la vista Adesso segue l'orologio del dispositivo."
                     : "Giorno e ora fissati manualmente per consultare un momento specifico.")
            }
            .listRowBackground(Color.sectionCard)
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
                    Self.row("Importa orario PDF", icon: "square.and.arrow.up", "#38BDF8")
                        .foregroundStyle(.primary)
                }
                Button { showBuilder = true } label: {
                    Self.row("Crea il mio orario", icon: "square.and.pencil", "#4E7CF6")
                        .foregroundStyle(.primary)
                }
            } header: {
                Self.header("Orario")
            } footer: {
                Text("Importa il PDF dell'orario, oppure crealo a mano.")
            }
            .listRowBackground(Color.sectionCard)
        }
    }

    private var valutazioneSection: some View {
        Section {
            Stepper(value: $sufficientGrade, in: 1...(max(maxGrade - 1, 2)), step: 0.5) {
                HStack {
                    Self.row("Voto sufficiente", icon: "checkmark.seal.fill", "#34D399")
                    Spacer()
                    Text(sufficientGrade.italianGrade)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color(hex: "#6EE7B7")!)
                }
            }
            Stepper(value: $maxGrade, in: (sufficientGrade + 1)...20, step: 1) {
                HStack {
                    Self.row("Voto massimo", icon: "star.fill", "#FBBF24")
                    Spacer()
                    Text(maxGrade.italianGrade)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color(hex: "#FCD34D")!)
                }
            }
            Picker(selection: $periodSystemRaw) {
                Text("Quadrimestri").tag(PeriodSystem.quadrimestri.rawValue)
                Text("Trimestre + Pentamestre").tag(PeriodSystem.trimestre.rawValue)
            } label: {
                Self.row("Periodi", icon: "calendar.badge.clock", "#8B5CF6")
            }
            MonthDayField(
                timestamp: $period1EndTimestamp,
                system: PeriodSystem(rawValue: periodSystemRaw) ?? .quadrimestri,
                label: "Fine \(period1Label)"
            )
        } header: {
            Self.header("Voti")
        } footer: {
            Text("Scala dei voti e periodi: colori, obiettivi e medie si adattano subito. La fine del primo periodo usa solo giorno e mese.")
        }
        .listRowBackground(Color.sectionCard)
    }

    private var infoSection: some View {
        Section {
            LabeledContent("Versione", value: appVersion)
            LabeledContent("Sviluppatore", value: "Davide Sogos")
        } header: {
            Self.header("Informazioni")
        }
        .listRowBackground(Color.sectionCard)
    }

    private var supportSection: some View {
        Section {
            NavigationLink { TutorialView() } label: {
                Self.row("Tutorial", icon: "graduationcap.fill", "#4E7CF6")
            }
            NavigationLink { ManualView() } label: {
                Self.row("Manuale", icon: "book.fill", "#8B5CF6")
            }
            NavigationLink { BugReportView() } label: {
                Self.row("Segnala un problema", icon: "exclamationmark.bubble.fill", "#FB923C")
            }
            NavigationLink { AboutAppView() } label: {
                Self.row("Chi sono", icon: "person.fill", "#F472B6")
            }
        } header: {
            Self.header("Supporto")
        }
        .listRowBackground(Color.sectionCard)
    }

    @ViewBuilder
    private var backupSection: some View {
        if notesStore != nil || gradesStore != nil {
            Section {
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Self.row("Esporta backup", icon: "square.and.arrow.up", "#38BDF8")
                            .foregroundStyle(.primary)
                    }
                }
                Button {
                    showImporter = true
                } label: {
                    Self.row("Importa backup", icon: "square.and.arrow.down", "#34D399")
                        .foregroundStyle(.primary)
                }
            } header: {
                Self.header("Dati e backup")
            } footer: {
                Text("Un unico file con orario, diario e voti: esportalo per sicurezza o per passare a un altro dispositivo.")
            }
            .listRowBackground(Color.sectionCard)
        }
    }

    @ViewBuilder
    private var dangerZoneSection: some View {
        if store.schedule != nil || notesStore != nil || gradesStore != nil {
            Section {
                if store.schedule != nil {
                    Button {
                        if store.schedule?.edited == true { showOverwriteWarn = true }
                        else {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showFilePicker = true }
                        }
                    } label: {
                        Self.row("Cambia PDF", icon: "arrow.triangle.2.circlepath", "#FB923C")
                            .foregroundStyle(.primary)
                    }
                    Button(role: .destructive) { showClearConfirmation = true } label: {
                        Self.row("Rimuovi orario", icon: "trash.fill", "#FB7185")
                            .foregroundStyle(.red)
                    }
                }
                if notesStore != nil {
                    Button(role: .destructive) { showDeleteNotesConfirm = true } label: {
                        Self.row("Cancella tutto il diario", icon: "trash.fill", "#F43F5E")
                            .foregroundStyle(.red)
                    }
                }
                if gradesStore != nil {
                    Button(role: .destructive) { showDeleteGradesConfirm = true } label: {
                        Self.row("Cancella tutti i voti", icon: "trash.fill", "#E11D48")
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "#FB7185")!)
                    Self.header("Zona di rischio", tint: Color(hex: "#FB7185")!)
                }
            } footer: {
                Text("Azioni definitive: prima di procedere viene sempre chiesta conferma.")
            }
            .listRowBackground(Color.sectionCard)
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 8)

                // Badge a gradiente col saluto, in linea col resto dell'app.
                Text("CIAO ☺️")
                    .font(.system(size: 52, weight: .heavy))
                    .kerning(-1)
                    .padding(.top, 12)

                Text("developed by davide 😗")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(scheme == .dark ? Color(hex: "#C4B5FD")! : Color(hex: "#7C3AED")!)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#A78BFA")!.opacity(0.13), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(hex: "#A78BFA")!.opacity(0.28), lineWidth: 1))

                Text("Innanzitutto grazie, perché stai leggendo questa sezione — cosa che non fa mai nessuno. Sono uno studente che ha appena finito di fare la maturità e ha tanto tempo libero. Una cosa che ho odiato durante gli anni delle superiori è non ricordarmi mai l'orario: volevo inventare un modo per consultare qualunque orario velocemente, senza impazzire a trovare la propria sezione. Questo è il mio miglior tentativo, almeno per ora. Grazie per aver provato la mia prima applicazione.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(20)
                    .auroraCard(radius: 22)

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background { AuroraBackground(section: .neutral) }
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


// MARK: - Colori personalizzati (classi, docenti, materie)

private struct EntityColorTarget: Identifiable {
    let id = UUID()
    let name: String
}

struct EntityColorsView: View {
    let schedule: ScheduleData
    @AppStorage("entityColorsVersion") private var version = 0
    @State private var editing: EntityColorTarget?

    private var subjects: [String] {
        Array(Set(schedule.lessons.map { $0.subject }.filter { !$0.isEmpty }))
            .sorted { $0.compare($1, locale: Locale(identifier: "it")) == .orderedAscending }
    }

    var body: some View {
        List {
            let _ = version   // refresh quando cambia un colore
            if !schedule.classes.isEmpty {
                Section {
                    ForEach(schedule.classes, id: \.self) { colorRow($0) }
                } header: { SettingsView.header("Classi · \(schedule.classes.count)") }
                .listRowBackground(Color.sectionCard)
            }
            if !schedule.teachers.isEmpty {
                Section {
                    ForEach(schedule.teachers, id: \.self) { colorRow($0) }
                } header: { SettingsView.header("Docenti · \(schedule.teachers.count)") }
                .listRowBackground(Color.sectionCard)
            }
            if !subjects.isEmpty {
                Section {
                    ForEach(subjects, id: \.self) { colorRow($0) }
                } header: { SettingsView.header("Materie · \(subjects.count)") }
                .listRowBackground(Color.sectionCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background { AuroraBackground(section: .neutral) }
        .navigationTitle("Colori")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { target in
            EntityColorPickerSheet(name: target.name)
                .presentationDetents([.medium, .large])
        }
    }

    private func colorRow(_ name: String) -> some View {
        Button { editing = EntityColorTarget(name: name) } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(entityGradient(name))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
                if hasEntityColorOverride(name) {
                    Text("Personalizzato")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Griglia di colori per un singolo nome, con ritorno all'automatico.
struct EntityColorPickerSheet: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @AppStorage("entityColorsVersion") private var version = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    let _ = version
                    // Anteprima dell'etichetta con il colore attuale
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.system(size: 12, weight: .bold))
                            .kerning(0.2)
                            .foregroundStyle(entityLabelColor(entityTint(name), scheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(entityTint(name).opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(entityTint(name).opacity(0.30), lineWidth: 1))
                    }
                    .padding(.top, 6)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(entityPalette.indices, id: \.self) { i in
                            let c = entityPalette[i]
                            let isCurrent = entityTint(name).hexString == c.hexString
                            Button {
                                setEntityColor(c, for: name)
                            } label: {
                                Circle()
                                    .fill(LinearGradient(colors: [c.blended(with: .white, by: 0.2), c],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        if isCurrent {
                                            Image(systemName: "checkmark")
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .overlay(Circle().strokeBorder(.white.opacity(isCurrent ? 0.7 : 0.15), lineWidth: isCurrent ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)

                    if hasEntityColorOverride(name) {
                        Button {
                            setEntityColor(nil, for: name)
                        } label: {
                            Label("Usa colore automatico", systemImage: "wand.and.stars")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(18)
            }
            .background { AuroraBackground(section: .neutral) }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}
