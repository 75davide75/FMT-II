import Foundation
import UIKit

struct NoteCreationContext: Identifiable {
    let id = UUID()
    var existingNote: Note?
    var day: DayId?
    var time: String?
    var teacherTag: String?
    var classTag: String?

    init(day: DayId? = nil, time: String? = nil, teacherTag: String? = nil, classTag: String? = nil) {
        self.existingNote = nil
        self.day = day; self.time = time
        self.teacherTag = teacherTag; self.classTag = classTag
    }

    init(existingNote: Note) {
        self.existingNote = existingNote
        self.day = existingNote.dayId
        self.time = existingNote.time
        self.teacherTag = existingNote.teacherTag
        self.classTag = existingNote.classTag
    }
}

struct Note: Identifiable, Codable {
    var id: UUID = UUID()
    var rtfData: Data = Data()
    var day: String? = nil
    var time: String? = nil
    var teacherTag: String? = nil
    var classTag: String? = nil
    var subjectTag: String? = nil
    var createdAt: Date = Date()
    var isArchived: Bool = false
    var reminder: Bool = false   // weekly recurring local notification (needs day + time)

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
        time = try c.decodeIfPresent(String.self, forKey: .time)
        teacherTag = try c.decodeIfPresent(String.self, forKey: .teacherTag)
        classTag = try c.decodeIfPresent(String.self, forKey: .classTag)
        subjectTag = try c.decodeIfPresent(String.self, forKey: .subjectTag)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        reminder = try c.decodeIfPresent(Bool.self, forKey: .reminder) ?? false
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

    func add(_ note: Note) { notes.insert(note, at: 0); save() }

    func update(_ note: Note) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note; save()
        }
    }

    func delete(ids: Set<UUID>) {
        notes.removeAll { ids.contains($0.id) }
        NotificationManager.shared.cancel(ids: ids)
        save()
    }

    func deleteAll() {
        NotificationManager.shared.cancel(ids: Set(notes.map(\.id)))
        notes.removeAll()
        save()
    }

    func replaceAll(_ newNotes: [Note]) {
        notes = newNotes
        save()
        NotificationManager.shared.reschedule(notes: newNotes)
    }

    func archive(ids: Set<UUID>) {
        for idx in notes.indices where ids.contains(notes[idx].id) {
            notes[idx].isArchived = true
        }
        save()
    }

    func unarchive(ids: Set<UUID>) {
        for idx in notes.indices where ids.contains(notes[idx].id) {
            notes[idx].isArchived = false
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = decoded
    }

    private func save() {
        try? JSONEncoder().encode(notes).write(to: storageURL)
    }
}
