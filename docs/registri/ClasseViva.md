# ClasseViva (Gruppo Spaggiari Parma) — protocollo per FMT

Stato: **login e voti verificati** (≥ 2 fonti indipendenti). **Peso:
BLOCKED-ON-USER** (vedi § Peso). Rischi generali in [README.md](README.md).

## 0. Due API diverse: quale usare

Esistono due API REST sullo stesso host, **non intercambiabili** (un token
dell'una non vale sull'altra [CV-K `docs/classeviva-api.md`]):

| | API "app" `rest/v1` (**raccomandata**) | API "web" `rest/w1` (alternativa) |
|---|---|---|
| Base | `https://web.spaggiari.eu/rest/v1` | `https://web.spaggiari.eu/rest/w1` |
| Login | `POST /rest/v1/auth/login`, JSON → token | `POST /auth-p7/app/default/AuthApi4.php?a=aLoginPwd`, form → cookie `PHPSESSID` |
| Sessione | header `Z-Auth-Token`, scadenza esplicita `expire` | cookie, scadenza non indicata |
| Voti | `GET /students/{id}/grades` | `GET /students/{id}/grades26` |
| Fonti | CV-A, CV-B, CV-C, CV-D, CV-E, CV-F, CV-J, CV-K (6+ client attivi nel 2026, uno in Swift) | CV-H (+ CV-I derivato da CV-H), CV-G |

**Scelta raccomandata: `rest/v1`.** Motivi: molte più fonti indipendenti e
attive (fra cui un'app iOS in Swift, CV-C, e un'osservazione dal vivo del
2026-09-16, CV-E); token con scadenza esplicita, che si adatta a
`RegistroSession(token, expiresAt)`; nessun cookie da gestire. L'API `w1` è
documentata in dettaglio da una sola fonte (CV-H e il suo fork
open-viva/endpoints sono lo stesso documento; CV-I ne riusa esempi e valori).
Il resto del documento descrive `v1`; § 11 riassume `w1` per completezza.

## 1. URL base e header comuni

- Base: `https://web.spaggiari.eu/rest/v1` [CV-A `README.md`, CV-B
  `adapters/spaggiari/http.go`, CV-C `BCW/Networking/ClassevivaClient.swift`,
  CV-D `classeviva_client.py`, CV-E `docs/endpoints.md`, CV-F
  `ClassevivaApiService.kt`].
- Header obbligatori su **ogni** richiesta ("senza, l'API rifiuta le
  richieste" [CV-A `README.md`, CV-C, CV-D, CV-E]):

| Header | Valore | Fonti |
|---|---|---|
| `Z-Dev-Apikey` | `Tg1NWEwNGIgIC0K` (costante dell'app ufficiale; nome dell'header case-insensitive, scritto anche `Z-Dev-ApiKey`) | CV-A `README.md`, CV-B `http.go`, CV-C `ClassevivaClient.swift`, CV-D, CV-E, CV-F `NetworkModule.kt` |
| `User-Agent` | `CVVS/std/4.2.3 Android/12` [CV-B, CV-C, CV-E] oppure `CVVS/std/4.1.7 Android/10` [CV-A, CV-D, CV-F]: entrambi funzionanti secondo le fonti | vedi a sinistra |
| `Content-Type` | `application/json` | CV-A, CV-B, CV-E, CV-F |
| `Z-Auth-Token` | token del login (tutte le richieste tranne il login) | CV-A `Authentication/status.md`, CV-B `openapi.yaml`, CV-C, CV-D, CV-E |

- Nota [CV-C]: una POST con corpo JSON `{}` viene rifiutata con
  `101:CvvRestApi/invalid payload`; una POST senza `Content-Length` viene
  bloccata dal CDN. FMT usa solo una POST (il login), con corpo non vuoto.
- TODO-CV1: non esiste uno User-Agent iOS documentato per l'app ufficiale;
  FMT dovrebbe inviare uno User-Agent Android (vedi TODO-R1 nel README).

## 2. Login passo per passo

**Richiesta**

```
POST https://web.spaggiari.eu/rest/v1/auth/login
Z-Dev-Apikey: Tg1NWEwNGIgIC0K
User-Agent: CVVS/std/4.2.3 Android/12
Content-Type: application/json

{"ident":null,"pass":"<password>","uid":"<nome utente>"}
```

- Corpo `{"ident": null, "pass", "uid"}` [CV-A `Authentication/login.md`,
  CV-C `performLogin()`, CV-E, CV-K]; CV-B omette `ident`. `ident` serve solo
  per scegliere un profilo fra più profili dello stesso account (§ 2.3).
- `uid` è il nome utente di ClasseViva (codice tipo `S1234567X` o email).

**Risposta 200** [CV-A `Authentication/login.md`, CV-B `openapi.yaml`
`Identity`, CV-C `BCW/Models/Account.swift` `LoginResponse`, CV-E, CV-F
`LoginResponseDto`]:

```json
{
  "ident": "S9000001X",
  "firstName": "NOME",
  "lastName": "COGNOME",
  "token": "<token opaco>",
  "release": "2026-11-15T16:00:00+01:00",
  "expire": "2026-11-15T17:30:00+01:00"
}
```

| Campo | Significato | Fonti |
|---|---|---|
| `ident` | identità: lettera di tipo (`S` studente, `G` genitore…), cifre, lettera di controllo | CV-A, CV-B `identity.go`, CV-C, CV-E |
| `firstName`, `lastName` | nome e cognome (non usati da FMT) | CV-A, CV-B, CV-C |
| `token` | da inviare come `Z-Auth-Token` | CV-A, CV-B, CV-C, CV-D, CV-E |
| `release`, `expire` | emissione e scadenza del token, ISO 8601 con offset (`+01:00`/`+02:00`) | CV-A, CV-B `openapi.yaml`, CV-C (`expire`), CV-F (`expire`) |

### 2.1 Come si ottiene `accountKey`

`studentId` = **solo le cifre** di `ident` (`S9000001X` → `9000001`). Tutti i
percorsi `/students/{studentId}/…` vogliono solo le cifre: con la lettera
finale rispondono `404 102:CvvRestApi/wrong uri` [CV-E `docs/endpoints.md`
(osservato), CV-B `identity.go` (regex `\D`), CV-C `studentId`, CV-D
`re.sub(r"\D", "", identita)`].

**`accountKey` = `studentId`** (cifre di `ident`). È l'identificativo usato da
tutte le fonti per lo studente; FMT lo usa per l'UUID v5 dei voti.
TODO-CV2: nessuna fonte dice esplicitamente che resta uguale da un anno
scolastico all'altro (è molto probabile, essendo l'id dell'utente).

### 2.2 Errori del login

| Segnale | Significato | Fonti |
|---|---|---|
| HTTP 422 o 401 | credenziali errate → `RegistroError.invalidCredentials`, **nessun nuovo tentativo automatico** | CV-C (`422/401/400`), CV-D (`401, 422`), CV-J `classeviva.py` (`401, 403, 422`) |
| HTTP 403 | da IP di provider cloud (non riguarda un iPhone) [CV-B]; per CV-J anche credenziali errate | CV-B `identity.go`, CV-J |
| HTTP 429 | troppe richieste → `rateLimited` | CV-D, CV-F `RestClient.kt` |
| 200 senza `token` ma con `choices` | account con più profili (genitore con più figli), § 2.3 | CV-C `LoginResponse`, CV-D `login()` |

Corpo degli errori: oggetto JSON con alcuni fra `statusCode`, `error` (forma
`NNN:CvvRestApi/testo`), `info`, `message` [CV-J `tests/test_classeviva.py`,
CV-F `RestClientNetworkTest.kt`, CV-C `errorMessage(from:)`, CV-E]. Per il
login sbagliato l'unico esempio è un server finto di test, `422 {"info":
"WrongCredentials"}` [CV-J]: **una sola fonte**. Il provider deve decidere
**solo dallo status HTTP**, mai dal testo (TODO-CV3: corpo reale del login
errato).

### 2.3 Account con più profili

Se la risposta contiene `choices` (array di `{ident, name}`) e nessun
`token`, si rifà il login passando l'`ident` scelto [CV-C, CV-D]. FMT è per
lo studente: TODO-CV4 (utente) — gestire questo caso (scelta del profilo) o
rifiutarlo con un messaggio? Nessuna fixture per ora.

## 3. Durata e rinnovo della sessione

- Il token dura **90 minuti**: esempio `release` 20:29:25 → `expire`
  21:59:25 [CV-A `Authentication/login.md`]; "Sessions last 90 minutes"
  [CV-E, osservato]. `expiresAt` = `expire` della risposta (CV-C usa `expire`,
  con ripiego a 1 ora).
- `GET /auth/status` (con `Z-Auth-Token`) restituisce
  `{"status": {"expire", "release", "ident", "remains"}}` (`remains` in
  secondi) [CV-A `Authentication/status.md`, CV-F `StatusResponseDto`]. FMT
  non ne ha bisogno.
- **Rinnovo = nuovo login** con le credenziali salvate: nessun refresh token
  esiste in `v1` [CV-C `ensureToken()` rinnova se mancano < 120 s; CV-F
  `ApiSessionManager.kt`; CV-K: su 401/403 nuovo login e un solo nuovo
  tentativo]. `refresh(session)` del provider = `login(credenziali)`.
- **Sessione scaduta**: HTTP 401 su un endpoint dati [CV-C `raw()`, CV-D
  `_api()`, CV-F]; CV-C e CV-K trattano allo stesso modo anche 403. Su 403
  però CV-D e CV-F dicono "sezione disattivata dalla scuola" → il provider
  rifà il login **una sola volta**; se il 403 persiste è `notSupported`
  (sezione voti disattivata), non `sessionExpired`.
- Logout: nessun endpoint di logout documentato in `v1`. `logout(session)` =
  solo cancellazione locale dal Keychain.

## 4. Endpoint voti e materie

| Endpoint | Uso in FMT | Fonti |
|---|---|---|
| `GET /students/{studentId}/grades` → `{"grades": [...]}` | tutti i voti dell'anno scolastico corrente | CV-A `Grades/grades.md`, CV-B `grades.go`, CV-C `AppModel.gradePaths`, CV-E, CV-F `getGrades` |
| `GET /students/{studentId}/periods` → `{"periods": [...]}` | periodi (per `coveredRange` e `period`) | CV-A `Periods/periods.md`, CV-C, CV-D, CV-E |
| `GET /students/{studentId}/subjects` → `{"subjects": [...]}` | materie con docenti (facoltativo) | CV-A `Subjects/subjects.md`, CV-D `_materie`, CV-E, CV-J |

- Varianti di percorso: CV-C prova in ordine `grades`, `grades2324`,
  `grades2`; CV-D prova prima `grades2` e poi `grades`. **Fonti in
  disaccordo sull'ordine e nessuna spiega le differenze** fra le varianti.
  Raccomandazione: usare `grades` (6 fonti). TODO-CV5: verificare con un
  account reale se `grades` restituisce tutti i campi della tabella § 6
  (in particolare `teacherName`, `noAverage`).
- L'API serve **solo l'anno scolastico corrente** [CV-E: "there is no way to
  retrieve a previous school year"]. Fra settembre e l'apertura dell'anno da
  parte della scuola le richieste possono rispondere `422` con
  "school year not started yet" [CV-F `RestClient.kt`]: per FMT è "nessun
  voto ancora", **non** un errore di credenziali (il 422 del login e quello
  degli endpoint dati vanno distinti). CV-C cita host di archivio
  `web{YY}.spaggiari.eu` per gli anni passati: **una sola fonte**, non usato.

### 4.1 `coveredRange`

`coveredRange` = da `dateStart` del primo periodo a `dateEnd` dell'ultimo
periodo di `/periods` (date `YYYY-MM-DD`). Struttura dei periodi:
`periodCode`, `periodPos`, `periodDesc`, `isFinal`, `dateStart`, `dateEnd`,
`miurDivisionCode` [CV-A `Periods/periods.md`, CV-H `README.md` § Periodi].
Nota: `periodPos` non è sequenziale (1 e 3 con due periodi) [CV-A esempio,
CV-H]. Se `/periods` fallisce, `coveredRange = nil` (nessuna cancellazione
automatica comunque, vincolo globale).

### 4.2 Materie

`/subjects`: `id`, `description`, `order`, `teachers[]` con `teacherId`
(stringa con prefisso `A`) e `teacherName` [CV-A `Subjects/subjects.md`,
CV-H § Materie]. Una materia può avere **più docenti** [CV-A esempio]: non
serve a stabilire chi ha messo un voto.

## 5. Esempio di risposta anonimizzato

Struttura dall'esempio di CV-A `Grades/grades.md` (dati del 2021) e dal
campione di CV-B `commands/testdata/grades.json`; tutti i valori qui sono
inventati.

```json
{
  "grades": [
    {
      "subjectId": 900101,
      "subjectCode": "",
      "subjectDesc": "MATEMATICA",
      "evtId": 7000001,
      "evtCode": "GRV0",
      "evtDate": "2026-09-22",
      "decimalValue": 7,
      "displayValue": "7",
      "displaPos": 1,
      "notesForFamily": "Verifica sulle equazioni",
      "color": "green",
      "canceled": false,
      "underlined": false,
      "periodPos": 1,
      "periodDesc": "TRIMESTRE",
      "componentPos": 1,
      "componentDesc": "Scritto",
      "weightFactor": 1,
      "skillId": 0,
      "gradeMasterId": 0,
      "skillDesc": null,
      "skillCode": null,
      "skillMasterId": 0,
      "skillValueDesc": " ",
      "skillValueShortDesc": null,
      "oldskillId": 0,
      "oldskillDesc": "",
      "noAverage": false,
      "teacherName": "DOCENTE PRIMO"
    }
  ]
}
```

Fixture completa: `FMT IITests/Fixtures/Registri/classeviva-grades.json`.

## 6. Mappatura campo remoto → `VotoRemoto`

| `VotoRemoto` | Campo `v1` | Regola | Fonti | Stato |
|---|---|---|---|---|
| `provider` | — | `.classeviva` | — | — |
| `remoteId` | `evtId` (intero) | `String(evtId)` | CV-A, CV-B `openapi.yaml`, CV-C `Grade.id`, CV-J (`id=str(g["evtId"])`) | verificato; TODO-CV6: stabilità di `evtId` se il docente modifica il voto |
| `date` | `evtDate` `YYYY-MM-DD` | giorno nel fuso `Europe/Rome` | CV-A, CV-B, CV-C `CVDate`, CV-D, CV-J | verificato (formato) |
| `hasTime` | — | sempre `false`: nessuna ora nei voti | CV-A, CV-B | verificato |
| `subjectId` | `subjectId` (intero) | `String(subjectId)` | CV-A, CV-B, CV-C, CV-D | verificato |
| `subjectName` | `subjectDesc` | così com'è (maiuscolo) | CV-A, CV-B, CV-C, CV-D, CV-J | verificato |
| `teacher` | `teacherName` | se presente e non vuoto, altrimenti `nil` | CV-C `Grade.swift`, CV-H (`w1`) | **una sola fonte per `v1`** (assente negli esempi CV-A/CV-B) — TODO-CV5 |
| `rawValue` | `displayValue` | stringa originale (`"7"`, `"6+"`, `"8½"`, `"ds"`) | CV-A, CV-B, CV-C, CV-D, CV-H (`"8½"` = 8.5, `"ds"`, `"o"`) | verificato |
| `numericValue` | `decimalValue` | passato come `providedNumeric` a `GradeValueNormalizer`; `null` → non numerico | CV-A, CV-B, CV-C (`Double?`), CV-D, CV-J | verificato il campo; vedi § 7 |
| `kind` | `componentDesc` | contiene "scritt" → `.written`; "oral" → `.oral`; "pratic" → `.practical`; altro (es. "Unico") → `.other` | CV-A (`"Orale"`), CV-B testdata (`"Unico"`), CV-D (match per sottostringa), CV-H (`"Pratico"`) | verificato |
| `kindRaw` | `componentDesc` | stringa originale | come sopra | verificato |
| `weight` | `weightFactor` | **`nil` finché TODO-CV7 non è risolto** | vedi § Peso | **BLOCKED-ON-USER** |
| `period` | `periodDesc` | stringa (es. "TRIMESTRE"); `periodPos` solo per ordinare | CV-A, CV-B, CV-C, CV-J | verificato |
| `comment` | `notesForFamily` | testo se non vuoto (dopo trim), altrimenti `nil` | CV-A, CV-B, CV-C, CV-D, CV-J | verificato; vedi nota su `skillValueDesc` |
| `notCounting` | `color`, `noAverage` | `true` se `color == "blue"` **o** `noAverage == true` | `"blue"`: CV-C `countsTowardAverage`, CV-D `fuori_media`; `noAverage`: CV-C, CV-H | verificato (2 fonti per `blue`) |
| `cancelled` | `canceled` (sic, una "l") | booleano | CV-A, CV-B, CV-C, CV-D, CV-J | verificato |
| `remoteModifiedAt` | — | `nil`: nessun campo di modifica nei voti | CV-A, CV-B (nessun campo) | verificato (assenza) |

Note:
- `evtCode` (`GRV0`, `GRV1`, `GRV2`, `GRT1`) **non** va usato per il tipo:
  CV-C lo mappa a Scritto/Orale/Pratico/Prova, ma l'esempio di CV-H ha
  `evtCode: "GRV0"` con `componentDesc: "Pratico"`. **Fonti in disaccordo** →
  si usa `componentDesc`.
- `componentPos`: CV-H dice 1 = Scritto/Grafico, 2 = Orale, 3 = Pratico, ma
  il campione di CV-B ha `componentPos: 1` con `componentDesc: "Unico"`.
  **Fonti in disaccordo** → non usato.
- `GRT1` (prova a punteggio, es. `"35/50"`) è escluso dalla media da CV-C:
  **una sola fonte**. Il normalizzatore già tratta `35/50` come non
  numerico; TODO-CV8: va anche marcato `notCounting`?
- `skillValueDesc`: nel campione di CV-B contiene la descrizione della prova
  (con `notesForFamily` vuoto), e CV-B la mostra come descrizione; nell'esempio
  di CV-A è `" "`. **Una sola fonte** → TODO-CV9: usarlo come ripiego per
  `comment` quando `notesForFamily` è vuoto?
- `underlined`, `displaPos` (sic), `subjectCode`, `skill*`, `gradeMasterId`,
  `oldskill*`: presenti [CV-A, CV-B], non usati da FMT.
- `color`: valori documentati `green`, `yellow`, `red` [CV-B `openapi.yaml`,
  CV-H] e `blue` (non fa media) [CV-C, CV-D].

## 7. Valori non numerici e segnaposto

- Giudizi (es. `"ds"`, `"o"` in Religione): `decimalValue: null` e
  `noAverage: true` [CV-H `README.md` § Voti, solo API `w1`]. CV-C e CV-F
  leggono `decimalValue` come opzionale; CV-D e CV-J ricadono su
  `displayValue` quando non è un numero.
- **Per `v1` nessuna fonte mostra se un giudizio arriva con `null` o con
  `0`.** Regola prudente per il provider: `decimalValue` `null` → `nil`;
  `decimalValue == 0` con `displayValue` che non è `"0"` → trattare come
  `nil` (non numerico). TODO-CV10: confermare con dati reali.
- Il valore di `decimalValue` per `+`, `-`, `½` è calcolato dal registro
  (es. `"8½"` = 8.5 [CV-H]); per `+`/`-` nessuna fonte riporta il valore
  esatto. Il provider passa sempre `decimalValue` come `providedNumeric`,
  così vince il valore del registro e non la regola ±0,25 di FMT.

## 8. Peso — BLOCKED-ON-USER

- `weightFactor` vale **1** negli unici esempi di risposte `v1` reali
  [CV-A `Grades/grades.md` (2021), CV-B `commands/testdata/grades.json`
  (2021)]. Quindi `1` = peso normale: **verificato** (2 fonti).
- Per valori ≠ 1 la scala `v1` **non è verificabile**:
  - CV-C la tratta come frazione (mostra `weight * 100` + "%", media pesata
    con `weight`): **una sola fonte**, nessun esempio reale con valore ≠ 1.
  - Nell'API `w1` lo stesso campo è una **percentuale** (`100` = peso 1)
    [CV-H]: scala diversa, API diversa.
  - Non è documentato se possano esistere pesi > 1 (es. 1,5 = 150 %).
- La scuola può non usare i pesi: in `w1` l'opzione
  `opt:votiWeightEnab` dice se la funzione è attiva [CV-H § Menu/Funzioni].
- Decisione per Task 11: `weight = nil` per ogni voto finché l'utente non
  conferma (TODO-CV7); il `weight` del `Grade` resta 1,0 come da spec.
  TODO-CV7 (utente): con un account in cui un docente usa i pesi, controllare
  che valore arriva (es. 0.5 o 50) e se esistono valori > 1.

## 9. Date e fuso orario

| Dove | Formato | Fonti |
|---|---|---|
| `evtDate`, `dateStart`, `dateEnd` | `YYYY-MM-DD` (solo data) | CV-A, CV-B, CV-H § Formati |
| `release`, `expire` | ISO 8601 con offset (`2026-11-15T17:30:00+01:00`) | CV-A, CV-B, CV-C |
| parametri nei percorsi (non usati da FMT) | `YYYYMMDD` | CV-E, CV-H |

Gli offset `+01:00`/`+02:00` degli esempi [CV-A, CV-B] sono quelli di
`Europe/Rome`: le date senza ora vanno interpretate come giorno del
calendario italiano (`hasTime = false`). TODO-CV11: nessuna fonte lo dice
esplicitamente (è dedotto dagli offset).

## 10. Errori noti (riepilogo per il provider)

| Situazione | Segnale | `RegistroError` |
|---|---|---|
| Credenziali errate | login 401/422 (§ 2.2) | `invalidCredentials` |
| Sessione scaduta | 401 su endpoint dati (§ 3) | `sessionExpired` → nuovo login automatico una volta |
| Sezione voti disattivata | 403 persistente dopo un nuovo login | `notSupported` |
| Anno non ancora aperto | 422 "school year not started yet" su endpoint dati | nessun voto, nessun errore (TODO-CV12: confermare) |
| Troppe richieste | 429 | `rateLimited` |
| Studente sbagliato nel percorso | 404 `102:CvvRestApi/wrong uri` | `unexpectedFormat` |
| Risposta non JSON / campi mancanti | — | `unexpectedFormat` |
| Errore di rete / 5xx | — | `network` |

## 11. API `w1` (alternativa, non raccomandata)

Solo per riferimento [CV-H `README.md`, `openapi.yaml`; CV-G
`src/classeviva/main.py`; CV-I `src/client.ts`]:
- Login: `POST https://web.spaggiari.eu/auth-p7/app/default/AuthApi4.php?a=aLoginPwd`,
  form `cid=&uid=…&pwd=…&pin=&target=`; successo se
  `data.auth.loggedIn == true`; cookie `PHPSESSID`, `webidentity`, `webrole`.
  CV-G tratta HTTP 422 come password errata; CV-I legge `data.auth.errors`.
- Studente: `GET /rest/w1/misc/whoami` → `id`.
- Voti: `GET /rest/w1/students/{id}/grades26` (il "26" non è l'anno [CV-H]),
  stessi campi di `v1` più `periodLabel`, `evtPosition`; `weightFactor` in
  percentuale (`100` = 1) e `decimalValue: null` per i giudizi [CV-H].
- Scadenza della sessione non indicata ("non hanno una scadenza, o perlomeno
  così sembra" [CV-G]); 401 = sessione non valida [CV-H, CV-I].

## 12. Fixture

| File | Contenuto | Struttura da |
|---|---|---|
| `classeviva-login.json` | risposta 200 di `POST /auth/login` | § 2 |
| `classeviva-login-failure.json` | corpo di una risposta 422 al login (da usare con status 422) | § 2.2 (una sola fonte per il corpo) |
| `classeviva-grades.json` | 8 voti: numerici, `+`/`-`/`½`, giudizio, blu, `noAverage`, annullato, due materie e due docenti, solo date | § 5, § 6 |
| `classeviva-periods.json` | due periodi | § 4.1 |
| `classeviva-subjects.json` | due materie con docenti | § 4.2 |

Tutti i valori sono inventati (id, nomi, date, token).

## 13. Fonti

| Codice | Progetto | Commit / versione | File letti |
|---|---|---|---|
| CV-A | https://github.com/Lioydiano/Classeviva-Official-Endpoints (fork aggiornato di michelangelomo/Classeviva-Official-Endpoints @ `bf99a250609290f0a8ade1f9b09843608d465b5e`) | `2d523a56a821d50eb5edf3cced5575ae7eb59749` (2025-11-25) | `README.md`, `Authentication/login.md`, `Authentication/status.md`, `Grades/grades.md`, `Subjects/subjects.md`, `Periods/periods.md` |
| CV-B | https://github.com/zmoog/classeviva (Go) | `69349928773cee9e7937313ed24c4e9c38f78be8` (2026-11-12) | `adapters/spaggiari/http.go`, `identity.go`, `grades.go`, `model.go`, `openapi.yaml`, `commands/testdata/grades.json` |
| CV-C | https://github.com/kubos5/BCW (Swift, iOS) | `6ccebf53c2c832c4c0bd37c7a2e5ba25959f5557` (2026-11-09) | `BCW/Networking/ClassevivaClient.swift`, `BCW/Models/Grade.swift`, `BCW/Models/Account.swift`, `BCW/Store/AppModel.swift`, `BCW/Store/GradeBook.swift`, `BCW/Features/Grades/GradesView.swift` (`BCW/Store/DemoServer.swift` contiene dati demo inventati: non usato come fonte) |
| CV-D | https://github.com/Double-bited-Hamburger/zaino (Python) | `4db0937573b8be6e915daeecf1caa5d3357ec1df` (2026-11-11) | `classeviva_client.py`, `classeviva_adatta.py` |
| CV-E | https://github.com/franciuto/classeviva-mcp | `061ac2f532e110528b64b2cc91db2870130fcd72` (2026-09-17) | `docs/endpoints.md` (osservazioni sul servizio reale del 2026-09-16), `src/classeviva/types.ts` |
| CV-F | https://github.com/Casual76/classeviva-expressive (Kotlin) | `c603e0dce00eb8c75779ce5e9cde723fb0f100dc` (2026-11-08) | `android/core/core-network/src/main/kotlin/.../client/ClassevivaApiService.kt`, `NetworkModule.kt`, `RestClient.kt`, `ApiSessionManager.kt`, `NetworkParsers.kt`; test `RestClientNetworkTest.kt` |
| CV-G | https://github.com/Lioydiano/Classeviva (Classeviva.py 1.3.0, API `w1`) | `1638e1ea286c537a856b871a8a227632373fa984` (2026-10-09) | `src/classeviva/main.py`, `variabili/variabili.py`, `collegamenti/collegamenti.py`, `CHANGELOG.md` |
| CV-H | https://github.com/GoldenMelky/classeviva_endpoints = https://github.com/open-viva/endpoints (API `w1`, stesso documento) | `47514f5fef15d69a3e742e69634852f7442f140c` (2026-11-10) / `de292387c25db1691e5a770fee919761dcfaf374` (2026-11-02) | `README.md`, `openapi.yaml` |
| CV-I | https://github.com/Just1diaxx/classeviva.js 1.0.1 (API `w1`, **derivato da CV-H**) | `8eed6b1fbf57387a15db0bb0c8fdd3f2fc84a783` (2026-10-27) | `src/client.ts`, `src/types.ts`, `test/client.test.js` |
| CV-J | https://github.com/Quezka/quire | `94f7fc9c0738bc15b2264875e6ddb76f4433eb3d` (2026-11-15) | `quire/infrastructure/classeviva.py`, `tests/test_classeviva.py` |
| CV-K | https://github.com/Maro314o/classeviva-mcp (Go) | `5c6571930d524ecff28f458498c0faba753a88f0` (2026-11-12) | `docs/classeviva-api.md` |

## 14. TODO / da chiedere all'utente

- TODO-CV1: nessuno User-Agent iOS documentato; usare quello Android (TODO-R1).
- TODO-CV2: `studentId` stabile fra anni scolastici? (probabile, non scritto).
- TODO-CV3: corpo reale della risposta di login errato (una sola fonte, test finto).
- TODO-CV4: account con più profili (`choices`): gestire o rifiutare?
- TODO-CV5: `teacherName`/`noAverage` presenti in `GET /grades` di `v1`? (solo CV-C).
- TODO-CV6: `evtId` resta uguale se il docente modifica il voto?
- TODO-CV7: **scala del peso** `weightFactor` per valori ≠ 1 (BLOCKED-ON-USER).
- TODO-CV8: le prove `GRT1` vanno marcate `notCounting`? (solo CV-C).
- TODO-CV9: usare `skillValueDesc` come commento di ripiego? (solo CV-B).
- TODO-CV10: giudizi in `v1`: `decimalValue` `null` o `0`?
- TODO-CV11: fuso `Europe/Rome` per le date senza ora (dedotto dagli offset).
- TODO-CV12: il 422 "school year not started yet" va trattato come "nessun voto"?
