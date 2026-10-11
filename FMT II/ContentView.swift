import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - App sections

enum AppSection: String, CaseIterable {
    case schedule = "schedule"
    case notes = "notes"
    case grades = "grades"
}

// MARK: - Root

struct ContentView: View {
    // Store condivisi da tutte le finestre (e dalla sync iCloud).
    @ObservedObject private var store = AppStores.shared.schedule
    @ObservedObject private var notesStore = AppStores.shared.notes
    @ObservedObject private var gradesStore = AppStores.shared.grades
    @AppStorage("appearanceMode") private var appearanceMode = "dark"   // scuro di default al primo avvio
    @AppStorage("useLiveTime") private var useLiveTime = true
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appSectionRaw") private var appSectionRaw = AppSection.notes.rawValue
    @AppStorage("dynamicTypeLevel") private var dynamicTypeLevel = 0
    @AppStorage(WhatsNew.storageKey) private var lastSeenWhatsNew = ""

    /// Valutato una volta all'avvio: il tutorial era già stato fatto prima di
    /// questo lancio (= aggiornamento)? Chi installa da zero non lo vede mai.
    @State private var showWhatsNew = ContentView.initialShowWhatsNew

    /// Layout iPad: dalla size class e dalla larghezza della finestra.
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var windowWidth: CGFloat = 0

    @State private var showFilePicker = false
    @State private var showTutorial = false
    @State private var targetMode: TargetMode = .class_
    @State private var viewMode: ViewMode = .now
    @State private var selectedClass = ""
    @State private var teacherQuery = ""
    @State private var clock = Date()
    @State private var lessonTapCount = 0
    @State private var showEasterEgg = false
    @State private var pagerProgress: CGFloat = 0
    @State private var showBuilder = false


    /// Text-size override, re-applied to the toolbar bar because UIKit-hosted
    /// toolbar content doesn't always inherit the app-root setting.
    private var overrideTypeSize: DynamicTypeSize? {
        switch dynamicTypeLevel {
        case 1: return .xLarge
        case 2: return .xxLarge
        case 3: return .xxxLarge
        default: return nil
        }
    }

    var body: some View {
        Group {
            if !hasSeenTutorial {
                TutorialView(onDismiss: {
                    lastSeenWhatsNew = WhatsNew.version   // nuova installazione: niente banner novità
                    withAnimation(.easeInOut(duration: 0.55)) { hasSeenTutorial = true }
                })
                    .transition(.opacity)
            } else if showEasterEgg {
                EasterEggView { showEasterEgg = false; lessonTapCount = 0 }
            } else if !hasCompletedOnboarding && store.schedule == nil {
                WelcomeView(
                    isImporting: false,
                    errorMessage: store.errorMessage,
                    onImport: { showFilePicker = true },
                    onShowTutorial: { showTutorial = true },
                    onSkip: { hasCompletedOnboarding = true },
                    onCreate: { showBuilder = true }
                )
                .transition(.opacity)
            } else {
                pagedSectionContent
            }
        }
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { windowWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in windowWidth = w }
            }
        }
        .environment(\.deviceLayout, DeviceLayout.resolve(horizontalSizeClass: hSizeClass, width: windowWidth))
        .animation(.easeInOut(duration: 0.55), value: hasSeenTutorial)
        .onChange(of: appearanceMode) { _, mode in applyAppearanceMode(mode) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                clock = Date()
            }
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerView(types: [.pdf, .json]) { url in
                showFilePicker = false
                Task {
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    guard let data = try? Data(contentsOf: url) else { return }
                    await store.importFile(data: data, name: url.lastPathComponent)
                    if let s = store.schedule {
                        selectedClass = resolveDefaultClass(s.classes, current: selectedClass)
                        appSectionRaw = AppSection.schedule.rawValue
                        hasCompletedOnboarding = true
                    }
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showBuilder) {
            NavigationStack {
                ScheduleBuilderView(existing: store.schedule) { newSchedule in
                    store.update(newSchedule)
                    selectedClass = resolveDefaultClass(newSchedule.classes, current: selectedClass)
                    appSectionRaw = AppSection.schedule.rawValue
                    hasCompletedOnboarding = true
                }
            }
        }
        .sheet(isPresented: $showTutorial) {
            NavigationStack {
                TutorialView(onDismiss: { showTutorial = false })
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Chiudi") { showTutorial = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
        }
        .alert("Import non riuscito", isPresented: Binding(
            get: { store.rejection != nil },
            set: { if !$0 { store.rejection = nil } }
        )) {
            Button("Crea orario manualmente") {
                store.rejection = nil
                showBuilder = true
            }
            Button("Prova un altro PDF") {
                store.rejection = nil
                showFilePicker = true
            }
            Button("Annulla", role: .cancel) { store.rejection = nil }
        } message: {
            Text("\(store.rejection?.message ?? "") Puoi creare l'orario manualmente.")
        }
        .sheet(isPresented: Binding(
            get: { store.pendingCompletion != nil },
            set: { if !$0 { store.pendingCompletion = nil } }
        )) {
            if let missing = store.pendingCompletion {
                ImportReviewView(store: store, missing: missing, onOpenBuilder: { showBuilder = true })
            }
        }
        .alert("Errore", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onAppear {
            applyAppearanceMode(appearanceMode)
            if hasSeenTutorial { hasCompletedOnboarding = true }
            #if DEBUG
            // Seed di dati demo per gli screenshot (solo con -FMTSeedDemo).
            DemoSeed.seedIfRequested(schedule: store, notes: notesStore, grades: gradesStore)
            let dbgArgs = ProcessInfo.processInfo.arguments
            if let i = dbgArgs.firstIndex(of: "-FMTViewMode"), i + 1 < dbgArgs.count {
                switch dbgArgs[i + 1] {
                case "day":  viewMode = .day
                case "week": viewMode = .week
                default:     viewMode = .now
                }
            }
            #endif
            CloudSyncManager.shared.start(grades: gradesStore, notes: notesStore, schedule: store)
            SettingsSync.shared.start()
            // A freddo la classe selezionata è vuota: riparti dalla
            // predefinita, altrimenti l'Orario mostra solo ore libere.
            if selectedClass.isEmpty, let s = store.schedule {
                selectedClass = resolveDefaultClass(s.classes, current: selectedClass)
            }
            // Hook di test: consente di pilotare un import PDF dal simulatore
            // (usato per demo/verifiche; inattivo in produzione).
            if let path = ProcessInfo.processInfo.environment["FMT_IMPORT_PDF"],
               let data = FileManager.default.contents(atPath: path) {
                Task {
                    await store.importFile(data: data, name: (path as NSString).lastPathComponent)
                    if let s = store.schedule {
                        selectedClass = resolveDefaultClass(s.classes, current: selectedClass)
                        appSectionRaw = AppSection.schedule.rawValue
                        hasCompletedOnboarding = true
                    }
                }
            }
        }
        .onChange(of: store.schedule) { _, newSchedule in
            if let s = newSchedule {
                selectedClass = resolveDefaultClass(s.classes, current: selectedClass)
            } else {
                appSectionRaw = AppSection.notes.rawValue
            }
        }
    }

    private var availableSections: [AppSection] {
        store.schedule != nil ? [.schedule, .notes, .grades] : [.notes, .grades]
    }

    @ViewBuilder
    private var pagedSectionContent: some View {
        let sections = availableSections
        let indexBinding = Binding<Int>(
            get: {
                let current = AppSection(rawValue: appSectionRaw) ?? .notes
                return sections.firstIndex(of: current) ?? 0
            },
            set: { newValue in
                let clamped = min(max(newValue, 0), sections.count - 1)
                appSectionRaw = sections[clamped].rawValue
            }
        )

        let activeIndex = indexBinding.wrappedValue

        NavigationStack {
            ZStack {
                // Sfondo unico: le aurore delle sezioni dissolvono l'una
                // nell'altra seguendo il pager (design 3a).
                AuroraCrossfadeBackground(
                    sections: sections.map(\.aurora),
                    progress: pagerProgress
                )
                SectionPager(count: sections.count, index: indexBinding, progress: $pagerProgress) { i in
                    pageView(for: sections[i], isActive: i == activeIndex)
                        .modifier(SectionEntrance(distance: CGFloat(i) - pagerProgress))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    GlassSectionBar(
                        titles: sections.map(\.title),
                        colors: sections.map(\.accent),
                        index: indexBinding,
                        progress: pagerProgress
                    )
                    .modifier(FixedTypeSize(size: overrideTypeSize))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sensoryFeedback(.selection, trigger: appSectionRaw)
            .overlay {
                if showWhatsNew {
                    WhatsNewBanner {
                        withAnimation(.easeInOut(duration: 0.3)) { showWhatsNew = false }
                        lastSeenWhatsNew = WhatsNew.version
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private static var initialShowWhatsNew: Bool {
        let defaults = UserDefaults.standard
        #if DEBUG
        // Screenshot App Store: niente banner, a meno di chiederlo esplicitamente.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-FMTShowWhatsNew") { return true }
        if DemoSeed.isRequested { return false }
        #endif
        return WhatsNew.shouldShow(tutorialDoneAtLaunch: defaults.bool(forKey: "hasSeenTutorial"),
                                   lastSeen: defaults.string(forKey: WhatsNew.storageKey) ?? "")
    }

    @ViewBuilder
    private func pageView(for section: AppSection, isActive: Bool) -> some View {
        switch section {
        case .schedule:
            scheduleSection(isActive: isActive)
        case .notes:
            NotesListView(
                store: notesStore,
                schedule: store.schedule,
                scheduleStore: store,
                showFilePicker: $showFilePicker,
                isActive: isActive,
                gradesStore: gradesStore
            )
        case .grades:
            GradesView(
                store: gradesStore,
                scheduleStore: store,
                showFilePicker: $showFilePicker,
                isActive: isActive,
                notesStore: notesStore
            )
        }
    }

    @ViewBuilder
    private func scheduleSection(isActive: Bool) -> some View {
        MainScheduleView(
            store: store,
            notesStore: notesStore,
            targetMode: $targetMode,
            viewMode: $viewMode,
            selectedClass: $selectedClass,
            teacherQuery: $teacherQuery,
            clock: $clock,
            showFilePicker: $showFilePicker,
            isActive: isActive,
            gradesStore: gradesStore,
            onLessonCountTap: {
                lessonTapCount += 1
                if lessonTapCount >= 10 { showEasterEgg = true }
            }
        )
    }
}

// MARK: - Welcome screen

struct WelcomeView: View {
    let isImporting: Bool
    let errorMessage: String?
    let onImport: () -> Void
    let onShowTutorial: () -> Void
    var onSkip: (() -> Void)? = nil
    var onCreate: (() -> Void)? = nil

    var body: some View {
        ZStack {
            // Stesso sfondo aurora del tutorial, così la dissolvenza resta continua.
            AuroraBackground(section: .neutral)

            VStack(spacing: 32) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(AuroraSection.neutral.gradient)
                        .opacity(0.22)
                        .frame(width: 110, height: 110)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 46))
                        .foregroundStyle(AuroraSection.neutral.gradient)
                }

                VStack(spacing: 8) {
                    Text("FindMyTeacher")
                        .font(.title.bold())
                    Text("Importa il PDF dell'orario, oppure crealo a mano")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let err = errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button(action: onImport) {
                    Label(isImporting ? "Caricamento..." : "Importa PDF", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(AuroraSection.neutral.gradient, in: Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(isImporting)
                .shadow(color: AuroraSection.neutral.tintB.opacity(0.35), radius: 8, y: 4)

                if let onCreate {
                    Button(action: onCreate) {
                        Label("Crea il mio orario", systemImage: "square.and.pencil")
                            .font(.headline)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(AuroraSection.neutral.tintB.opacity(0.16), in: Capsule())
                            .foregroundStyle(AuroraSection.neutral.accent)
                    }
                }

                if let onSkip {
                    Button(action: onSkip) {
                        Label("Salta per ora", systemImage: "arrow.right")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onShowTutorial) {
                    Label("Tutorial", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 36)
            }
            .padding(32)
        }
    }
}

// MARK: - Unsupported PDF screen

struct UnsupportedPDFView: View {
    let onRetry: () -> Void
    @State private var showContactSheet = false

    var body: some View {
        ZStack {
            Color(.secondarySystemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.10))
                        .frame(width: 110, height: 110)
                    Image(systemName: "doc.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                }

                VStack(spacing: 10) {
                    Text("PDF non supportato")
                        .font(.title2.bold())
                    Text("Non è stato possibile leggere l'orario da questo file.\nIl formato potrebbe non essere compatibile.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 14) {
                    Button(action: onRetry) {
                        Label("Prova un altro PDF", systemImage: "doc.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)

                    Button {
                        showContactSheet = true
                    } label: {
                        Label("Contatta l'assistenza", systemImage: "envelope")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 32)
            }
            .padding(32)
        }
        .sheet(isPresented: $showContactSheet) {
            NavigationStack {
                BugReportView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Chiudi") { showContactSheet = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
        }
    }
}

// MARK: - Easter egg

struct EasterEggView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                Button(action: onDismiss) {
                    Image(systemName: "arrow.left")
                        .font(.title2)
                        .padding()
                        .background(.ultraThinMaterial, in: Circle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                Spacer()
                Text("ao ma la smetti di cliccare? hai capito che questo tasto non funziona. Comunque troppe lezioni pure noi ci siamo stancati.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Text("developed by davide 😗")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

// MARK: - Utility functions

/// Applica il tema a livello di finestra: a differenza di
/// `preferredColorScheme(nil)`, tornare ad «Automatico» segue subito il
/// sistema anche negli sheet già aperti.
func applyAppearanceMode(_ mode: String) {
    let style: UIUserInterfaceStyle
    switch mode {
    case "light": style = .light
    case "dark": style = .dark
    default: style = .unspecified
    }
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
        for window in scene.windows { window.overrideUserInterfaceStyle = style }
    }
}

enum TargetMode { case class_, teacher }
enum ViewMode { case now, day, week }

func dayFromDate(_ date: Date) -> DayId? {
    let weekday = Calendar.current.component(.weekday, from: date)
    switch weekday {
    case 2: return .monday
    case 3: return .tuesday
    case 4: return .wednesday
    case 5: return .thursday
    case 6: return .friday
    default: return nil
    }
}

func timeFromDate(_ date: Date) -> String {
    String(format: "%02d:%02d",
           Calendar.current.component(.hour, from: date),
           Calendar.current.component(.minute, from: date))
}

func resolveTeacher(_ teachers: [String], query: String) -> String? {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return nil }
    return teachers.first { $0.lowercased() == q }
        ?? teachers.first { $0.lowercased().hasPrefix(q) }
        ?? teachers.first { $0.lowercased().contains(q) }
}

func resolveDefaultClass(_ classes: [String], current: String) -> String {
    if classes.contains(current) { return current }
    return classes.first { normalizeClassKey($0) == "5GSA" } ?? classes.first ?? ""
}

func normalizeClassKey(_ name: String) -> String {
    name.applyingTransform(.stripDiacritics, reverse: false)?
        .uppercased()
        .components(separatedBy: .alphanumerics.inverted).joined() ?? name.uppercased()
}

func findCurrentLesson(_ lessons: [Lesson], day: DayId?, time: String) -> Lesson? {
    guard let day else { return nil }
    let mins = minutesFromMidnight(time)
    return lessons.first {
        $0.day == day
        && mins >= minutesFromMidnight($0.startTime)
        && mins < minutesFromMidnight($0.endTime)
    }
}

func findNextLesson(_ lessons: [Lesson], day: DayId?, time: String, current: Lesson?) -> Lesson? {
    guard let day else { return nil }
    let threshold = current.map { minutesFromMidnight($0.startTime) } ?? minutesFromMidnight(time)
    return lessons
        .filter { $0.day == day && minutesFromMidnight($0.startTime) > threshold }
        .sorted { minutesFromMidnight($0.startTime) < minutesFromMidnight($1.startTime) }
        .first
}

func nearestTimeIndex(_ time: String, times: [String]) -> Int {
    guard !times.isEmpty else { return 0 }
    let mins = minutesFromMidnight(time)
    var nearest = 0; var dist = Int.max
    for (i, t) in times.enumerated() {
        let d = abs(mins - minutesFromMidnight(t))
        if d < dist { dist = d; nearest = i }
    }
    return nearest
}

func weekendText(day: DayId?, time: String) -> String {
    guard day != nil else { return "Oggi non è nel calendario scolastico." }
    let mins = minutesFromMidnight(time)
    if mins < minutesFromMidnight("08:10") { return "Le lezioni non sono ancora iniziate." }
    if mins >= minutesFromMidnight("14:10") { return "Le lezioni sono terminate." }
    return "Nessun docente in questa fascia."
}

// MARK: - Document picker

struct DocumentPickerView: UIViewControllerRepresentable {
    let types: [UTType]
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

/// Applies a fixed Dynamic Type size when set; otherwise follows the system.
struct FixedTypeSize: ViewModifier {
    let size: DynamicTypeSize?
    func body(content: Content) -> some View {
        if let size {
            content.dynamicTypeSize(size)
        } else {
            content
        }
    }
}

#Preview {
    ContentView()
}
