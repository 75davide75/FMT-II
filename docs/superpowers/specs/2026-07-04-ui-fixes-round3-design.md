# UI/UX round 3 — design

Data: 2026-07-04. Fonte: richieste utente (elenco dettagliato) + design system
"Aurora Glass" (canvas «Riprogettazione interfaccia app stile Apple», schermate
3d "Crea orario (foglio zoomabile)" e 2c "Voti"; token nel README del design
handoff).

**Assunzioni prese in autonomia** (l'utente non ha risposto alle domande):

1. «tasto che non permette di rinominare la classe» → interpretato come *tasto
   che permette di rinominare* nel foglio «Impostazioni orario» del builder
   (probabile refuso di dettatura); il nome classe resta obbligatorio all'avvio.
2. Diario con date reali: le note esistenti con solo giorno settimanale vengono
   migrate alla **prossima occorrenza** di quel giorno rispetto a oggi.

## A. Builder «Crea orario» (ScheduleBuilderView)

- **Nome classe obbligatorio**: all'apertura senza classe, prompt che non si
  può aggirare (OK con campo vuoto → si ripresenta; Annulla chiude il builder).
- **Rinomina classe**: nuovo tasto nel foglio «Impostazioni orario» (oltre che
  nel menu classe) che apre l'alert di rinomina esistente.
- **Redesign 3d**: sfondo aurora Orario (radiali cilestino→blu su base scura),
  griglia dentro card glass (radius 22, bordo bianco 11%); intestazioni giorno
  pill scure (testo #DCE7FF su bianco 7%); celle piene = chip tinta materia
  (bg 13%, bordo 28%, testo tinta chiara 800), celle vuote = bordo
  tratteggiato rgba(148,183,255,0.24) con "+"; pill classe in alto a sinistra
  con bordo gradiente (#38BDF8→#4E7CF6); hint «Pizzica per lo zoom · trascina
  il foglio».
- **Salva**: pill gradiente Orario (#38BDF8→#4E7CF6), testo bianco 750, ombra
  `0 6px 18px rgba(56,132,246,0.45)`, in alto a destra, ben visibile
  (disabilitato = opacità 0.4).
- **Zoom & pan**: la griglia è un "foglio" zoomabile con pinch (UIScrollView
  representable con contenuto SwiftUI, zoom 0.5×–2×, pan libero).
  - **In basso a sinistra**: controllo zoom pill glass «– 80% +».
  - **In basso a destra**: minimappa (proporzioni del foglio, finestra visibile
    evidenziata con bordo #7DD3FC luminoso) — visibile **solo** quando il
    foglio è zoomato (zoom > 1.02 o pan attivo fuori vista) — serve per
    orientarsi tra le classi/griglia.
- **Contrasto**: testi celle e orari secondo i token 3d (niente grigi deboli su
  sfondo chiaro; in light mode equivalenti a contrasto pieno).

## B. Completamento orario (ImportReviewView, missing == .subject)

- **Autocomplete materie**: sotto ogni campo attivo compaiono suggerimenti
  (materie comuni italiane + materie già usate); **Invio inserisce la prima**
  in elenco.
- **Auto-propagazione per docente**: confermata la materia per una lezione di
  un docente, la stessa materia si precompila in **tutti gli altri campi
  vuoti** delle lezioni di quel docente (marcati come "auto").
- **Cambio di un campo auto-compilato**: alla modifica compare un alert
  «ROSSI insegna più di una materia?» — *Sì* → il campo diventa modificabile e
  la modifica non tocca gli altri; *No* → il campo torna al valore propagato.

## C. Bordi tagliati nel context menu

- Le celle con bordo arrotondato usate come sorgente di `contextMenu`
  (lezione in DayView, righe note Diario, righe voto) ricevono
  `.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: r,
  style: .continuous))` con lo stesso raggio della card, così la preview non
  taglia gli angoli del bordo.

## D. Impostazioni

- **Zona di rischio**: riprogettata nello stesso linguaggio delle altre
  sezioni: header `ZONA DI RISCHIO` in maiuscoletto (stile header ma rosa/rosso),
  righe su card `sectionCard` con icone a badge gradiente rosso/rosa
  (stile `SettingsView.row`), testo rosso per le azioni distruttive. Niente più
  card grigia con bordo tratteggiato.
- **Tema automatico**: il tema viene applicato a livello di finestra
  (`UIWindow.overrideUserInterfaceStyle`) da un unico punto osservando
  `appearanceMode`; rimossi i `preferredColorScheme` sparsi. Così passando a
  «Automatico» con telefono in scuro la UI (Impostazioni incluse) si aggiorna
  subito, senza chiudere/riaprire.
- **Versione**: `MARKETING_VERSION` 1.2 → **2.1.0** (la riga «Versione» legge
  già `CFBundleShortVersionString`).

## E. Diario

- **Date reali**: `Note.date: Date?` (giorno+mese+anno). Migrazione al load:
  nota con `day` settimanale e senza `date` → prossima occorrenza del giorno.
  Il picker «Giorno» nei Dettagli diventa un DatePicker a data completa.
- **Barra giorni infinita**: scorre senza limite avanti e indietro (finestra
  iniziale ±2 anni, LazyHStack; parte centrata su oggi). Tocco su una data →
  salto alle note di quella data. I puntini per tipo si calcolano per data.
- **Conflitto di scorrimento**: scorrere la barra giorni (o i filtri) NON deve
  trascinare il pager delle sezioni: il pan orizzontale interno ha priorità
  (gesture esclusiva sull'area della barra / `scrollDisabled` sul pager durante
  il drag interno).
- **Niente eliminazione con swipe**: rimosso il bottone Elimina dalle
  `swipeActions` (resta Archivia/Ripristina); eliminare si fa dal menu con
  pressione prolungata (o selezione multipla).
- **Empty state contestuale**: con filtro tipo attivo «Nessuna verifica in
  programma» / «Nessun compito» / «Nessuna interrogazione»; con filtro tag
  «Nessuna nota per SUBJ/DOCENTE/CLASSE»; con ricerca resta «Nessun risultato…»;
  senza filtri resta «Diario vuoto».
- **Raggruppamento**: le sezioni della lista sono per data reale in ordine
  cronologico («Oggi», «Domani», poi «Venerdì 10 luglio» ecc.), gruppo finale
  «Senza data» per note prive di data.

## F. Voti (design 2c)

- **FAB «+»** in basso a destra, identico per posizione/dimensioni a quello del
  Diario, ma con gradiente Voti (#8B5CF6 → #F472B6 → #F8A87E) e ombra viola/rosa.
- **Toolbar**: rimossi «+» e il tasto Materie; resta **solo** `ellipsis.circle`
  con menu: «Materie» (push alla lista materie) e «Impostazioni» (sheet
  Impostazioni condivise) — Impostazioni sempre presente, anche con orario.
- Resto della schermata già conforme a 2c (anello media, barre periodo, bolle
  ultimi voti, righe con barra colore, chip tipo, trend).

## G. Orario

- **Header fisso**: `AuroraTitle("Orario", sottotitolo)` resta fissato in cima;
  il resto (strip statistiche, pannello, viste) scorre **sotto** di esso (il
  titolo esce dalla ScrollView; leggera dissolvenza/materiale sotto il titolo
  per leggibilità).
- **Toolbar**: `ellipsis.circle` unico in alto a destra con menu: «Condividi
  orario» (ShareLink), «Dati orario» (editor DB con disclaimer),
  «Impostazioni».
- **Dimensione testo Enorme**: il selettore Orario/Diario/Voti scala con
  `@ScaledMetric`; a xxxLarge finiva sopra i bottoni trailing rendendoli non
  toccabili. Fix: larghezza del selettore limitata (cap alla larghezza
  disponibile) così i tasti a destra restano raggiungibili e funzionanti.

## H. Tre pallini uniformi

- Tutte e tre le sezioni hanno lo stesso identico bottone `ellipsis.circle` in
  alto a destra; dentro: azioni specifiche della sezione + «Impostazioni»
  (condivise) sempre presente in tutte e tre.

## Architettura / note tecniche

- Tema: nuovo helper `AppearanceManager` (funzione che applica
  `overrideUserInterfaceStyle` a tutte le finestre) chiamato da `ContentView`
  su `onChange(appearanceMode)` e all'avvio. I sheet non ri-applicano più
  `preferredColorScheme`.
- Zoom builder: `ZoomableSheet` (UIViewRepresentable con `UIScrollView` +
  `UIHostingController`), espone `zoomScale` e `visibleRect` via binding per
  pilotare controllo zoom e minimappa.
- Note: campo `date: Date?` codificato accanto a `day` (retro-compatibile;
  `day` resta per i promemoria settimanali); migrazione in `NotesStore.load()`.
- Nessuna nuova dipendenza. Target iOS 17+ (API già usate: scrollTargetBehavior
  ecc.).

## Test

- Unit: migrazione note (weekday→data), propagazione materia per docente,
  goal/empty-state helpers dove estraibili.
- UI/manuale: build + smoke test su simulatore; verifica dei flussi toccati
  (builder, import parziale, diario, voti, impostazioni tema).
