import Foundation

/// A single-file backup of the user's Diary entries and grades, shareable as JSON
/// and importable to restore on the same or another device.
struct BackupData: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var notes: [Note]
    var grades: [Grade]
    var schedule: ScheduleData? = nil
}
