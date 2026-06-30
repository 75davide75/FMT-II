import Foundation
import UserNotifications

/// Schedules weekly-recurring local notifications for Diary entries that have a
/// day + time and the reminder flag enabled. Identifier = note UUID, so a note's
/// reminder can be updated or cancelled by id.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    /// Asks for permission (first time only). Returns whether it's granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// DayId → Calendar weekday (Sunday = 1 ... Saturday = 7).
    private func weekday(for day: DayId) -> Int {
        switch day {
        case .sunday:    return 1
        case .monday:    return 2
        case .tuesday:   return 3
        case .wednesday: return 4
        case .thursday:  return 5
        case .friday:    return 6
        case .saturday:  return 7
        }
    }

    func schedule(note: Note) {
        cancel(ids: [note.id])
        guard note.reminder,
              let dayStr = note.day, let day = DayId(rawValue: dayStr),
              let time = note.time else { return }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }

        var comps = DateComponents()
        comps.weekday = weekday(for: day)
        comps.hour = parts[0]
        comps.minute = parts[1]

        let content = UNMutableNotificationContent()
        content.title = "Diario"
        let title = note.displayTitle
        content.body = title.isEmpty ? "Hai un promemoria" : title
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: note.id.uuidString, content: content, trigger: trigger)
        center.add(request)
    }

    func cancel(ids: Set<UUID>) {
        center.removePendingNotificationRequests(withIdentifiers: ids.map(\.uuidString))
    }

    /// Used after a bulk import: clear and reschedule everything that needs it.
    func reschedule(notes: [Note]) {
        cancel(ids: Set(notes.map(\.id)))
        for n in notes where n.reminder { schedule(note: n) }
    }
}
