import Foundation
import CloudKit
import os

/// Sincronizzazione iCloud (CloudKit, database privato) di voti, note e orario.
/// Gli store restano la fonte di verità locale: il manager accoda le modifiche
/// locali e applica quelle remote (vedi `SyncMerge`).
@MainActor
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    static let containerIdentifier = "iCloud.com.davide.fmtII"
    static let zoneID = CKRecordZone.ID(zoneName: "FMTZone", ownerName: CKCurrentUserDefaultName)

    private var engine: CKSyncEngine?

    private init() {}

    func enqueueSave(_ items: [SyncItem]) {
        guard let engine, !items.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: items.map { .saveRecord(recordID(for: $0)) })
    }

    func enqueueDelete(_ items: [SyncItem]) {
        guard let engine, !items.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: items.map { .deleteRecord(recordID(for: $0)) })
    }

    private func recordID(for item: SyncItem) -> CKRecord.ID {
        CKRecord.ID(recordName: item.recordName, zoneID: Self.zoneID)
    }
}
