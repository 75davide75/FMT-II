import Foundation

/// Esito della lettura del file voti.
struct GradeLoadResult {
    var grades: [Grade]
    /// Voti del file che non è stato possibile leggere (ignorati, ma conservati nella copia).
    var skippedCount: Int
    /// Copia di sicurezza del file originale, se qualcosa non era leggibile.
    var quarantinedURL: URL?
}

/// Lettura/scrittura sicura del file dei voti. Regola: mai perdere dati dell'utente.
/// Se il file (o parte di esso) non è leggibile, ne viene fatta una copia in
/// `fmt_grades.unreadable-<data>.json` PRIMA che un salvataggio possa sovrascriverlo.
struct GradeFileStore {
    let url: URL

    init(url: URL) { self.url = url }

    func load() -> GradeLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return GradeLoadResult(grades: [], skippedCount: 0, quarantinedURL: nil)
        }
        // File presente ma non leggibile dal disco: nessuna scrittura, nessun dato "inventato".
        guard let data = try? Data(contentsOf: url) else {
            return GradeLoadResult(grades: [], skippedCount: 0, quarantinedURL: nil)
        }
        if let decoded = try? JSONDecoder().decode([Grade].self, from: data) {
            return GradeLoadResult(grades: decoded, skippedCount: 0, quarantinedURL: nil)
        }
        // Decodifica elemento per elemento, così un voto rovinato non fa perdere gli altri.
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            return GradeLoadResult(grades: [], skippedCount: 0, quarantinedURL: quarantine(data))
        }
        let decoder = JSONDecoder()
        var grades: [Grade] = []
        var skipped = 0
        for element in array {
            guard JSONSerialization.isValidJSONObject([element]),
                  let item = try? JSONSerialization.data(withJSONObject: [element]),
                  let one = try? decoder.decode([Grade].self, from: item).first else {
                skipped += 1
                continue
            }
            grades.append(one)
        }
        return GradeLoadResult(grades: grades, skippedCount: skipped,
                               quarantinedURL: skipped > 0 ? quarantine(data) : nil)
    }

    /// Scrittura atomica: il file originale resta intatto se qualcosa va storto.
    func save(_ grades: [Grade]) throws {
        let data = try JSONEncoder().encode(grades)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Quarantena

    private func quarantine(_ data: Data) -> URL? {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let prefix = "\(base).unreadable-"
        let fm = FileManager.default
        // Stesso contenuto già messo in quarantena (avvii ripetuti): riusa la copia.
        let existing = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for candidate in existing where candidate.lastPathComponent.hasPrefix(prefix) {
            if (try? Data(contentsOf: candidate)) == data { return candidate }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: Date())
        var target = dir.appendingPathComponent("\(prefix)\(stamp).json")
        var n = 1
        while fm.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent("\(prefix)\(stamp)-\(n).json")
            n += 1
        }
        do {
            try data.write(to: target, options: .atomic)
            return target
        } catch {
            return nil
        }
    }
}
