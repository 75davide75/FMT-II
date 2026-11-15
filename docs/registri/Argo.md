# Argo didUP Famiglia (Argo Software) — protocollo per FMT

Stato: **login e voti verificati** (≥ 2 fonti indipendenti). **Peso:
BLOCKED-ON-USER** (vedi § 8). Rischi generali in [README.md](README.md).

## 0. Quale API

| | API "app" `appfamiglia` (**raccomandata**) | API "web" `didattica…/famiglia/api` | Vecchia API ScuolaNext |
|---|---|---|---|
| Base | `https://www.portaleargo.it/appfamiglia/api/rest/` | `https://didattica.portaleargo.it/famiglia/api` | `https://www.portaleargo.it/famiglia/api/rest` |
| Login | OAuth2 + PKCE con il `client_id` dell'app didUP Famiglia | OAuth2 + PKCE con il `client_id` del portale web | header `x-key-app` statico |
| Fonti | AR-A, AR-B, AR-C, AR-D, AR-E, AR-F, AR-G, AR-H | AR-J soltanto | AR-K (2022) |
| Stato | usata da tutti i client attivi nel 2026 | una sola fonte | non più usata dai client attivi |

**Scelta: `appfamiglia`.** Le fonti appartengono a due "famiglie" di
codice indipendenti che concordano su tutto il login:
- famiglia DTrombett: AR-A (TypeScript, la libreria di riferimento) e i suoi
  porting AR-E (Swift), AR-F (Kotlin), probabilmente AR-G, AR-H, AR-D;
- famiglia argofamiglia: AR-B (Python, 2023) e il suo derivato AR-C (Python,
  dichiarato nel docstring di `api.py`).
AR-J (API web, analisi del traffico propria) conferma in modo indipendente la
stessa sequenza OAuth/SSO con un altro `client_id`.

## 1. URL e costanti

| Costante | Valore | Fonti |
|---|---|---|
| Server OAuth | `https://auth.portaleargo.it/oauth2/auth`, `https://auth.portaleargo.it/oauth2/token` | AR-A `src/util/generateLoginLink.ts`, `getToken.ts`; AR-B `argofamiglia/auth.py`; AR-C `api.py`; AR-D `argo_client.py`; AR-E `ArgoSupport.swift`; AR-F `ArgoConstants.kt`; AR-G `Argo.java` |
| Form SSO | `https://www.portaleargo.it/auth/sso/login` | AR-A `getCode.ts`, AR-B, AR-C, AR-D, AR-E, AR-F, AR-G |
| API | `https://www.portaleargo.it/appfamiglia/api/rest/` | AR-A `BaseClient.ts`, AR-B `CONSTANTS.py`, AR-C, AR-D, AR-E, AR-F |
| `client_id` | `72fd6dea-d0ab-4bb9-8eaa-3ac24c84886c` | AR-A `Constants.ts`, AR-B, AR-C, AR-D, AR-E, AR-F, AR-G, AR-H; AR-J lo indica come "Mobile App" |
| `redirect_uri` | `it.argosoft.didup.famiglia.new://login-callback` | AR-A, AR-B, AR-C, AR-D, AR-E, AR-F, AR-G, AR-H |
| `scope` | `openid offline profile user.roles argo` | AR-A, AR-B, AR-C, AR-D, AR-E, AR-F |
| `argo-client-version` | versione dell'app didUP Famiglia: `1.27.0` [AR-A, AR-F], `1.29.2` [AR-G, ripiego], `1.30.2` [AR-D, AR-E, AR-H] | vedi § 3.2 |

## 2. Login passo per passo

Serve un cookie jar per tutta la sequenza dei passi 1–2 [AR-A `getCode.ts`
(`CookieJar`), AR-E `applyCookies`, AR-G "cookies only on the 1st and 3rd
hop"]. Credenziali: **codice scuola**, nome utente, password
(`LoginField.schoolCode`, `.username`, `.password`).

### Passo 1 — avvio OAuth con PKCE

```
GET https://auth.portaleargo.it/oauth2/auth
    ?redirect_uri=it.argosoft.didup.famiglia.new%3A%2F%2Flogin-callback
    &client_id=72fd6dea-d0ab-4bb9-8eaa-3ac24c84886c
    &response_type=code
    &prompt=login
    &state=<casuale, 22 caratteri>
    &nonce=<casuale, 22 caratteri>
    &scope=openid%20offline%20profile%20user.roles%20argo
    &code_challenge=<base64url(SHA256(code_verifier)) senza "=">
    &code_challenge_method=S256
```

- `code_verifier`: stringa casuale di 43 caratteri alfanumerici [AR-A
  `generateLoginLink.ts`, AR-E `getCode()`]; AR-B e AR-C usano 128 caratteri
  esadecimali (anche questo è valido per PKCE).
- Risposta: `302` con `Location: …/auth/sso/login/?login_challenge=<hex>`; si
  estrae `login_challenge` [AR-A, AR-B (`login_challenge=([0-9a-f]+)`), AR-C,
  AR-D, AR-E, AR-G, AR-J].
- `state` deve avere almeno 8 caratteri, altrimenti `invalid_state` [AR-J,
  una sola fonte; con 22 caratteri il problema non si pone].

### Passo 2 — credenziali nel form SSO

```
POST https://www.portaleargo.it/auth/sso/login
Content-Type: application/x-www-form-urlencoded

challenge=<login_challenge>&client_id=72fd6dea-…&prefill=false
&famiglia_customer_code=<codice scuola>&username=<utente>&password=<password>
&remember_me=false&login=true
```

- Campi `challenge`, `client_id`, `famiglia_customer_code`, `username`,
  `password`, `login=true` in tutte le fonti [AR-A, AR-B, AR-C, AR-D, AR-E,
  AR-G, AR-J]. `prefill`: `false` [AR-E, AR-G, AR-H, AR-J] o `true` [AR-B,
  AR-C]; AR-A non lo invia. `remember_me=false` [AR-E, AR-J].
- `login=true` è obbligatorio: senza, il server lo tratta come "annulla"
  [AR-J, una sola fonte, coerente con tutte le altre che lo inviano].
- **Successo**: risposta con `Location`. Si seguono i redirect **senza**
  seguirli automaticamente, fino a un URL che inizia con
  `it.argosoft.didup.famiglia.new://login-callback?code=…`, e si estrae
  `code` [AR-A, AR-B (ciclo sui `Location`), AR-C, AR-D, AR-E, AR-G].
  Alcuni passi sono pagine di consenso [AR-E
  `completeConsentChainAndExtractCode`].
- **Pagina "Accesso completato"**: oggi Argo può rispondere `200` con una
  pagina HTML al posto del redirect; il passo successivo è l'`href` del link
  con l'attributo `data-auth-app-redirect` [AR-D `_link_continua`, AR-G
  `completedLoginRedirect`, AR-C `prossimo_da_html`].
- Il redirect finale verso lo schema `it.argosoft…://` non va "aperto":
  `URLSession` non lo segue; il provider deve fermarsi e leggere `code`
  dall'header `Location`.

### Passo 3 — scambio del codice

```
POST https://auth.portaleargo.it/oauth2/token
Content-Type: application/x-www-form-urlencoded

code=<code>&grant_type=authorization_code
&redirect_uri=it.argosoft.didup.famiglia.new%3A%2F%2Flogin-callback
&code_verifier=<code_verifier>&client_id=72fd6dea-…
```

Risposta 200 [AR-A `types/apiTypes.ts` `APIToken`, AR-E `TokenPartial`,
AR-I `utils/localStorage.json` (chiavi del token salvato), AR-J]:

```json
{
  "access_token": "<opaco>",
  "expires_in": 3599,
  "id_token": "<JWT>",
  "refresh_token": "<opaco>",
  "scope": "openid offline profile user.roles argo",
  "token_type": "bearer"
}
```

Errore: `{"error": "…", "error_description": "…"}` [AR-A `getToken.ts`,
AR-D, AR-E `TokenError`].

Scadenza: `expireDate` = header HTTP `Date` della risposta + `expires_in`
secondi [AR-A `getToken.ts`, AR-E `exchangeCodeForToken`]. Valori osservati:
`3600` [AR-J], `3599` [AR-I].

### Passo 4 — login applicativo

```
POST https://www.portaleargo.it/appfamiglia/api/rest/login
accept: application/json
content-type: application/json
authorization: Bearer <access_token>
argo-client-version: <versione didUP, § 3.2>
x-date-exp-auth: <expireDate, "YYYY-MM-DD HH:mm:ss.SSS">

{"lista-opzioni-notifiche":"{}","lista-x-auth-token":"[]","clientID":"<casuale, 163 caratteri>"}
```

- Corpo come sopra [AR-A `BaseClient.getLoginData`, AR-D `login()`, AR-E
  `fetchLoginData`, AR-G, AR-H]; AR-B e AR-C aggiungono
  `"x-auth-token-corrente": "null"` e usano un `clientID` più corto: entrambe
  le varianti risultano funzionanti.
- Risposta [AR-A `APILogin`, AR-I (chiavi), AR-J]:

```json
{
  "success": true,
  "msg": null,
  "data": [
    {
      "codMin": "<codice scuola>",
      "opzioni": [{"chiave": "VALUTAZIONI_GIORNALIERE", "valore": true}],
      "isPrimoAccesso": false,
      "profiloDisabilitato": false,
      "isResetPassword": false,
      "isSpid": false,
      "token": "<x-auth-token>",
      "username": "<utente>"
    }
  ],
  "total": 1
}
```

- Da qui: `token` → header `x-auth-token`, `codMin` → header `x-cod-min`
  [AR-A `apiRequest`, AR-D `_api`, AR-E `apiRequestRaw`, AR-J]. AR-C invia
  come `x-cod-min` il codice scuola digitato dall'utente.
- `data` può contenere **più profili** (es. genitore con più figli): AR-C li
  legge tutti, AR-A/AR-D/AR-E usano `data[0]`. TODO-AR1 (utente): con un
  account studente c'è sempre un solo elemento? Se sono più di uno, scegliere
  o rifiutare?

### Passo 5 — profilo

`GET appfamiglia/api/rest/profilo` (header del § 3) → `{"success", "msg",
"data"}` [AR-A `APIProfilo`, AR-I (stesse chiavi; `anno` =
`{"dataInizio":"2023-09-01","anno":"2023","dataFine":"2024-08-31"}`), AR-C
`_profilo`, AR-D `dashboard()`, AR-J (sottoinsieme)]. Campi di `data`:

| Campo | Uso in FMT |
|---|---|
| `anno.dataInizio`, `anno.anno`, `anno.dataFine` | `coveredRange` e data del download completo (§ 4) |
| `alunno.pk` | `accountKey` (§ 2.1) |
| `alunno.nome`, `alunno.cognome`, `alunno.nominativo`, `alunno.desEmail`, `alunno.maggiorenne`, `alunno.isUltimaClasse` | non usati (dati personali: non salvarli) |
| `scheda.pk`, `scheda.classe` (`pk`, `desDenominazione`, `desSezione`), `scheda.corso` (`descrizione`, `pk`), `scheda.sede` (`descrizione`, `pk`), `scheda.scuola` (`desOrdine`, `descrizione`, `pk`) | non usati |
| `profiloDisabilitato`, `isSpid`, `resetPassword`, `ultimoCambioPwd`, `primoAccesso`, `profiloStorico` | `profiloDisabilitato` → § 10; gli altri non usati |

AR-A elenca anche `genitore` (`desEMail`, `nominativo`, `pk`), omesso nella
fixture perché non serve.

### Passo 6 — dashboard (voti)

Vedi § 4.

### 2.1 Come si ottiene `accountKey`

Candidati documentati:
- `profilo.alunno.pk` (stringa) [AR-A `APIProfilo`, AR-I];
- `login.data[0].username` + `codMin` [AR-A `APILogin`, AR-J].

**Raccomandazione:** `accountKey = codMin + "|" + profilo.alunno.pk`. TODO-AR2
(utente/verifica): nessuna fonte dice se `alunno.pk` resta uguale da un anno
scolastico all'altro (`scheda.pk` invece è per anno, AR-J lo chiama
"SCHEDA_PK"); se cambiasse, gli UUID dei voti cambierebbero.

### 2.2 Errori del login

| Segnale | Significato | Fonti |
|---|---|---|
| Passo 2 senza header `Location` (pagina HTML) | credenziali errate → `invalidCredentials`, nessun nuovo tentativo automatico | AR-A (`ok(location, "Invalid login redirect")`), AR-B (`"Wrong credentials"`), AR-C (`DidupAuthError("credenziali rifiutate")`) |
| … con riquadro `alert` visibile, testo tipo "Username e/o password non validi" | conferma delle credenziali errate | AR-D `_errore_pagina` (**una sola fonte** per il testo) |
| HTTP 429 sulla pagina di login | troppi tentativi → `rateLimited` | AR-D (**una sola fonte**) |
| HTTP 403 | non documentato per Argo; per decisione del coordinatore → `rateLimited` (§ 3.4) | — |
| HTTP ≥ 500 | `network` (temporaneo) | AR-D |
| `login_challenge` assente al passo 1, `code` assente alla fine | `unexpectedFormat` | AR-A, AR-C, AR-E, AR-G |
| Passo 3 con `{"error", "error_description"}` | `unexpectedFormat` (o credenziali, se `invalid_grant`: TODO-AR3) | AR-A, AR-D, AR-E |
| Passo 4 con `success: false` | vedi § 3.3 | AR-A, AR-D |

## 3. Richieste API, sessione e rinnovo

### 3.1 Header di ogni richiesta `appfamiglia`

| Header | Valore | Fonti |
|---|---|---|
| `authorization` | `Bearer <access_token>` | AR-A, AR-B, AR-C, AR-D, AR-E, AR-J |
| `x-auth-token` | `token` del passo 4 | AR-A, AR-C, AR-D, AR-E, AR-J |
| `x-cod-min` | `codMin` del passo 4 | AR-A, AR-C, AR-D, AR-E, AR-J |
| `argo-client-version` | § 3.2 | AR-A, AR-D, AR-E, AR-F, AR-G, AR-H (assente in AR-B, AR-C) |
| `x-date-exp-auth` | scadenza dell'`access_token`, `YYYY-MM-DD HH:mm:ss.SSS` ora locale | AR-A, AR-D, AR-E, AR-F, AR-G, AR-H (assente in AR-B, AR-C) |
| `accept` / `content-type` | `application/json` | tutte |

Nessuno `User-Agent` particolare è richiesto: AR-A non lo imposta, AR-B/AR-C
usano uno UA di Chrome desktop, AR-E uno UA tipo
`didUPFamiglia/420 CFNetwork/… Darwin/…`. TODO-AR4: scegliere lo UA (vedi
TODO-R1 nel README).

### 3.2 `argo-client-version`

Argo rifiuta i client con una versione vecchia: risposta `success: false`
con `msg` che contiene "ultima versione" [AR-D `_api`, commento
"Argo rifiuta i client con una versione vecchia" — **una sola fonte per il
testo**]. AR-D e AR-G leggono la versione corrente dall'App Store
(`https://itunes.apple.com/lookup?bundleId=it.argosoft.didup.famiglia.new`,
campo `results[0].version`) e ripiegano su una costante. TODO-AR5 (utente):
FMT può fare questa richiesta all'App Store, oppure si tiene una costante
aggiornata a ogni release?

### 3.3 Durata, rinnovo, scadenza

- `access_token`: circa 1 ora (§ 2, passo 3). Il `token` del passo 4
  (`x-auth-token`) viene riusato dopo un rinnovo dell'`access_token` [AR-A
  `refreshToken`, AR-E].
- **Rinnovo raccomandato = nuovo login completo** (passi 1–4) quando
  `expireDate` è passato o manca meno di 2 minuti: è ciò che fanno AR-C (un
  login nuovo per ogni lettura) e AR-D (nessun refresh), di due famiglie
  diverse. Il nuovo login lo fa il coordinatore, non il provider (§ 3.4).
- Alternativa (solo famiglia DTrombett: AR-A `refreshToken`, AR-E, AR-F
  `RefreshProtocol.kt`): `POST appfamiglia/api/rest/auth/refresh-token` con
  corpo `r-token`, `client-id`, `scopes` (`"[openid, offline, …]"`),
  `old-bearer`, `primo-accesso: "false"`, `ripeti-login: "false"`,
  `exp-bearer`, `ts-app`, `proc: "initState_global_random_12345"`,
  `username`. Una sola famiglia di fonti → non usata nella fase 1.
- Errori applicativi: `{"success": false, "msg": "…"}` [AR-A `APIResponse`,
  AR-D, AR-E]. **Nessuna fonte documenta lo status HTTP o il messaggio di una
  sessione scaduta** (TODO-AR6). Per questo il provider controlla
  `expiresAt` **prima** di ogni chiamata (§ 3.4), così la scadenza non
  dipende da un segnale del server non documentato.
- Logout: AR-A chiama `rimuoviprofilo` (rimuove il dispositivo dal profilo).
  FMT non lo chiama: `logout(session)` = solo cancellazione dal Keychain
  (TODO-AR7: confermare).
- Chiamate extra dell'app ufficiale (`logtoken`, `dashboard/what`,
  `dashboard/aggiornadata`) [AR-A, AR-E]: non necessarie, AR-C e AR-D leggono
  i voti senza.

### 3.4 Regole per l'interfaccia `RegistroProvider`

Il nuovo tentativo **non** lo fa il provider (che in `refresh` non riceve le
credenziali): lo fa il coordinatore (`RegistroSyncCoordinator.download()`):
`fetchGrades` → se `.sessionExpired` → `refresh(session)` → se `refresh`
lancia un errore diverso da `.network` e `.rateLimited` →
`login(credenziali)` → `fetchGrades` **una sola volta**. Il provider quindi:

| Metodo / situazione | Comportamento |
|---|---|
| `login(credenziali)` | passi 1–5 del § 2; `token` = `access_token`; `expiresAt` = `Date` + `expires_in`; `extra` = `x-auth-token` e `codMin` del passo 4; `accountKey` § 2.1 |
| `refresh(session)` | nella fase 1 FMT non usa `auth/refresh-token` (una sola famiglia di fonti): lancia sempre `.sessionExpired`, così il coordinatore rifà `login` una volta |
| `fetchGrades(session)` con `expiresAt` passato o a meno di 2 minuti | lancia `.sessionExpired` **senza** chiamare il server |
| HTTP 401 su `profilo` o `dashboard/dashboard` | `.sessionExpired` (decisione del coordinatore; nessuna fonte Argo documenta il 401, TODO-AR6) |
| HTTP 403 (login o endpoint dati) | `.rateLimited`: "accesso bloccato o limitato: nessun nuovo tentativo automatico" |
| HTTP 429 | `.rateLimited` |
| `success: false` con "ultima versione" | `.notSupported` (§ 3.2) |
| `success: false` con altro `msg` | `.unexpectedFormat` |

Perché 403 → `.rateLimited` (decisione del coordinatore, round 1 della
revisione): nessuna fonte Argo documenta il 403, e per ClasseViva le fonti
gli danno significati diversi (credenziali errate, blocco IP, sezione
disattivata). Trattarlo come blocco ferma i tentativi automatici e non
insiste su un account che il server sta già rifiutando; il coordinatore non
rifà il login dopo `.rateLimited`.

## 4. Endpoint voti e materie

```
POST https://www.portaleargo.it/appfamiglia/api/rest/dashboard/dashboard
(header del § 3.1)

{"dataultimoaggiornamento":"2026-09-01 00:00:00.000","opzioni":"{\"VALUTAZIONI_GIORNALIERE\":true,…}"}
```

- **Download completo** = `dataultimoaggiornamento` all'inizio dell'anno
  scolastico, `profilo.anno.dataInizio` formattata `YYYY-MM-DD HH:mm:ss.SSS`
  [AR-A `getDashboard` (prima volta), AR-D `dashboard()`, AR-E
  `fetchDashboard`, AR-H `_get_dashboard`]; AR-G usa una data fissa
  `2000-01-01 00:00:00.000`. AR-C invia l'ora corrente: **fonte in
  disaccordo**, non seguita. FMT non usa la modalità incrementale (scarica
  sempre tutto: serve per `coveredRange`).
- `opzioni`: **stringa JSON** dell'oggetto `{chiave: valore}` costruito
  dalle `opzioni` del passo 4 [AR-A, AR-D, AR-E, AR-G, AR-H]; AR-B/AR-C usano
  una tabella fissa equivalente.
- Risposta: `{"success", "msg", "data": {"dati": [ { … } ]}}`; i dati sono in
  `data.dati[0]` [AR-A `APIDashboard`, AR-C, AR-D, AR-E, AR-J].
- Ogni voce di `voti` può avere `operazione`: `"I"` (o assente) = inserito o
  aggiornato, `"D"` = cancellato, con solo `pk` [AR-A `APIOperation`,
  `handleOperation.ts`; AR-F `Voto.kt` (commento)]. FMT **scarta in
  silenzio** le voci `"D"`, **senza contarle** in `skippedCount`: non sono
  voti illeggibili. Il voto cancellato semplicemente manca dal download, e il
  controllo protetto "rimossi dal registro" del piano può funzionare (il
  coordinatore azzera `coveredRange` quando `skippedCount > 0`, e mostra
  `skippedCount` all'utente come "voti non letti"). La sync non cancella mai
  voti in automatico (vincolo globale).
- Le voci con `codTipo` diverso da `"V"` (es. `"N"` = nota) **non sono
  voti**: FMT le scarta in silenzio, senza contarle in `skippedCount` (§ 7).
- `skippedCount` conta **solo** le voci di voto (`codTipo == "V"`, nessuna
  `operazione: "D"`) che non si riescono a leggere (campi obbligatori
  mancanti o malformati).
- `rimuoviDatiLocali: true` chiede al client di scartare la copia locale
  [AR-A]: per un download completo non cambia nulla.

Campi di `data.dati[0]` usati o presenti nella fixture [AR-A `APIDashboard`,
AR-I (chiavi di un campione reale), AR-E `DashboardDati`]: `voti`,
`listaPeriodi`, `listaMaterie`, `listaDocentiClasse`, `opzioni`,
`mediaGenerale`, `rimuoviDatiLocali`, `ricaricaDati`, `profiloDisabilitato`,
`msg`, `pk`, `fuoriClasse`, `promemoria`, `bacheca`, `bachecaAlunno`,
`registro`, `appello`.

### 4.1 Periodi e `coveredRange`

- **`coveredRange`** = da `profilo.anno.dataInizio` a `profilo.anno.dataFine`
  (`YYYY-MM-DD`) [AR-A `APIProfilo`, AR-I (`2023-09-01` → `2024-08-31`),
  AR-D usa `dataInizio`]. È l'intervallo richiesto alla dashboard.
- `listaPeriodi[]`: `pkPeriodo`, `codPeriodo`, `descrizione`, `dataInizio`,
  `dataFine`, `datInizio`, `datFine`, `votoUnico`, `mediaScrutinio`,
  `isMediaScrutinio`, `isScrutinioFinale` [AR-A]. Nel campione AR-I
  `dataInizio`/`dataFine` sono `dd/MM/yyyy` e `datInizio`/`datFine` sono
  `YYYY-MM-DD`; c'è anche un periodo `codPeriodo: "*"` "Intero Anno". Il
  provider usa solo `pkPeriodo` → `descrizione`.

### 4.2 Materie e docenti

- `listaMaterie[]`: `pk`, `materia`, `abbreviazione`, `codTipo`, `faMedia`,
  `scrut` [AR-A, AR-I (chiavi)]. Il voto ha già `pkMateria` e `desMateria`.
- `listaDocentiClasse[]`: `pk`, `desCognome`, `desNome`, `desEmail`,
  `materie[]` [AR-A]. Non necessario: il voto ha `docente`.
- `faMedia: false` (materia che non fa media): il significato è dedotto dal
  nome, **non documentato**; nel campione AR-I è `false` solo per la materia
  con `codTipo: "RE"` (religione), `true` per quelle con `codTipo: "NO"`
  (normali). Una sola fonte → TODO-AR8: marcare `notCounting` i voti di quella
  materia?

## 5. Esempio di risposta anonimizzato

Struttura dal tipo `APIDashboard` di AR-A e dal campione AR-I (stesse
chiavi); valori inventati.

```json
{
  "pk": "VOTO-0001",
  "operazione": "I",
  "datEvento": "2026-09-23",
  "datGiorno": "2026-09-23",
  "pkPeriodo": "PER-0001",
  "codCodice": "7",
  "valore": 7,
  "codVotoPratico": "S",
  "docente": "Docente A.",
  "pkDocente": "DOC-0001",
  "pkMateria": "MAT-0001",
  "desMateria": "MATEMATICA",
  "tipoValutazione": null,
  "prgVoto": 1,
  "descrizioneProva": "Verifica sulle equazioni",
  "faMenoMedia": "",
  "descrizioneVoto": "sette",
  "codTipo": "V",
  "mese": 9,
  "numMedia": 1,
  "desCommento": "",
  "materiaLight": {
    "scuMateriaPK": {"codMin": "XX00000", "prgScuola": 1, "numAnno": 2026, "prgMateria": 1},
    "codMateria": "MAT",
    "desDescrizione": "MATEMATICA",
    "desDescrAbbrev": "MAT",
    "flgConcorreMedia": "S",
    "prgMateria": 1,
    "idmateria": "MAT-0001"
  }
}
```

Fixture completa: `FMT IITests/Fixtures/Registri/argo-dashboard.json`.

## 6. Mappatura campo remoto → `VotoRemoto`

| `VotoRemoto` | Campo | Regola | Fonti | Stato |
|---|---|---|---|---|
| `provider` | — | `.argo` | — | — |
| `remoteId` | `pk` (stringa) | così com'è | AR-A (`pk` usato per le cancellazioni), AR-F, AR-I, AR-J | verificato; formato non uniforme (corto in AR-I, "hash lunghi" per AR-J) → trattarlo come opaco |
| `date` | `datGiorno` `YYYY-MM-DD` | giorno nel fuso `Europe/Rome` | AR-A, AR-C, AR-D, AR-I, AR-J | verificato |
| `hasTime` | — | sempre `false` | AR-I (nessuna ora in `datGiorno`) | verificato |
| `subjectId` | `pkMateria` | stringa | AR-A, AR-F, AR-I | verificato |
| `subjectName` | `desMateria` | così com'è | AR-A, AR-C, AR-D, AR-I, AR-J | verificato |
| `teacher` | `docente` | trim; vuoto → `nil` | AR-A, AR-C, AR-D, AR-I, AR-J | verificato il campo; formato del nome non uniforme fra le fonti |
| `rawValue` | `codCodice` | stringa originale (`"7"`, `"6+"`, `"8--"`, `"7½"`, lettere) | AR-A, AR-D, AR-I (`"8--"`), AR-J | verificato |
| `numericValue` | `valore` | (le voci con `codTipo` diverso da `"V"` sono già scartate, § 4) `valore` nullo → `nil`; `valore == 0` con `codCodice` diverso da `"0"` → `nil` (segnaposto, § 7); passato come `providedNumeric` | AR-A, AR-D (`valore > 0`), AR-C (giudizi senza valore), AR-I (`codTipo`) | verificato con riserva (TODO-AR9) |
| `kind` | `codVotoPratico` | `"S"` → `.written`, `"N"` → `.oral`, `"P"` → `.practical`, altro → `.other` | AR-C `TIPO_VOTO`, AR-D `TIPI_VOTO`, AR-I (`"S"` scritta, `"N"` nel campione) | verificato; AR-J dice `"O"` = orale (**fonti in disaccordo**, `"O"` → `.other`, TODO-AR10) |
| `kindRaw` | `codVotoPratico` | stringa originale | come sopra | verificato |
| `weight` | `numMedia` | **`nil` finché TODO-AR11 non è risolto** | § 8 | **BLOCKED-ON-USER** |
| `period` | `pkPeriodo` → `listaPeriodi[].descrizione` | descrizione del periodo; se non trovato `nil` | AR-A, AR-I | verificato |
| `comment` | `descrizioneProva`, `desCommento` | testi non vuoti, uniti con `\n` se diversi | AR-C `voti()`, AR-D `parser.voti`, AR-F (`desCommento` può mancare) | verificato |
| `notCounting` | `faMenoMedia` | `true` se `faMenoMedia == "S"` | AR-D, AR-E `VotiView.swift`, AR-J | verificato (3 fonti); AR-F commenta che `"N"` esclude: **in disaccordo**, ma il suo è un dato di test inventato e nel campione reale AR-I il valore normale è `""` |
| `cancelled` | — | sempre `false`: Argo non ha un flag "annullato" per i voti; le rimozioni arrivano come `operazione: "D"` | AR-A, AR-F, AR-I (nessun campo) | verificato (assenza) |
| `remoteModifiedAt` | (`datEvento`) | `nil` per ora | AR-I UI ordina "Ultima modifica" per `datEvento`; AR-F: "formato variabile" | TODO-AR12 |

Altri campi presenti, non usati: `descrizioneVoto` (voto in lettere),
`tipoValutazione` (`null` nel campione), `prgVoto`, `mese`, `pkDocente`,
`materiaLight` [AR-A, AR-I]. `materiaLight.flgConcorreMedia`: significato
non documentato (TODO-AR8).

## 7. Valori non numerici e segnaposto

- `codTipo`: `"V"` = voto, `"N"` = nota/annotazione (mostrata come "Nota",
  senza valore) [AR-I `votiGiornalieri/utils.ts`, `Voto.tsx`]; `"V"` anche in
  AR-J. **Regola:** una voce con `codTipo` diverso da `"V"` non è un voto:
  il provider la scarta in silenzio, **senza** contarla in `skippedCount`
  (non è un errore di lettura) e non la importa. Senza questa regola le note
  finirebbero fra i voti dell'utente con valore 0. `codTipo` mancante:
  nessuna fonte lo mostra → la voce è malformata e conta in `skippedCount`.
- **Segnaposto 0:** AR-D legge `valore` con `or 0` e conta un voto solo se
  `valore > 0` ("giudizi senza numero" esclusi); AR-C salta le voci il cui
  `valore` non è convertibile (cioè `null`). Quindi un giudizio può arrivare
  con `valore: 0` **o** `valore: null`: il provider tratta entrambi come
  `nil`, salvo `codCodice == "0"`. TODO-AR9: confermare con dati reali.
- Il valore di `+`, `-`, `½` lo calcola Argo: nel campione AR-I
  `codCodice: "8--"` ha `valore: 7.75` (con la regola di FMT ±0,25 per segno
  verrebbe 7,5). Per questo il provider passa **sempre** `valore` come
  `providedNumeric`, mai la sola stringa.
- `numMedia == 0`: AR-D esclude il voto dalla media. Una sola fonte → il
  provider non lo usa per `notCounting` finché TODO-AR11 non è risolto.

## 8. Peso — BLOCKED-ON-USER

- `numMedia` vale `1` nel campione reale AR-I e nell'esempio di AR-J: `1` =
  peso normale è **verificato** (2 fonti).
- Il significato per valori ≠ 1 è scritto **solo** in AR-J ("peso del voto
  (es. `1.0` = 100%, `0.5` = 50%)"): **una sola fonte**. AR-F lo chiama
  invece `runningAverage` e nella sua fixture inventata vale `7.5`: **fonti
  in disaccordo**. AR-D tratta `0` come "non fa media".
- Decisione per Task 12: `weight = nil` per ogni voto finché l'utente non
  conferma (TODO-AR11); il `weight` del `Grade` resta 1,0 come da spec.
  TODO-AR11 (utente): con un account in cui un docente usa i pesi,
  controllare che `numMedia` vale (0.5? 50?) e se può superare 1.

## 9. Date e fuso orario

| Dove | Formato | Fonti |
|---|---|---|
| `datGiorno`, `profilo.anno.dataInizio/dataFine`, `listaPeriodi[].datInizio/datFine` | `YYYY-MM-DD` | AR-A, AR-I, AR-J |
| `listaPeriodi[].dataInizio/dataFine` | `dd/MM/yyyy` nel campione AR-I | AR-I (una sola fonte; AR-F usa ISO in una fixture inventata) |
| `datEvento` | `YYYY-MM-DD` [AR-I] o `YYYY-MM-DD HH:mm:ss` [AR-F, AR-J per i timestamp] | non usato |
| Date inviate (`dataultimoaggiornamento`, `x-date-exp-auth`, `exp-bearer`) | `YYYY-MM-DD HH:mm:ss.SSS`, ora locale | AR-A `formatDate.ts`, AR-D `_format_date`, AR-E `argoFormatDate` |
| Scadenza token | header HTTP `Date` (RFC 1123, GMT) + `expires_in` | AR-A, AR-E `parseHTTPDate` |

Le date senza ora sono giorni del calendario della scuola: il provider le
interpreta in `Europe/Rome` (`hasTime = false`). TODO-AR13: nessuna fonte
indica esplicitamente il fuso (le fonti usano l'ora locale del dispositivo).

## 10. Errori noti (riepilogo per il provider)

| Situazione | Segnale | `RegistroError` |
|---|---|---|
| Credenziali errate | passo 2 senza redirect (§ 2.2) | `invalidCredentials` |
| Troppi tentativi | 429 al login o su endpoint dati | `rateLimited` |
| Accesso bloccato o limitato | 403 al login o su endpoint dati (§ 3.4, decisione del coordinatore) | `rateLimited`, nessun nuovo tentativo automatico |
| Versione dell'app troppo vecchia | `success: false`, `msg` con "ultima versione" | `notSupported` (va aggiornata `argo-client-version`) |
| Sessione scaduta | `expiresAt` passato (controllo locale) o 401 (§ 3.4) | `sessionExpired` → il coordinatore rifà il login una volta |
| Account disattivato | `profiloDisabilitato: true` nel login o nel profilo [AR-A] | `notSupported` (TODO-AR14: confermare) |
| `success: false` con altro `msg` | — | `unexpectedFormat` |
| Pagina o JSON inattesi | — | `unexpectedFormat` |
| Rete / 5xx | — | `network` |

## 11. Fixture

Nomi secondo i passi del login:

| File | Passo | Contenuto |
|---|---|---|
| `argo-token.json` | 3 | risposta 200 di `oauth2/token` |
| `argo-token-error.json` | 3 | errore OAuth `{error, error_description}` |
| `argo-login.json` | 4 | risposta di `appfamiglia/api/rest/login` |
| `argo-profilo.json` | 5 | risposta di `profilo` |
| `argo-dashboard.json` | 6 | `dashboard/dashboard` con 9 voci di `voti` (7 voti validi): numerici (scritto `S`, orale `N`, pratico `P`), `+`/`--`/`½`, giudizio `"buono"` con segnaposto `valore: 0`, `faMenoMedia: "S"`, una nota `codTipo: "N"` (da scartare senza contarla), una cancellazione `operazione: "D"` (da scartare senza contarla), due materie e due docenti, solo date; `listaPeriodi`, `listaMaterie`, `listaDocentiClasse` |
| `argo-api-error.json` | 4–6 | risposta applicativa con `success: false` |

Il passo 2 (credenziali errate) è una pagina HTML, non JSON: nessuna fixture
JSON; i test del provider simulano una risposta `200` senza `Location`.
Tutti i valori sono inventati.

## 12. Fonti

| Codice | Progetto | Commit / versione | File letti |
|---|---|---|---|
| AR-A | https://github.com/DTrombett/portaleargo-api (TypeScript, npm `portaleargo-api` 1.0.0 nel `package.json`) | `d77c406e89a8b2601fec49b4c4c71f6a6a13caa3` (2026-10-29) | `src/util/Constants.ts`, `getCode.ts`, `getToken.ts`, `generateLoginLink.ts`, `formatDate.ts`, `handleOperation.ts`, `src/BaseClient.ts`, `src/types/apiTypes.ts` |
| AR-B | https://github.com/salvatore-abello/argofamiglia (Python, 0.1.2) | `61d50e19b069d72bc76054796778966841b4981b` (2023-04-11) | `argofamiglia/auth.py`, `argofamiglia/CONSTANTS.py` |
| AR-C | https://github.com/power80it/ha-didup (Python, derivato da AR-B) | `b778e4940aa68bbde7f34d56c1224df0fad229c7` (2026-10-29) | `custom_components/didup/api.py`, `parsing.py`, `tests/test_parsing.py` |
| AR-D | https://github.com/Double-bited-Hamburger/zaino (Python) | `4db0937573b8be6e915daeecf1caa5d3357ec1df` (2026-11-11) | `argo_client.py`, `parser.py` |
| AR-E | https://github.com/cranci1/Atlas (Swift, iOS; porting di AR-A) | `d77d5814a80ee34730970db73af7c31278eae76c` (2026-10-01) | `Atlas/ArgoKit/ArgoSupport.swift`, `ArgoClient+Auth.swift`, `ArgoClient+Network.swift`, `Models.swift`, `Atlas/Views/VotiView.swift` |
| AR-F | https://github.com/Hydr46605/Argos (Kotlin) | `f6e5fa391498da5cb98ef27c6f4d475b1a0a39a8` (2026-08-28) | `src/main/kotlin/it/hydr4/argo/api/ArgoConstants.kt`, `models/Voto.kt`, `auth/RefreshProtocol.kt`, `src/test/resources/fixtures/dashboard-full.json` (dati di test inventati) |
| AR-G | https://github.com/lpaladini1980/minerva-android (Java) | `366daf7b47b59f60b0522b877d4cc678595ccf55` (2026-11-07) | `app/src/it/paladia/minerva/core/Argo.java`, `fixtures/dashboard.json` (inventato) |
| AR-H | https://github.com/fcaloro-beep/argo-family-dashboard (Python) | `c1384792a66d3ad27a767908fb94c51218c8bffc` (2026-09-28) | `custom_components/argo_family_dashboard/argo_client.py` |
| AR-I | https://github.com/DTrombett/argo-dashboard (TypeScript, web) | `07f9c85de69c77430ca21b36810029d21ffa9182` (2024-11-27) | `utils/localStorage.json` (campione di dati salvati dalla libreria: lette **solo chiavi e formati**, nessun valore personale riportato qui), `app/dashboard/menu/votiGiornalieri/utils.ts`, `Voto.tsx`, `PopupVoto.tsx` |
| AR-J | https://github.com/dddevid/Volta (`DIDUP_API.md`, API web `didattica.portaleargo.it`) | `05be030335a4a8afe7926b129438f1e1f04ae1d8` (2026-10-15) | `DIDUP_API.md` |
| AR-K | https://github.com/47PADO47/Argo.js (vecchia API ScuolaNext) | `285f0dd8f3cf99a3740e48d24949489121630b80` (2022-02-28) | `src/Argo.ts` |

## 13. TODO / da chiedere all'utente

- TODO-AR1: più profili in `login.data[]`: scegliere o rifiutare?
- TODO-AR2: `accountKey` = `codMin|alunno.pk`: `alunno.pk` è stabile fra anni?
- TODO-AR3: un `invalid_grant` al passo 3 va trattato come credenziali errate?
- TODO-AR4: quale `User-Agent` inviare (nessuno è richiesto dalle fonti).
- TODO-AR5: `argo-client-version` da App Store lookup o costante aggiornata a mano?
- TODO-AR6: segnale reale di sessione scaduta sugli endpoint dati (non documentato).
- TODO-AR7: logout solo locale (senza `rimuoviprofilo`)?
- TODO-AR8: `listaMaterie[].faMedia` / `materiaLight.flgConcorreMedia`: rendono `notCounting` i voti?
- TODO-AR9: giudizi con `valore` `0` o `null`: confermare con dati reali.
- TODO-AR10: `codVotoPratico: "O"` (solo AR-J) esiste? Oggi → `.other`.
- TODO-AR11: **scala del peso** `numMedia` per valori ≠ 1 (BLOCKED-ON-USER).
- TODO-AR12: `datEvento` è la data di ultima modifica? Usarla per `remoteModifiedAt`?
- TODO-AR13: fuso `Europe/Rome` per le date senza ora (non scritto nelle fonti).
- TODO-AR14: `profiloDisabilitato: true` → `notSupported`?
