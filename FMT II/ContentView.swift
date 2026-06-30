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
    @StateObject private var store = ScheduleStore()
    @StateObject private var notesStore = NotesStore()
    @StateObject private var gradesStore = GradesStore()
    @AppStorage("appearanceMode") private var appearanceMode = "auto"
    @AppStorage("useLiveTime") private var useLiveTime = true
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appSectionRaw") private var appSectionRaw = AppSection.notes.rawValue

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
    @AppStorage("dynamicTypeLevel") private var dynamicTypeLevel = 0

    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    /// Optional app-wide text-size override (nil = follow the system setting).
    private var overrideTypeSize: DynamicTypeSize? {
        switch dynamicTypeLevel {
        case 1: return .xLarge
        case 2: return .xxLarge
        case 3: return .xxxLarge
        case 4: return .accessibility2
        default: return nil
        }
    }

    var body: some View {
        Group {
            if !hasSeenTutorial {
                TutorialView(onDismiss: { withAnimation(.easeInOut(duration: 0.55)) { hasSeenTutorial = true } })
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
        .animation(.easeInOut(duration: 0.55), value: hasSeenTutorial)
        .modifier(FixedTypeSize(size: overrideTypeSize))
        .preferredColorScheme(preferredColorScheme)
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
        .alert("PDF non supportato", isPresented: $store.isPDFUnsupported) {
            Button("Annulla", role: .cancel) { store.isPDFUnsupported = false }
            Button("Prova un altro PDF") {
                store.isPDFUnsupported = false
                showFilePicker = true
            }
        } message: {
            Text("Non è stato possibile leggere l'orario. Il formato potrebbe non essere compatibile.")
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
            if hasSeenTutorial { hasCompletedOnboarding = true }
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
            SectionPager(count: sections.count, index: indexBinding, progress: $pagerProgress) { i in
                pageView(for: sections[i], isActive: i == activeIndex)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    GlassSectionBar(
                        titles: sections.map(\.title),
                        colors: sections.map(\.accent),
                        index: indexBinding,
                        progress: pagerProgress
                    )
                }
            }
            .sensoryFeedback(.selection, trigger: appSectionRaw)
        }
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
            // Same backdrop as the tutorial, so the crossfade looks like a
            // continuous gradient rather than a hard cut.
            Color(.systemGroupedBackground).ignoresSafeArea()
            LinearGradient(
                colors: [Color.indigo.opacity(0.12), .clear, Color.purple.opacity(0.10)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 110, height: 110)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 46))
                        .foregroundStyle(.tint)
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
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(isImporting)
                .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)

                if let onCreate {
                    Button(action: onCreate) {
                        Label("Crea il mio orario", systemImage: "square.and.pencil")
                            .font(.headline)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
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
