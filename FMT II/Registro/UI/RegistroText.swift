import Foundation

/// Testi del registro per l'interfaccia: nomi dei registri, stato, tipi di
/// istantanea e messaggi d'errore chiari (mai dettagli tecnici o dati del registro).
enum RegistroText {
    /// Nomi commerciali: non si traducono.
    static func providerName(_ id: RegistroProviderID) -> String {
        switch id {
        case .classeviva: return "ClasseViva"
        case .argo: return "Argo"
        case .axios: return "Axios"
        case .nuvola: return "Nuvola"
        case .mastercom: return "Mastercom"
        case .pronote: return "Pronote"
        }
    }

    /// Sottotitolo dei registri disponibili (produttore o app di riferimento).
    static func providerDetail(_ id: RegistroProviderID) -> String {
        switch id {
        case .classeviva: return "Spaggiari"
        case .argo: return "didUP Famiglia"
        default: return ""
        }
    }

    /// Ordine nella scelta: prima quelli disponibili.
    static let providerOrder: [RegistroProviderID] = [.classeviva, .argo, .axios, .nuvola, .mastercom, .pronote]

    static func status(_ s: RegistroStatus) -> String {
        switch s {
        case .disconnected: return L("Non collegato")
        case .idle: return L("Collegato")
        case .syncing: return L("Sincronizzazione…")
        case .needsLogin: return L("Accesso richiesto")
        case .needsConfirmation: return L("Da confermare")
        case .error: return L("Errore")
        }
    }

    /// Avviso di "Scollega → Tenere i voti importati" sui giudizi non numerici
    /// (singolare per 1, come `counted`).
    static func nonNumericUnlinkWarning(_ n: Int) -> String {
        n == 1
            ? L("Attenzione: 1 giudizio senza voto numerico (es. «N.C.») perde l'etichetta del registro e resta come voto che non fa media.")
            : L("Attenzione: \(n) giudizi senza voto numerico (es. «N.C.») perdono l'etichetta del registro e restano come voti che non fanno media.")
    }

    static func snapshotKind(_ k: SnapshotKind) -> String {
        switch k {
        case .preLink: return L("Prima del collegamento")
        case .preSync: return L("Prima di una sincronizzazione")
        case .preRestore: return L("Prima di un ripristino")
        case .preUnlink: return L("Prima dello scollegamento")
        }
    }

    static func message(for error: Error) -> String {
        message(forCode: RegistroSyncCoordinator.code(for: error))
    }

    /// Messaggio per un codice di `RegistroStatus.error` (vedi `RegistroSyncCoordinator.code(for:)`).
    static func message(forCode code: String) -> String {
        if code.hasPrefix("invalidPlan") {
            return L("Le modifiche arrivate dal registro sembravano anomale e non sono state applicate. I tuoi voti sono invariati.")
        }
        switch code {
        case "invalidCredentials":
            return L("Nome utente o password non corretti. Per sicurezza FMT non riprova da solo: accedi di nuovo con i dati giusti.")
        case "rateLimited":
            return L("Il registro ha limitato o bloccato temporaneamente l'accesso a questo account. FMT non riprova da solo: attendi un po' prima di riprovare.")
        case "network":
            return L("Impossibile raggiungere il registro. Controlla la connessione e riprova.")
        case "sessionExpired":
            return L("La sessione del registro è scaduta. Riprova.")
        case "notSupported":
            return L("Questo account non è supportato oppure il profilo è stato disattivato dalla scuola.")
        case "unexpectedFormat:client-version":
            return L("Il registro non accetta più questa versione: serve un aggiornamento di FMT.")
        case "unexpectedFormat:profili":
            return L("Account con più studenti non ancora supportato. Usa le credenziali dello studente.")
        case "unexpectedFormat":
            return L("Il registro ha risposto in un formato inatteso (potrebbe essere cambiato). Nessun voto è stato modificato.")
        case "providerUnavailable":
            return L("Questo registro non è ancora disponibile.")
        case "alreadyConnected":
            return L("È già collegato un altro registro: scollegalo prima di collegarne uno nuovo.")
        case "differentAccount":
            return L("Queste credenziali sono di un altro account. Per cambiare account scollega prima il registro.")
        case "keychain":
            return L("Impossibile salvare le credenziali nel Portachiavi. Riprova.")
        case "cancelled":
            return L("Operazione annullata: il registro è stato scollegato.")
        case "writeBlocked", "writeFailed":
            return L("Impossibile salvare i voti in sicurezza in questo momento. Nessun voto è stato modificato.")
        case "snapshotFailed":
            return L("Impossibile salvare la copia di sicurezza dei voti, quindi non è stato modificato nulla.")
        default:
            return L("Si è verificato un errore imprevisto. Nessun voto è stato modificato.")
        }
    }
}
