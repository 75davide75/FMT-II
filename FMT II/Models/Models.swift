import Foundation

// School days only — used by the PDF parser (timetables have 5 day columns).
let dayOrder: [DayId] = [.monday, .tuesday, .wednesday, .thursday, .friday]

// Full week — used by the Diary, which is independent of the school timetable.
let weekOrder: [DayId] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

let dayLabels: [DayId: String] = [
    .monday: "Lunedì",
    .tuesday: "Martedì",
    .wednesday: "Mercoledì",
    .thursday: "Giovedì",
    .friday: "Venerdì",
    .saturday: "Sabato",
    .sunday: "Domenica"
]

enum DayId: String, Codable, CaseIterable, Hashable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    /// Nome nella lingua dell'app. I `dayLabel` salvati negli orari restano in
    /// italiano (dati): a schermo si usa sempre questo.
    var displayName: String {
        switch self {
        case .monday:    return L("Lunedì")
        case .tuesday:   return L("Martedì")
        case .wednesday: return L("Mercoledì")
        case .thursday:  return L("Giovedì")
        case .friday:    return L("Venerdì")
        case .saturday:  return L("Sabato")
        case .sunday:    return L("Domenica")
        }
    }

    /// Abbreviazione (intestazioni della Settimana e del Diario).
    var shortName: String {
        switch self {
        case .monday:    return L("Lun")
        case .tuesday:   return L("Mar")
        case .wednesday: return L("Mer")
        case .thursday:  return L("Gio")
        case .friday:    return L("Ven")
        case .saturday:  return L("Sab")
        case .sunday:    return L("Dom")
        }
    }
}

struct DayInfo: Codable, Identifiable, Equatable {
    var id: DayId
    var label: String
}

struct Lesson: Codable, Identifiable, Hashable, Equatable {
    var id: String
    var className: String
    var teacher: String
    var day: DayId
    var dayLabel: String
    var period: Int
    var startTime: String
    var endTime: String
    var sourcePage: Int
    var subject: String = ""   // used by manually-created schedules
}

extension Lesson {
    // Backwards-compatible decoding: PDF-parsed lessons have no `subject`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        className = try c.decode(String.self, forKey: .className)
        teacher = try c.decode(String.self, forKey: .teacher)
        day = try c.decode(DayId.self, forKey: .day)
        dayLabel = try c.decode(String.self, forKey: .dayLabel)
        period = try c.decode(Int.self, forKey: .period)
        startTime = try c.decode(String.self, forKey: .startTime)
        endTime = try c.decode(String.self, forKey: .endTime)
        sourcePage = try c.decode(Int.self, forKey: .sourcePage)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
    }

    /// What to show in class view: the subject if set, otherwise the teacher.
    var classModeTitle: String { subject.isEmpty ? teacher : subject }
    /// Secondary text in class view (the teacher, when a subject is shown).
    var classModeSubtitle: String? { (!subject.isEmpty && !teacher.isEmpty) ? teacher : nil }
}

struct Period: Codable, Identifiable, Equatable {
    var id: Int { number }
    var number: Int
    var startTime: String
    var endTime: String
}

struct ScheduleData: Codable, Equatable {
    var id: String
    var sourceName: String
    var importedAt: String
    var startsFrom: String?
    var days: [DayInfo]
    var periods: [Period]
    var classes: [String]
    var teachers: [String]
    var lessons: [Lesson]
    var warnings: [String]
    /// True when the user has manually edited or created the schedule.
    /// Such schedules skip `normalizeScheduleTimes` so custom times survive.
    var edited: Bool = false
    /// Learned subject -> teacher pairs, used to auto-fill teachers while building.
    var subjectTeachers: [String: String] = [:]
    /// v2.2: ogni classe può avere la sua ora d'inizio (durata e numero di ore restano globali).
    var perClassStartTimes: Bool = false
    /// Classe → "HH:mm" d'inizio della 1ª ora (usato solo con `perClassStartTimes`).
    var classStartTimes: [String: String] = [:]
    /// Ultima modifica locale (per la sync iCloud: vince la più recente).
    var modifiedAt: Date = .distantPast

    /// Safe placeholder used during the brief render pass when the schedule is
    /// being removed, so views that assume a non-nil schedule don't crash.
    static let empty = ScheduleData(
        id: "", sourceName: "", importedAt: "", startsFrom: nil,
        days: [], periods: [], classes: [], teachers: [], lessons: [], warnings: []
    )
}

extension ScheduleData {
    // Backwards-compatible decoding: schedules saved before `edited` existed
    // must still load (default it to false).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        importedAt = try c.decodeIfPresent(String.self, forKey: .importedAt) ?? ""
        startsFrom = try c.decodeIfPresent(String.self, forKey: .startsFrom)
        days = try c.decodeIfPresent([DayInfo].self, forKey: .days) ?? []
        periods = try c.decodeIfPresent([Period].self, forKey: .periods) ?? []
        classes = try c.decodeIfPresent([String].self, forKey: .classes) ?? []
        teachers = try c.decodeIfPresent([String].self, forKey: .teachers) ?? []
        lessons = try c.decodeIfPresent([Lesson].self, forKey: .lessons) ?? []
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        edited = try c.decodeIfPresent(Bool.self, forKey: .edited) ?? false
        subjectTeachers = try c.decodeIfPresent([String: String].self, forKey: .subjectTeachers) ?? [:]
        perClassStartTimes = try c.decodeIfPresent(Bool.self, forKey: .perClassStartTimes) ?? false
        classStartTimes = try c.decodeIfPresent([String: String].self, forKey: .classStartTimes) ?? [:]
        // Orari 2.1.1 senza data di modifica: vale la data di import, così tra
        // due dispositivi vince l'orario importato più di recente.
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
            ?? ISO8601DateFormatter().date(from: importedAt)
            ?? .distantPast
    }
}

/// Re-aligns lesson times to their period (respecting manually-set period times,
/// unlike `normalizeScheduleTimes` which forces the fixed 08:10 formula),
/// regenerates lesson ids, and marks the schedule as manually edited.
/// Each lesson follows its own class's periods (per-class start time, v2.2).
func applyManualEdits(_ s: ScheduleData) -> ScheduleData {
    var periodsByClass: [String: [Int: Period]] = [:]
    func period(_ number: Int, of className: String) -> Period? {
        if periodsByClass[className] == nil {
            var map: [Int: Period] = [:]
            for p in s.periods(forClass: className) { map[p.number] = p }
            periodsByClass[className] = map
        }
        return periodsByClass[className]?[number]
    }

    let lessons = s.lessons.map { lesson -> Lesson in
        let p = period(lesson.period, of: lesson.className)
        let start = p?.startTime ?? lesson.startTime
        let end = p?.endTime ?? lesson.endTime
        return Lesson(
            id: lessonId(lesson.className, lesson.day, start, lesson.teacher.isEmpty ? lesson.subject : lesson.teacher),
            className: lesson.className,
            teacher: lesson.teacher,
            day: lesson.day,
            dayLabel: lesson.dayLabel,
            period: lesson.period,
            startTime: start,
            endTime: end,
            sourcePage: lesson.sourcePage,
            subject: lesson.subject
        )
    }

    var result = s
    result.lessons = lessons
    result.edited = true
    return result
}

// MARK: - Time helpers

func minutesFromMidnight(_ time: String) -> Int {
    let parts = time.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return 0 }
    return parts[0] * 60 + parts[1]
}

func addMinutes(_ time: String, _ amount: Int) -> String {
    let total = minutesFromMidnight(time) + amount
    let h = total / 60
    let m = total % 60
    return String(format: "%02d:%02d", h, m)
}

func periodToStartTime(_ period: Int) -> String {
    String(format: "%02d:10", period + 7)
}

func lessonId(_ className: String, _ day: DayId, _ startTime: String, _ teacher: String) -> String {
    [className, day.rawValue, startTime, teacher]
        .joined(separator: "-")
        .replacingOccurrences(of: "[^a-zA-Z0-9]+", with: "-", options: .regularExpression)
        .lowercased()
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

func normalizeScheduleTimes(_ schedule: ScheduleData) -> ScheduleData {
    let periods = schedule.periods.enumerated().map { (index, period) -> Period in
        let startTime = periodToStartTime(period.number)
        let nextPeriod = index + 1 < schedule.periods.count ? schedule.periods[index + 1] : nil
        let endTime = nextPeriod != nil ? periodToStartTime(nextPeriod!.number) : addMinutes(startTime, 60)
        return Period(number: period.number, startTime: startTime, endTime: endTime)
    }
    var periodByNumber: [Int: Period] = [:]
    for p in periods { periodByNumber[p.number] = p }

    let lessons = schedule.lessons.map { lesson -> Lesson in
        let period = periodByNumber[lesson.period]
        let startTime = period?.startTime ?? periodToStartTime(lesson.period)
        let endTime = period?.endTime ?? addMinutes(startTime, 60)
        return Lesson(
            // Subject-only lessons (teacher unknown) key the id on the subject,
            // like applyManualEdits, so ids stay unique.
            id: lessonId(lesson.className, lesson.day, startTime, lesson.teacher.isEmpty ? lesson.subject : lesson.teacher),
            className: lesson.className,
            teacher: lesson.teacher,
            day: lesson.day,
            dayLabel: lesson.dayLabel,
            period: lesson.period,
            startTime: startTime,
            endTime: endTime,
            sourcePage: lesson.sourcePage,
            subject: lesson.subject
        )
    }

    // Copy so the fields that don't change (days, classes, subjectTeachers, …)
    // survive: rebuilding from scratch silently dropped `subject` data.
    var result = schedule
    result.periods = periods
    result.lessons = lessons
    return result
}
