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

    @State private var showGradeEntry = false
    @State private var gradeToEdit: Grade? = nil
    @State private var showSettings = false
    @State private var openSubject: String? = nil

    private var period1End: Date? {
        if period1EndTimestamp > 0 { return Date(timeIntervalSince1970: period1EndTimestamp) }
        return defaultPeriod1End(for: periodSystem)
    }
    private var periodSystem: PeriodSystem { PeriodSystem(rawValue: periodSystemRaw) ?? .quadrimestri }
    private var periodLabel1: String { periodSystem == .quadrimestri ? "1° Quadrimestre" : "Trimestre" }
    private var periodLabel2: String { periodSystem == .quadrimestri ? "2° Quadrimestre" : "Pentamestre" }

    private var sortedGrades: [Grade] {
        store.grades.sorted { $0.date > $1.date }
    }

    var body: some View {
        // Touch the grading scale so the whole list re-renders (and recomputes
        // grade colours) when the sufficient/max grade changes elsewhere.
        let _ = sufficientGrade + maxGrade
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 220)
            .ignoresSafeArea()

            Group {
                if store.grades.isEmpty {
                    emptyState
                } else {
                    gradesList
                }
            }
        }
        .background(Color.sectionPage.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isActive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showGradeEntry = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Aggiungi voto")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !store.grades.isEmpty {
                        NavigationLink {
                            SubjectsListView(
                                store: store,
                                period1End: period1End,
                                periodSystem: periodSystem,
                                periodLabel1: periodLabel1,
                                periodLabel2: periodLabel2,
                                schedule: scheduleStore.schedule
                            )
                        } label: {
                            Image(systemName: "list.bullet.below.rectangle")
                        }
                        .accessibilityLabel("Elenco materie")
                    }
                }
                if scheduleStore.schedule == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Impostazioni")
                    }
                }
            }
        }
        .sheet(isPresented: $showGradeEntry) {
            GradeEntrySheet(store: store, schedule: scheduleStore.schedule)
        }
        .sheet(item: $gradeToEdit) { grade in
            GradeEntrySheet(store: store, grade: grade, schedule: scheduleStore.schedule)
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
                Circle().fill(Color.purple.opacity(0.12)).frame(width: 110, height: 110)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 46))
                    .foregroundStyle(.purple)
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

    private var gradesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                GradesSummaryCard(
                    overall: store.overallAverage(),
                    period1Avg: store.overallAverage(period: 1, periodBoundary: period1End),
                    period2Avg: store.overallAverage(period: 2, periodBoundary: period1End),
                    period1Label: periodLabel1,
                    period2Label: periodLabel2
                )
                .padding(.horizontal, 16)

                if sortedGrades.count >= 2 {
                    RecentGradesRow(grades: Array(sortedGrades.prefix(20)))
                        .padding(.horizontal, 16)
                }

                ForEach(sortedGrades) { grade in
                    GradeHomeRow(grade: grade, trend: store.overallTrend(for: grade), color: store.color(for: grade.subject))
                        .contentShape(Rectangle())
                        .onTapGesture { gradeToEdit = grade }
                        .contextMenu {
                            Button { gradeToEdit = grade } label: { Label("Modifica", systemImage: "pencil") }
                            Button { openSubject = grade.subject } label: { Label("Apri materia", systemImage: "chart.bar.doc.horizontal") }
                            Button(role: .destructive) {
                                store.delete(ids: [grade.id])
                            } label: { Label("Elimina", systemImage: "trash") }
                        }
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Grade home row

private struct GradeHomeRow: View {
    let grade: Grade
    let trend: GradeTrend?
    var color: Color = .gray

    var body: some View {
        HStack(spacing: 12) {
            // Per-subject colour bar
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                Text(grade.subject)
                    .font(.callout.bold())
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    // Coloured type badge
                    Label(grade.type.label, systemImage: grade.type.icon)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(grade.type.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(grade.type.color.opacity(0.14), in: Capsule())
                    Text(grade.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if grade.countsForAverage && grade.weight != 1.0 {
                        Text("×\(Int((grade.weight * 100).rounded()))%")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }
                if !grade.teacher.isEmpty {
                    Text(grade.teacher)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            HStack(alignment: .center, spacing: 10) {
                Text(grade.value.italianGrade)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(grade.countsForAverage ? grade.value.gradeColor : .blue)
                    .monospacedDigit()
                    .frame(minWidth: 46, alignment: .trailing)
                // Fixed-width trend column so the arrows line up across rows,
                // regardless of how wide the grade number is.
                Group {
                    if let trend {
                        Image(systemName: trend.systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(trend.color)
                    }
                }
                .frame(width: 24)
            }
        }
        .padding(14)
        .background(Color.sectionCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - Grades summary card

private struct GradesSummaryCard: View {
    let overall: Double?
    let period1Avg: Double?
    let period2Avg: Double?
    let period1Label: String
    let period2Label: String
    @ScaledMetric private var ring: CGFloat = 84

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 9)
                if let avg = overall {
                    Circle()
                        .trim(from: 0, to: min(avg / 10.0, 1.0))
                        .stroke(
                            AngularGradient(
                                colors: [avg.gradeColor.opacity(0.6), avg.gradeColor],
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(-90 + 360 * (avg / 10.0))
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: avg)
                }
                VStack(spacing: 1) {
                    Text(overall?.italianGrade ?? "—")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(overall?.gradeColor ?? .secondary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: overall)
                    Text("MEDIA")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                }
            }
            .frame(width: ring, height: ring)

            VStack(alignment: .leading, spacing: 12) {
                PeriodBarRow(label: period1Label, avg: period1Avg)
                PeriodBarRow(label: period2Label, avg: period2Avg)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color.sectionCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

private struct PeriodBarRow: View {
    let label: String
    let avg: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(avg?.italianGrade ?? "N/D")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(avg?.gradeColor ?? Color(.tertiaryLabel))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: avg)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill)).frame(height: 5)
                    if let avg {
                        Capsule()
                            .fill(avg.gradeColor.opacity(0.75))
                            .frame(width: max(geo.size.width * (avg / 10.0), 0), height: 5)
                            .animation(.easeOut(duration: 0.5), value: avg)
                    }
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Recent grades bubbles

private struct RecentGradesRow: View {
    let grades: [Grade]
    @ScaledMetric private var bubble: CGFloat = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ultimi voti")
                .font(.subheadline.weight(.semibold))
                .padding(.leading, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(grades) { grade in
                        let c = grade.countsForAverage ? grade.value.gradeColor : .blue
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(c.opacity(0.10))
                                    .frame(width: bubble, height: bubble)
                                Circle()
                                    .stroke(c.opacity(0.30), lineWidth: 1.5)
                                    .frame(width: bubble, height: bubble)
                                Text(grade.value.italianGrade)
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
        .background(Color.sectionCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
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
                    Color.sectionPage
                    LinearGradient(
                        colors: [top.opacity(0.14), .clear],
                        startPoint: .top, endPoint: .center
                    )
                    LinearGradient(
                        colors: [.clear, bottom.opacity(0.10)],
                        startPoint: .center, endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
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
                Text("\(count) vot\(count == 1 ? "o" : "i")")
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
    // Local mirrors of the grading scale so the view refreshes when it changes.
    @AppStorage("sufficientGrade") private var sufficientGrade: Double = 6
    @AppStorage("maxGrade") private var maxGrade: Double = 10

    private static let motivations = [
        "Un voto alla volta: la media si costruisce con costanza. 💪",
        "Non è la singola interrogazione, è la rotta che tieni. 🚀",
        "Ogni studio di oggi è un voto migliore domani. 📚",
        "La distanza tra il 6 e l'8 è solo un po' di costanza in più. ⭐️",
        "Sbagliare fa parte del percorso: conta rialzare la media. 🌱",
        "Piccoli passi, grandi risultati. Continua così! 🎯",
        "Il prossimo voto è un'occasione, non una minaccia. 😉",
        "Credici: la media più alta è più vicina di quanto pensi. ✨"
    ]

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

    var body: some View {
        List {
            if grades.count >= 2 {
                Section("Andamento") {
                    GradeChartView(grades: grades, tint: store.color(for: subject))
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

            Section("Statistiche") {
                if let avg = store.average(for: subject) {
                    averageRow("Media", avg)
                }
                if let avg = store.average(for: subject, period: 1, periodBoundary: period1End) {
                    averageRow(periodLabel1, avg)
                }
                if let avg = store.average(for: subject, period: 2, periodBoundary: period1End) {
                    averageRow(periodLabel2, avg)
                }
            }
            .listRowBackground(Color.sectionCard)

            Section("Obiettivo") {
                Menu {
                    ForEach(targetOptions, id: \.self) { t in
                        Button {
                            targetAverage = t
                        } label: {
                            if t == targetAverage {
                                Label(t.italianGrade, systemImage: "checkmark")
                            } else {
                                Text(t.italianGrade)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Label("Media obiettivo", systemImage: "target")
                        Spacer()
                        Text(targetAverage.italianGrade)
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(.tint)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)

                goalResultRow

                if !motivation.isEmpty {
                    Text(motivation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.sectionCard)

            Section("Voti (\(grades.count))") {
                ForEach(grades.reversed()) { grade in
                    GradeRowView(grade: grade, trend: store.subjectTrend(for: grade))
                        .contentShape(Rectangle())
                        .onTapGesture { gradeToEdit = grade }
                        .contextMenu {
                            Button { gradeToEdit = grade } label: { Label("Modifica", systemImage: "pencil") }
                            Button(role: .destructive) {
                                store.delete(ids: [grade.id])
                            } label: { Label("Elimina", systemImage: "trash") }
                        }
                }
                .onDelete { offsets in
                    let ids = Set(offsets.map { grades.reversed()[$0].id })
                    store.delete(ids: ids)
                }
            }
            .listRowBackground(Color.sectionCard)
        }
        .navigationTitle(subject)
        .navigationBarTitleDisplayMode(.large)
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

    @ViewBuilder
    private var goalResultRow: some View {
        switch goal(for: targetAverage) {
        case .reached:
            Label("Obiettivo raggiunto 🎉", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .impossibleTen:
            Label("Per il massimo servono solo voti pieni", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .needsOne(let v):
            HStack(spacing: 5) {
                Text("Ti basta un voto da")
                Text(v.italianGrade)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(v.gradeColor)
            }
        case .needsMany(let k):
            HStack(spacing: 5) {
                Text("Ti servono circa")
                Text("\(k)")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(.tint)
                Text("voti da \(maxGrade.italianGrade)")
            }
        }
    }

    @ViewBuilder
    private func averageRow(_ label: String, _ avg: Double) -> some View {
        LabeledContent(label) {
            Text(avg.italianGrade)
                .font(.system(.callout, design: .rounded, weight: .bold))
                .foregroundStyle(avg.gradeColor)
                .contentTransition(.numericText())
                .animation(.snappy, value: avg)
        }
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

// MARK: - Grade chart

private struct GradeChartView: View {
    let grades: [Grade]

    var tint: Color = Color(red: 0.42, green: 0.45, blue: 0.62)

    private var sorted: [Grade] { grades.sorted { $0.date < $1.date } }
    private var lineColor: Color { tint }
    @State private var selectedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Detail of the tapped point, OUTSIDE the plot so it's never clipped.
            HStack(spacing: 7) {
                if let s = selectedIndex, s >= 0, s < sorted.count {
                    Circle().fill(sorted[s].countsForAverage ? sorted[s].value.gradeColor : .blue).frame(width: 8, height: 8)
                    Text(sorted[s].value.italianGrade)
                        .font(.subheadline.weight(.bold))
                    Text("·").foregroundStyle(.tertiary)
                    Text(sorted[s].date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "hand.tap").font(.caption2)
                    Text("Tocca un punto per i dettagli").font(.caption)
                }
            }
            .foregroundStyle(selectedIndex == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .frame(height: 20)
            .animation(.easeInOut(duration: 0.15), value: selectedIndex)

            Chart {
                RuleMark(y: .value("Sufficienza", sufficientGrade))
                    .foregroundStyle(.secondary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))

                ForEach(Array(sorted.enumerated()), id: \.offset) { i, grade in
                    LineMark(x: .value("n", i), y: .value("Voto", grade.value))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(lineColor)

                    PointMark(x: .value("n", i), y: .value("Voto", grade.value))
                        .foregroundStyle(grade.countsForAverage ? (selectedIndex == i ? lineColor : lineColor.opacity(0.8)) : Color.blue)
                        .symbolSize(selectedIndex == i ? 120 : 42)
                }

                if let s = selectedIndex, s >= 0, s < sorted.count {
                    RuleMark(x: .value("n", s))
                        .foregroundStyle(lineColor.opacity(0.30))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartYScale(domain: 1...(maxGrade + 0.4))
            .chartXScale(domain: -0.4 ... (Double(max(sorted.count - 1, 1)) + 0.4))
            .chartXSelection(value: $selectedIndex)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color(.separator).opacity(0.3))
                    AxisValueLabel()
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(.label))
                }
            }
            .animation(.easeOut(duration: 0.2), value: selectedIndex)
            .sensoryFeedback(.selection, trigger: selectedIndex)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
                Text(grade.date.formatted(date: .abbreviated, time: .omitted))
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
                        .accessibilityLabel(trend == .improved ? "Ha alzato la media della materia"
                                             : trend == .declined ? "Ha abbassato la media della materia"
                                             : "Media della materia invariata")
                }
                Text(grade.value.italianGrade)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(grade.countsForAverage ? grade.value.gradeColor : .blue)
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
    private static let commonSubjects = [
        "Italiano", "Matematica", "Storia", "Geografia", "Geostoria",
        "Inglese", "Francese", "Spagnolo", "Tedesco", "Latino", "Greco",
        "Scienze", "Scienze naturali", "Biologia", "Chimica", "Fisica",
        "Filosofia", "Storia dell'arte", "Disegno e storia dell'arte",
        "Diritto", "Economia", "Informatica", "Tecnologia",
        "Scienze motorie", "Educazione fisica", "Educazione civica",
        "Religione", "Musica", "Arte e immagine"
    ]

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
            return periodSystem == .quadrimestri ? "1° Quadrimestre" : "Trimestre"
        } else {
            return periodSystem == .quadrimestri ? "2° Quadrimestre" : "Pentamestre"
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
            Form {
                Section("Materia") {
                    TextField(
                        "",
                        text: $subject,
                        prompt: Text(subjectError ? "Campo obbligatorio" : "Es. Matematica")
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

                Section("Voto") {
                    GradeValuePickerView(value: $value)
                }

                Section {
                    Picker("Tipo", selection: $type) {
                        ForEach(GradeType.allCases, id: \.rawValue) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                } footer: {
                    Text("Periodo: \(gradePeriodLabel). Cambia la data per modificare il periodo.")
                }

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
                         ? "Il peso determina quanto incide nella media ponderata."
                         : "Il voto verrà mostrato in blu e non conterà nella media.")
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
            .navigationTitle(isNew ? "Nuovo voto" : "Modifica voto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") {
                        guard !subject.trimmingCharacters(in: .whitespaces).isEmpty else {
                            withAnimation { subjectError = true }
                            return
                        }
                        save()
                    }
                    .fontWeight(.semibold)
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

    var body: some View {
        HStack(spacing: 0) {
            Text(value.italianGrade)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(value.gradeColor)
                .frame(width: 72, alignment: .center)
                .animation(.easeInOut(duration: 0.1), value: value)

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
