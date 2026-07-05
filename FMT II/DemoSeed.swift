#if DEBUG
import Foundation
import UIKit

/// Popola l'app con dati scolastici realistici (orario, voti, note) per generare
/// gli screenshot dell'App Store e del sito.
///
/// Attivo **solo** nei build DEBUG e **solo** se l'app è lanciata con l'argomento
/// `-FMTSeedDemo` (o la variabile d'ambiente `FMT_SEED_DEMO=1`). L'intero file è
/// racchiuso in `#if DEBUG`, quindi non entra nel build App Store (Release lo esclude).
@MainActor
enum DemoSeed {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-FMTSeedDemo")
            || ProcessInfo.processInfo.environment["FMT_SEED_DEMO"] == "1"
    }

    /// Ripristina orario + voti + note demo passando per gli stessi metodi del
    /// restore da backup, così i dati seguono la normale pipeline dell'app.
    static func seedIfRequested(schedule: ScheduleStore, notes: NotesStore, grades: GradesStore) {
        guard isRequested else { return }
        schedule.restore(makeSchedule())
        grades.replaceAll(makeGrades())
        notes.replaceAll(makeNotes())
    }

    // MARK: - Orario

    private static let klass = "3ªB"

    /// (giorno, ora, materia, docente) — settimana completa di un liceo.
    private static let grid: [(DayId, Int, String, String)] = [
        (.monday,    1, "Matematica",  "Bianchi"),
        (.monday,    2, "Italiano",    "Rossi"),
        (.monday,    3, "Inglese",     "Verdi"),
        (.monday,    4, "Storia",      "Conti"),
        (.monday,    5, "Scienze",     "Greco"),
        (.tuesday,   1, "Fisica",      "Bianchi"),
        (.tuesday,   2, "Latino",      "Rossi"),
        (.tuesday,   3, "Filosofia",   "Conti"),
        (.tuesday,   4, "Ed. Fisica",  "Marino"),
        (.tuesday,   5, "Informatica", "Neri"),
        (.wednesday, 1, "Italiano",    "Rossi"),
        (.wednesday, 2, "Matematica",  "Bianchi"),
        (.wednesday, 3, "Inglese",     "Verdi"),
        (.wednesday, 4, "Arte",        "Ferrari"),
        (.wednesday, 5, "Scienze",     "Greco"),
        (.thursday,  1, "Storia",      "Conti"),
        (.thursday,  2, "Fisica",      "Bianchi"),
        (.thursday,  3, "Latino",      "Rossi"),
        (.thursday,  4, "Filosofia",   "Conti"),
        (.thursday,  5, "Ed. Fisica",  "Marino"),
        (.friday,    1, "Matematica",  "Bianchi"),
        (.friday,    2, "Italiano",    "Rossi"),
        (.friday,    3, "Inglese",     "Verdi"),
        (.friday,    4, "Informatica", "Neri"),
        (.friday,    5, "Arte",        "Ferrari"),
    ]

    private static func makeSchedule() -> ScheduleData {
        let weekdays: [DayId] = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let days = weekdays.map { DayInfo(id: $0, label: dayLabels[$0] ?? $0.rawValue) }
        let periods = (1...5).map { Period(number: $0, startTime: "", endTime: "") }
        // Tempi e id vengono ricalcolati da `restore` → `normalizeScheduleTimes`.
        let lessons = grid.map { day, period, subject, teacher in
            Lesson(id: "", className: klass, teacher: teacher, day: day,
                   dayLabel: dayLabels[day] ?? day.rawValue, period: period,
                   startTime: "", endTime: "", sourcePage: 1, subject: subject)
        }
        var subjectTeachers: [String: String] = [:]
        for (_, _, subject, teacher) in grid { subjectTeachers[subject] = teacher }

        return ScheduleData(
            id: "demo-3b",
            sourceName: "Orario 3ªB",
            importedAt: ISO8601DateFormatter().string(from: Date()),
            startsFrom: nil,
            days: days,
            periods: periods,
            classes: [klass],
            teachers: Array(Set(grid.map { $0.3 })).sorted(),
            lessons: lessons,
            warnings: [],
            edited: false,
            subjectTeachers: subjectTeachers
        )
    }

    // MARK: - Voti

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 10
        return Calendar.current.date(from: c) ?? Date()
    }

    private static func makeGrades() -> [Grade] {
        // (materia, docente, voto, data, tipo, nota, peso, fa media)
        typealias Row = (String, String, Double, Date, GradeType, String, Double, Bool)
        let rows: [Row] = [
            ("Matematica", "Bianchi", 5.5, date(2025, 10, 8),  .written,   "Equazioni di 2° grado",  1.0, true),
            ("Matematica", "Bianchi", 7.0, date(2025, 11, 12), .oral,      "",                        1.0, true),
            ("Matematica", "Bianchi", 6.5, date(2026, 1, 15),  .written,   "Disequazioni",            1.0, true),
            ("Matematica", "Bianchi", 8.0, date(2026, 3, 10),  .written,   "Studio di funzione",      1.0, true),
            ("Italiano",   "Rossi",   6.0, date(2025, 10, 20), .oral,      "",                        1.0, true),
            ("Italiano",   "Rossi",   7.5, date(2025, 12, 3),  .written,   "Tema argomentativo",      1.0, true),
            ("Italiano",   "Rossi",   7.0, date(2026, 2, 18),  .written,   "",                        1.0, true),
            ("Italiano",   "Rossi",   8.5, date(2026, 4, 22),  .oral,      "",                        1.0, true),
            ("Inglese",    "Verdi",   8.0, date(2025, 10, 15), .written,   "",                        1.0, true),
            ("Inglese",    "Verdi",   7.5, date(2025, 12, 10), .oral,      "",                        1.0, true),
            ("Inglese",    "Verdi",   9.0, date(2026, 3, 5),   .written,   "Reading comprehension",   1.0, true),
            ("Storia",     "Conti",   6.5, date(2025, 11, 5),  .oral,      "",                        1.0, true),
            ("Storia",     "Conti",   7.0, date(2026, 1, 28),  .oral,      "",                        1.0, true),
            ("Storia",     "Conti",   5.5, date(2026, 4, 8),   .written,   "",                        1.0, true),
            ("Fisica",     "Bianchi", 6.0, date(2025, 11, 19), .written,   "Cinematica",              1.0, true),
            ("Fisica",     "Bianchi", 7.0, date(2026, 2, 4),   .oral,      "",                        1.0, true),
            ("Fisica",     "Bianchi", 7.5, date(2026, 3, 25),  .practical, "Laboratorio",             0.5, true),
            ("Scienze",    "Greco",   7.0, date(2025, 10, 29), .oral,      "",                        1.0, true),
            ("Scienze",    "Greco",   8.0, date(2026, 1, 21),  .written,   "",                        1.0, true),
            ("Scienze",    "Greco",   6.5, date(2026, 4, 15),  .oral,      "",                        1.0, true),
            ("Latino",     "Rossi",   5.0, date(2025, 11, 26), .written,   "Versione dal latino",     1.0, true),
            ("Latino",     "Rossi",   6.5, date(2026, 2, 11),  .written,   "",                        1.0, true),
            ("Latino",     "Rossi",   7.0, date(2026, 4, 29),  .oral,      "",                        1.0, true),
        ]
        var grades = rows.map {
            Grade(id: UUID(), subject: $0.0, teacher: $0.1, value: $0.2, date: $0.3,
                  note: $0.5, type: $0.4, weight: $0.6, countsForAverage: $0.7)
        }
        // Una giustifica: non fa media, mostrata come "G".
        grades.append(Grade(id: UUID(), subject: "Matematica", teacher: "Bianchi", value: 6,
                            date: date(2026, 5, 6), note: "", type: .giustifica,
                            weight: 1, countsForAverage: false))
        return grades
    }

    // MARK: - Diario

    private static func makeNote(_ title: String, _ body: String,
                                 daysFromNow: Int, time: String? = nil,
                                 task: NoteTaskType? = nil,
                                 subject: String? = nil, teacher: String? = nil) -> Note {
        var n = Note()
        let day = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        n.date = Calendar.current.startOfDay(for: day)
        n.createdAt = day
        n.time = time
        n.taskType = task?.rawValue
        n.subjectTag = subject
        n.teacherTag = teacher
        let a = NSMutableAttributedString(
            string: title + "\n",
            attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .semibold)])
        a.append(NSAttributedString(
            string: body,
            attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .regular)]))
        n.setAttributedText(a)
        return n
    }

    private static func makeNotes() -> [Note] {
        [
            makeNote("Verifica di Matematica",
                     "Capitoli 4–5: funzioni e limiti. Ripassare gli esercizi svolti in classe.",
                     daysFromNow: 2, time: "08:10", task: .verifica, subject: "Matematica", teacher: "Bianchi"),
            makeNote("Compito di Inglese",
                     "Reading comprehension Unit 6, esercizi pag. 88–90.",
                     daysFromNow: 1, time: "11:10", task: .compito, subject: "Inglese", teacher: "Verdi"),
            makeNote("Interrogazione di Storia",
                     "La Prima Guerra Mondiale: cause, svolgimento e conseguenze.",
                     daysFromNow: 3, time: "10:10", task: .interrogazione, subject: "Storia", teacher: "Conti"),
            makeNote("Relazione di Fisica",
                     "Consegnare la relazione sul moto uniformemente accelerato.",
                     daysFromNow: 5, task: .compito, subject: "Fisica", teacher: "Bianchi"),
            makeNote("Uscita didattica",
                     "Gita al museo della scienza: ritrovo alle 8:00 davanti a scuola.",
                     daysFromNow: 0),
        ]
    }
}
#endif
