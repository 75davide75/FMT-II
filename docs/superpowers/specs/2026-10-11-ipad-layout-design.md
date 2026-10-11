# FMT 2.2 — Layout ottimizzato per iPad — design

Data: 2026-10-11. Fonte: richiesta utente («interfaccia rivista e ottimizzata
per iPad… non mi piace la vista settimanale… disposizione per l'iPad in
orizzontale… nessun cambio di funzionalità o stile») + risposte: impianto
«colonne dove serve», Diario con editor nel foglio come oggi, ottimizzare
iPad sia in verticale sia in orizzontale. Fa parte della 2.2 (banner Novità).

## Vincoli

- Nessun cambio di funzionalità, stile (Aurora) o navigazione (barra
  Orario/Diario/Voti in alto, menu •••, FAB, fogli).
- iPhone (e iPad in Split View stretta) identici a oggi.
- Unica eccezione accettata dall'utente: nel Diario su iPad lo swipe
  «Archivia/Ripristina» non c'è (griglia a 2 colonne); le stesse azioni
  restano nel menu a pressione prolungata.

## Modalità di layout

`DeviceLayout` (Models/DeviceLayout.swift), funzione pura
`DeviceLayout.resolve(horizontalSizeClass:width:)`:
- `.compact`: size class compatta o larghezza < 700 pt → layout iPhone.
- `.regular`: size class regolare e 700 ≤ larghezza < 1000 (iPad verticale).
- `.wide`: size class regolare e larghezza ≥ 1000 (iPad orizzontale).

Calcolata in `ContentView` dalla larghezza della finestra e passata a tutte le
viste con `@Environment(\.deviceLayout)` (default `.compact`).

## Orario

- **Settimana** (`.regular`/`.wide`): colonne giorno flessibili =
  (larghezza − colonna ore) / giorni, nessuno scroll orizzontale
  (`WeekGridMetrics.dayColumnWidth`, pura, con minimo 88 pt: sotto il minimo
  si torna allo scroll come oggi); righe 76 pt; chip con font 12.5 e seconda
  riga (classe: docente sotto la materia; docente: materia sotto la classe).
  Tap, menu «Crea nota» e «+N» invariati. `.compact` invariato.
- **`.wide`**: due colonne. Sinistra fissa (340 pt): statistiche
  (`statusStrip`), `controlPanel`, `timeIndicator`. Destra: contenuto
  (Adesso/Giorno/Settimana) che scorre. Titolo fisso in alto come oggi.
- **`.regular`**: colonna unica come oggi; Adesso e Giorno con larghezza
  massima 760 pt centrata; Settimana a tutta larghezza.

## Diario

- `.regular`/`.wide`: per ogni gruppo di date le card su `LazyVGrid` a 2
  colonne (ScrollView + LazyVStack con le stesse intestazioni di gruppo e lo
  stesso scroll alla data della striscia). Stesse card, tap, selezione
  multipla e menu contestuale. Intestazione (striscia giorni, filtri,
  ricerca) invariata. Editor sempre in foglio.
- `.compact`: la `List` attuale, invariata (con lo swipe).

## Voti

- `.wide`: colonna sinistra fissa (380 pt) con titolo, `GradesSummaryCard` e
  `RecentGradesRow`; a destra l'elenco dei voti che scorre.
- `.regular`: titolo, riepilogo e ultimi voti a tutta larghezza; elenco voti
  su `LazyVGrid` a 2 colonne.
- Tap, menu, FAB, dettaglio materia invariati.

## Banner Novità

Solo su iPad (`UIDevice.current.userInterfaceIdiom == .pad`) una terza riga:
icona `ipad.landscape`, «Pensata per iPad» — «Settimana a tutto schermo e
schermate su due colonne in orizzontale.». Testi App Store «Novità»
aggiornati con la stessa voce.

## Verifica

- XCTest: `DeviceLayoutTests` (soglie e size class), `WeekGridMetricsTests`
  (larghezza colonne, minimo, giorni 5/6).
- Hook solo DEBUG `-FMTOrientation landscape|portrait` che chiede la
  rotazione con `UIWindowScene.requestGeometryUpdate`.
- Screenshot iPad Pro 11'' verticale e orizzontale (Orario Settimana/Adesso,
  Diario, Voti, banner) e iPhone 18 Pro (regressione: identico a prima).
