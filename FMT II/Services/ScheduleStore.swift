import Foundation
import Combine

@MainActor
final class ScheduleStore: ObservableObject {
    @Published var schedule: ScheduleData? = nil
    @Published var isImporting = false
    @Published var errorMessage: String? = nil
    @Published var isPDFUnsupported = false
    /// Set after a partial import: the missing element the user can complete.
    @Published var pendingCompletion: ScheduleField? = nil
    /// Set when a PDF is rejected: the reason shown along with the manual-creation offer.
    @Published var rejection: ScheduleRejectReason? = nil

    private let storageKey = "findmyteacher.schedule"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        schedule = loadStored()
    }

    func importFile(data: Data, name: String) async {
        isImporting = true
        errorMessage = nil
        isPDFUnsupported = false
        defer { isImporting = false }

        let lower = name.lowercased()
        if lower.hasSuffix(".json") || lower.hasSuffix(".fmt2") {
            await _importJSON(data: data)
        } else {
            await _importPDF(data: data, name: name)
        }
    }

    private func _importPDF(data: Data, name: String) async {
        let outcome = await Task.detached(priority: .userInitiated) {
            importSchedulePDF(data: data, sourceName: name)
        }.value

        switch outcome {
        case .complete(let parsed):
            let normalized = normalizeScheduleTimes(parsed)
            commit(normalized)
            savePDF(data: data)
        case .partial(let parsed, let missing):
            let normalized = normalizeScheduleTimes(parsed)
            commit(normalized)
            savePDF(data: data)
            pendingCompletion = missing
        case .rejected(let reason):
            rejection = reason
        }
    }

    private func _importJSON(data: Data) async {
        do {
            let decoded = try decoder.decode(ScheduleData.self, from: data)
            commit(decoded.edited ? decoded : normalizeScheduleTimes(decoded))
        } catch {
            errorMessage = "File non valido o danneggiato."
        }
    }

    /// Saves a manually-edited schedule (from the database editor) without
    /// re-normalizing, so custom teacher/class names and times are preserved.
    func update(_ newSchedule: ScheduleData) {
        commit(newSchedule)
    }

    /// Restores a schedule from a backup (normalizes unless it was manually edited).
    func restore(_ newSchedule: ScheduleData) {
        let s = newSchedule.edited ? newSchedule : normalizeScheduleTimes(newSchedule)
        commit(s)
    }

    func clearSchedule() {
        schedule = nil
        isPDFUnsupported = false
        UserDefaults.standard.removeObject(forKey: storageKey)
        try? FileManager.default.removeItem(at: pdfStorageURL)
        UserDefaults.standard.set(Date(), forKey: clearedAtKey)
        CloudSyncManager.shared.enqueueSave([.schedule])
    }

    // MARK: - iCloud

    private let clearedAtKey = "findmyteacher.scheduleClearedAt"
    /// Quando l'orario è stato rimosso (tombstone per gli altri dispositivi).
    var clearedAt: Date? { UserDefaults.standard.object(forKey: clearedAtKey) as? Date }

    /// Salva un orario modificato localmente e lo accoda per iCloud.
    private func commit(_ s: ScheduleData) {
        var stamped = s
        stamped.modifiedAt = Date()
        schedule = stamped
        persist(stamped)
        UserDefaults.standard.removeObject(forKey: clearedAtKey)
        CloudSyncManager.shared.enqueueSave([.schedule])
    }

    /// Orario arrivato da iCloud (o rimosso su un altro dispositivo).
    func applyRemote(schedule remote: ScheduleData?, remoteModifiedAt: Date, deleted: Bool) {
        let localModified = schedule?.modifiedAt ?? clearedAt
        guard SyncMerge.remoteWins(local: localModified, remote: remoteModifiedAt) else { return }
        if deleted {
            schedule = nil
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.set(remoteModifiedAt, forKey: clearedAtKey)
        } else if let remote {
            let s = remote.edited ? remote : normalizeScheduleTimes(remote)
            schedule = s
            persist(s)
            UserDefaults.standard.removeObject(forKey: clearedAtKey)
        }
    }

    func exportScheduleURL() -> URL? {
        guard let schedule else { return nil }
        guard let data = try? encoder.encode(schedule) else { return nil }
        let baseName = schedule.sourceName
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orario \(baseName).json")
        try? data.write(to: url)
        return url
    }

    var savedPDFURL: URL? {
        FileManager.default.fileExists(atPath: pdfStorageURL.path) ? pdfStorageURL : nil
    }

    private var pdfStorageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("loaded_schedule.pdf")
    }

    private func savePDF(data: Data) {
        try? data.write(to: pdfStorageURL)
    }

    private func persist(_ data: ScheduleData) {
        guard let encoded = try? encoder.encode(data) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }

    private func loadStored() -> ScheduleData? {
        guard let raw = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        guard let decoded = try? decoder.decode(ScheduleData.self, from: raw) else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return nil
        }
        return decoded.edited ? decoded : normalizeScheduleTimes(decoded)
    }
}
