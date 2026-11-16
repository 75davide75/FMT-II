import Foundation
import CryptoKit

/// Identità deterministica dei voti importati: lo stesso voto del registro
/// produce lo stesso UUID su ogni dispositivo (nessun duplicato via iCloud).
enum RegistroIdentity {
    /// Namespace fisso per gli UUID v5 dei voti. NON cambiarlo mai: cambierebbe
    /// l'id di tutti i voti già importati.
    static let namespace = UUID(uuidString: "6F4D3C2A-8B1E-4A7F-9C55-2E0D1B7A93C4")!

    /// UUID v5 (RFC 4122) da `provider|accountKey|remoteId`.
    static func gradeID(provider: RegistroProviderID, accountKey: String, remoteId: String) -> UUID {
        uuidV5(namespace: namespace, name: "\(provider.rawValue)|\(accountKey)|\(remoteId)")
    }

    static func uuidV5(namespace: UUID, name: String) -> UUID {
        var input = Data()
        withUnsafeBytes(of: namespace.uuid) { input.append(contentsOf: $0) }
        input.append(Data(name.utf8))
        var h = Array(Insecure.SHA1.hash(data: input).prefix(16))
        h[6] = (h[6] & 0x0F) | 0x50   // versione 5
        h[8] = (h[8] & 0x3F) | 0x80   // variante RFC 4122
        return UUID(uuid: (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7],
                           h[8], h[9], h[10], h[11], h[12], h[13], h[14], h[15]))
    }
}
