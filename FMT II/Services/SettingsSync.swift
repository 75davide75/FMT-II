import Foundation

extension Notification.Name {
    /// Impostazioni scuola cambiate da un altro dispositivo.
    static let fmtSyncedSettingsChanged = Notification.Name("fmtSyncedSettingsChanged")
}

/// Impostazioni "di scuola" condivise via iCloud key-value store. Le preferenze
/// del dispositivo (tema, testo, tutorial…) restano locali.
@MainActor
final class SettingsSync {
    static let shared = SettingsSync()
    nonisolated static let syncedKeys = ["sufficientGrade", "maxGrade", "periodSystem", "period1EndTimestamp",
                                         "fmt_subject_colors", "fmt_entity_colors"]

    private let kvs = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private var applyingRemote = false
    private var started = false

    private init() {}

    func start() {
        let env = ProcessInfo.processInfo.environment
        guard !started, env["XCTestConfigurationFilePath"] == nil,
              !ProcessInfo.processInfo.arguments.contains("-FMTSeedDemo") else { return }
        started = true
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: kvs, queue: .main) { [weak self] note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? SettingsSync.syncedKeys
            MainActor.assumeIsolated { self?.pull(keys: keys) }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.push() }
        }
        kvs.synchronize()
        // Primo avvio: i valori già in iCloud vincono, quelli solo locali salgono.
        pull(keys: Self.syncedKeys.filter { kvs.object(forKey: $0) != nil })
        push()
    }

    private func push() {
        guard !applyingRemote else { return }
        for key in Self.syncedKeys {
            guard let local = defaults.object(forKey: key) else { continue }
            if !Self.same(local, kvs.object(forKey: key)) { kvs.set(local, forKey: key) }
        }
    }

    private func pull(keys: [String]) {
        let relevant = keys.filter { Self.syncedKeys.contains($0) }
        guard !relevant.isEmpty else { return }
        applyingRemote = true
        defer { applyingRemote = false }
        var changed = false
        for key in relevant {
            guard let remote = kvs.object(forKey: key) else { continue }
            if !Self.same(remote, defaults.object(forKey: key)) {
                defaults.set(remote, forKey: key)
                changed = true
            }
        }
        guard changed else { return }
        // Forza il refresh delle tinte docenti/classi nelle viste.
        defaults.set(defaults.integer(forKey: "entityColorsVersion") + 1, forKey: "entityColorsVersion")
        NotificationCenter.default.post(name: .fmtSyncedSettingsChanged, object: nil)
    }

    nonisolated static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil):   return true
        case let (a?, b?): return (a as AnyObject).isEqual(b)
        default:           return false
        }
    }
}
