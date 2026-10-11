import SwiftUI
import Charts
import UIKit

// MARK: - Grades root view

struct GradesView: View {
    @ObservedObject var store: GradesStore
    @ObservedObject var scheduleStore: ScheduleStore
    @Binding var showFilePicker: Bool
    var isActive: Bool = true
    var notesStore: NotesStore? = nil

    @AppStorage("periodSystem") private var periodSystemRaw = PeriodSystem.quadrimestri.rawValue
    @AppStorage("period1EndTimestamp") private var period1EndTimestamp: Double = 0
    // Observed so grade colours refresh live when the scale changes in Settings.
    @AppStorage("sufficientGrade") private var sufficientGrade: Double = 6
    @AppStorage("maxGrade") private var maxGrade: Double = 10
    @Environment(\.deviceLayout) private var layout

    @State private var showGradeEntry = false
    @State private var showAllSubjects = false
    @State private var gradeToEdit: Grade? = nil
    @State private var showSettings = false
    @State private var openSubject: String? = nil

    private var period1End: Date? {
        if period1EndTimestamp > 0 { return Date(timeIntervalSince1970: period1EndTimestamp) }
        return defaultPeriod1End(for: periodSystem)
    }
    private var periodSystem: PeriodSystem { PeriodSystem(rawValue: periodSystemRaw) ?? .quadrimestri }
    private var periodLabel1: String { periodSystem == .quadrimestri ? L("1° Quadrimestre") : L("Trimestre") }
    private var periodLabel2: String { periodSystem == .quadrimestri ? L("2° Quadrimestre") : L("Pentamestre") }

    private var sortedGrades: [Grade] {
        store.grades.sorted { $0.date > $1.date }
    }

    private var votiSubtitle: String {
        "\(periodLabel2) · " + gradesCountLabel(store.grades.count)
    }

    var body: some View {
        // Touch the grading scale so the whole list re-renders (and recomputes
        // grade colours) when the sufficient/max grade changes elsewhere.
        let _ = sufficientGrade + maxGrade
        ZStack(alignment: .top) {
            Group {
                if store.grades.isEmpty {
                    emptyState
                } else {
                    gradesList
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isActive {
                // Stesso bottone ⋯ in tutte e tre le sezioni.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !store.grades.isEmpty {
                            Button { showAllSubjects = true } label: {
                                Label("Materie", systemImage: "list.bullet.below.rectangle")
                            }
                        }
                        Button { showSettings = true } label: {
                            Label("Impostazioni", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Altre azioni")
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // FAB "+" come nel Diario, con il gradiente della sezione Voti.
            if isActive {
                Button { showGradeEntry = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(
                            LinearGradient(colors: [Color(hex: "#8B5CF6")!, Color(hex: "#F472B6")!, Color(hex: "#F8A87E")!],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle()
                        )
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        .shadow(color: Color(hex: "#C4459E")!.opacity(0.55), radius: 15, y: 7)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 26)
                .accessibilityLabel("Aggiungi voto")
            }
        }
        .sheet(isPresented: $showGradeEntry) {
            GradeEntrySheet(store: store, schedule: scheduleStore.schedule)
        }
        .sheet(item: $gradeToEdit) { grade in
            GradeEntrySheet(store: store, grade: grade, schedule: scheduleStore.schedule)
        }
        .navigationDestination(isPresented: $showAllSubjects) {
            SubjectsListView(
                store: store,
                period1End: period1End,
                periodSystem: periodSystem,
                periodLabel1: periodLabel1,
                periodLabel2: periodLabel2,
                schedule: scheduleStore.schedule
            )
        }
        .navigationDestination(item: $openSubject) { subject in
            SubjectDetailView(
                subject: subject,
                store: store,
                period1End: period1End,
                periodSystem: periodSystem,
                periodLabel1: periodLabel1,
                periodLabel2: periodLabel2,
                schedule: scheduleStore.schedule
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: scheduleStore, notesStore: notesStore, gradesStore: store, showFilePicker: $showFilePicker)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(AuroraSection.voti.gradient).opacity(0.22).frame(width: 110, height: 110)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 46))
                    .foregroundStyle(AuroraSection.voti.accent)
            }
            VStack(spacing: 8) {
                Text("Ancora nessun voto")
                    .font(.title3.bold())
                Text("Tocca + per aggiungere il primo voto e iniziare a tenere d'occhio la media.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Titolo, media e ultimi voti (in cima su iPhone, colonna sinistra su iPad).
    @ViewBuilder
    private var gradesHeader: some View {
        AuroraTitle(title: L("Voti"), subtitle: votiSubtitle)
            .padding(.horizontal, 16)
            .padding(.top, 2)
        GradesSummaryCard(
            overall: store.overallAverage(),
            period1Avg: store.overallAverage(period: 1, periodBoundary: period1End),
            period2Avg: store.overallAverage(period: 2, periodBoundary: period1End),
            period1Label: periodLabel1,
            period2Label: periodLabel2
        )
        .padding(.horizontal, 16)

        if sortedGrades.count >= 2 {
            RecentGradesRow(grades: Array(sortedGrades.prefix(20)), onSeeAll: { showAllSubjects = true })
                .padding(.horizontal, 16)
        }
    }

    /// Un voto dell'elenco: tocco per modificare, menu (uguale ovunque).
    private func gradeRow(_ grade: Grade) -> some View {
        GradeHomeRow(grade: grade, trend: store.overallTrend(for: grade), color: store.color(for: grade.subject))
            .id("\(grade.id)-\(sufficientGrade)-\(maxGrade)")
            .contentShape(Rectangle())
            .onTapGesture { gradeToEdit = grade }
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contextMenu {
                Button { gradeToEdit = grade } label: { Label("Modifica", systemImage: "pencil") }
                Button { openSubject = grade.subject } label: { Label("Apri materia", systemImage: "chart.bar.doc.horizontal") }
                Button(role: .destructive) {
                    store.delete(ids: [grade.id])
                } label: { Label("Elimina", systemImage: "trash") }
            }
    }

    private var gradesList: some View {
        // L'id lega le righe alla scala voti: cambiandola in
        // Impostazioni i colori suff./insuff. si aggiornano subito.
        let _ = (sufficientGrade, maxGrade)
        return Group {
            switch layout {
            case .wide:
                // iPad in orizzontale: riepilogo a sinistra, elenco a destra.
                HStack(alignment: .top, spacing: 2) {
                    ScrollView {
                        VStack(spacing: 12) { gradesHeader }
                            .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: 380)
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(sortedGrades) { grade in
                                gradeRow(grade)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 90)
                    }
                }
            case .regular:
                // iPad in verticale: elenco su due colonne.
                ScrollView {
                    LazyVStack(spacing: 12) {
                        gradesHeader
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                  spacing: 12) {
                            ForEach(sortedGrades) { grade in
                                gradeRow(grade)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                    .padding(.bottom, 78)
                }
            case .compact:
                ScrollView {
                    LazyVStack(spacing: 12) {
                        gradesHeader
                        ForEach(sortedGrades) { grade in
                            gradeRow(grade)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .id("scale-\(sufficientGrade)-\(maxGrade)")
    }
}

/// «1 voto» / «N voti» nella lingua dell'app.
func gradesCountLabel(_ n: Int) -> String {
    n == 1 ? L("1 voto") : L("\(n) voti")
}

/// «+1,5» / «−0,5» (in inglese «+1.5»), senza decimali inutili.
func gradeDeltaText(_ delta: Double) -> String {
    let sign = delta >= 0 ? "+" : "−"
    let v = abs(delta)
    let text = v.formatted(.number.precision(.fractionLength(0...1)).locale(LanguageSettings.currentLocale))
    return sign + text
}

// MARK: - Grade home row

private struct GradeHomeRow: View {
    let grade: Grade
    let trend: GradeTrend?
    var color: Color = .gray

    var body: some View {
        HStack(spacing: 12) {
            // Per-subject colour bar
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [color.blended(with: .white, by: 0.25), color],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(grade.subject)
                    .font(.system(size: 16, weight: .bold))
                    .kerning(-0.2)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    AuroraChip(text: grade.type.label, color: grade.type.color)
                    Text(grade.date.appFormatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    if grade.countsForAverage && grade.weight != 1.0 {
                        Text("×\(Int((grade.weight * 100).rounded()))%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.white.opacity(0.07), in: Capsule())
                    }
                }
                if !grade.teacher.isEmpty {
                    Text(grade.teacher)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            HStack(alignment: .center, spacing: 8) {
                Text(grade.displayValue)
                    .font(.system(size: 26, weight: .heavy))
                    .kerning(-0.5)
                    .foregroundStyle(grade.displayColor)
                    .monospacedDigit()
                    .frame(minWidth: 46, alignment: .trailing)
                // Cerchietto trend (design 2c)
                Group {
                    if let trend {
                        Image(systemName: trend == .improved ? "arrow.up" : trend == .declined ? "arrow.down" : "equal")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(trend.color)
                            .frame(width: 20, height: 20)
                            .background(trend.color.opacity(0.14), in: Circle())
                            .overlay(Circle().strokeBorder(trend.color.opacity(0.3), lineWidth: 1))
                    }
                }
                .frame(width: 24)
            }
        }
        .padding(14)
        .auroraCard(radius: 14)
    }
}

// MARK: - Grades summary card

private struct GradesSummaryCard: View {
    let overall: Double?
    let period1Avg: Double?
    let period2Avg: Double?
    let period1Label: String
    let period2Label: String
    @ScaledMetric private var ring: CGFloat = 96
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08),
                            lineWidth: 10)
                if let avg = overall {
                    // Anello a gradiente conico proporzionato alla scala voti
                    // (design 2c).
                    let fraction = min(avg / maxGrade, 1.0)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            AngularGradient(
                                colors: [avg.gradeColor, avg.gradeColor.blended(with: Color(hex: "#A3E635")!, by: 0.75)],
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(-90 + 360 * fraction)
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: avg)
                }
                VStack(spacing: 1) {
                    Text(overall?.italianGrade ?? "—")
                        .font(.system(size: 24, weight: .heavy))
                        .kerning(-0.5)
                        .foregroundStyle(overall?.gradeColor ?? .secondary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: overall)
                    Text("MEDIA")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(.secondary)
                        .tracking(1.6)
                }
            }
            .frame(width: ring, height: ring)

            VStack(alignment: .leading, spacing: 12) {
                PeriodBarRow(label: period1Label, avg: period1Avg)
                PeriodBarRow(label: period2Label, avg: period2Avg)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .auroraCard(radius: 22)
    }
}

private struct PeriodBarRow: View {
    let label: String
    let avg: Double?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(avg?.italianGrade ?? L("N/D"))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(avg?.gradeColor ?? Color(.tertiaryLabel))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: avg)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        .frame(height: 7)
                    if let avg {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [avg.gradeColor, avg.gradeColor.blended(with: Color(hex: "#A3E635")!, by: 0.75)],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(geo.size.width * min(avg / maxGrade, 1.0), 0), height: 7)
                            .animation(.easeOut(duration: 0.5), value: avg)
                    }
                }
            }
            .frame(height: 7)
        }
    }
}

// MARK: - Recent grades bubbles

private struct RecentGradesRow: View {
    let grades: [Grade]
    var onSeeAll: (() -> Void)? = nil
    @ScaledMetric private var bubble: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ultimi voti")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                if let onSeeAll {
                    Button(action: onSeeAll) {
                        Text("Vedi tutti ›")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Color(hex: "#A5B4FC")!)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(grades) { grade in
                        let c = grade.displayColor
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(c.opacity(0.10))
                                    .frame(width: bubble, height: bubble)
                                Circle()
                                    .stroke(c.opacity(0.30), lineWidth: 1.5)
                                    .frame(width: bubble, height: bubble)
                                Text(grade.displayValue)
                                    .font(.system(.footnote, design: .rounded, weight: .bold))
                                    .foregroundStyle(c)
                            }
                            Text(grade.subject.prefix(5) + (grade.subject.count > 5 ? "." : ""))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: bubble)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .auroraCard(radius: 14)
    }
}

// MARK: - Gradient page background

/// Grey base + a soft tint gradient from the top and a fainter one from the
/// bottom, matching the look of the other sections. Use `.scrollContentBackground(.hidden)`
/// is applied internally so it works behind grouped Lists.
private struct GradientPageBackground: ViewModifier {
    var top: Color
    var bottom: Color

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    AuroraBackground(section: .voti)
                    LinearGradient(
                        colors: [top.opacity(0.12), .clear],
                        startPoint: .top, endPoint: .center
                    )
                    .ignoresSafeArea()
                }
            }
    }
}

extension View {
    func gradientPageBackground(top: Color, bottom: Color) -> some View {
        modifier(GradientPageBackground(top: top, bottom: bottom))
    }
}

// MARK: - Subjects list view

struct SubjectsListView: View {
    @ObservedObject var store: GradesStore
    let period1End: Date?
    let periodSystem: PeriodSystem
    let periodLabel1: String
    let periodLabel2: String
    var schedule: ScheduleData? = nil
    @AppStorage("sufficientGrade") private var sufficientGrade: Double = 6
    @AppStorage("maxGrade") private var maxGrade: Double = 10

    var body: some View {
        let _ = sufficientGrade + maxGrade
        List {
            ForEach(store.subjects, id: \.self) { subject in
                NavigationLink {
                    SubjectDetailView(
                        subject: subject,
                        store: store,
                        period1End: period1End,
                        periodSystem: periodSystem,
                        periodLabel1: periodLabel1,
                        periodLabel2: periodLabel2,
                        schedule: schedule
                    )
                } label: {
                    SubjectListRow(subject: subject, store: store)
                }
                .listRowBackground(Color.sectionCard)
            }
        }
        .id("scale-\(sufficientGrade)-\(maxGrade)")
        .navigationTitle("Materie")
        .navigationBarTitleDisplayMode(.large)
        .gradientPageBackground(top: .indigo, bottom: .blue)
    }
}

private struct SubjectListRow: View {
    let subject: String
    @ObservedObject var store: GradesStore

    private var avg: Double? { store.average(for: subject) }
    private var count: Int { store.gradesForSubject(subject).count }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(store.color(for: subject))
                .frame(width: 11, height: 11)
            VStack(alignment: .leading, spacing: 3) {
                Text(subject)
                    .font(.callout.bold())
                Text(gradesCountLabel(count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let avg {
                Text(avg.italianGrade)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(avg.gradeColor)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: avg)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Subject detail view

struct SubjectDetailView: View {
    let subject: String
    @ObservedObject var store: GradesStore
    let period1End: Date?
    let periodSystem: PeriodSystem
    let periodLabel1: String
    let periodLabel2: String
    var schedule: ScheduleData? = nil

    @State private var gradeToEdit: Grade? = nil
    @State private var targetAverage: Double = 6.0
    @State private var didInitTarget = false
    @State private var motivation: String = ""
    @State private var showColorPicker = false
    @Environment(\.colorScheme) private var scheme
    // Local mirrors of the grading scale so the view refreshes when it changes.
    @AppStorage("sufficientGrade") private var sufficientGrade: Double = 6
    @AppStorage("maxGrade") private var maxGrade: Double = 10

    private static var motivations: [String] { [
        L("Un voto alla volta: la media si costruisce con costanza. 💪"),
        L("Non è la singola interrogazione, è la rotta che tieni. 🚀"),
        L("Ogni studio di oggi è un voto migliore domani. 📚"),
        L("La distanza tra il 6 e l'8 è solo un po' di costanza in più. ⭐️"),
        L("Sbagliare fa parte del percorso: conta rialzare la media. 🌱"),
        L("Piccoli passi, grandi risultati. Continua così! 🎯"),
        L("Il prossimo voto è un'occasione, non una minaccia. 😉"),
        L("Credici: la media più alta è più vicina di quanto pensi. ✨")
    ] }

    private var targetOptions: [Double] {
        stride(from: sufficientGrade, through: maxGrade, by: 0.5).map { $0 }
    }

    private var grades: [Grade] { store.gradesForSubject(subject) }

    private var reachedGoal: Bool { (store.average(for: subject) ?? 0) >= targetAverage }

    private enum Goal {
        case reached
        case impossibleTen          // target 10 but not all grades are 10
        case needsOne(Double)       // a single grade of this value reaches the target
        case needsMany(Int)         // roughly this many top grades (10) are needed
    }

    /// How to reach `targetAverage` from the current subject grades.
    private func goal(for target: Double) -> Goal {
        let vals = grades.map(\.value)
        guard !vals.isEmpty else { return .needsOne(min(target, 10)) }
        let n = Double(vals.count)
        let sum = vals.reduce(0, +)
        if sum / n >= target { return .reached }
        let single = target * (n + 1) - sum
        if single <= maxGrade { return .needsOne(max(single, 1)) }
        if target >= maxGrade { return .impossibleTen }
        let k = Int(ceil((target * n - sum) / (maxGrade - target)))
        return .needsMany(max(k, 1))
    }

    private var subjectTeacher: String? {
        grades.last { !$0.teacher.isEmpty }?.teacher
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Titolo grande + chip conteggio e docente (design 2d).
                VStack(alignment: .leading, spacing: 8) {
                    Text(subject)
                        .font(.system(size: 32, weight: .heavy))
                        .kerning(-0.6)
                    HStack(spacing: 6) {
                        AuroraChip(text: gradesCountLabel(grades.count),
                                   color: store.color(for: subject))
                        if let t = subjectTeacher {
                            AuroraChip(text: t, color: Color(hex: "#60A5FA")!, icon: "person.fill")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 2)

                if grades.count >= 2 {
                    GradeChartView(grades: grades, tint: store.color(for: subject))
                }

                statsCard
                goalCard

                if !motivation.isEmpty {
                    Text(motivation)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 22)
                }

                gradesListCard
            }
            .padding(.vertical, 12)
        }
        .id("scale-\(sufficientGrade)-\(maxGrade)")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .gradientPageBackground(top: store.color(for: subject), bottom: store.color(for: subject))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showColorPicker = true } label: {
                    Circle()
                        .fill(store.color(for: subject))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                }
                .accessibilityLabel("Colore materia")
            }
        }
        .sheet(isPresented: $showColorPicker) {
            SubjectColorPickerSheet(store: store, subject: subject)
        }
        .sheet(item: $gradeToEdit) { grade in
            GradeEntrySheet(store: store, grade: grade, schedule: schedule)
        }
        .onAppear {
            if motivation.isEmpty { motivation = Self.motivations.randomElement() ?? "" }
            if !didInitTarget { targetAverage = sufficientGrade; didInitTarget = true }
        }
        .onChange(of: targetAverage) { _, _ in
            motivation = Self.motivations.randomElement() ?? ""
        }
        .sensoryFeedback(.selection, trigger: targetAverage)
        .sensoryFeedback(.success, trigger: reachedGoal)
    }

    // MARK: Card statistiche (design 2d: righe con hairline)

    private var statItems: [(label: String, value: Double)] {
        var items: [(String, Double)] = []
        if let a = store.average(for: subject) { items.append((L("Media"), a)) }
        if let a = store.average(for: subject, period: 1, periodBoundary: period1End) { items.append((periodLabel1, a)) }
        if let a = store.average(for: subject, period: 2, periodBoundary: period1End) { items.append((periodLabel2, a)) }
        return items
    }

    @ViewBuilder
    private var statsCard: some View {
        if !statItems.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(statItems.enumerated()), id: \.offset) { i, item in
                    if i > 0 { hairline }
                    HStack {
                        Text(item.label)
                            .font(.system(size: 14.5, weight: .semibold))
                        Spacer()
                        Text(item.value.italianGrade)
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(item.value.gradeColor)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: item.value)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                }
            }
            .auroraCard(radius: 22)
            .padding(.horizontal, 16)
        }
    }

    // MARK: Card obiettivo (design 2d: stepper nella card + esito)

    private var goalCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#A5B4FC")!)
                    .frame(width: 26)
                Text("Media obiettivo")
                    .font(.system(size: 14.5, weight: .semibold))
                Spacer()
                HStack(spacing: 10) {
                    stepButton("minus") {
                        targetAverage = max(sufficientGrade, targetAverage - 0.5)
                    }
                    Text(targetAverage.italianGrade)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color(hex: "#7CB3FF")!)
                        .frame(minWidth: 26)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: targetAverage)
                    stepButton("plus") {
                        targetAverage = min(maxGrade, targetAverage + 0.5)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05), in: Capsule())
                .overlay(Capsule().strokeBorder(scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08), lineWidth: 1))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            hairline

            goalResultRow
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
        }
        .auroraCard(radius: 22)
        .padding(.horizontal, 16)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(scheme == .dark ? Color(hex: "#C7D2FF")! : .primary)
                .frame(width: 24, height: 24)
                .background(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var hairline: some View {
        Rectangle()
            .fill(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 14)
    }


    @ViewBuilder
    private var goalResultRow: some View {
        switch goal(for: targetAverage) {
        case .reached:
            HStack(spacing: 10) {
                goalIcon("checkmark", tint: Color(hex: "#34D399")!)
                Text("Obiettivo raggiunto")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(scheme == .dark ? Color(hex: "#6EE7B7")! : Color(hex: "#047857")!)
                Spacer()
                if let avg = store.average(for: subject) {
                    Text("\(gradeDeltaText(avg - targetAverage)) sopra")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(scheme == .dark ? Color(hex: "#6EE7B7")! : Color(hex: "#047857")!)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#34D399")!.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(hex: "#34D399")!.opacity(0.28), lineWidth: 1))
                }
            }
        case .impossibleTen:
            HStack(spacing: 10) {
                goalIcon("exclamationmark.triangle.fill", tint: .orange)
                Text("Per il massimo servono solo voti pieni")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.orange)
                Spacer()
            }
        case .needsOne(let v):
            HStack(spacing: 10) {
                goalIcon("arrow.up.right", tint: Color(hex: "#7CB3FF")!)
                Text("Ti basta un voto da")
                    .font(.system(size: 14.5, weight: .semibold))
                Text(v.italianGrade)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(v.gradeColor)
                Spacer()
            }
        case .needsMany(let k):
            HStack(spacing: 10) {
                goalIcon("arrow.up.right", tint: Color(hex: "#7CB3FF")!)
                Text("Ti servono circa")
                    .font(.system(size: 14.5, weight: .semibold))
                Text("\(k)")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Color(hex: "#7CB3FF")!)
                Text("voti da \(maxGrade.italianGrade)")
                    .font(.system(size: 14.5, weight: .semibold))
                Spacer()
            }
        }
    }

    private func goalIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(tint.opacity(0.15), in: Circle())
            .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }

    // MARK: Card elenco voti

    private var gradesListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsView.header(L("Voti · \(grades.count)"))
                .padding(.leading, 6)
            VStack(spacing: 0) {
                let ordered = Array(grades.reversed())
                ForEach(Array(ordered.enumerated()), id: \.element.id) { i, grade in
                    if i > 0 { hairline }
                    GradeRowView(grade: grade, trend: store.subjectTrend(for: grade))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { gradeToEdit = grade }
                        .contextMenu {
                            Button { gradeToEdit = grade } label: { Label("Modifica", systemImage: "pencil") }
                            Button(role: .destructive) {
                                store.delete(ids: [grade.id])
                            } label: { Label("Elimina", systemImage: "trash") }
                        }
                }
            }
            .auroraCard(radius: 22)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Subject colour picker

struct SubjectColorPickerSheet: View {
    @ObservedObject var store: GradesStore
    let subject: String

    @Environment(\.dismiss) private var dismiss
    @State private var pendingColor: Color? = nil
    @State private var showConfirm = false
    @State private var conflicts: [String] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(subjectPalette.indices, id: \.self) { i in
                        let c = subjectPalette[i]
                        let isCurrent = store.color(for: subject).hexString == c.hexString
                        Button { choose(c) } label: {
                            Circle()
                                .fill(c)
                                .frame(width: 46, height: 46)
                                .overlay {
                                    if isCurrent {
                                        Image(systemName: "checkmark")
                                            .font(.headline.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay(Circle().strokeBorder(.primary.opacity(isCurrent ? 0.6 : 0), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Colore · \(subject)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fine") { dismiss() } }
            }
            .alert("Colore già usato", isPresented: $showConfirm, presenting: pendingColor) { c in
                Button("Usa comunque") { store.setColor(c, for: subject); dismiss() }
                Button("Annulla", role: .cancel) {}
            } message: { _ in
                Text("Questo colore è già usato da: \(conflicts.joined(separator: ", ")). Vuoi usarlo lo stesso?")
            }
        }
    }

    private func choose(_ c: Color) {
        let used = store.subjectsUsing(c, excluding: subject)
        if used.isEmpty {
            store.setColor(c, for: subject)
            dismiss()
        } else {
            conflicts = used
            pendingColor = c
            showConfirm = true
        }
    }
}

// MARK: - Grade chart (design 2d: card ANDAMENTO)

private struct GradeChartView: View {
    let grades: [Grade]

    var tint: Color = Color(hex: "#60A5FA")!

    // Le giustifiche non hanno valore numerico: fuori dal grafico.
    private var sorted: [Grade] { grades.filter { !$0.isGiustifica }.sorted { $0.date < $1.date } }
    @State private var selectedIndex: Int?
    @Environment(\.colorScheme) private var scheme

    private let rose = Color(hex: "#FB7185")!
    private let roseText = Color(hex: "#FDA4AF")!
    private let violet = Color(hex: "#A78BFA")!
    private let violetText = Color(hex: "#C4B5FD")!

    /// Riempimento interno dei punti: il colore della pagina, così l'anello
    /// colorato risalta come nel canvas.
    private var pointFill: Color {
        scheme == .dark ? Color(hex: "#0B101F")! : .white
    }

    private func pointColor(_ grade: Grade, index: Int) -> Color {
        if selectedIndex == index { return violet }
        if !grade.countsForAverage { return .blue }
        return grade.value < sufficientGrade ? rose : tint
    }

    private var yGridValues: [Double] {
        stride(from: 2.0, through: maxGrade, by: 2.0).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header della card: ANDAMENTO + dettaglio del punto toccato
            HStack(spacing: 7) {
                Text("ANDAMENTO")
                    .font(.system(size: 10.5, weight: .heavy))
                    .kerning(1)
                    .foregroundStyle(Color(hex: "#A5B4FC")!)
                Spacer()
                if let s = selectedIndex, s >= 0, s < sorted.count {
                    Circle()
                        .fill(pointColor(sorted[s], index: -1))
                        .frame(width: 7, height: 7)
                    Text(sorted[s].value.italianGrade)
                        .font(.system(size: 13, weight: .bold))
                    Text(sorted[s].date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("tocca un punto per i dettagli")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
            }
            .frame(height: 18)
            .animation(.easeInOut(duration: 0.15), value: selectedIndex)

            Chart {
                // Linea della sufficienza: rosa, tratteggiata (canvas 2d)
                RuleMark(y: .value(L("Sufficienza"), sufficientGrade))
                    .foregroundStyle(rose.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))

                ForEach(Array(sorted.enumerated()), id: \.offset) { i, grade in
                    LineMark(x: .value("n", i), y: .value(L("Voto"), grade.value))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(tint)

                    // Punto: anello colorato con interno scuro; alone violetto
                    // quando selezionato; insufficienze in rosa con valore sotto.
                    PointMark(x: .value("n", i), y: .value(L("Voto"), grade.value))
                        .symbolSize(0)
                        .annotation(position: .overlay) {
                            ZStack {
                                if selectedIndex == i {
                                    Circle().fill(violet.opacity(0.18)).frame(width: 24, height: 24)
                                }
                                Circle()
                                    .fill(selectedIndex == i ? violet : pointFill)
                                    .frame(width: selectedIndex == i ? 11 : 9, height: selectedIndex == i ? 11 : 9)
                                    .overlay(
                                        Circle().strokeBorder(
                                            selectedIndex == i ? violetText : pointColor(grade, index: i),
                                            lineWidth: selectedIndex == i ? 1.5 : 2)
                                    )
                            }
                        }
                        .annotation(position: grade.value < sufficientGrade ? .bottom : .top, spacing: 5) {
                            if selectedIndex == i {
                                Text(grade.value.italianGrade)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(violetText)
                            } else if grade.value < sufficientGrade {
                                Text(grade.value.italianGrade)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(roseText)
                            }
                        }
                }
            }
            .frame(height: 170)
            .chartYScale(domain: 1...(maxGrade + 0.4))
            .chartXScale(domain: -0.4 ... (Double(max(sorted.count - 1, 1)) + 0.4))
            .chartXSelection(value: $selectedIndex)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: yGridValues) { value in
                    let v = value.as(Double.self) ?? 0
                    let isSufficiency = abs(v - sufficientGrade) < 0.01
                    if !isSufficiency {
                        // La riga della sufficienza è già il RuleMark rosa.
                        AxisGridLine().foregroundStyle(.white.opacity(scheme == .dark ? 0.06 : 0.0))
                        if scheme == .light {
                            AxisGridLine().foregroundStyle(.black.opacity(0.06))
                        }
                    }
                    AxisValueLabel()
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isSufficiency ? rose.opacity(0.7)
                                         : (scheme == .dark ? Color(hex: "#E2E8FF")!.opacity(0.35) : Color.secondary))
                }
            }
            .animation(.easeOut(duration: 0.2), value: selectedIndex)
            .sensoryFeedback(.selection, trigger: selectedIndex)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: scheme == .dark
                        ? [.white.opacity(0.08), .white.opacity(0.035)]
                        : [.white.opacity(0.92), .white.opacity(0.65)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.65), lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.07), radius: 14, y: 6)
        .padding(.horizontal, 16)
    }
}

// MARK: - Grade row

struct GradeRowView: View {
    let grade: Grade
    var trend: GradeTrend? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label(grade.type.label, systemImage: grade.type.icon)
                    .font(.callout.weight(.medium))
                Text(grade.date.appFormatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !grade.note.isEmpty {
                    Text(grade.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                if let trend {
                    Image(systemName: trend.systemImage)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(trend.color)
                        .accessibilityLabel(trend == .improved ? L("Ha alzato la media della materia")
                                             : trend == .declined ? L("Ha abbassato la media della materia")
                                             : L("Media della materia invariata"))
                }
                Text(grade.displayValue)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(grade.displayColor)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Grade entry sheet

struct GradeEntrySheet: View {
    @ObservedObject var store: GradesStore
    var grade: Grade? = nil
    var schedule: ScheduleData? = nil

    /// Subjects common to most Italian schools, offered as suggestions even
    /// before the user has ever entered them. Anything missing the user can add,
    /// and it becomes a suggestion from then on (via `store.subjects`).
    private static var commonSubjects: [String] { SubjectSuggestions.all }

    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var teacher = ""
    @State private var value: Double = 6.0
    @State private var date = Date()
    @State private var type: GradeType = .oral
    @State private var note = ""
    @State private var subjectError = false
    @State private var weight: Double = 1.0
    @State private var countsForAverage = true

    @AppStorage("periodSystem") private var periodSystemRaw = PeriodSystem.quadrimestri.rawValue
    @AppStorage("period1EndTimestamp") private var period1EndTimestamp: Double = 0

    private var isNew: Bool { grade == nil }
    private var period1End: Date? {
        if period1EndTimestamp > 0 { return Date(timeIntervalSince1970: period1EndTimestamp) }
        return defaultPeriod1End(for: periodSystem)
    }
    private var periodSystem: PeriodSystem { PeriodSystem(rawValue: periodSystemRaw) ?? .quadrimestri }

    private var gradePeriodLabel: String {
        let period = store.gradePeriod(for: date, boundary: period1End)
        if period == 1 {
            return periodSystem == .quadrimestri ? L("1° Quadrimestre") : L("Trimestre")
        } else {
            return periodSystem == .quadrimestri ? L("2° Quadrimestre") : L("Pentamestre")
        }
    }

    private var subjectSuggestions: [String] {
        let q = subject.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        // User's own subjects first, then the common catalogue, de-duplicated.
        var seen = Set<String>()
        var pool: [String] = []
        for s in store.subjects + Self.commonSubjects where seen.insert(s.lowercased()).inserted {
            pool.append(s)
        }
        return pool
            .filter { $0.lowercased().contains(q) && $0.lowercased() != q }
            .prefix(5)
            .map { $0 }
    }

    private var teacherSuggestions: [String] {
        let q = teacher.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        // With a schedule loaded, autocomplete from its teachers; otherwise fall
        // back to teachers the user has typed on previous grades.
        let base: [String]
        if let schedule, !schedule.teachers.isEmpty {
            base = schedule.teachers
        } else {
            base = Array(Set(store.grades.compactMap { $0.teacher.isEmpty ? nil : $0.teacher }))
        }
        return base
            .filter { $0.lowercased().contains(q) && $0.lowercased() != q }
            .sorted()
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section("Materia") {
                    TextField(
                        "",
                        text: $subject,
                        prompt: Text(subjectError ? L("Campo obbligatorio") : L("Es. Matematica"))
                            .foregroundStyle(subjectError ? Color.red : Color.secondary)
                    )
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onChange(of: subject) { _, _ in subjectError = false }
                    .onSubmit { if let first = subjectSuggestions.first { subject = first } }
                    ForEach(subjectSuggestions, id: \.self) { s in
                        Button { subject = s } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(s)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .id("materia")

                Section("Professore") {
                    TextField("Es. ROSSI", text: $teacher)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .submitLabel(.done)
                        .onSubmit { if let first = teacherSuggestions.first { teacher = first } }
                    ForEach(teacherSuggestions, id: \.self) { t in
                        Button { teacher = t } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(t)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // La giustifica non è un voto: niente valore da scegliere.
                if type != .giustifica {
                    Section("Voto") {
                        GradeValuePickerView(value: $value)
                    }
                }

                Section {
                    Picker("Tipo", selection: $type) {
                        ForEach(GradeType.allCases, id: \.rawValue) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                } footer: {
                    Text(type == .giustifica
                         ? L("La giustifica viene registrata come «G»: non ha voto, non ha peso e non fa media.")
                         : L("Periodo: \(gradePeriodLabel). Cambia la data per modificare il periodo."))
                }

                if type != .giustifica {
                    Section {
                        Toggle(isOn: $countsForAverage) {
                            Label("Fa media", systemImage: "function")
                        }
                        if countsForAverage {
                            HStack {
                                Label("Peso", systemImage: "scalemass")
                                Spacer()
                                Text("\(Int((weight * 100).rounded()))%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $weight, in: 0...1, step: 0.05)
                        }
                    } footer: {
                        Text(countsForAverage
                             ? L("Il peso determina quanto incide nella media ponderata.")
                             : L("Il voto verrà mostrato in blu e non conterà nella media."))
                    }
                }

                Section("Annotazione") {
                    TextField("Opzionale", text: $note, axis: .vertical)
                        .lineLimit(3, reservesSpace: false)
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            if let g = grade {
                                store.delete(ids: [g.id])
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Elimina voto", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? L("Nuovo voto") : L("Modifica voto"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") {
                        guard !subject.trimmingCharacters(in: .whitespaces).isEmpty else {
                            // Il campo materia torna in vista anche da fine
                            // pagina, così è chiaro cosa manca.
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                                subjectError = true
                                proxy.scrollTo("materia", anchor: .top)
                            }
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                            return
                        }
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
            }
        }
        .onAppear { setupInitialState() }
    }

    private func setupInitialState() {
        if let g = grade {
            subject = g.subject
            teacher = g.teacher
            value = g.value
            date = g.date
            type = g.type
            note = g.note
            weight = g.weight
            countsForAverage = g.countsForAverage
        }
    }

    private func save() {
        var g = grade ?? Grade()
        g.subject = subject.trimmingCharacters(in: .whitespaces)
        g.teacher = teacher.trimmingCharacters(in: .whitespaces)
        g.value = value
        g.date = date
        g.type = type
        g.note = note.trimmingCharacters(in: .whitespaces)
        g.weight = weight
        g.countsForAverage = countsForAverage
        if type == .giustifica {
            // Nessun voto e nessun peso: la "G" non entra mai nella media.
            g.countsForAverage = false
            g.weight = 1.0
        }
        if isNew { store.add(g) } else { store.update(g) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Grade value picker

struct GradeValuePickerView: View {
    @Binding var value: Double

    // Index 0 = 1.0, step 0.25, up to the configured maximum grade.
    private var steps: Int { max(Int(((maxGrade - 1.0) / 0.25).rounded()), 1) }

    private var selectedIndex: Binding<Int> {
        Binding(
            get: { min(max(Int(((value - 1.0) / 0.25).rounded()), 0), steps) },
            set: { value = 1.0 + Double($0) * 0.25 }
        )
    }

    private var isMax: Bool { value >= maxGrade - 0.001 }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 3) {
                // Stelline quando è il voto massimo della scala.
                if isMax {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: "sparkle")
                                .font(.system(size: i == 1 ? 12 : 8, weight: .bold))
                                .foregroundStyle(Color(hex: "#FBBF24")!)
                                .shadow(color: Color(hex: "#FBBF24")!.opacity(0.8), radius: 3)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                Text(value.italianGrade)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(value.gradeColor)
            }
            .frame(width: 72, alignment: .center)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isMax)
            .animation(.easeInOut(duration: 0.1), value: value)
            .sensoryFeedback(.success, trigger: isMax)

            Picker("", selection: selectedIndex) {
                ForEach(0...steps, id: \.self) { i in
                    let v = 1.0 + Double(i) * 0.25
                    Text(v.italianGrade).tag(i)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
        }
    }
}
