import Foundation
import SwiftUI
import UIKit

// MARK: - Italian grade display + colors

extension Double {
    var italianGrade: String {
        let whole = Int(self)
        let frac = self - Double(whole)
        if frac < 0.13 { return "\(whole)" }
        if frac < 0.38 { return "\(whole)+" }
        if frac < 0.63 { return "\(whole)½" }
        return "\(whole + 1)-"
    }

    var gradeColor: Color {
        let s = sufficientGrade
        if self >= s + 2 { return Color(red: 0.05, green: 0.58, blue: 0.18) }
        if self >= s { return .green }
        if self >= s - 1 { return .orange }
        return .red
    }
}

/// User-configurable grading scale (defaults 6 and 10).
var sufficientGrade: Double {
    let v = UserDefaults.standard.double(forKey: "sufficientGrade")
    return v > 0 ? v : 6
}
var maxGrade: Double {
    let v = UserDefaults.standard.double(forKey: "maxGrade")
    return v > 0 ? v : 10
}

// MARK: - Trend

enum GradeTrend {
    case improved, declined, same

    var systemImage: String {
        switch self {
        case .improved: return "arrow.up.circle.fill"
        case .declined: return "arrow.down.circle.fill"
        case .same:     return "equal.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .improved: return Color(red: 0.05, green: 0.58, blue: 0.18)
        case .declined: return .red
        case .same:     return Color(.tertiaryLabel)
        }
    }
}

// MARK: - Grade type

enum GradeType: String, Codable, CaseIterable {
    case oral = "oral"
    case written = "written"
    case practical = "practical"
    case giustifica = "giustifica"

    var label: String {
        switch self {
        case .oral:       return "Orale"
        case .written:    return "Scritto"
        case .practical:  return "Pratico"
        case .giustifica: return "Giustifica"
        }
    }

    var icon: String {
        switch self {
        case .oral:       return "bubble.left.fill"
        case .written:    return "pencil.line"
        case .practical:  return "hand.raised.fill"
        case .giustifica: return "g.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .oral:       return .blue
        case .written:    return .purple
        case .practical:  return .orange
        case .giustifica: return .gray
        }
    }
}

extension Grade {
    /// La giustifica non è un voto numerico: si mostra come "G", non fa media
    /// e non ha peso.
    var isGiustifica: Bool { type == .giustifica }

    var displayValue: String { isGiustifica ? "G" : value.italianGrade }

    var displayColor: Color {
        if isGiustifica { return .gray }
        return countsForAverage ? value.gradeColor : .blue
    }
}

// MARK: - Per-subject color

/// A stable, sober colour derived from the subject name, so each subject keeps
/// the same colour across the whole Voti section (rows, list, chart).
/// ~24 mid-tone colours chosen to be clearly distinguishable and readable on
/// both light and dark backgrounds (no too-light / too-dark values).
let subjectPalette: [Color] = [
    "#EF4444", "#F97316", "#F59E0B", "#CA8A04", "#65A30D", "#16A34A",
    "#059669", "#0D9488", "#0891B2", "#0284C7", "#2563EB", "#4F46E5",
    "#7C3AED", "#9333EA", "#C026D3", "#DB2777", "#E11D48", "#BE123C",
    "#92400E", "#B45309", "#475569", "#0F766E", "#1D4ED8", "#7E22CE"
].compactMap { Color(hex: $0) }

func subjectColor(_ name: String) -> Color {
    let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !key.isEmpty else { return .gray }
    var hash = 5381
    for scalar in key.unicodeScalars { hash = (hash &* 33) &+ Int(scalar.value) }
    return subjectPalette[abs(hash) % subjectPalette.count]
}

// MARK: - Adaptive section backgrounds

/// Page + card colours that keep good contrast in BOTH light and dark:
/// - Light: light-grey page, white cards (the standard grouped look).
/// - Dark:  soft dark-grey page (NOT pure black), slightly lighter cards.
/// Built with a dynamic UIColor provider so they adapt automatically anywhere.
extension Color {
    static let sectionPage = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.secondarySystemGroupedBackground   // ~#1C1C1E, not pure black
            : UIColor.systemGroupedBackground            // ~#F2F2F7 grey
    })
    static let sectionCard = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.08)           // vetro chiaro sopra lo sfondo aurora
            : UIColor.secondarySystemGroupedBackground   // white
    })
}

// MARK: - Color <-> hex (for persisting custom subject colours)

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var hexString: String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Period system

enum PeriodSystem: String {
    case quadrimestri = "quadrimestri"
    case trimestre = "trimestre_pentamestre"
}

/// The year in which the current school year started (schools start in Aug/Sep).
func schoolYearStartYear(_ now: Date = Date()) -> Int {
    let c = Calendar.current.dateComponents([.year, .month], from: now)
    let m = c.month ?? 1, y = c.year ?? 2024
    return m >= 8 ? y : y - 1
}

func daysIn(month: Int, year: Int) -> Int {
    var c = DateComponents(); c.year = year; c.month = month; c.day = 1
    let cal = Calendar.current
    guard let d = cal.date(from: c), let r = cal.range(of: .day, in: .month, for: d) else { return 31 }
    return r.count
}

/// A date built from a day + month placed in the current school year (autumn
/// months land in the start year, spring months in the following one). The year
/// is inferred so the user only ever picks day + month.
func schoolYearDate(month: Int, day: Int, now: Date = Date()) -> Date {
    let start = schoolYearStartYear(now)
    let year = month >= 8 ? start : start + 1
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = min(max(day, 1), daysIn(month: month, year: year))
    return Calendar.current.date(from: comps) ?? now
}

/// Sensible default end of the first period:
/// - Quadrimestri → 31 January.
/// - Trimestre → 23 December (just before the Christmas break).
func defaultPeriod1End(for system: PeriodSystem, now: Date = Date()) -> Date {
    switch system {
    case .quadrimestri: return schoolYearDate(month: 1, day: 31, now: now)
    case .trimestre:    return schoolYearDate(month: 12, day: 23, now: now)
    }
}

// MARK: - Grade model

struct Grade: Identifiable, Codable {
    var id: UUID = UUID()
    var subject: String = ""
    var teacher: String = ""
    var value: Double = 6.0
    var date: Date = Date()
    var note: String = ""
    var type: GradeType = .oral
    var weight: Double = 1.0          // 0...1 (100% by default)
    var countsForAverage: Bool = true // when false, shown in blue and excluded from averages
}

extension Grade {
    // Backwards-compatible decoding: older saved grades have no weight /
    // countsForAverage keys, so default them instead of failing to load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        teacher = try c.decodeIfPresent(String.self, forKey: .teacher) ?? ""
        value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 6.0
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        type = try c.decodeIfPresent(GradeType.self, forKey: .type) ?? .oral
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1.0
        countsForAverage = try c.decodeIfPresent(Bool.self, forKey: .countsForAverage) ?? true
    }
}

// MARK: - Grades store

@MainActor
class GradesStore: ObservableObject {
    @Published var grades: [Grade] = []
    @Published var subjectColors: [String: String] = [:]   // subject -> hex

    private let storageURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("fmt_grades.json")
    }()
    private let colorsKey = "fmt_subject_colors"

    init() {
        load()
        if let data = UserDefaults.standard.data(forKey: colorsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            subjectColors = decoded
        }
    }

    /// The colour for a subject: a user-chosen override, or a distinct default
    /// based on the subject's position (so two subjects don't share a colour
    /// until the palette is exhausted).
    func color(for subject: String) -> Color {
        if let hex = subjectColors[subject], let c = Color(hex: hex) { return c }
        let idx = subjects.firstIndex(of: subject) ?? abs(subject.hashValue)
        return subjectPalette[idx % subjectPalette.count]
    }

    func setColor(_ color: Color, for subject: String) {
        subjectColors[subject] = color.hexString
        UserDefaults.standard.set(try? JSONEncoder().encode(subjectColors), forKey: colorsKey)
    }

    /// Other subjects whose (resolved) colour equals `candidate`.
    func subjectsUsing(_ candidate: Color, excluding subject: String) -> [String] {
        guard let target = candidate.hexString else { return [] }
        return subjects.filter { $0 != subject && color(for: $0).hexString == target }
    }

    func add(_ grade: Grade) { grades.insert(grade, at: 0); save() }

    func update(_ grade: Grade) {
        if let idx = grades.firstIndex(where: { $0.id == grade.id }) {
            grades[idx] = grade; save()
        }
    }

    func delete(ids: Set<UUID>) { grades.removeAll { ids.contains($0.id) }; save() }

    func deleteAll() { grades.removeAll(); save() }

    func replaceAll(_ newGrades: [Grade]) { grades = newGrades; save() }

    var subjects: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for g in grades {
            if seen.insert(g.subject).inserted { result.append(g.subject) }
        }
        return result.sorted()
    }

    func gradesForSubject(_ subject: String) -> [Grade] {
        grades.filter { $0.subject == subject }.sorted { $0.date < $1.date }
    }

    /// Weighted mean that ignores grades flagged as not counting.
    private func weightedAverage(_ list: [Grade]) -> Double? {
        let counting = list.filter { $0.countsForAverage }
        let totalW = counting.map(\.weight).reduce(0, +)
        guard totalW > 0 else { return nil }
        return counting.map { $0.value * $0.weight }.reduce(0, +) / totalW
    }

    func average(for subject: String, period: Int? = nil, periodBoundary: Date? = nil) -> Double? {
        weightedAverage(grades.filter { g in
            g.subject == subject &&
            (period == nil || gradePeriod(for: g.date, boundary: periodBoundary) == period)
        })
    }

    func overallAverage(period: Int? = nil, periodBoundary: Date? = nil) -> Double? {
        weightedAverage(grades.filter { g in
            period == nil || gradePeriod(for: g.date, boundary: periodBoundary) == period
        })
    }

    func gradePeriod(for date: Date, boundary: Date?) -> Int {
        guard let boundary else { return 1 }
        return date <= boundary ? 1 : 2
    }

    /// Whether this grade pushed the OVERALL running average up or down at the
    /// moment it landed (chronologically). Stable over time: it only depends on
    /// the grades dated at or before this one, so once shown it stays put.
    func overallTrend(for grade: Grade) -> GradeTrend? {
        guard grade.countsForAverage else { return nil }
        return runningTrend(for: grade, in: grades.filter { $0.countsForAverage })
    }

    /// Same idea, but relative to the average of THIS subject only.
    func subjectTrend(for grade: Grade) -> GradeTrend? {
        guard grade.countsForAverage else { return nil }
        return runningTrend(for: grade, in: grades.filter { $0.subject == grade.subject && $0.countsForAverage })
    }

    private func runningTrend(for grade: Grade, in pool: [Grade]) -> GradeTrend? {
        let ordered = pool.sorted {
            $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString
        }
        guard let idx = ordered.firstIndex(where: { $0.id == grade.id }), idx > 0 else { return nil }
        guard let prevAvg = weightedAverage(Array(ordered[0..<idx])) else { return nil }
        let delta = grade.value - prevAvg
        if delta > 0.05 { return .improved }
        if delta < -0.05 { return .declined }
        return .same
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Grade].self, from: data) else { return }
        grades = decoded
    }

    private func save() {
        try? JSONEncoder().encode(grades).write(to: storageURL)
    }
}
