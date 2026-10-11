import Foundation

/// Materie più comuni, suggerite prima che l'utente ne abbia inserite.
/// Ricalcolate a ogni lettura così seguono la lingua dell'app.
enum SubjectSuggestions {
    static var all: [String] {
        [L("Italiano"), L("Matematica"), L("Storia"), L("Geografia"), L("Geostoria"),
         L("Inglese"), L("Francese"), L("Spagnolo"), L("Tedesco"), L("Latino"), L("Greco"),
         L("Scienze"), L("Scienze naturali"), L("Biologia"), L("Chimica"), L("Fisica"),
         L("Filosofia"), L("Storia dell'arte"), L("Disegno e storia dell'arte"),
         L("Diritto"), L("Economia"), L("Informatica"), L("Tecnologia"),
         L("Scienze motorie"), L("Educazione fisica"), L("Educazione civica"),
         L("Religione"), L("Musica"), L("Arte e immagine")]
    }
}
