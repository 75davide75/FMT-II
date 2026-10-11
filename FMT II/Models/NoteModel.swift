import Foundation
import UIKit

struct NoteCreationContext: Identifiable {
    let id = UUID()
    var existingNote: Note?
    var day: DayId?
    var date: Date?
    var time: String?
    var teacherTag: String?
    var classTag: String?
    var subjectTag: String?

    init(day: DayId? = nil, date: Date? = nil, time: String? = nil, teacherTag: String? = nil, classTag: String? = nil, subjectTag: String? = nil) {
        self.existingNote = nil
        self.day = day; self.date = date; self.time = time
        self.teacherTag = teacherTag; self.classTag = classTag
        self.subjectTag = subjectTag
    }

    init(existingNote: Note) {
        self.existingNote = existingNote
        self.day = existingNote.dayId
        self.date = existingNote.date
        self.time = existingNote.time
        self.teacherTag = existingNote.teacherTag
        self.classTag = existingNote.classTag
        self.subjectTag = existingNote.subjectTag
    }
}

/// Prossima occorrenza (oggi inclusa) del giorno settimanale a partire da `now`.
func nextOccurrence(of day: DayId, from now: Date = Date()) -> Date {
    let cal = Calendar.current
    let targetIdx = weekOrder.firstIndex(of: day) ?? 0
    let todayIdx = weekOrder.firstIndex(of: todayDayId(now)) ?? 0
    let delta = (targetIdx - todayIdx + 7) % 7
    return cal.startOfDay(for: cal.date(byAdding: .day, value: delta, to: now) ?? now)
}

enum NoteTaskType: String, CaseIterable, Identifiable {
    case compito, verifica, interrogazione
    var id: String { rawValue }
    var label: String {
        switch self {
        case .compito:        return "Compito"
        case .verifica:       return "Verifica"
        case .interrogazione: return "Interrogazione"
        }
    }
}

struct NoteReminder: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var day: String          // DayId raw value
    var time: String         // "HH:mm"
    var dayId: DayId? { DayId(rawValue: day) }
}

struct Note: Identifiable, Codable {
    var id: UUID = UUID()
    var rtfData: Data = Data()
    var day: String? = nil       // giorno settimanale (legacy + promemoria)
    var date: Date? = nil        // data di calendario della voce
    var time: String? = nil
    var teacherTag: String? = nil
    var classTag: String? = nil
    var subjectTag: String? = nil
    var taskType: String? = nil   // NoteTaskType raw: compito / verifica / interrogazione
    var createdAt: Date = Date()
    var isArchived: Bool = false
    var reminder: Bool = false   // legacy single-reminder flag (kept for migration)
    var reminders: [NoteReminder] = []   // weekly recurring reminders (day + time)
    /// Ultima modifica (per la sync iCloud: vince la più recente).
    var modifiedAt: Date = Date()

    var attributedText: NSAttributedString {
        guard !rtfData.isEmpty else { return NSAttributedString(string: "") }
        return (try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        )) ?? NSAttributedString(string: "")
    }

    mutating func setAttributedText(_ text: NSAttributedString) {
        rtfData = (try? text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
    }

    var dayId: DayId? { day.flatMap { DayId(rawValue: $0) } }

    /// Migrazione: ogni nota ha una data. Nota vecchia con solo giorno
    /// settimanale → prossima occorrenza di quel giorno; senza nemmeno il
    /// giorno → data di creazione.
    func migratingDate(from now: Date = Date()) -> Note {
        guard date == nil else { return self }
        var n = self
        if let d = dayId {
            n.date = nextOccurrence(of: d, from: now)
        } else {
            n.date = Calendar.current.startOfDay(for: createdAt)
        }
        return n
    }

    var displayTitle: String {
        let str = attributedText.string
        let first = str.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        return first.isEmpty ? "Nota senza titolo" : String(first.prefix(60))
    }

    var displayPreview: String {
        let str = attributedText.string
        let lines = str.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.dropFirst().prefix(2).joined(separator: " ")
    }
}

extension Note {
    // Backwards-compatible decoding: older notes have no `reminder` key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        rtfData = try c.decodeIfPresent(Data.self, forKey: .rtfData) ?? Data()
        day = try c.decodeIfPresent(String.self, forKey: .day)
        date = try c.decodeIfPresent(Date.self, forKey: .date)
        time = try c.decodeIfPresent(String.self, forKey: .time)
        teacherTag = try c.decodeIfPresent(String.self, forKey: .teacherTag)
        classTag = try c.decodeIfPresent(String.self, forKey: .classTag)
        subjectTag = try c.decodeIfPresent(String.self, forKey: .subjectTag)
        taskType = try c.decodeIfPresent(String.self, forKey: .taskType)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        reminder = try c.decodeIfPresent(Bool.self, forKey: .reminder) ?? false
        reminders = try c.decodeIfPresent([NoteReminder].self, forKey: .reminders) ?? []
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        // Migrate the old single-reminder flag into the new list.
        if reminders.isEmpty, reminder, let d = day, let t = time {
            reminders = [NoteReminder(day: d, time: t)]
        }
    }
}

@MainActor
class NotesStore: ObservableObject {
    @Published var notes: [Note] = []

    private let storageURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("fmt_notes.json")
    }()

    init() { load() }

    private var sync: CloudSyncManager { .shared }

    func add(_ note: Note) {
        var n = note; n.modifiedAt = Date()
        notes.insert(n, at: 0); save()
        sync.enqueueSave([.note(n.id)])
    }

    func update(_ note: Note) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            var n = note; n.modifiedAt = Date()
            notes[idx] = n; save()
            sync.enqueueSave([.note(n.id)])
        }
    }

    func delete(ids: Set<UUID>) {
        notes.removeAll { ids.contains($0.id) }
        NotificationManager.shared.cancel(ids: ids)
        save()
        sync.enqueueDelete(ids.map { .note($0) })
    }

    func deleteAll() {
        let ids = notes.map(\.id)
        NotificationManager.shared.cancel(ids: Set(ids))
        notes.removeAll()
        save()
        sync.enqueueDelete(ids.map { .note($0) })
    }

    func replaceAll(_ newNotes: [Note]) {
        let removed = Set(notes.map(\.id)).subtracting(newNotes.map(\.id))
        let now = Date()
        notes = newNotes.map { var n = $0; n.modifiedAt = now; return n }
        save()
        NotificationManager.shared.reschedule(notes: notes)
        sync.enqueueDelete(removed.map { .note($0) })
        sync.enqueueSave(notes.map { .note($0.id) })
    }

    func archive(ids: Set<UUID>) { setArchived(true, ids: ids) }

    func unarchive(ids: Set<UUID>) { setArchived(false, ids: ids) }

    private func setArchived(_ archived: Bool, ids: Set<UUID>) {
        let now = Date()
        for idx in notes.indices where ids.contains(notes[idx].id) {
            notes[idx].isArchived = archived
            notes[idx].modifiedAt = now
        }
        save()
        sync.enqueueSave(ids.map { .note($0) })
    }

    /// Modifiche arrivate da iCloud: non vengono rinviate (niente loop);
    /// i promemoria delle note cambiate vengono riprogrammati qui.
    func applyRemote(upserts: [Note], deletions: Set<UUID>) {
        notes = SyncMerge.apply(upserts: upserts.map { $0.migratingDate() }, deletions: deletions,
                                to: notes, modifiedAt: \.modifiedAt)
        save()
        NotificationManager.shared.cancel(ids: deletions)
        let changed = Set(upserts.map(\.id))
        for n in notes where changed.contains(n.id) {
            if n.reminders.isEmpty { NotificationManager.shared.cancel(ids: [n.id]) }
            else { NotificationManager.shared.schedule(note: n) }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else { return }
        // Migrazione una tantum: ogni nota riceve una data (prossima
        // occorrenza del giorno settimanale, o la data di creazione).
        notes = decoded.map { $0.migratingDate() }
        if decoded.contains(where: { $0.date == nil }) { save() }
    }

    private func save() {
        try? JSONEncoder().encode(notes).write(to: storageURL)
    }
}
