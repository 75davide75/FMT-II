import Foundation
import CryptoKit

/// Voto come lo restituisce un registro, già normalizzato ma non ancora applicato.
struct VotoRemoto: Codable, Equatable {
    var provider: RegistroProviderID
    var remoteId: String
    var date: Date
    var hasTime: Bool
    var subjectId: String?
    var subjectName: String
    var teacher: String?
    var rawValue: String
    var numericValue: Double?
    var kind: RemoteGradeKind?
    var kindRaw: String?
    var weight: Double?
    var period: String?
    var comment: String?
    var notCounting: Bool
    var cancelled: Bool
    var remoteModifiedAt: Date?

    /// SHA-256 esadecimale della forma canonica del voto: JSON con chiavi ordinate
    /// (tutti i campi, opzionali assenti omessi) e date come `timeIntervalSince1970` esatto.
    /// Le stringhe sono quotate ed escapate, quindi i confini tra campi non possono collidere.
    /// Deterministico tra un avvio e l'altro (nessun `Hasher`).
    func fingerprint() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let canonical = (try? encoder.encode(self)) ?? Data()
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }
}

/// Esito di una lettura dal registro.
struct RemoteFetch {
    var grades: [VotoRemoto]
    var skippedCount: Int
    var coveredRange: DateInterval?
}
