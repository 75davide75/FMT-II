# FMT 2.3 — Voti dal registro elettronico — design

Data: 2026-11-15. Stato App Store: **2.2.0 pubblicata il 2026-10-11** (quindi
dispositivi in 2.2 e 2.3 convivranno sullo stesso iCloud). Fonte: richiesta utente (prompt "Sincronizzazione dei voti dai
registri elettronici italiani") + risposte in brainstorming. Base: branch
`feature/registro-sync`, nato da `feature/icloud-sync-v2.2` (PR #2 non ancora
unita a `main`).

## Perché

Lo studente oggi copia a mano nella tab Voti i voti che trova sul registro.
Vuole che arrivino da soli, completi di tutti i dettagli che il registro
fornisce, senza perdere né duplicare quelli già inseriti a mano.

## Priorità assoluta (decisione utente)

**Non perdere mai un dato già inserito dall'utente, anche se qualcosa si
rompe.** Se il collegamento al registro fallisce, cambia formato, viene
bloccato o ha un bug, l'app deve continuare a funzionare come oggi e i voti
esistenti devono restare intatti. Sul dispositivo si tiene sempre un backup dei
voti inseriti a mano. Ogni scelta qui sotto cede a questa regola.

## Obiettivi

1. Collegare un registro (fase 1: **ClasseViva** e **Argo DidUP**) da
   Impostazioni con utente e password.
2. Importare i voti già presenti e quelli nuovi nella tab Voti, con data, ora
   (se c'è), materia, docente, voto originale, voto numerico, tipo, peso,
   periodo, commento, "non fa media"/annullato.
3. Nessun duplicato dei voti già inseriti a mano: collegamento automatico solo
   se certo, altrimenti domanda all'utente.
4. Sync manuale, all'apertura (con limite di frequenza) e in background;
   notifica locale facoltativa per i voti nuovi.
5. Struttura pronta per Axios, Nuvola, Mastercom, Pronote (solo stub).

## Non-obiettivi

- Nessun backend: tutto avviene sul dispositivo, nessun dato inviato a terzi
  oltre al registro stesso.
- Niente GRDB/SQLite (l'app non lo usa: vedi Approcci).
- Niente SPID/CIE nella fase 1 (vedi Sicurezza).
- Niente scrittura verso il registro: solo lettura.
- Nessun altro dato del registro (assenze, compiti, agenda) in questa fase.

## Anti-obiettivi (fallimento anche se "funziona")

- Un voto inserito a mano sparisce, cambia valore senza conferma o viene
  sovrascritto dopo che l'utente l'ha modificato.
- La sync crea duplicati (anche fra iPhone e iPad via iCloud).
- Un errore del registro rende la tab Voti vuota o l'app inutilizzabile.
- Credenziali in chiaro in file, UserDefaults, iCloud o log.
- Dati inventati: ora, peso o docente mostrati come "dal registro" quando il
  registro non li fornisce.

## Vincoli

- iOS 17+, SwiftUI, Swift 5, progetto Xcode con gruppi sincronizzati.
- Voti salvati oggi in `Documents/fmt_grades.json` (`GradesStore`, array di
  `Grade` Codable) e sincronizzati con CloudKit (`CloudSyncManager`, record
  `grade-<UUID>` con payload JSON; i campi sconosciuti a versioni vecchie
  vengono già preservati da `SyncMerge.mergePayload`).
- App localizzata it/en (`L()`, `Localizable.xcstrings`): ogni testo nuovo
  ha la traduzione inglese.
- Stile Aurora Glass esistente (Theme.swift, righe/sezioni di SettingsView).
- Nessuno dei registri ha API pubbliche ufficiali. **Nessun endpoint o campo
  inventato**: ogni dettaglio deve venire da client open source verificabili e
  stare documentato in `Docs/Registri/<provider>.md` con le fonti; ciò che non
  è verificabile resta TODO e va chiesto all'utente.
- App Store: funzione facoltativa, spenta di default, con disclaimer
  "collegamento non ufficiale". L'utente accetta il rischio di rifiuto.

## Approcci considerati

- **A. Estendere il `Grade` esistente con una parte facoltativa "dal
  registro" (scelto dall'utente).** Medie, grafici, tab Voti e sync iCloud
  restano quelli di oggi; la logica di confronto/unione vive in un modulo
  separato e testabile.
- B. Archivio separato per i voti del registro, unito in visualizzazione.
  Scartato: medie, grafici, ~1.500 righe di GradesView e sync iCloud
  dovrebbero gestire due fonti.
- C. Migrare a GRDB come nel prompt originale. Scartato: riscrittura di
  salvataggio e sync iCloud non giustificata da questa funzione.

## Design

### 1. Modello dati

`Grade` riceve un campo facoltativo `origin: RegistroOrigin?` (nil = voto
manuale, come oggi). Decodifica retrocompatibile: i file e i record iCloud
esistenti senza `origin` si leggono identici.

`RegistroOrigin` contiene:
- `provider` (enum: classeviva, argo, axios, nuvola, mastercom, pronote),
  `accountKey` (identificativo stabile dell'account sul registro, non la
  password), `remoteId` (id stabile del voto sul registro);
- `rawValue` (stringa originale, es. "7½", "6/7", "N.C.", "buono"),
  `numericValue: Double?` (nil se non numerico);
- `hasTime: Bool` (false se il registro dà solo la data), `remoteSubjectId`,
  `remoteSubjectName`, `remoteTeacher: String?`, `remoteType` (stringa grezza
  + tipo normalizzato), `remoteWeight: Double?`, `remotePeriod: String?`,
  `remoteComment: String?`, `cancelled/notCounting: Bool`,
  `remoteModifiedAt: Date?`;
- `fingerprint` (hash dei campi remoti all'ultima sync, per capire se il
  registro ha cambiato qualcosa);
- `appliedValues`: i valori che l'ultima sync ha scritto nei campi del
  `Grade`. Un campo che oggi è diverso da `appliedValues` è stato modificato
  dall'utente (su qualunque versione dell'app, anche la 2.2 che non conosce
  questa logica) e la sync non lo tocca più;
- `manualSnapshot: Grade?` (copia del voto manuale com'era prima del
  collegamento, per poterlo ripristinare esattamente);
- `status`: attivo / rimosso dal registro.

`Grade` resta la fonte per medie e UI: la sync scrive nei campi normali
(`subject`, `teacher`, `value`, `date`, `type`, `weight`, `countsForAverage`)
i valori del registro, **solo dove il registro li fornisce**:
- docente assente → `teacher` resta "" (non inventato);
- peso assente → `weight` resta 1.0 come per i voti manuali (serve per la
  media), ma `remoteWeight = nil` e la UI non mostra "peso dal registro";
- ora assente → data a mezzanotte locale con `hasTime = false`, la UI mostra
  solo la data;
- voto non numerico (giudizio non convertibile, N.C.) → `countsForAverage =
  false`, escluso da medie e grafico, mostrato con `rawValue`.

`note` resta sempre dell'utente; il commento del registro va in
`remoteComment` e si mostra separato.

Tipo: **nessun nuovo caso** in `GradeType` (la 2.2, già sull'App Store dal
2026-10-11, non saprebbe decodificarlo e nasconderebbe quei voti). I tipi del
registro non riconducibili a scritto/orale/pratico tengono il tipo grezzo in
`remoteType`; la 2.3 li mostra come "Altro", nel `Grade` il tipo resta quello
di default. *Mia scelta:* meglio un'etichetta imprecisa sui dispositivi
ancora in 2.2 che voti invisibili.

**Peso**: se il registro fornisce un peso, lo si converte nella scala 0…1
dell'app solo se il significato è certo dalla documentazione (es. percentuale
100 → 1,0); se il formato è diverso (pesi relativi > 1) si conserva in
`remoteWeight`, il `weight` resta 1,0 e lo si segnala come TODO da decidere
con l'utente dopo la fase di ricerca. *Mia scelta.*

### 2. Identità e iCloud

- L'id di un voto importato è **deterministico**: UUID v5 da
  `provider|accountKey|remoteId`. iPhone e iPad che importano lo stesso voto
  producono lo stesso record iCloud → nessun duplicato.
- Collegare un voto manuale a uno remoto **mantiene il suo id**: si aggiunge
  `origin` al voto esistente. *Mia scelta*: ri-identificarlo creerebbe
  doppioni se un dispositivo ancora in 2.2, offline, rimandasse il record
  vecchio.
- Rete di sicurezza: se dopo una sync o un arrivo da iCloud esistono due voti
  con la stessa coppia `(provider, remoteId)` (es. due dispositivi hanno
  importato/collegato in contemporanea), se ne tiene uno solo: prima il voto
  manuale collegato, poi quello con modifiche dell'utente; la nota viene unita
  e l'altro finisce nell'istantanea prima della rimozione.
- La 2.2 conserva già i campi che non conosce (`SyncMerge.mergePayload`),
  quindi non perde `origin` modificando un voto importato.
- La sync iCloud esistente porta i voti importati sugli altri dispositivi:
  basta collegare il registro su uno solo.
- La sync non deve "toccare" `modifiedAt` se nulla è cambiato (idempotenza, e
  niente traffico iCloud inutile).

### 3. Architettura

```
Registro/
  Core/      RegistroProvider (protocollo), VotoRemoto, capabilities,
             errori, GradeValueNormalizer, SubjectMapping
  Engine/    RegistroSyncEngine (puro: piano di sync), GradeMatcher,
             SyncPlan + validazione, applicazione via GradesStore
  Providers/ ClasseViva/, Argo/  (completi)
             Axios/, Nuvola/, Mastercom/, Pronote/  (stub: tutti i metodi
             lanciano .notSupported, capabilities vuote)
  Storage/   KeychainStore, RegistroAccountStore, GradeSnapshots
  UI/        Collega registro (Impostazioni), conflitti, mapping materie
```

`RegistroProvider`: `login(credentials) -> Session`, `refresh(session)`,
`fetchGrades(session) -> [VotoRemoto]`, `fetchSubjects/Teachers` (se
disponibili), `logout(session)`, `capabilities` (forniscePeso, fornisceOra,
fornisceDocente, fornisceCommento, forniscePeriodo, …). Il trasporto HTTP è
iniettabile (mock nei test). Un provider non sa niente di `Grade`.

`VotoRemoto` è il modello normalizzato richiesto dal prompt (provider,
remoteId, data, ora opzionale, materia grezza + id, docente opzionale, valore
grezzo + numerico, tipo, peso opzionale, periodo, commento, annullato/non fa
media, ultima modifica remota).

`RegistroSyncEngine` è una funzione pura: (voti locali, voti remoti, mapping
materie, conflitti già risolti) → `SyncPlan` (inserimenti, aggiornamenti,
collegamenti certi, conflitti da chiedere, voti da segnare come rimossi,
materie nuove da mappare). Nessun I/O: è il cuore dei test.

### 4. Normalizzazione dei voti

`GradeValueNormalizer` converte la stringa originale in numero, conservando
sempre la stringa. Casi da testare almeno: `7`, `7+` (7.25), `7-` (6.75),
`7½` e `7 1/2` (7.5), `7.5`, `7,25`, `6/7` e `6-7` (6.5), `7--` (6.5),
`7++`, giudizi (ottimo, distinto, buono, discreto, sufficiente,
insufficiente, gravemente insufficiente, non classificato), vuoto, `N.C.`,
`NC`, `ass.`. *Mia scelta:* i valori numerici dei giudizi seguono una
tabella unica documentata in codice (es. ottimo 10, distinto 9, buono 8,
discreto 7, sufficiente 6, insufficiente 5, gravemente insufficiente 4);
se il registro fornisce già un valore numerico, vince quello del registro.
Valori fuori dalla scala dell'app (`maxGrade`) → non numerici.

### 5. Matching e deduplicazione

Ordine per ogni voto remoto:
1. Esiste già un voto con la stessa `(provider, remoteId)` (o l'id
   deterministico)? → aggiornamento, mai un nuovo voto.
2. Altrimenti si cercano candidati fra i voti **manuali non collegati**:
   - materia: la materia del registro mappata su quella dell'app deve
     coincidere (filtro obbligatorio);
   - valore: stesso numerico (tolleranza 0,01) o, se il remoto non è
     numerico, stesso `displayValue`/giustifica (filtro obbligatorio);
   - data: stesso giorno 1,0; ±1 giorno 0,7; ±2–3 giorni 0,4; oltre 3 giorni
     non è candidato;
   - tipo: uguale +0,2; diverso (entrambi noti) −0,3; ignoto 0;
   - docente uguale (se entrambi presenti) +0,1.
3. **Collegamento automatico** solo se c'è un unico candidato con punteggio
   ≥ 0,9 e il secondo migliore < 0,5, e quel voto manuale non è conteso da un
   altro remoto nella stessa sync. Ogni voto manuale può essere collegato a un
   solo remoto.
4. Candidati presenti ma nessun collegamento certo → **conflitto**: schermata
   "È questo il voto che hai già inserito?" con le scelte "Sì, è questo" (uno
   dei candidati), "No, è un voto diverso" (importa come nuovo), "Decidi dopo"
   (il remoto resta in attesa e non viene importato).
5. Nessun candidato → nuovo voto importato.

Le soglie sono costanti in un solo punto (taratura con dati reali).

Le risposte dell'utente ai conflitti vengono ricordate (un "No" non si
ripropone). Conflitti in attesa: salvati sul dispositivo; un badge nella tab
Voti e in Impostazioni li segnala.

**Primo collegamento**: dopo il primo download e **prima di importare
qualsiasi voto**, l'utente conferma il mapping delle materie (schermata con
proposte automatiche, modificabili). *Mia scelta*: i registri usano nomi
ministeriali ("LINGUA E LETTERATURA ITALIANA", "SCIENZE MOTORIE E SPORTIVE")
diversi da quelli scritti dagli studenti; senza conferma il filtro "stessa
materia" non troverebbe i voti manuali e reimporterebbe tutto come doppioni.
Le proposte usano: uguaglianza normalizzata, poi una piccola tabella di
alias comuni (es. italiano, matematica, inglese, scienze motorie ↔ ed. fisica,
religione) come **suggerimento** da confermare, mai applicata in silenzio.
Le materie del registro comparse dopo il primo collegamento vengono proposte
allo stesso modo; finché non sono confermate i loro voti restano in attesa.

**Mapping materie**: tabella `materia del registro (id + nome) → materia
dell'app`. Proposta automatica: uguaglianza senza maiuscole, accenti, spazi e
punteggiatura (es. "MATEMATICA" → "Matematica"); se non c'è corrispondenza si
crea la materia con il nome del registro in forma leggibile. L'utente può
cambiarla in Impostazioni; cambiare un mapping aggiorna la materia dei voti
importati non modificati dall'utente. Sincronizzata fra dispositivi con il
key-value store iCloud già usato da `SettingsSync`.

**Voti modificati sul registro**: fingerprint diverso → si aggiornano i
campi non presenti in `userEditedFields`.

**Voti spariti dal registro**: solo dopo un download **completo e riuscito**,
il voto viene segnato "rimosso dal registro" (badge), **mai cancellato
automaticamente**; l'utente può eliminarlo o tenerlo. Se il download restituisce
zero voti mentre ce n'erano di collegati, o meno della metà del previsto, il
passaggio "rimossi" viene saltato e segnalato (probabile errore del registro).

**Voti importati eliminati dall'utente**: restano eliminati. La coppia
`(provider, remoteId)` va in un elenco di "ignorati", sincronizzato fra i
dispositivi (key-value store iCloud), così nessuna sync li reimporta;
l'elenco si azzera scollegando il registro. Lo stesso vale per "Elimina tutti
i voti" e per il ripristino di un backup che non li contiene. Un voto manuale
collegato ed eliminato: il collegamento finisce negli ignorati, il voto è
comunque nel backup dei voti manuali. *Mia scelta.*

**Nuovo anno scolastico**: i voti degli anni passati restano nell'app (come
oggi per i voti manuali). Il controllo "rimossi dal registro" considera solo i
voti collegati con data nell'intervallo coperto dal download (l'anno
scolastico restituito dal registro): i voti dell'anno prima non vengono mai
segnati come rimossi né fanno scattare la protezione "pochi voti". Si
importano solo i voti che il registro restituisce (di norma l'anno in corso).
*Mia scelta.*

**Idempotenza**: due sync di fila con gli stessi dati remoti producono un
piano vuoto e nessuna scrittura.

### 6. Protezione dei dati (priorità assoluta)

1. **Salvataggio sicuro dei voti.** Oggi `GradesStore.load()`, se il file
   non si decodifica, parte da un array vuoto e il salvataggio successivo
   sovrascrive il file: va corretto prima di tutto.
   - scrittura atomica;
   - decodifica voto per voto: un voto illeggibile viene messo da parte, gli
     altri si caricano;
   - se il file esiste ma non si legge, viene copiato in
     `fmt_grades.unreadable-<data>.json` e non viene mai sovrascritto senza
     quella copia.
2. **Backup automatici sul dispositivo** (Application Support, esclusi da
   iCloud Drive):
   - `voti-manuali.json`: i voti inseriti a mano (senza `origin`, più i
     `manualSnapshot` dei collegati), aggiornato a ogni salvataggio dei voti;
   - una istantanea completa dei voti **prima del primo collegamento** (tenuta
     per sempre) e **prima di ogni sync che cambia qualcosa** (ultime 10).
   - Impostazioni → Collega registro → "Ripristina voti" elenca le istantanee
     con data e numero di voti; il ripristino chiede conferma e prima salva a
     sua volta un'istantanea dello stato attuale.
3. **Sync a due fasi.** Download e calcolo del piano non toccano nulla. Il
   piano viene validato prima di essere applicato in un'unica operazione:
   - nessuna cancellazione di voti, mai;
   - un collegamento automatico non può cambiare il valore di un voto
     manuale (il valore uguale è un requisito);
   - se il piano tocca più di 20 voti manuali in una volta → non si applica,
     si chiede conferma all'utente.
   Qualsiasi errore (rete, login, formato inatteso, decodifica) → nessuna
   scrittura, stato "errore" in Impostazioni, l'app funziona come prima.
4. **Isolamento.** Se nessun registro è collegato, il codice del registro non
   gira (né all'avvio né in background). La tab Voti non dipende dal
   registro. Formato inatteso dal registro → quel voto viene saltato e
   contato in "voti non letti", non blocca gli altri.
5. **Scollega**: chiede "Tenere i voti importati" (tornano voti normali senza
   collegamento) oppure "Eliminare i voti importati". Anche eliminando:
   istantanea prima; i voti manuali collegati tornano al loro
   `manualSnapshot` più le modifiche dell'utente, **mai eliminati**; i voti
   importati modificati dall'utente vengono tenuti (con avviso).

### 7. Sicurezza e privacy

- Credenziali e token solo nel Portachiavi, `ThisDeviceOnly` (non copiati su
  iCloud), accessibili dopo il primo sblocco (serve per il background). Mai in
  file, UserDefaults, iCloud o log; nessun `print` di richieste/risposte in
  Release.
- La password viene salvata per poter rifare il login quando la sessione
  scade (anche in background); lo si dice chiaramente al momento del login.
- Tutto on-device: l'app parla solo con i server del registro.
- SPID/CIE: non supportati nella fase 1 (gli studenti hanno credenziali del
  registro); da valutare in seguito con `ASWebAuthenticationSession`.
- Disclaimer al collegamento: collegamento non ufficiale, non affiliato a
  Spaggiari/Argo, può smettere di funzionare, i dati restano sul dispositivo.
  L'utente deve confermare prima del primo login.
- Informativa privacy dell'app (pagina di supporto) e note per la revisione
  Apple da aggiornare al rilascio.
- Rate limit: niente sync più frequenti di una ogni 15 minuti all'apertura;
  su errori di login, nessun nuovo tentativo automatico finché l'utente non
  interviene (evita blocchi dell'account).

### 8. Esperienza utente

- **Un solo account collegato alla volta** nella fase 1 (cambio scuola =
  scollega e ricollega); `accountKey` resta nel modello per il futuro. *Mia
  scelta.*
- **Impostazioni → "Collega registro"** (nuova sezione nello stile esistente):
  scelta del registro (gli stub appaiono come "presto disponibile"),
  disclaimer, login (campi richiesti dal provider, es. codice scuola per
  Argo), stato, ultima sync, voti importati, "Sincronizza ora", conflitti in
  attesa, mapping materie, notifiche voti nuovi, "Ripristina voti",
  "Scollega".
- **Quando si sincronizza**: "Sincronizza ora"; all'apertura dell'app (al più
  ogni 15 minuti); in background con `BGAppRefreshTask` (iOS decide quando;
  richiesta non prima di 2 ore).
- **Notifica locale facoltativa** (spenta di default) per i voti nuovi; mai
  per il primo import.
- **Tab Voti**: piccolo badge discreto sui voti dal registro (icona nel
  linguaggio grafico esistente); stato "rimosso dal registro" visibile;
  dettaglio del voto con valore originale, ora (se c'è), periodo e commento del
  registro. Modificare un voto importato è consentito e lo marca come
  modificato dall'utente.

### 9. Fasi (ognuna con commit e test propri)

1. Protezione dati: salvataggio sicuro, backup, istantanee, ripristino.
2. Modello (`origin`, `GradeType.other`), migrazione testata su un file con
   voti manuali reali, normalizzatore.
3. Engine: matching, piano, validazione, idempotenza, unione via iCloud.
4. Ricerca e documentazione: `Docs/Registri/ClasseViva.md`, `Argo.md`
   (endpoint, header, login, risposte, campi, fonti, TODO).
5. Provider ClasseViva e Argo con fixture JSON anonimizzate e trasporto
   simulato; stub degli altri.
6. UI: Collega registro, conflitti, mapping, badge, ripristino; sync
   all'apertura, background, notifiche; traduzioni.
7. Verifica end-to-end con un account reale (serve l'utente).

### 10. Test

- Unit: normalizzatore (tutti i formati sopra), punteggio e collegamento,
  conflitti, piano e validazione, idempotenza (due sync = nessuna modifica),
  voti modificati/rimossi, convergenza dell'id fra due dispositivi, scollega.
- Protezione dati: file illeggibile non sovrascritto, voto corrotto isolato,
  istantanee create e ripristinabili, errore di rete = nessuna scrittura.
- Migrazione: `fmt_grades.json` attuale con voti manuali → letto identico.
- Provider: fixture JSON realistiche anonimizzate (dai formati documentati)
  e client di rete simulato; login scaduto → refresh → nuovo login.

## Lasciato a chi costruisce

- Struttura interna dei file, nomi dei tipi oltre a quelli citati, dettagli
  di layout delle schermate nello stile esistente.
- Formato su disco di backup e conflitti (JSON nella cartella di supporto).
- Testi esatti dei messaggi, purché in italiano e inglese e con il
  disclaimer descritto.

## Da chiedere all'utente durante il lavoro

- Account reale ClasseViva e/o Argo per la verifica finale (fase 7).
- Ogni dettaglio di protocollo non verificabile da fonti open source.
