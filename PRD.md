# App Scolastica – Redesign UI e Parser Orario PRD
*(nome placeholder — rinominalo pure prima di usarlo)*

> **Nota per Claude Code**: leggi questo file per intero prima di iniziare qualsiasi modifica. La sezione "Goal Condition" in fondo è il testo esatto da incollare dopo `/goal` nel terminale — è una versione condensata di questo documento, perché `/goal` accetta al massimo 4000 caratteri.

## One-Liner
Riprogettare graficamente l'app iOS Orario/Diario/Voti (Swift, tab-based, iPhone + iPad) applicando il nuovo design system creato con Claude Design/Fable 5 — inclusa una generalizzazione del parser PDF per riconoscere layout di orari scolastici diversi da quelli già supportati — mantenendo invariate tutte le funzionalità e le interazioni esistenti.

## Stack
- Swift, iOS + iPadOS, architettura a tab.
- Framework UI (SwiftUI / UIKit / misto), deployment target minimo, gestore pacchetti (SPM / CocoaPods / nessuno) e librerie di terze parti per la UI: **non noti in anticipo.** Identificali ispezionando il repo come primo step, prima di modificare qualsiasi file, e riportali nel transcript.
- Persistenza dati: presumibilmente SQLite via GRDB.swift — da confermare comunque durante l'ispezione iniziale.
- File di riferimento per il nuovo design: sulla Scrivania (`~/Desktop`). Se sono presenti più file candidati, chiedi conferma di quale usare prima di procedere.

## Surfaces
Schermate che cambiano graficamente (funzionalità invariata):
1. Splash / avvio
2. Tutorial (onboarding)
3. Orario — vista giornaliera (modificabile), vista ora attuale + ora successiva, vista settimanale; visualizzabile per classe o per docente
4. Diario — lista note
5. Diario — schermata di scrittura/modifica nota
6. Voti — overview, gestione singola materia, grafico andamento
7. Impostazioni
8. Modifica del database
9. Aggiunta di un proprio orario (creazione manuale e import da PDF)

Componenti di stile coinvolti: tab bar, icone, pulsanti, palette colori (stessa base, alcune tinte cambiano), gradienti. Font: applicati secondo il file di design se lo specifica, altrimenti invariati.

Componente funzionale (non grafico) incluso nello scope: generalizzazione del parser PDF — vedi Data.

## Data
**Storage**: invariato per Orario/Diario/Voti — nessuna migrazione, nessun cambio di schema. Conferma lo schema esistente leggendo il codice, non modificarlo.

**Orario** — input: creazione manuale o import PDF. Viste: giornaliera (modificabile), ora attuale+successiva, settimanale. Visualizzazione adattiva: materie riconosciute → filtro per materia/classe; docenti riconosciuti → filtro per classe/docente. Campi minimi per riga: classe, giorno, ora, e almeno uno tra materia/docente (aula: opzionale, come da schema esistente).

**Diario** — note create liberamente, o generate tenendo premuto su una classe/docente nella vista settimanale (nota collegata a quell'elemento).

**Voti** — inseriti manualmente, salvati sul dispositivo; gestione per singola materia + grafico andamento nel tempo.

**Parser PDF (revisione nello scope)** — oggi riconosce 2 formati specifici. Deve generalizzare basandosi su 4 elementi strutturali: **classe, giorno/ora, materia, docente**. I 3 PDF reali forniti (`Orario_def_materie_Centrale.pdf`, `Orario-definitivo-per-classe-Cassia-734__1_.pdf`, `Orario-definitivo-per-classe-Gallina-Scientifico.pdf`) sono esempi della varietà da gestire, non l'elenco chiuso di cosa deve funzionare.

Regole:
- 0 elementi mancanti + nessun conflitto → import completo
- 1 elemento mancante → import parziale; utente completa a mano, scegliendo lui per quali classi
- 2+ elementi mancanti, struttura non riconoscibile, o file non è un PDF valido → rifiuto totale, orario da creare manualmente
- Conflitto docente doppio (stesso docente, stesso giorno/ora, due classi) → rifiuto totale
- Conflitto materia doppia (stessa classe, stesso giorno/ora, due materie) → rifiuto totale
- Orario implausibile (giorno fuori lun–sab, o ora fuori 07:00–19:00) → rifiuto totale

Nessuna importazione parziale sui conflitti: stesso esito del caso "2+ mancanti".

## Constraints
- **UI**: cambia solo l'estetica dei componenti. Tap, long-press (creazione nota da weekly), swipe tra le viste: comportamento identico a prima.
- **Navigazione**: tab bar con esattamente 3 tab (Orario, Diario, Voti), nessuna fusione/divisione/riorganizzazione.
- **Parser — regressione**: i formati già riconosciuti oggi continuano a funzionare esattamente come ora.
- **Parser — logica accettazione/rifiuto**: quella sopra, applicata rigorosamente.
- **Schema dati**: nessuna modifica a Voti/Diario/Orario. Se un requisito risultasse incompatibile con lo schema esistente, segnala il blocco invece di modificarlo di nascosto.

## Success Criteria
1. Framework UI, deployment target minimo, gestore pacchetti e librerie di terze parti sono identificati e riportati prima di modificare qualsiasi file — Prova: nota nel transcript con i risultati dell'ispezione del repo.
2. La build compila senza errori — Prova: output del comando di build del progetto (es. `xcodebuild build`).
3. L'app si avvia correttamente su un simulatore iPhone e su un simulatore iPad — Prova: screenshot della schermata iniziale su entrambi.
4. Ognuna delle schermate/viste elencate in Surfaces (incluse le 3 sotto-viste di Orario e i 3 aspetti di Voti) mostra i componenti aggiornati secondo il file di design sulla Scrivania — Prova: uno screenshot per schermata/vista, confrontato al riferimento del design (non pixel-perfect).
5. Nessuna schermata presenta elementi sovrapposti/tagliati, nessuna transizione causa crash, nessun componente vecchio stile resta in mezzo al nuovo design — Prova: screenshot di ogni schermata più una navigazione dimostrata nel transcript.
6. Le interazioni esistenti restano identiche: tap, long-press su classe/docente per creare una nota, swipe tra le viste — Prova: comportamento dimostrato nel transcript per ciascuna.
7. La tab bar mantiene esattamente 3 tab (Orario, Diario, Voti) — Prova: screenshot della tab bar.
8. Il parser importa correttamente i 3 PDF reali (`Orario_def_materie_Centrale.pdf`, `Orario-definitivo-per-classe-Cassia-734__1_.pdf`, `Orario-definitivo-per-classe-Gallina-Scientifico.pdf`), senza regressioni — Prova: dump del database risultante per ciascun PDF (classi, giorni/ore, materie).
9. Con un PDF sintetico a cui manca 1 dei 4 elementi, l'app importa i dati parziali e permette all'utente di scegliere per quali classi completarli — Prova: comportamento dimostrato nel transcript, screenshot della schermata di completamento.
10. Con un PDF sintetico a cui mancano 2+ dei 4 elementi, l'app rifiuta il file per intero e propone la creazione manuale — Prova: comportamento dimostrato nel transcript.
11. Con un PDF non riconoscibile come orario scolastico (es. testo a caso, nessuna struttura tabellare), l'app rifiuta il file per intero — Prova: comportamento dimostrato nel transcript.
12. Con un PDF sintetico con conflitto docente doppio, l'app rifiuta il file per intero — Prova: comportamento dimostrato nel transcript.
13. Con un PDF sintetico con conflitto materia doppia, l'app rifiuta il file per intero — Prova: comportamento dimostrato nel transcript.
14. Con un PDF sintetico con orario implausibile (fuori lun–sab o fuori 07:00–19:00), l'app rifiuta il file per intero — Prova: comportamento dimostrato nel transcript.
15. Vista adattiva: quando sono riconosciute le materie l'interfaccia filtra per materia/classe; quando sono riconosciuti i docenti filtra per classe/docente — Prova: comportamento dimostrato nel transcript per entrambi i casi.
16. Lo schema dati di Voti, Diario e Orario non è stato modificato — Prova: diff del codice relativo a schema/modello dati.
17. Dove tecnicamente fattibile (in particolare la logica del parser, indipendente dalla UI), esiste una suite di test automatici XCTest che copre i casi 8–14 — Prova: output di `xcodebuild test` con esito PASS per ciascun test. Dove non fattibile (comportamento legato alla UI), vale la verifica manuale già descritta sopra.

**Seed data**: prima della verifica devono esistere il file di design system sulla Scrivania (`~/Desktop`); i tre PDF reali (`Orario_def_materie_Centrale.pdf`, `Orario-definitivo-per-classe-Cassia-734__1_.pdf`, `Orario-definitivo-per-classe-Gallina-Scientifico.pdf`) nella cartella Download (`~/Downloads`); un account/backup già pronto da ripristinare su iPhone con almeno qualche voto, qualche nota diario e un orario già caricato; e i PDF sintetici per i casi 9–14, creati come parte del lavoro.

---

## Goal Condition (da incollare dopo `/goal`)

Testo condensato (2.322 caratteri, limite 4.000) — fa riferimento a questo file per il contesto completo:

```
Leggi prima PRD.md (root del progetto) per stack, surfaces, data e constraints completi. Poi lavora finché sono vere TUTTE le condizioni seguenti, ciascuna dimostrata nel transcript:

1. Framework UI, deployment target, package manager, librerie terze parti: identificati e riportati prima di modificare qualsiasi file.
2. `xcodebuild build` esce con successo; app avviata su simulatore iPhone e su simulatore iPad (screenshot di entrambi).
3. Ogni schermata elencata in PRD.md sezione Surfaces mostra il nuovo design (screenshot confrontato al file di riferimento in ~/Desktop): nessun elemento sovrapposto/tagliato, nessun crash nelle transizioni, nessun componente vecchio stile residuo.
4. Tab bar con esattamente 3 tab (Orario/Diario/Voti), nessuna fusione/riorganizzazione. Tap, long-press su classe/docente per creare una nota, swipe tra le viste: comportamento identico a prima (dimostrato).
5. Schema dati di Orario/Diario/Voti non modificato (diff del codice a conferma).
6. I 3 PDF reali in ~/Downloads elencati in PRD.md importano correttamente, senza regressioni sui 2 formati già supportati oggi (dump del database risultante per ciascuno dei 3).
7. Con un PDF sintetico creato da te: manca 1 dei 4 elementi (classe, giorno/ora, materia, docente) → import parziale, l'utente sceglie per quali classi completare i dati (comportamento dimostrato).
8. Con un PDF sintetico: mancano 2+ elementi, o la struttura non è riconoscibile, o il file non è un PDF valido → rifiuto totale, propone creazione manuale (dimostrato).
9. Con PDF sintetici distinti, dimostrati singolarmente: stesso docente in due classi nello stesso giorno/ora → rifiuto totale. Stessa classe con due materie nello stesso giorno/ora → rifiuto totale. Giorno fuori lun-sab o ora fuori 07:00-19:00 → rifiuto totale.
10. Vista adattiva: materie riconosciute → filtro per materia/classe; docenti riconosciuti → filtro per classe/docente (entrambi dimostrati).
11. Dove tecnicamente fattibile (logica del parser, indipendente dalla UI), una suite XCTest copre gli scenari dei punti 6-9; `xcodebuild test` esce con successo.

Vincoli: non modificare codice oltre a UI e logica del parser. Non disabilitare o eliminare test esistenti per far passare la condizione. Ferma dopo 40 turni e riporta cosa resta, se non hai finito prima.
```

*Il limite di 40 turni è un valore di sicurezza di default — alzalo (es. 80-100) se preferisci lasciare più margine prima che Claude Code si fermi a fare rapporto, dato che il lavoro (redesign di 9 schermate + generalizzazione parser) è sostanzioso.*
