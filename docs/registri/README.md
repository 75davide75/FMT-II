# Registri elettronici: protocolli, fonti e rischi

Questa cartella documenta i protocolli **non ufficiali** con cui FMT 2.3 legge i
voti dello studente dai registri elettronici, usando le credenziali dello
studente stesso e solo sul dispositivo.

| Provider | Documento | Stato (gate Task 10) |
|---|---|---|
| ClasseViva (Spaggiari) | [ClasseViva.md](ClasseViva.md) | Login e voti verificati da ≥ 2 fonti. **Peso: BLOCKED-ON-USER** (scala dei valori ≠ 1 non verificabile). |
| Argo didUP Famiglia | [Argo.md](Argo.md) | Login e voti verificati da ≥ 2 fonti. **Peso: BLOCKED-ON-USER** (significato di `numMedia` da una sola fonte). |

Regola del progetto (vincoli globali): i provider implementano **solo** ciò che
è scritto in questi documenti con una fonte. Tutto il resto è un punto
**TODO** da chiedere all'utente; nessun endpoint, campo o valore va indovinato.

## Come leggere le fonti

- Nessuno dei due registri ha un'API pubblica documentata. Le sole fonti sono
  client open source della community e documentazioni ricavate dal traffico
  dell'app ufficiale.
- Ogni dettaglio critico cita almeno due fonti indipendenti con commit SHA.
  Quando c'è una sola fonte, o le fonti non concordano, è scritto
  esplicitamente ("una sola fonte", "fonti in disaccordo") ed è un TODO.
- I sorgenti sono stati **letti**, mai eseguiti, installati o importati.
  Nessuna richiesta è stata inviata ai server dei registri, né con né senza
  credenziali.
- "Indipendenti" va letto con cautela: diversi client discendono da uno stesso
  progetto (indicato nelle tabelle delle fonti). Le fonti della stessa
  "famiglia" contano come una sola.
- Data della ricerca: 2026-11-15.
- I codici tra parentesi quadre (`[CV-B]`, `[AR-D]`, …) rimandano alla tabella
  "Fonti" di [ClasseViva.md](ClasseViva.md) e [Argo.md](Argo.md), con URL,
  file e commit SHA.

## Rischi

### Accesso non ufficiale

- Entrambi i protocolli sono quelli usati dalle **app ufficiali** (ClasseViva
  Studenti/Famiglia, didUP Famiglia), ricostruiti dalla community. Né
  Spaggiari né Argo li documentano o li garantiscono: possono cambiare senza
  preavviso e l'importazione può smettere di funzionare da un giorno all'altro.
  L'app deve degradare in modo sicuro: nessuna scrittura sui voti in caso di
  errore (vincolo globale).
- Per parlare con questi server FMT deve presentarsi con gli identificativi
  dell'app ufficiale:
  - ClasseViva: header `Z-Dev-Apikey` statico e `User-Agent` dell'app Android
    ufficiale (vedi ClasseViva.md).
  - Argo: `client_id` OAuth e `redirect_uri` dell'app didUP Famiglia, header
    `argo-client-version` con la versione dell'app ufficiale (vedi Argo.md).
  Questo significa che, lato server, FMT è indistinguibile dall'app ufficiale.
  È una scelta con implicazioni legali e di revisione App Store: **TODO
  (decisione utente)**, vedi sotto.

### Termini di servizio

- Non ho trovato condizioni d'uso pubbliche di Spaggiari o Argo che
  autorizzino o vietino esplicitamente l'accesso da app di terze parti.
  **TODO (utente):** leggere le condizioni d'uso dei due servizi (e quelle
  accettate dallo studente al primo accesso) prima del rilascio.
- Le scuole possono disattivare sezioni del registro per le famiglie/studenti
  (ClasseViva risponde 403 sulle sezioni disattivate; Argo espone le opzioni
  della scuola nel login). Un voto non visibile nell'app ufficiale non lo è
  nemmeno per FMT.

### Rate limit e blocchi

- ClasseViva: due client gestiscono esplicitamente HTTP **429** ("troppe
  richieste") [CV-D `classeviva_client.py`, CV-F `RestClient.kt`]; uno
  descrive l'API come "con limiti stretti" e limita il numero di chiamate
  [CV-D]. Le chiamate da IP di provider cloud ricevono **403** [CV-B
  `adapters/spaggiari/identity.go`]; da un iPhone questo non si applica, ma
  vieta qualunque proxy server-side.
- Argo: un client gestisce **429** sulla pagina di login ("troppi tentativi di
  accesso") [AR-D `argo_client.py`]. Argo **rifiuta i client con versione
  vecchia** (messaggio che contiene "ultima versione"); due client leggono la
  versione corrente dell'app ufficiale dall'App Store per aggirarlo [AR-D,
  AR-G]. Il valore di `argo-client-version` va quindi mantenuto aggiornato.
- Il piano cita blocchi passati di client non ufficiali da parte di Argo.
  **Nelle fonti consultate non ho trovato una conferma primaria** (né notizie
  né issue): resta un rischio plausibile ma **non verificato** (TODO). Fatto
  documentato: la vecchia API "ScuolaNext" (`/famiglia/api/rest` con header
  `x-key-app`) usata dai client fino al 2022 [AR-K] non è più usata da nessun
  client attivo, che sono tutti passati al login OAuth dell'app didUP
  Famiglia.
- Mitigazioni già previste dalla spec: sync all'apertura al più ogni 15
  minuti, background non prima di 2 ore, **nessun nuovo tentativo automatico
  dopo un errore di credenziali** (evita il blocco dell'account), un solo
  download completo per sync.

### App Store, linea guida 5.2.2

La linea guida 5.2.2 ("Third-Party Sites/Services") chiede che un'app che usa
o mostra contenuti di un servizio di terzi sia espressamente autorizzata dalle
condizioni d'uso di quel servizio, e aggiunge: "Authorization must be provided
upon request" (fonte: developer.apple.com/app-store/review/guidelines,
consultata il 2026-11-15). Poiché né Spaggiari né Argo concedono
un'autorizzazione pubblica, la revisione Apple potrebbe chiederla e rifiutare
l'app. **TODO (utente):** decidere se chiedere un'autorizzazione scritta ai
due fornitori o come presentare la funzione nelle note per la revisione.

### Credenziali e privacy

- Credenziali e token solo nel **Keychain**, con
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, non sincronizzabili;
  mai in file, UserDefaults, iCloud o log (vincolo globale). Nessun `print`
  di richieste o risposte in Release: le risposte contengono dati personali
  (nome, codice fiscale, email) e i token.
- La password resta salvata per poter rifare il login quando la sessione
  scade (entrambi i registri hanno sessioni di circa un'ora, vedi i
  documenti); va detto chiaramente all'utente al momento del collegamento.
- Tutto on-device: l'app parla solo con i server del registro (e,
  eventualmente, con l'App Store per la versione di didUP, vedi Argo.md).
- I client mostrano che le risposte contengono anche dati che FMT non usa
  (anagrafica, codice fiscale, email): il provider deve leggere solo i campi
  elencati nelle tabelle di mappatura e non salvare il resto.

## Fixture

Le fixture in `FMT IITests/Fixtures/Registri/` hanno la stessa struttura delle
risposte documentate, ma **dati inventati**: nessuna persona, scuola o id
reale. Ogni campo usato nelle fixture compare nel documento del provider con
la sua fonte.

## TODO comuni (da chiedere all'utente)

1. TODO-R1: accettare il rischio legale/ToS di presentarsi con gli
   identificativi delle app ufficiali (header e `client_id`), o rinunciare?
2. TODO-R2: strategia per la revisione App Store (5.2.2): chiedere
   un'autorizzazione scritta a Spaggiari/Argo?
3. TODO-R3: leggere le condizioni d'uso dei due servizi prima del rilascio.
4. TODO-R4: conferma dei "blocchi passati" di Argo citati nel piano (nessuna
   fonte trovata).
5. TODO-R5: verifica finale con un account reale (fase 7 della spec) di tutti
   i punti marcati "una sola fonte".
