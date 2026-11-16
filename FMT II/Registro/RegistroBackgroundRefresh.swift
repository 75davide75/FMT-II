import Foundation
import BackgroundTasks

/// Quando notificare i voti nuovi: funzione pura, senza I/O.
enum RegistroNotificationPolicy {
    /// Voti da annunciare dopo una sync. Solo con preferenza attiva, solo per sync
    /// automatiche (all'apertura o in background), mai al primo import e solo per
    /// i voti inseriti da questa sync (`newGradeIDs`) e davvero presenti nei voti.
    static func gradesToNotify(plan: SyncPlan, trigger: SyncTrigger, isFirstImport: Bool,
                               toggleOn: Bool, grades: [Grade]) -> [Grade] {
        guard toggleOn, !isFirstImport, trigger != .manual, !plan.newGradeIDs.isEmpty else { return [] }
        let ids = Set(plan.newGradeIDs)
        return grades.filter { ids.contains($0.id) }
    }
}

/// Aggiornamento periodico in background (BGAppRefreshTask). Tutte le scritture
/// passano da `RegistroSyncCoordinator.syncNow(.background)`.
@MainActor
enum RegistroBackgroundRefresh {
    nonisolated static let identifier = "com.davide.fmtII.registroRefresh"
    /// Non prima di 2 ore dalla richiesta.
    static let minimumInterval: TimeInterval = 2 * 3600

    /// Da chiamare prima della fine di `didFinishLaunching`.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            nonisolated(unsafe) let task = task
            Task { @MainActor in handle(task) }
        }
    }

    /// Richiesta per la prossima esecuzione; nil se nessun registro è collegato.
    /// Non invia nulla (vedi `submit`).
    static func schedule(now: Date = .now, registro: RegistroSyncCoordinator? = nil) -> BGAppRefreshTaskRequest? {
        let registro = registro ?? AppStores.shared.registro
        guard registro.connectedProvider != nil else { return nil }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = now.addingTimeInterval(minimumInterval)
        return request
    }

    /// Prepara e invia la richiesta; gli errori di invio si ignorano in silenzio.
    static func scheduleAndSubmit(now: Date = .now) {
        #if DEBUG
        if FakeRegistro.isRequested { return }
        #endif
        guard let request = schedule(now: now) else { return }
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Scollegato: niente più esecuzioni in background.
    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    private static func handle(_ task: BGTask) {
        // Prima la prossima esecuzione, poi la sync.
        scheduleAndSubmit()
        let work = Task { @MainActor in
            let plan = await AppStores.shared.registro.syncNow(.background)
            task.setTaskCompleted(success: plan != nil)
        }
        task.expirationHandler = {
            // Il coordinatore applica il piano in modo atomico dopo il download:
            // annullare qui interrompe solo l'attesa di rete.
            work.cancel()
        }
    }
}
