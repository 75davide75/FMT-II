import Foundation

/// Tipo di istantanea dei voti, in base all'operazione che la precede.
enum SnapshotKind: String, Codable {
    case preLink, preSync, preRestore, preUnlink
}

/// Istantanea ripristinabile dei voti.
struct GradeSnapshot: Identifiable, Equatable {
    let id: String
    let kind: SnapshotKind
    let date: Date
    let count: Int
    let url: URL
}

/// Backup dei voti fuori dal file principale: `voti-manuali.json` (sempre aggiornato
/// al salvataggio) e istantanee `snapshot-<kind>-<yyyyMMdd-HHmmss>.json`.
/// Regola: gli errori di I/O qui non bloccano mai il salvataggio principale.
final class GradeBackups {
    /// Application Support/GradeBackups: resta nel backup del dispositivo, fuori da iCloud Drive.
    static let standard: GradeBackups = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return GradeBackups(directory: base.appendingPathComponent("GradeBackups", isDirectory: true))
    }()

    /// Istantanee a rotazione (le `preLink` non ruotano mai).
    static let maxRotating = 10

    private let directory: URL
    private let manualURL: URL

    init(directory: URL) {
        self.directory = directory
        self.manualURL = directory.appendingPathComponent("voti-manuali.json")
    }

    // MARK: Backup manuale

    /// Regola unica di cosa è "manuale" (il Task 3 la restringe in base a `origin`).
    private func manualGrades(_ grades: [Grade]) -> [Grade] { grades }

    func writeManualBackup(_ grades: [Grade]) {
        guard prepareDirectory(),
              let data = try? JSONEncoder().encode(manualGrades(grades)) else { return }
        try? data.write(to: manualURL, options: .atomic)
    }

    func manualBackup() -> [Grade] {
        guard let data = try? Data(contentsOf: manualURL),
              let grades = try? JSONDecoder().decode([Grade].self, from: data) else { return [] }
        return grades
    }

    // MARK: Istantanee

    @discardableResult
    func snapshot(_ grades: [Grade], kind: SnapshotKind, now: Date = .now) -> GradeSnapshot? {
        guard prepareDirectory(), let data = try? JSONEncoder().encode(grades) else { return nil }
        let stamp = Self.formatter.string(from: now)
        let base = "snapshot-\(kind.rawValue)-\(stamp)"
        // Stesso secondo: non si sovrascrive mai un'istantanea esistente.
        var name = base
        var n = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(name + ".json").path) {
            name = "\(base)-\(n)"; n += 1
        }
        let url = directory.appendingPathComponent(name + ".json")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        rotate()
        return GradeSnapshot(id: name, kind: kind, date: Self.truncated(now), count: grades.count, url: url)
    }

    /// Dalla più recente alla più vecchia.
    func list() -> [GradeSnapshot] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let snaps = files.compactMap { url -> GradeSnapshot? in
            guard url.pathExtension == "json" else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            let parts = name.split(separator: "-").map(String.init)
            guard parts.count >= 4, parts[0] == "snapshot",
                  let kind = SnapshotKind(rawValue: parts[1]),
                  let date = Self.formatter.date(from: parts[2] + "-" + parts[3]),
                  let data = try? Data(contentsOf: url),
                  let grades = try? JSONDecoder().decode([Grade].self, from: data) else { return nil }
            return GradeSnapshot(id: name, kind: kind, date: date, count: grades.count, url: url)
        }
        return snaps.sorted { $0.date != $1.date ? $0.date > $1.date : $0.id > $1.id }
    }

    func load(_ s: GradeSnapshot) -> [Grade]? {
        guard let data = try? Data(contentsOf: s.url) else { return nil }
        return try? JSONDecoder().decode([Grade].self, from: data)
    }

    // MARK: Interni

    private func rotate() {
        let rotating = list().filter { $0.kind != .preLink }
        for s in rotating.dropFirst(Self.maxRotating) {
            try? FileManager.default.removeItem(at: s.url)
        }
    }

    private func prepareDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = false
            var dir = directory
            try? dir.setResourceValues(values)
            return true
        } catch { return false }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private static func truncated(_ d: Date) -> Date {
        Date(timeIntervalSince1970: d.timeIntervalSince1970.rounded(.down))
    }
}
