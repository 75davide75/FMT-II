# FMT 2.2 — Sincronizzazione iCloud + ora d'inizio per classe — design

Data: 2026-10-11. Fonte: richiesta utente + risposte alle domande di
brainstorming. Base: branch `feature/ui-round-3` (v2.1.1 pubblicata).

## Obiettivo

1. Tutti i dati dell'app sincronizzati fra i dispositivi con lo stesso Apple ID
   (un voto aggiunto su iPad compare su iPhone).
2. Ora d'inizio lezioni uguale per tutte le classi **oppure** diversa per
   classe (toggle).
3. Banner «Novità 2.2» visto solo da chi aggiorna (tutorial già fatto), mai da
   chi installa da zero.
4. Stile Aurora Glass come il resto dell'app; rilascio 2.2.0 su App Store,
   codice su GitHub con PR verso `main`.

Decisioni utente: per classe cambia **solo l'inizio** (durata e numero di ore
globali); sync di **dati + impostazioni scuola**; App Store: upload e invio
alla revisione **solo dopo OK esplicito**; GitHub: push + PR verso `main`.

## A. Sincronizzazione — CloudKit con CKSyncEngine

**Container**: `iCloud.com.davide.fmtII`, database privato, zona custom
`FMTZone`. Entitlements: iCloud (CloudKit), `aps-environment`, background mode
`remote-notification`.

**Record**

| recordType | recordName | campi |
|---|---|---|
| `Grade` | `grade-<UUID>` | `payload` (JSON del `Grade`), `modifiedAt` |
| `Note` | `note-<UUID>` | `payload` (JSON, Bytes), `modifiedAt` |
| `Schedule` | `schedule-current` | `payloadAsset` (JSON di `ScheduleData`, CKAsset), `modifiedAt`, `deleted` (Int 0/1: orario rimosso) |

Il payload JSON riusa i `Codable` esistenti: nessun campo CloudKit per singolo
attributo, quindi aggiungere attributi in futuro non richiede modifiche allo
schema.

Nota (implementazione): le note sono solo testo RTF, quindi restano sempre
in un campo Bytes; l'orario usa sempre un CKAsset. Così in Development
vengono creati tutti i campi dello schema prima del deploy in Production.

**Modelli**: `Grade`, `Note` e `ScheduleData` ricevono `modifiedAt: Date`
(decodeIfPresent, default = `createdAt`/`date`/distantPast) aggiornato a ogni
modifica locale.

**Componenti**

- `CloudSyncManager` (Services/CloudSyncManager.swift, @MainActor singleton):
  possiede il `CKSyncEngine`, persiste `State.Serialization` in
  `Application Support/fmt_sync_state.json`, crea la zona al primo avvio,
  traduce eventi in chiamate agli store.
- `SyncMerge` (Services/SyncMerge.swift): funzioni pure, testabili —
  last-writer-wins su `modifiedAt` (a parità vince il remoto, così i
  dispositivi convergono).
- Store (`GradesStore`, `NotesStore`, `ScheduleStore`): dopo ogni save
  locale notificano il manager (cambiati / cancellati); espongono
  `applyRemote(upserts:deletions:)` che **non** rinotifica il manager (niente
  loop). `NotesStore.applyRemote` riprogramma le notifiche locali.

**Flussi**

- Primo avvio con sync: tutti gli elementi locali vengono accodati come
  modifiche in uscita; quelli remoti scaricati vengono uniti per id
  (unione, mai sostituzione totale).
- Conflitto `serverRecordChanged`: confronto `modifiedAt`; se vince il locale si
  ri-invia sopra il record server, altrimenti si applica il server.
- Cancellazioni: locale → `deleteRecord` in coda; remota → rimozione locale.
  Orario rimosso → record `Schedule` con `deleted = 1` (così un dispositivo
  con orario vecchio non lo ri-carica).
- Account iCloud assente/cambiato: l'app resta locale; su cambio account lo
  stato del sync engine viene azzerato (i dati locali restano).
- Errori di rete/quota: retry di CKSyncEngine; quota piena →
  stato «Spazio iCloud esaurito».

**Impostazioni scuola** — `NSUbiquitousKeyValueStore` tramite
`SettingsSync` (Services/SettingsSync.swift): chiavi `sufficientGrade`,
`maxGrade`, `periodSystem`, `period1EndTimestamp`, `fmt_subject_colors`,
colori docenti/classi (+ bump di `entityColorsVersion` in arrivo). Push al
cambio, pull su `didChangeExternallyNotification`. **Non** sincronizzate:
`appearanceMode`, `dynamicTypeLevel`, `useLiveTime`, `manualDayRaw`,
`manualTime`, `appSectionRaw`, `hasSeenTutorial`, `hasCompletedOnboarding`,
`lastSeenWhatsNew`.

**UI**: in Impostazioni nuova sezione Aurora «Sincronizzazione iCloud»:
icona `icloud`, stato (Attiva · aggiornata alle HH:mm / In corso… / Accedi a
iCloud per sincronizzare / Spazio iCloud esaurito / Errore) + pulsante
«Sincronizza ora».

## B. Ora d'inizio per classe

**Modello** (`ScheduleData`, additivo, decodeIfPresent):
- `perClassStartTimes: Bool = false`
- `classStartTimes: [String: String] = [:]` (classe → "HH:mm" della 1ª ora)

**Logica** (Models/ClassTimes.swift, funzioni pure):
- `periods(for className:)` → `periods` globali traslati in modo che la 1ª ora
  inizi a `classStartTimes[className]` (se toggle on e valore presente),
  altrimenti globali.
- `applyManualEdits` riallinea `startTime/endTime` di ogni lezione alle fasce
  **della sua classe** e rigenera gli id.
- `timeSlots(forClass:)` / `allTimeSlots` → inizi delle fasce (+ fine ultima
  ora) per una classe o unione ordinata di tutte (vista docente, scelta orario
  nota, impostazioni).
- Rinomina classe sposta la chiave; classe rimossa → chiave rimossa.

**Viste**: Settimana/Giorno/Main in modalità **classe** usano
le fasce di `selectedClass`; in modalità **docente** usano l'unione (righe per
orario reale, abbinamento lezione↔riga per `startTime` come oggi).

**Editor** (DatabaseEditorView → «Fasce orarie», stile Aurora): sotto
«Durata lezione» toggle «Inizio diverso per classe». On → per ogni classe una
riga con chip classe colorato + DatePicker (default = inizio globale)
+ anteprima «1ª–ultima». Footer: «La durata delle lezioni resta uguale per
tutte le classi.» Off → come oggi (i valori per classe restano memorizzati ma
ignorati).

## C. Banner «Novità 2.2»

- `@AppStorage("lastSeenWhatsNew")` (locale).
- `WhatsNew.shouldShow(tutorialDoneAtLaunch:lastSeen:)` (pura, testata):
  true se il tutorial era già stato completato **al lancio** e la 2.2 non è
  ancora stata vista.
- Al termine del tutorial (nuova installazione) → `lastSeenWhatsNew = "2.2"`.
- UI: card glass Aurora in alto sopra il contenuto principale (icona gradiente,
  titolo «Novità di FMT 2.2», due righe: «Sincronizzazione iCloud tra iPhone e
  iPad» / «Ora d'inizio diversa per ogni classe», pulsante «Ho capito»).

## D. Test

XCTest: `ClassTimesTests`, `SyncMergeTests`, `WhatsNewTests`,
`BackwardCompatTests` (decodifica JSON 2.1.1 senza i nuovi campi). Build +
avvio su simulatore iPhone e iPad; screenshot di editor fasce, banner e
sezione iCloud. Test sync reale su due dispositivi: a cura dell'utente.

## E. Rilascio

- `MARKETING_VERSION = 2.2.0`, `CURRENT_PROJECT_VERSION = 2`.
- Testi «Novità» IT/EN in `AppStore/metadata/whats-new-2.2.md`; privacy
  policy aggiornata (dati nell'iCloud dell'utente, nessun server dello
  sviluppatore).
- CloudKit Console: **Deploy Schema to Production** prima dell'invio.
- Archive + upload con `xcodebuild -allowProvisioningUpdates`; invio alla
  revisione solo dopo OK esplicito dell'utente.
- Git: push `feature/ui-round-3`, push `feature/icloud-sync-v2.2`, PR verso
  `main`.

## Fuori scope

Condivisione tra Apple ID diversi, sync del PDF originale importato
(resta locale), orari diversi per giorno della settimana, durata per classe.
