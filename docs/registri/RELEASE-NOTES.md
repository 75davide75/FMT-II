# FMT 2.3.0 — Note di rilascio / Release notes

Testi per App Store Connect e per la revisione Apple della funzione «Registro
elettronico». Usano solo fatti presenti in
[la spec](../superpowers/specs/2026-11-15-registro-sync-design.md) e nei
documenti di questa cartella. Dove solo il proprietario dell'app può decidere,
c'è scritto `TODO: ask the user`.

---

## (a) Novità / What's new (App Store Connect)

### Italiano

Novità della versione 2.3
• Voti dal registro elettronico (facoltativo, spento di default): in Impostazioni → Registro elettronico puoi collegare ClasseViva o Argo DidUP. I voti arrivano nella tab Voti insieme a quelli che inserisci tu, senza duplicati e senza mai cancellare i tuoi.
• Prima di ogni cambiamento FMT salva una copia dei voti sul dispositivo; da Impostazioni puoi ripristinarla.
• Aggiornamento all'apertura dell'app e in background, con notifica facoltativa per i voti nuovi.
• Nome utente e password restano nel Portachiavi del tuo dispositivo; FMT parla solo con il registro della tua scuola.
• FMT non è affiliato né approvato da Spaggiari (ClasseViva) o da Argo. Il collegamento non è ufficiale e può smettere di funzionare se il registro cambia.
• Piccoli miglioramenti e correzioni.

### English

What's new in 2.3
• Grades from your school register (optional, off by default): in Settings → School register you can connect ClasseViva or Argo DidUP. Register grades appear in the Grades tab next to the ones you enter yourself, without duplicates and without ever deleting yours.
• Before any change FMT saves a copy of your grades on the device; you can restore it from Settings.
• Updates when you open the app and in the background, with an optional notification for new grades.
• Your username and password stay in your device's Keychain; FMT only talks to your school's register.
• FMT is not affiliated with or endorsed by Spaggiari (ClasseViva) or Argo. The connection is unofficial and may stop working if the register changes.
• Minor improvements and fixes.

---

## (b) Privacy: indicazioni per l'etichetta e per l'informativa / Privacy label guidance

### Italiano

Fatti (spec §7, `docs/registri/README.md`, «Credenziali e privacy»):

- Nome utente e password del registro sono salvati **solo nel Portachiavi del
  dispositivo** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, non
  sincronizzabili). Mai in file, UserDefaults, iCloud o log. La password resta
  salvata solo per rifare il login quando la sessione scade, e viene
  cancellata quando l'utente scollega il registro.
- I dati vanno **direttamente dal dispositivo ai server del registro scelto
  dall'utente** (ClasseViva o Argo). Nessun backend dello sviluppatore, nessun
  server intermedio, nessuna terza parte, nessun tracciamento.
- La funzione è di sola lettura: FMT non scrive nulla sul registro.
- I voti importati vengono salvati come gli altri voti dell'app e, come quelli
  inseriti a mano, possono sincronizzarsi tra i dispositivi dell'utente
  tramite il suo iCloud (comportamento già presente nell'app dalla 2.2).
- Backup e istantanee dei voti restano sul dispositivo.
- Il manifest `PrivacyInfo.xcprivacy` non cambia: nessuna nuova API a motivo
  obbligatorio (vedi il report del task).

Indicazione per l'etichetta «Privacy dell'app» (da verificare nella
dichiarazione effettiva): lo sviluppatore non raccoglie né riceve i dati del
registro, perché non transitano da server dello sviluppatore.
`TODO: ask the user` — confermare come dichiarare il caso nell'etichetta di
App Store Connect e aggiornare la pagina dell'informativa privacy
(`AppStore/metadata/privacy-policy.md`, la spec §7 prevede l'aggiornamento al
rilascio).

### English

Facts (spec §7, `docs/registri/README.md`, "Credenziali e privacy"):

- The register username and password are stored **only in the on-device
  Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not
  synchronizable). Never in files, UserDefaults, iCloud or logs. The password
  is kept only to log in again when the session expires, and it is deleted
  when the user unlinks the register.
- Data goes **directly from the device to the school register servers chosen
  by the user** (ClasseViva or Argo). No developer backend, no intermediary
  server, no third parties, no tracking.
- The feature is read-only: FMT never writes anything to the register.
- Imported grades are stored like the app's other grades and, like manually
  entered ones, may sync between the user's own devices through their iCloud
  (existing app behaviour since 2.2).
- Grade backups and snapshots stay on the device.
- The `PrivacyInfo.xcprivacy` manifest is unchanged: no new required-reason
  API (see the task report).

Guidance for the App Privacy label (to check against the actual
questionnaire): the developer does not collect or receive the register data,
because it never passes through developer servers. `TODO: ask the user` —
confirm how to answer the App Store Connect questionnaire and update the
privacy policy page (`AppStore/metadata/privacy-policy.md`; spec §7 requires
updating it at release).

---

## (c) Note per la revisione Apple / App Review notes

### English (paste into App Store Connect "Notes")

Version 2.3 adds an optional, off-by-default feature: importing the student's
own grades from their school's electronic register (ClasseViva or Argo DidUP)
into the Grades tab. Settings → School register.

Demo account: the feature requires a real student account at the student's
school register, issued by the school. We are not able to provide a demo
account. The rest of the app does not depend on this feature and is fully
usable without it.

What can be reviewed without logging in:
- The settings screen: Settings → School register, with the provider list and
  the optional features that only appear after connecting.
- The disclaimer shown before the first login: the connection is unofficial,
  FMT is not affiliated with or endorsed by Spaggiari or Argo, it may stop
  working if the register changes, data stays on the device, and the user
  must accept it before any login.
- The other providers (Axios, Nuvola, Mastercom, Pronote) are stubs, shown
  greyed out and marked "Coming soon" (Italian: "Presto disponibile"); they
  cannot be selected.

How it works and privacy:
- Username and password are stored only in the device Keychain
  (this-device-only, not in iCloud) and are sent only to the register the user
  chose. There is no developer backend and no third party.
- The feature is read-only: nothing is written to the register.
- Safety: grades the user entered are never deleted by the sync; a backup is
  saved on the device before any change; on any register error nothing is
  written and the app keeps working as before.

Third-party service (guideline 5.2.2): neither Spaggiari nor Argo publishes a
public API or a public authorization for third-party apps; the app uses the
same access as the providers' own apps, with the user's own credentials, on
the user's device. `TODO: ask the user` — decide how to present this and
whether to request written authorization from the providers (TODO-R1, TODO-R2
in `docs/registri/README.md`) before submitting.

`TODO: ask the user` — decide whether to attach a demo video of the feature
working with a real account (to be recorded by the app owner with their own or
a consenting student's account).

### Italiano (promemoria interno)

- Nessun account demo: serve un account studente reale del registro della
  scuola.
- Visibile senza login: schermata Impostazioni → Registro elettronico, il
  disclaimer prima del login, i provider non ancora disponibili (Axios,
  Nuvola, Mastercom, Pronote), grigi e con la dicitura «Presto disponibile».
- `TODO: ask the user`: video dimostrativo, strategia per la linea guida
  5.2.2, dichiarazione dell'etichetta privacy.
- Prima del rilascio resta la verifica con un account reale (fase 7 della
  spec, TODO-R5): non eseguita in questo task.
