import Foundation

/// Gli store dell'app, unici per processo: tutte le finestre (multi-scena su
/// iPad) e la sincronizzazione iCloud lavorano sugli stessi dati. Prima erano
/// `@StateObject` di ogni `ContentView`, e la sync restava legata alla prima
/// finestra anche dopo la sua chiusura.
@MainActor
final class AppStores {
    static let shared = AppStores()

    let schedule = ScheduleStore()
    let notes = NotesStore()
    let grades = GradesStore()

    private init() {}
}
