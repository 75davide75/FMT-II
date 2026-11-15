# Voti dal registro elettronico (FMT 2.3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Importare in sicurezza i voti da ClasseViva e Argo nella tab Voti, senza duplicati e senza mai perdere i voti inseriti a mano.

**Architecture:** `Grade` riceve un `origin: RegistroOrigin?` facoltativo. Un motore puro (`RegistroSyncEngine`) confronta voti locali e remoti e produce un `SyncPlan`, che viene validato e applicato in un'unica scrittura da `GradesStore` dopo un'istantanea di backup. I provider (ClasseViva, Argo, stub per gli altri) parlano col registro tramite un trasporto HTTP iniettabile; il `RegistroSyncCoordinator` orchestra login, sync, conflitti e scollegamento.

**Tech Stack:** Swift 5, SwiftUI (iOS 17+), CloudKit (sync esistente), NSUbiquitousKeyValueStore (`SettingsSync`), Security (Keychain), CryptoKit, BackgroundTasks, UserNotifications, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-15-registro-sync-design.md`

## Global Constraints

- Priorità assoluta: nessun voto inserito dall'utente va perso; ogni errore del registro = nessuna scrittura, app funzionante come prima.
- Nessun voto viene mai cancellato automaticamente dalla sync.
- Nessun endpoint o campo inventato: i provider implementano solo ciò che è documentato in `docs/registri/<provider>.md` con fonti; il resto è TODO da chiedere all'utente.
- Nessun dato inventato: ora, peso, docente assenti restano assenti (`hasTime = false`, `remoteWeight = nil`, `teacher = ""`).
- Credenziali e token solo nel Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, non sincronizzabili; mai in file, UserDefaults, iCloud, log.
- Nessun nuovo caso in `GradeType` (la 2.2 è sull'App Store e non lo decodificherebbe).
- Un solo account collegato alla volta.
- Ogni testo nuovo passa da `L()`/catalogo con traduzione inglese (`LocalizationCompletenessTests` deve restare verde).
- Stile Aurora Glass esistente (`Theme.swift`, `SettingsView.row/header`).
- Soglie: collegamento automatico punteggio ≥ 0,9 e secondo < 0,5; conferma utente se il piano tocca > 20 voti manuali; sync all'apertura al più ogni 15 minuti; background non prima di 2 ore; istantanee a rotazione: ultime 10 (+ quella "prima del collegamento" per sempre).
- Test: `xcodebuild test -project "FMT II.xcodeproj" -scheme "FMT II" -destination 'platform=iOS Simulator,id=5442426A-6EE8-4C62-9FEE-CA746ED4396E' -parallel-testing-enabled NO -only-testing:"FMT IITests/<Classe>"`; suite completa con `-only-testing:"FMT IITests"`.
- Commit con riga finale `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Due dispositivi importano/collegano lo stesso voto prima che iCloud li allinei → dopo la convergenza resta un solo voto (Task 9, `testDuplicateRemoteKeysCollapseKeepingLinkedManual`).
2. Il registro cambia un voto che l'utente aveva modificato → il valore dell'utente resta (Task 8, `testUserEditedFieldIsNotOverwritten`).
3. Errore di rete o formato a metà download → nessuna scrittura, nessuna istantanea inutile, stato errore (Task 9, `testProviderFailureWritesNothing`).
4. App reinstallata / nuovo telefono: credenziali Keychain assenti ma voti collegati presenti via iCloud → stato "accedi di nuovo", nessun crash, voti intatti (Task 9, `testMissingCredentialsNeedsLogin`).
5. Data senza ora "2026-11-14" interpretata nel fuso Europe/Rome → giorno 14, non 13 (Task 11 e 12, `testDateOnlyIsRomeMidnight`).

## Nota sul percorso dei documenti

La spec dice `Docs/Registri/`; il disco del Mac non distingue maiuscole e il repo ha già `docs/`, quindi si usa `docs/registri/<provider>.md`.

---

### Task 1: Salvataggio sicuro dei voti

**Files:**
- Create: `FMT II/Registro/Storage/GradeFileStore.swift`
- Modify: `FMT II/Models/GradeModel.swift` (`GradesStore.init`, `load`, `save`)
- Test: `FMT IITests/GradeFileStoreTests.swift`

**Interfaces:**
- Produces: `struct GradeFileStore { init(url: URL); func load() -> GradeLoadResult; func save(_ grades: [Grade]) throws }`, `struct GradeLoadResult { var grades: [Grade]; var skippedCount: Int; var quarantinedURL: URL? }`, `GradesStore.init(storageURL: URL = GradesStore.defaultURL, backups: GradeBackups? = .standard)` (il parametro `backups` è usato dal Task 2; qui può essere ignorato), `static let GradesStore.defaultURL`.

- [ ] **Step 1: Test che falliscono** (directory temporanea per test)
  - `testUnreadableFileIsQuarantinedNotOverwritten`: scrivi `"{non json"` nel file → `load()` dà `grades == []`, `quarantinedURL != nil`, il file in quarantena (`fmt_grades.unreadable-<yyyyMMdd-HHmmss>.json`) contiene esattamente `"{non json"`.
  - `testOneCorruptGradeDoesNotLoseTheOthers`: array JSON con 2 voti validi + 1 oggetto con `"value": "x"` → `grades.count == 2`, `skippedCount == 1`, e il file originale viene copiato in quarantena prima di qualunque `save`.
  - `testSaveIsAtomicAndRoundTrips`: `save` di 3 voti → `load` restituisce gli stessi (Equatable sui campi).
  - `testGradesStoreDoesNotWipeUnreadableFile`: `GradesStore(storageURL:)` su file illeggibile, poi `add(Grade())` → la copia in quarantena esiste ancora con il contenuto originale.
- [ ] **Step 2: Esegui** `-only-testing:"FMT IITests/GradeFileStoreTests"` → FAIL (tipo non definito).
- [ ] **Step 3: Implementa** `GradeFileStore`: decodifica prima come `[Grade]`; se fallisce, come `[JSONValue]`/`[Data]` elemento per elemento (`JSONSerialization` + decodifica singola); se nemmeno l'array si legge → quarantena. Scrittura con `.atomic`. `GradesStore` usa `GradeFileStore`; `Grade` diventa `Equatable` se non lo è.
- [ ] **Step 4: Esegui** la classe → PASS; poi la suite completa → tutto verde.
- [ ] **Step 5: Commit** `fix(voti): un file voti illeggibile non viene più sovrascritto`.

### Task 2: Backup dei voti manuali e istantanee

**Files:**
- Create: `FMT II/Registro/Storage/GradeBackups.swift`
- Modify: `FMT II/Models/GradeModel.swift` (`save()` aggiorna il backup manuale; `restore(_:)`)
- Test: `FMT IITests/GradeBackupsTests.swift`

**Interfaces:**
- Consumes: `GradeFileStore` (Task 1); `Grade.origin` / `RegistroOrigin.manualSnapshot` arrivano col Task 3: in questo task il backup manuale = voti senza `origin` (aggiornare la regola nel Task 3).
- Produces: `final class GradeBackups { static let standard: GradeBackups; init(directory: URL); func writeManualBackup(_ grades: [Grade]); func manualBackup() -> [Grade]; @discardableResult func snapshot(_ grades: [Grade], kind: SnapshotKind, now: Date = .now) -> GradeSnapshot?; func list() -> [GradeSnapshot]; func load(_ s: GradeSnapshot) -> [Grade]? }`, `enum SnapshotKind: String, Codable { case preLink, preSync, preRestore, preUnlink }`, `struct GradeSnapshot: Identifiable, Equatable { id: String; kind: SnapshotKind; date: Date; count: Int; url: URL }`, `GradesStore.restore(_ s: GradeSnapshot) -> Bool`.
- Directory standard: `Application Support/GradeBackups/` con `isExcludedFromBackup` = false (resta nel backup del dispositivo) ma fuori da iCloud Drive.

- [ ] **Step 1: Test**
  - `testManualBackupKeepsOnlyManualGrades`: dopo `writeManualBackup`, `manualBackup()` contiene tutti e soli i voti manuali.
  - `testPreLinkSnapshotIsNeverRotatedAway`: 1 `.preLink` + 15 `.preSync` → `list()` ha 11 elementi, il `.preLink` c'è.
  - `testRotationKeepsNewestTen`: 12 `.preSync` con date crescenti → restano le 10 più recenti.
  - `testRestoreTakesSnapshotOfCurrentStateFirst`: `GradesStore.restore(s)` → esiste una `.preRestore` con i voti di prima, e `grades` = contenuto di `s`.
  - `testStoreSaveUpdatesManualBackup`: `GradesStore.add` di un voto manuale → `manualBackup()` lo contiene.
- [ ] **Step 2: Esegui** → FAIL.
- [ ] **Step 3: Implementa**: file JSON `snapshot-<kind>-<yyyyMMdd-HHmmss>.json` + `voti-manuali.json`; scritture atomiche; errori di I/O ignorati senza bloccare il salvataggio principale (mai un crash).
- [ ] **Step 4: Esegui** classe + suite → PASS.
- [ ] **Step 5: Commit** `feat(voti): backup automatico dei voti manuali e istantanee ripristinabili`.

### Task 3: Modello `RegistroOrigin` e compatibilità

**Files:**
- Create: `FMT II/Registro/Core/RegistroOrigin.swift`, `FMT II/Registro/Core/RegistroIdentity.swift`
- Modify: `FMT II/Models/GradeModel.swift` (`Grade.origin`, decodifica, `displayValue`), `FMT II/Registro/Storage/GradeBackups.swift` (backup manuale include `manualSnapshot`)
- Test: `FMT IITests/RegistroModelTests.swift`, fixture `FMT IITests/Fixtures/grades-v2.2.json` (voti manuali reali anonimizzati, formato attuale)

**Interfaces:**
- Produces:
  - `enum RegistroProviderID: String, Codable, CaseIterable { case classeviva, argo, axios, nuvola, mastercom, pronote }`
  - `enum RemoteGradeKind: String, Codable { case written, oral, practical, other }`
  - `struct AppliedValues: Codable, Equatable { subject: String; teacher: String; value: Double; date: Date; type: GradeType; weight: Double; countsForAverage: Bool }` + `init(_ g: Grade)` + `func editedFields(in g: Grade) -> Set<GradeField>`
  - `enum GradeField: String, Codable { case subject, teacher, value, date, type, weight, countsForAverage }`
  - `struct ManualGradeSnapshot: Codable, Equatable` (stessi campi di `Grade` tranne `origin`) con `init(_ g: Grade)` e `func restored(id: UUID) -> Grade`
  - `enum RemoteStatus: String, Codable { case active, removedFromRegistro }`
  - `struct RegistroOrigin: Codable, Equatable { provider; accountKey: String; remoteId: String; rawValue: String; numericValue: Double?; hasTime: Bool; remoteSubjectId: String?; remoteSubjectName: String; remoteTeacher: String?; remoteTypeRaw: String?; remoteKind: RemoteGradeKind?; remoteWeight: Double?; remotePeriod: String?; remoteComment: String?; notCounting: Bool; cancelled: Bool; remoteModifiedAt: Date?; fingerprint: String; applied: AppliedValues; manualSnapshot: ManualGradeSnapshot?; status: RemoteStatus }` + `var remoteKey: String` (`"provider|accountKey|remoteId"`)
  - `Grade.origin: RegistroOrigin?`, `Grade.isImported: Bool` (origin != nil && manualSnapshot == nil)
  - `enum RegistroIdentity { static func gradeID(provider: RegistroProviderID, accountKey: String, remoteId: String) -> UUID }` (UUID v5, SHA-1 di CryptoKit `Insecure.SHA1`, namespace costante fissato nel file)

- [ ] **Step 1: Test**
  - `testV22FileDecodesIdentically`: `grades-v2.2.json` → stessi id/valori/date, `origin == nil` per tutti; ri-codifica → nessuna chiave `origin`.
  - `testOriginRoundTripsThroughJSON`.
  - `testV22CanDecodeGradeWithOrigin`: payload con `origin` decodificato con una copia del decoder 2.2 (struct di test con le sole chiavi 2.2) → riuscito.
  - `testDisplayValueUsesRawValueUntilUserEditsValue`: origin `rawValue "7½"`, `value == applied.value` → `displayValue == "7½"`; cambiando `value` → `displayValue == value.italianGrade`.
  - `testDeterministicIDIsStable`: stessa terna → stesso UUID; `remoteId` diverso → UUID diverso; valore atteso fisso per `("classeviva","S123","4567")` scritto nel test dopo la prima esecuzione verde (regressione).
  - `testEditedFieldsDetectsChanges`.
  - `testManualBackupIncludesManualSnapshotsOfLinkedGrades`.
- [ ] **Step 2: Esegui** → FAIL.
- [ ] **Step 3: Implementa** (decodifica `origin` con `decodeIfPresent`; `displayValue` per giustifica invariato).
- [ ] **Step 4: Esegui** classe + suite → PASS.
- [ ] **Step 5: Commit** `feat(registro): modello del voto collegato al registro`.

### Task 4: Normalizzazione dei voti

**Files:**
- Create: `FMT II/Registro/Core/GradeValueNormalizer.swift`
- Test: `FMT IITests/GradeValueNormalizerTests.swift`

**Interfaces:**
- Produces: `enum GradeValueNormalizer { static func normalize(_ raw: String, providedNumeric: Double?, maxGrade: Double) -> Double? }`

- [ ] **Step 1: Test** (tabella, `maxGrade: 10`):
  `"7"`→7, `"7+"`→7.25, `"7-"`→6.75, `"7½"`→7.5, `"7 1/2"`→7.5, `"7.5"`→7.5, `"7,25"`→7.25, `"6/7"`→6.5, `"6-7"`→6.5, `"7--"`→6.5, `"7++"`→7.5, `"10-"`→9.75, `"ottimo"`→10, `"Distinto"`→9, `"buono"`→8, `"discreto"`→7, `"sufficiente"`→6, `"insufficiente"`→5, `"gravemente insufficiente"`→4, `"N.C."`/`"NC"`/`"n.c."`/`"non classificato"`/`""`/`"ass."`→nil, `"11"`→nil, `" 8 "`→8; `providedNumeric: 7.75` con raw `"7/8"` → 7.75 (vince il registro); `providedNumeric: 12` → nil (fuori scala).
- [ ] **Step 2: Esegui** → FAIL.
- [ ] **Step 3: Implementa** (tabella giudizi come costante documentata; confronto senza maiuscole/accenti/punti finali).
- [ ] **Step 4: Esegui** → PASS.
- [ ] **Step 5: Commit** `feat(registro): normalizzazione dei voti del registro`.

### Task 5: Protocollo provider, Keychain, stub

**Files:**
- Create: `FMT II/Registro/Core/RegistroProvider.swift`, `FMT II/Registro/Core/VotoRemoto.swift`, `FMT II/Registro/Core/HTTPTransport.swift`, `FMT II/Registro/Storage/KeychainStore.swift`, `FMT II/Registro/Providers/Stubs/StubProviders.swift`
- Test: `FMT IITests/RegistroCoreTests.swift`

**Interfaces:**
- Produces:
  - `struct VotoRemoto: Codable, Equatable { provider: RegistroProviderID; remoteId: String; date: Date; hasTime: Bool; subjectId: String?; subjectName: String; teacher: String?; rawValue: String; numericValue: Double?; kind: RemoteGradeKind?; kindRaw: String?; weight: Double?; period: String?; comment: String?; notCounting: Bool; cancelled: Bool; remoteModifiedAt: Date? }` + `func fingerprint() -> String` (SHA-256 esadecimale dei campi in ordine fisso)
  - `struct RemoteFetch { var grades: [VotoRemoto]; var skippedCount: Int; var coveredRange: DateInterval? }`
  - `struct RegistroCapabilities: OptionSet { forniscePeso, fornisceOra, fornisceDocente, fornisceCommento, forniscePeriodo }`
  - `enum LoginField: String { case username, password, schoolCode }`
  - `struct RegistroCredentials: Codable, Equatable { username: String; password: String; schoolCode: String? }`
  - `struct RegistroSession: Codable, Equatable { accountKey: String; token: String; expiresAt: Date?; extra: [String: String] }`
  - `enum RegistroError: Error, Equatable { case invalidCredentials, sessionExpired, network, unexpectedFormat(String), notSupported, rateLimited }`
  - `protocol HTTPTransport { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`, `struct URLSessionTransport: HTTPTransport` (sessione `.ephemeral`, niente cookie persistenti), `final class MockTransport: HTTPTransport` nei test (risposte per URL+metodo, registro delle richieste)
  - `protocol RegistroProvider { var id: RegistroProviderID { get }; var isAvailable: Bool { get }; var capabilities: RegistroCapabilities { get }; var loginFields: [LoginField] { get }; func login(_ c: RegistroCredentials) async throws -> RegistroSession; func refresh(_ s: RegistroSession) async throws -> RegistroSession; func fetchGrades(_ s: RegistroSession) async throws -> RemoteFetch; func logout(_ s: RegistroSession) async }`
  - Stub `AxiosProvider`, `NuvolaProvider`, `MastercomProvider`, `PronoteProvider`: `isAvailable = false`, capabilities vuote, ogni metodo lancia `.notSupported`
  - `struct KeychainStore { init(service: String = "com.davide.fmtII.registro"); func set(_ data: Data, for key: String) throws; func data(for key: String) -> Data?; func remove(_ key: String) }`

- [ ] **Step 1: Test**: `testStubsAreUnavailableAndThrowNotSupported`; `testKeychainRoundTripAndRemove` (service di test dedicato, pulizia in `tearDown`); `testKeychainItemsAreThisDeviceOnly` (legge gli attributi con `SecItemCopyMatching` + `kSecReturnAttributes`: `kSecAttrAccessible == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable` assente/false); `testFingerprintChangesWhenValueChanges`.
- [ ] **Step 2: Esegui** → FAIL. **Step 3: Implementa.** **Step 4: Esegui** classe + suite → PASS.
- [ ] **Step 5: Commit** `feat(registro): protocollo provider, Keychain e stub`.

### Task 6: Mapping materie e voti ignorati

**Files:**
- Create: `FMT II/Registro/Core/SubjectMapping.swift`, `FMT II/Registro/Storage/RegistroSettingsStore.swift`
- Modify: `FMT II/Services/SettingsSync.swift` (`syncedKeys` + `"registroSubjectMap"`, `"registroIgnored"`)
- Test: `FMT IITests/SubjectMappingTests.swift`

**Interfaces:**
- Produces:
  - `struct RemoteSubjectRef: Codable, Hashable { id: String?; name: String; var key: String }` (`key` = `id` se presente, altrimenti `SubjectMatcher.normalizedKey(name)`)
  - `struct SubjectMappingTable: Codable, Equatable { var entries: [String: String]; var confirmed: Set<String>; func appSubject(for r: RemoteSubjectRef) -> String? }` (restituisce solo se confermato)
  - `enum SubjectProposal: Equatable { case existing(String, viaAlias: Bool); case new(String) }`
  - `enum SubjectMatcher { static func normalizedKey(_ s: String) -> String; static func readableName(_ s: String) -> String; static func propose(_ r: RemoteSubjectRef, appSubjects: [String]) -> SubjectProposal }`
  - `final class RegistroSettingsStore { init(defaults: UserDefaults = .standard); var mapping: SubjectMappingTable; var ignored: Set<String>; func ignore(_ remoteKey: String); func clearIgnored() }` (JSON in UserDefaults sotto le due chiavi sincronizzate)
- Alias (gruppi equivalenti, chiavi normalizzate): {italiano, lingua e letteratura italiana, lingua italiana}, {matematica, matematica e complementi di matematica}, {inglese, lingua inglese, lingua e cultura inglese, lingua e letteratura inglese}, {scienze motorie, scienze motorie e sportive, educazione fisica, ed fisica}, {religione, religione cattolica, irc}, {storia, storia e geografia, geostoria}, {scienze, scienze naturali, scienze integrate}.

- [ ] **Step 1: Test**: `testNormalizedKey` (`"MATEMATICA"`, `" Matemàtica. "` → `"matematica"`); `testExactProposal` (→ `.existing("Matematica", viaAlias: false)`); `testAliasProposal` (`"LINGUA E LETTERATURA ITALIANA"` con app `["Italiano"]` → `.existing("Italiano", viaAlias: true)`); `testNewProposalIsReadable` (`"SCIENZE MOTORIE E SPORTIVE"` senza materie app → `.new("Scienze motorie e sportive")`); `testUnconfirmedMappingReturnsNil`; `testStoreRoundTripsAndKeysAreSynced` (le due chiavi sono in `SettingsSync.syncedKeys`).
- [ ] **Step 2–4:** FAIL → implementa → PASS (classe + suite).
- [ ] **Step 5: Commit** `feat(registro): mapping materie e voti ignorati`.

### Task 7: Punteggio di corrispondenza

**Files:**
- Create: `FMT II/Registro/Engine/GradeMatcher.swift`
- Test: `FMT IITests/GradeMatcherTests.swift`

**Interfaces:**
- Consumes: `VotoRemoto`, `Grade`.
- Produces: `struct MatchCandidate: Equatable { gradeID: UUID; score: Double }`, `enum MatchThresholds { static let autoLink = 0.9; static let runnerUpMax = 0.5; static let maxDayDistance = 3 }`, `enum GradeMatcher { static func candidates(for r: VotoRemoto, appSubject: String, among manual: [Grade], calendar: Calendar) -> [MatchCandidate]; static func isCertain(_ c: [MatchCandidate]) -> Bool }`
- Regole (spec §5): materia e valore obbligatori (tolleranza 0,01; remoto non numerico → `displayValue` uguale); data stesso giorno 1,0, ±1 0,7, ±2–3 0,4, oltre → escluso; tipo uguale +0,2, diverso noto −0,3; docente uguale +0,1; ordinamento decrescente; solo voti con `origin == nil`.

- [ ] **Step 1: Test**: `testSameDaySameValueIsCertain`; `testDifferentValueIsNeverACandidate`; `testDifferentSubjectIsNeverACandidate`; `testFourDaysApartIsExcluded`; `testTwoSameDayCandidatesAreNotCertain`; `testOneDayApartWithSameTypeIsCertain` (0,9); `testOneDayApartWithoutTypeIsNotCertain` (0,7); `testAlreadyLinkedGradeIsIgnored`.
- [ ] **Step 2–4:** FAIL → implementa → PASS.
- [ ] **Step 5: Commit** `feat(registro): punteggio di corrispondenza fra voti`.

### Task 8: Motore di sync (piano puro)

**Files:**
- Create: `FMT II/Registro/Engine/RegistroSyncEngine.swift`, `FMT II/Registro/Engine/SyncPlan.swift`
- Test: `FMT IITests/RegistroSyncEngineTests.swift`

**Interfaces:**
- Consumes: Task 3–7.
- Produces:
  - `enum ConflictDecision: Codable, Equatable { case linkTo(UUID), importAsNew, later }`
  - `struct PendingConflict: Codable, Identifiable, Equatable { id: String /* remoteKey */; remote: VotoRemoto; candidateIDs: [UUID] }`
  - `struct RegistroSyncInput { local: [Grade]; fetch: RemoteFetch; provider: RegistroProviderID; accountKey: String; mapping: SubjectMappingTable; ignored: Set<String>; decisions: [String: ConflictDecision]; maxGrade: Double; calendar: Calendar }`
  - `struct SyncPlan: Equatable { var inserts: [Grade]; var updates: [Grade]; var links: [Grade]; var conflicts: [PendingConflict]; var pendingSubjects: [RemoteSubjectRef]; var newGradeIDs: [UUID]; var removalCheckSkipped: Bool; var isEmpty: Bool }` (`updates` include i voti segnati/ripristinati come rimossi)
  - `enum RegistroSyncEngine { static func plan(_ input: RegistroSyncInput) -> SyncPlan }`
- Regole (spec §1, §2, §5): voto remoto `cancelled` o in `ignored` → saltato (se già collegato: nessuna modifica); materia non confermata → `pendingSubjects`, voto non importato; voto già presente (stessa `remoteKey` o id deterministico) → aggiornato solo se il fingerprint è cambiato o lo stato era "rimosso", e solo nei campi non modificati dall'utente (`applied.editedFields`), aggiornando `applied` e `fingerprint`; nuovi voti con id `RegistroIdentity.gradeID`; collegamento automatico mantiene l'id manuale e salva `manualSnapshot`; decisione `linkTo`/`importAsNew`/`later` rispettata; rimozioni solo per voti collegati con data dentro `coveredRange` (nil → nessun controllo); salta il controllo e imposta `removalCheckSkipped` se i remoti nel range sono 0 con collegati > 0, o meno della metà dei collegati attivi nel range; valori: `value` = numerico o, se nil, quello già presente (o 0 per i nuovi) con `countsForAverage = false`; `notCounting` → `countsForAverage = false`; `weight` = 1,0 salvo conversione certa decisa dal provider (`VotoRemoto.weight` già in scala 0…1); `teacher` = remoto ?? ""; `date` = data remota; `type` da `kind` (`other`/nil → resta il default `.oral` per i nuovi, invariato per gli esistenti); `note` mai toccata; se il mapping di una materia cambia, i voti importati/collegati con `subject` non modificato dall'utente passano alla nuova materia (anche a fingerprint invariato).

- [ ] **Step 1: Test**
  - `testFirstImportCreatesDeterministicGrades`
  - `testSecondIdenticalSyncIsEmpty` (idempotenza: applica il piano, ricalcola → `isEmpty`)
  - `testRemoteChangeUpdatesUneditedFields`
  - `testUserEditedFieldIsNotOverwritten` (Review Focus 2)
  - `testCertainMatchLinksManualKeepingIDAndNote`
  - `testAmbiguousMatchBecomesConflict`
  - `testDecisionImportAsNewAndLinkTo`
  - `testLaterDecisionKeepsConflictPendingWithoutImport`
  - `testUnconfirmedSubjectIsPending`
  - `testIgnoredRemoteIsNeverImported`
  - `testMissingRemoteIsMarkedRemovedNeverDeleted`
  - `testRemovedGradeReappearingIsReactivated`
  - `testEmptyFetchSkipsRemovalCheck` e `testFewerThanHalfSkipsRemovalCheck`
  - `testLastYearGradesAreOutsideCoveredRange`
  - `testNonNumericRemoteDoesNotCountForAverage`
  - `testMissingTimeTeacherWeightStayEmpty` (`hasTime == false`, `teacher == ""`, `origin.remoteWeight == nil`, `weight == 1`)
  - `testMappingChangeMovesUneditedImportedGrades` (e lascia quelli con materia modificata dall'utente)
  - `testOneManualGradeLinksToOneRemoteOnly` (due remoti identici, un manuale → 1 link + 1 conflitto o nuovo, mai due link)
- [ ] **Step 2–4:** FAIL → implementa → PASS (classe + suite).
- [ ] **Step 5: Commit** `feat(registro): motore di sincronizzazione dei voti`.

### Task 9: Validazione, applicazione, coordinatore, scollega

**Files:**
- Create: `FMT II/Registro/Engine/SyncPlanValidator.swift`, `FMT II/Registro/Engine/RegistroDedupe.swift`, `FMT II/Registro/Engine/RegistroUnlink.swift`, `FMT II/Registro/RegistroSyncCoordinator.swift`
- Modify: `FMT II/Models/GradeModel.swift` (`applyRegistroPlan`, dedupe in `applyRemote`, voti con `origin` eliminati → `ignore`), `FMT II/Services/AppStores.swift` (coordinatore condiviso)
- Test: `FMT IITests/RegistroCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 1–8.
- Produces:
  - `enum PlanValidation: Equatable { case ok, needsConfirmation(manualTouched: Int), rejected(String) }`, `enum SyncPlanValidator { static func validate(_ p: SyncPlan, local: [Grade]) -> PlanValidation }` (rifiuta se un link cambia il valore di un voto manuale o se un id del piano non esiste dove dovrebbe; conferma se > 20 voti manuali toccati)
  - `enum RegistroDedupe { static func resolve(_ grades: [Grade]) -> (grades: [Grade], dropped: [Grade]) }` (stessa `remoteKey`: tiene il manuale collegato, poi quello con campi modificati, poi il più recente; unisce le note distinte con "\n")
  - `enum RegistroUnlink { static func apply(_ grades: [Grade], keepImported: Bool) -> (grades: [Grade], removedIDs: Set<UUID>) }` (spec §6.5: collegati → `origin` rimosso, campi non modificati tornano a `manualSnapshot`; importati non modificati eliminati solo se `keepImported == false`; importati modificati tenuti senza `origin`)
  - `GradesStore.applyRegistroPlan(_ p: SyncPlan)`: una sola `save`, `modifiedAt` aggiornato solo per voti cambiati, `enqueueSave` solo per quelli
  - `enum RegistroStatus: Equatable { case disconnected, idle, syncing, needsLogin, needsConfirmation(Int), error(String) }`, `enum SyncTrigger { case manual, appOpen, background }`
  - `@MainActor final class RegistroSyncCoordinator: ObservableObject { @Published status; @Published lastSync: Date?; @Published pendingConflicts: [PendingConflict]; @Published pendingSubjects: [RemoteSubjectRef]; var connectedProvider: RegistroProviderID?; init(grades: GradesStore, backups: GradeBackups, settings: RegistroSettingsStore, keychain: KeychainStore, providers: [RegistroProvider], defaults: UserDefaults, now: @escaping () -> Date = Date.init); func connect(_ id: RegistroProviderID, credentials: RegistroCredentials) async throws -> [(RemoteSubjectRef, SubjectProposal)]; func confirmMapping(_ table: SubjectMappingTable) async; func syncNow(_ trigger: SyncTrigger) async -> SyncPlan?; func confirmPendingPlan() async; func resolve(_ conflictID: String, _ decision: ConflictDecision) async; func unlink(keepImported: Bool) async }`
  - Flusso `syncNow`: throttle (`appOpen` < 15 min dall'ultimo tentativo → nulla); credenziali dal Keychain (assenti → `needsLogin`); sessione salvata → `refresh` su `sessionExpired` → nuovo `login`; `invalidCredentials` → `needsLogin` e nessun nuovo tentativo automatico; fetch → plan → validate; piano non vuoto → istantanea `.preSync` (o `.preLink` alla prima) → `applyRegistroPlan`; qualsiasi errore → nessuna scrittura, `status = .error`.
  - Chiavi UserDefaults locali: `registroProvider`, `registroAccountKey`, `registroLastSync`, `registroLastAttempt`, `registroPendingConflicts`, `registroDecisions`; Keychain: `credentials`, `session`.

- [ ] **Step 1: Test** (provider finto in memoria, directory e defaults temporanei)
  - `testFirstSyncTakesPreLinkSnapshotThenImports`
  - `testProviderFailureWritesNothing` (Review Focus 3: fetch lancia `.network` → `grades` e istantanee invariati, `status == .error`)
  - `testInvalidCredentialsStopsAutomaticRetries` (dopo `.invalidCredentials`, `syncNow(.appOpen)` non chiama il provider)
  - `testMissingCredentialsNeedsLogin` (Review Focus 4)
  - `testAppOpenThrottleFifteenMinutes`
  - `testExpiredSessionRefreshesThenRelogins`
  - `testPlanTouchingMoreThanTwentyManualGradesNeedsConfirmation`
  - `testValidatorRejectsLinkChangingValue`
  - `testDuplicateRemoteKeysCollapseKeepingLinkedManual` (Review Focus 1, via `applyRemote`)
  - `testDeletingImportedGradeIgnoresIt` (anche `deleteAll` e `replaceAll`)
  - `testUnlinkKeepImported` e `testUnlinkDeleteImportedKeepsEditedAndManual` (istantanea `.preUnlink`, `ignored` svuotato, credenziali rimosse dal Keychain)
  - `testNoWritesWhenPlanIsEmpty` (`modifiedAt` di tutti i voti invariato)
- [ ] **Step 2–4:** FAIL → implementa → PASS (classe + suite).
- [ ] **Step 5: Commit** `feat(registro): coordinatore di sync con protezioni sui dati`.

### Task 10: Ricerca e documentazione ClasseViva e Argo

**Files:**
- Create: `docs/registri/ClasseViva.md`, `docs/registri/Argo.md`, `docs/registri/README.md` (rischi: ToS, rate limit, blocchi, App Store 5.2.2; fonti), fixture `FMT IITests/Fixtures/Registri/classeviva-login.json`, `classeviva-grades.json`, `argo-*.json` (nomi secondo i passi del login documentato)

Contenuto obbligatorio per provider: URL base, flusso di login passo per passo (richieste, header, corpo, risposta), come si ottiene `accountKey`, durata e rinnovo della sessione, endpoint voti e materie, esempio di risposta anonimizzato, tabella campo-remoto → campo `VotoRemoto` (inclusi data/ora, tipo, peso e sua scala, periodo, commento, annullato/non fa media), formati di data e fuso, errori noti (credenziali errate, sessione scaduta, blocchi), fonti con link e commit/versione dei progetti open source consultati (almeno due indipendenti per i dettagli critici), elenco **TODO** dei punti non verificabili.

- [ ] **Step 1:** Studia i client open source (ClasseViva: es. `GoldenMelky/classeviva_endpoints`, `Classeviva.py`; Argo: client recenti del nuovo login didUP/famiglia) e scrivi i documenti con fonti.
- [ ] **Step 2:** Crea le fixture dai formati documentati, con dati inventati ma struttura identica (nessun dato reale di persone).
- [ ] **Step 3: Verifica**: ogni campo usato nelle fixture compare nel documento con la sua fonte; `grep -n "TODO" docs/registri/*.md` elenca i punti aperti.
- [ ] **Step 4: Gate**: se il login di un provider o la scala del peso non sono verificabili da fonti, fermati e chiedi all'utente (non implementare quel provider a indovinare).
- [ ] **Step 5: Commit** `docs(registro): protocolli ClasseViva e Argo con fonti`.

### Task 11: Provider ClasseViva

**Files:**
- Create: `FMT II/Registro/Providers/ClasseViva/ClasseVivaProvider.swift` (+ eventuale `ClasseVivaDTO.swift`)
- Test: `FMT IITests/ClasseVivaProviderTests.swift`

**Interfaces:**
- Consumes: `RegistroProvider`, `HTTPTransport`, `GradeValueNormalizer`, `docs/registri/ClasseViva.md`.
- Produces: `struct ClasseVivaProvider: RegistroProvider { init(transport: HTTPTransport) }` con endpoint, header e campi **esattamente** come nel documento.

- [ ] **Step 1: Test** (MockTransport + fixture): `testLoginSendsDocumentedRequestAndParsesSession` (metodo, URL, header e corpo come da documento; `accountKey` atteso); `testWrongPasswordMapsToInvalidCredentials`; `testUnauthorizedMapsToSessionExpired`; `testGradesMapToVotoRemoto` (ogni campo della tabella del documento, incluso `notCounting`/`cancelled`); `testDateOnlyIsRomeMidnight` (Review Focus 5); `testUnparseableGradeIsSkippedAndCounted` (`skippedCount == 1`, gli altri presenti); `testCoveredRangeIsCurrentSchoolYear` (secondo quanto documentato; se il registro non lo indica: dal 1° settembre di `schoolYearStartYear` al 31 agosto successivo); `testCredentialsNeverAppearInRequestURL`.
- [ ] **Step 2–4:** FAIL → implementa → PASS (classe + suite).
- [ ] **Step 5: Commit** `feat(registro): provider ClasseViva`.

### Task 12: Provider Argo

**Files:**
- Create: `FMT II/Registro/Providers/Argo/ArgoProvider.swift` (+ DTO)
- Test: `FMT IITests/ArgoProviderTests.swift`

**Interfaces:**
- Consumes: come Task 11, con `docs/registri/Argo.md`; `loginFields` include `.schoolCode`.
- Produces: `struct ArgoProvider: RegistroProvider { init(transport: HTTPTransport) }`.

- [ ] **Step 1: Test**: stessi casi del Task 11 adattati al flusso Argo documentato (incluso ogni passo intermedio del login), più `testSchoolCodeIsRequired` (`schoolCode == nil` → `.invalidCredentials` senza richieste di rete).
- [ ] **Step 2–4:** FAIL → implementa → PASS (classe + suite).
- [ ] **Step 5: Commit** `feat(registro): provider Argo`.

### Task 13: Impostazioni → Collega registro

**Files:**
- Create: `FMT II/Registro/UI/RegistroSettingsView.swift`, `RegistroConnectFlow.swift` (scelta provider → disclaimer → login → mapping → primo import), `SubjectMappingView.swift`, `RegistroConflictView.swift`, `GradeSnapshotsView.swift`
- Modify: `FMT II/Views/SettingsView.swift` (riga "Registro elettronico" nella sezione dati, stile `Self.row`)
- Test: `FMT IIUITests/RegistroSettingsUITests.swift` (provider finto attivato da argomento di lancio `-FMTFakeRegistro`, solo in DEBUG)

Contenuti (spec §8): stub mostrati "Presto disponibile" e non selezionabili; disclaimer da accettare prima del login (non ufficiale, non affiliato a Spaggiari/Argo, può smettere di funzionare, dati solo sul dispositivo, password salvata nel Portachiavi per i rinnovi); stato, ultima sync, numero voti importati, voti non letti (`skippedCount`) e avviso se il controllo "rimossi" è stato saltato, "Sincronizza ora", conflitti in attesa ("È questo il voto che hai già inserito?" con "Sì, è questo" / "No, è un voto diverso" / "Decidi dopo"), mapping materie modificabile, toggle notifiche voti nuovi (spento), "Ripristina voti" (elenco istantanee con data e numero voti, conferma), "Scollega" con scelta "Tenere i voti importati" / "Eliminare i voti importati"; conferma per piani > 20 voti manuali.

- [ ] **Step 1: Test UI**: `testConnectFlowRequiresDisclaimer`; `testFirstImportWaitsForMappingConfirmation`; `testConflictSheetLinksChosenGrade`; `testUnlinkOffersKeepOrDelete`; `testRestoreListsSnapshots`.
- [ ] **Step 2–4:** FAIL → implementa → PASS.
- [ ] **Step 5: Commit** `feat(registro): impostazioni Collega registro`.

### Task 14: Tab Voti

**Files:**
- Modify: `FMT II/Views/GradesView.swift` (`GradeRowView`, `GradeHomeRow`, `RecentGradesRow`, `GradeEntrySheet` in modifica, grafico)
- Test: `FMT IITests/RegistroGradeDisplayTests.swift`, screenshot in `FMT IIUITests/RegistroSettingsUITests.swift`

Badge discreto (SF Symbol `building.columns.fill`, `.caption2`, `.secondary`) sui voti con `origin`; "Rimosso dal registro" (etichetta + testo barrato) se `status == .removedFromRegistro`, con azioni "Elimina" / "Tieni"; nel dettaglio sezione "Dal registro" in sola lettura: valore originale, ora solo se `hasTime`, periodo, commento, docente del registro; voti non numerici esclusi dal grafico.

- [ ] **Step 1: Test**: `testNonNumericGradesAreExcludedFromChartPoints`; `testRemovedStatusLabel`; `testTimeShownOnlyWhenProvided` (funzioni di formattazione estratte e testabili).
- [ ] **Step 2–4:** FAIL → implementa → PASS; screenshot iPhone e iPad.
- [ ] **Step 5: Commit** `feat(registro): badge e dettagli dei voti dal registro`.

### Task 15: Quando si sincronizza + notifiche

**Files:**
- Create: `FMT II/Registro/RegistroBackgroundRefresh.swift`
- Modify: `FMT II/FMT_IIApp.swift` (registrazione task, `scenePhase == .active` → `syncNow(.appOpen)`), `FMT-II-Info.plist` (`BGTaskSchedulerPermittedIdentifiers` = `com.davide.fmtII.registroRefresh`; `UIBackgroundModes` + `fetch`), `FMT II/Services/NotificationManager.swift` (`notifyNewGrades(_ grades: [Grade])`)
- Test: `FMT IITests/RegistroSchedulingTests.swift`

**Interfaces:**
- Produces: `enum RegistroBackgroundRefresh { static let identifier = "com.davide.fmtII.registroRefresh"; static func register(); static func schedule(now: Date = .now) -> BGAppRefreshTaskRequest? }` (nil se nessun registro collegato; `earliestBeginDate` = now + 2 h); notifiche solo se toggle attivo, solo per `newGradeIDs` e mai al primo import.

- [ ] **Step 1: Test**: `testNoScheduleWhenDisconnected`; `testScheduleEarliestTwoHours`; `testNoNotificationOnFirstImport`; `testNotificationOnlyWhenToggleOn`; `testInfoPlistDeclaresIdentifier` (legge il bundle).
- [ ] **Step 2–4:** FAIL → implementa → PASS (classe + suite).
- [ ] **Step 5: Commit** `feat(registro): sync all'apertura, in background e notifiche`.

### Task 16: Traduzioni, versione e verifica finale

**Files:**
- Modify: `FMT II/Localizable.xcstrings` (inglese per ogni testo nuovo), `FMT II.xcodeproj/project.pbxproj` (`MARKETING_VERSION = 2.3.0`, `CURRENT_PROJECT_VERSION = 1` per l'app), `FMT II/PrivacyInfo.xcprivacy` se cambia l'uso di API dichiarate
- Create: `docs/registri/RELEASE-NOTES.md` (testo per informativa privacy e note per la revisione Apple, in italiano e inglese)

- [ ] **Step 1:** Suite completa unit + `RegistroSettingsUITests` + `RotationPagerUITests` → tutto verde, nessuna stringa senza inglese.
- [ ] **Step 2:** `grep -rn "print(\|NSLog\|os_log" "FMT II/Registro"` → nessun log di richieste, risposte o credenziali in Release.
- [ ] **Step 3:** Archivio Release riuscito (`xcodebuild archive … -allowProvisioningUpdates`), senza caricarlo.
- [ ] **Step 4: Commit** `chore(registro): traduzioni e versione 2.3.0`.
- [ ] **Step 5:** Fase 7 della spec (prova con account reale) e caricamento su App Store Connect: solo con l'utente.
