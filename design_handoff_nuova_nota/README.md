# Handoff: Nuova nota (Diario) — Aurora Glass

## Overview
Riprogettazione delle due schermate di inserimento nota del Diario nell'app scolastica (Orario / Diario / Voti), nello stile "Aurora Glass" definito per l'intera app: sfondo aurora scuro con gradienti blu → violetto, superfici liquid glass, sistema di etichette (chip) colorate.

1. **Scrittura** (`nuova-nota-scrittura.html`) — editor a tutto schermo con barra riepilogo Dettagli sopra la tastiera.
2. **Foglio Dettagli** (`nuova-nota-dettagli.html`) — bottom sheet con tutti i metadati della nota.

## About the Design Files
I file di questo pacchetto sono **riferimenti di design creati in HTML** — prototipi che mostrano l'aspetto e il comportamento voluti, NON codice di produzione da copiare. Il compito è **ricreare questi design nell'ambiente del codebase di destinazione** (SwiftUI — l'app è iOS/iPadOS) usando i suoi pattern: `.ultraThinMaterial`/`.regularMaterial` per il vetro, `LinearGradient`/`RadialGradient` per aurora e accenti, componenti nativi (sheet con detents, TextEditor, DatePicker) dove indicato.

## Fidelity
**High-fidelity (hifi).** Colori, tipografia, spaziature e raggi sono definitivi: ricreare pixel-perfect con i componenti nativi equivalenti. Font: SF Pro (`-apple-system` nei file HTML).

## Screens / Views

### 1. Scrittura (nuova-nota-scrittura.html)
- **Purpose**: scrivere il testo della nota; vedere a colpo d'occhio i dettagli già impostati; salvare.
- **Layout** (viewport di riferimento 402×874, safe-area top 64px):
  - Header (padding orizzontale 18px): pill "Annulla" (glass), titolo centrato "Nuova nota" (16px/750, #F4F6FF), pill "Salva".
  - Area editor `flex:1` (padding 20px 22px): testo 19px/600 #F4F6FF, cursore 2.5×22px #7CA0FF con glow `0 0 8px rgba(124,160,255,0.8)`; placeholder 13px rgba(226,232,255,0.35).
  - Barra Dettagli (margin 0 12px 8px): card glass radius 18px, icona tag violetto + label "Dettagli" (13.5px/700) + chip riepilogo (Tipo colorata, Giorno, Ora neutre) + chevron a destra.
  - Barra formattazione: Aa | B I U S + "Fine" (gradiente testo #7CA0FF→#B49AFF), fondo rgba(12,14,26,0.6) + blur 24px, hairline top rgba(255,255,255,0.08).
  - Tastiera **nativa iOS** (nei file HTML è disegnata solo come riferimento visivo).
- **Componenti chiave**:
  - Pill Annulla: padding 9px 16px, radius 999, 13.5px/650 #DCE4FF, bg rgba(255,255,255,0.07), bordo 1px rgba(255,255,255,0.12), blur 20px.
  - Pill Salva (attiva): stesso ma 750 #FFFFFF, bg `linear-gradient(135deg,#4E7CF6,#8B5CF6)`, ombra `0 6px 18px rgba(105,96,246,0.45)`, luce interna `inset 0 1px 0 rgba(255,255,255,0.3)`. **Disattiva**: opacità 0.4, senza ombra.
  - Chip riepilogo tipo "Nota": 10.5px/650 #7DD3FC, bg rgba(56,189,248,0.14), bordo rgba(56,189,248,0.28), pallino 4px #38BDF8. Chip neutre (Giorno/Ora): #E8EEFFc7 su rgba(255,255,255,0.07), bordo rgba(255,255,255,0.12).

### 2. Foglio Dettagli (nuova-nota-dettagli.html)
- **Purpose**: impostare tipo, giorno, ora, docente, classe, materia e promemoria.
- **Layout**: bottom sheet (radius top 30px) su contenuto retrostante attenuato (header/testo a opacità 0.3–0.4). Sheet: bg `linear-gradient(180deg,rgba(20,23,42,0.92),rgba(12,14,26,0.96))`, bordo 1px rgba(255,255,255,0.13) (senza bottom), blur 30px sat 160%, ombra `0 -20px 50px rgba(2,4,16,0.6)`, padding 10px 18px 26px. Grabber 38×5px rgba(255,255,255,0.22). Header: titolo centrato "Dettagli", pill "Fine" a gradiente (come Salva, padding 7px 15px, 12.5px).
- **Sezioni** (ordine e comportamento):
  1. **Tipo** — label con icona bandierina in squircle 28px violetto; sotto, riga di chip a un tocco (sostituisce il menu): Nessuno (neutra), Verifica (rosa), Compito (ambra), **Nota selezionata** (pill piena `linear-gradient(135deg,#7DD3FC,#38BDF8)`, testo #0B1024 800, ombra `0 5px 14px rgba(56,189,248,0.4)`), Interrogazione (viola). Chip non selezionate: 11.5px/650, tinta al 12% di bg e 26% di bordo, pallino 4px.
  2. **Giorno** — striscia LUN–SAB (flex, gap 5px): celle radius 12px, 11px/700 rgba(226,232,255,0.6) su rgba(255,255,255,0.05); selezionata (VEN): bianco 800 su `linear-gradient(160deg,#4E7CF6,#8B5CF6)`, bordo rgba(255,255,255,0.28), ombra `0 8px 18px rgba(104,92,246,0.5)`.
  3. **Lista campi** (card inset radius 18px, bg rgba(255,255,255,0.05), righe divise da hairline rgba(255,255,255,0.07) indentata a 51px):
     - **Ora**: icona orologio cilestino; valore chip "09:10" (#7DD3FC su rgba(125,211,252,0.12)) + bottone ✕ circolare 20px per azzerare. Tocco sul valore → time picker nativo.
     - **Docente**: icona persona blu; placeholder "Cognome" 13px rgba(226,232,255,0.35). Campo testo con suggerimenti dai docenti esistenti.
     - **Classe**: icona tocco verde; valore chip "2LSA" (#6EE7B7 su rgba(52,211,153,0.12)).
     - **Materia**: icona libro fucsia; placeholder "Es. Matematica".
  4. **Promemoria** — label con icona campanella verde; a destra bottone ＋ circolare 26px a gradiente blu→violetto; sotto, chip rimovibili "Ven · 07:30 ✕", "Gio · 20:00 ✕" (11.5px/700 #6EE7B7 su rgba(52,211,153,0.11), ✕ in cerchietto 16px rgba(255,255,255,0.09)); hint 10.5px rgba(226,232,255,0.4): "Uno o più avvisi settimanali, ciascuno con giorno e ora".
- **Icone campo**: squircle 28px radius 9px, bg tinta al 12–14%, bordo tinta al 26–30%, glifo stroke 2.2 nella tinta chiara. Tinte: Tipo violetto (#C4B5FD), Giorno blu (#93C5FD), Ora cilestino (#7DD3FC), Docente blu (#93C5FD), Classe verde (#6EE7B7), Materia fucsia (#F0ABFC), Promemoria verde (#6EE7B7).

## Interactions & Behavior
- **Salva**: disabilitato (opacità 0.4, nessuna ombra) finché il testo è vuoto; con contenuto anima verso lo stato gradiente (transizione 400ms, `cubic-bezier(0.4,0,0.2,1)`).
- **Barra Dettagli** (tap) → apre il foglio Dettagli come sheet con detent medio/alto; il contenuto retrostante scala leggermente e si attenua (opacità 0.3–0.4).
- **Chip Tipo / celle Giorno**: selezione a un tocco con spring leggero (scale 0.96 → 1, ~300ms); la chip selezionata passa allo stile pieno a gradiente.
- **Ora ✕**: azzera l'ora (torna placeholder). **＋ Promemoria**: aggiunge una chip con picker giorno+ora; ✕ sulla chip la rimuove.
- **Chip riepilogo** nella barra Dettagli si aggiornano live al cambiare dei valori nel foglio.
- Transizioni generali dell'app: dissolvenze di gradienti 750ms `cubic-bezier(0.4,0,0.2,1)`; contenuti che entrano con fade + translateY 14px, 500–560ms.

## State Management
- `noteText: String` (abilita Salva se non vuoto)
- `tipo: enum {nessuno, verifica, compito, nota, interrogazione}` (default nessuno)
- `giorno: enum LUN…SAB`, `ora: Time?` (azzerabile)
- `docente: String?`, `classe: String` (default classe corrente), `materia: String?`
- `promemoria: [(giorno, ora)]` (lista, aggiunta/rimozione)
- Salvataggio → la nota appare nel Diario con le stesse etichette colorate (tipo, materia, ora, docente).

## Design Tokens
- **Aurora Diario (sfondo)**: base `linear-gradient(180deg,#070A15 0%,#05060D 45%,#04050A 100%)` + radiali: 15%/-4% rgba(78,124,246,0.40) · 95%/2% rgba(139,92,246,0.34) · 65%/-8% rgba(125,211,252,0.16). Altre schede: Orario cilestino→blu (#38BDF8→#4E7CF6), Voti violetto→pesca (#8B5CF6→#F472B6→#F8A87E).
- **Gradiente primario Diario**: `linear-gradient(135deg,#4E7CF6,#8B5CF6)`.
- **Vetro**: card `linear-gradient(150deg,rgba(255,255,255,0.10),rgba(255,255,255,0.045))`, bordo rgba(255,255,255,0.13), `backdrop-blur 20–30px saturate(160%)`, luce interna `inset 0 1px 0 rgba(255,255,255,0.10)`, ombra `0 14px 34px rgba(2,4,16,0.5)`.
- **Tinte etichette (tipo)**: Verifica #FB7185 · Compito #F59E0B · Nota #38BDF8 · Interrogazione #A78BFA. Ricetta chip: testo nella variante chiara (es. #FDA4AF), bg tinta 11–15%, bordo tinta 24–30%, pallino 4–5px pieno.
- **Testo**: titoli 32px/800 -0.6px #F4F6FF · titolo barra 16px/750 · corpo 14–14.5px/600–650 #E9EDFF · secondario 12.5–13px rgba(226,232,255,0.55) · hint 10.5px rgba(226,232,255,0.4).
- **Raggi**: pill 999 · card 18–22px · sheet top 30px · squircle icona 9px · celle giorno 12px.
- **Spaziatura**: padding schermo 18px; gap chip 6px; righe lista padding 11px 13px.

## Assets
Nessun asset esterno: icone come SVG stroke inline (equivalenti SF Symbols: flag, calendar, clock, person, graduationcap, book, bell), tutto il resto è CSS.

## Files
- `nuova-nota-scrittura.html` — schermata 1 (statica, apribile nel browser; la tastiera è solo riferimento visivo)
- `nuova-nota-dettagli.html` — schermata 2 (statica)
Il design system completo (tutte le schede, transizioni, icone app) vive nel canvas `Redesign Diario.dc.html` del progetto originale.
