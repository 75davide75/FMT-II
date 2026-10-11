# FMT 2.2 — Inglese + scelta lingua — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App interamente traducibile in inglese con scelta Italiano/English in Impostazioni e lingua iniziale in base al paese App Store.

**Architecture:** String Catalog con italiano come lingua sorgente; `LanguageSettings` decide la lingua e la propaga con `.environment(\.locale)` + `.id` alla radice; le stringhe fuori da `Text` usano `L()` col bundle `.lproj` della lingua scelta. Regola iniziale pura e testata.

**Tech Stack:** SwiftUI iOS 17, String Catalog, StoreKit 2 (`Storefront`), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-11-english-localization-design.md`

## Global Constraints

- Italiano invariato; nessun cambio di funzioni/stile oltre la riga Lingua.
- `appLanguage` locale al dispositivo (mai in `SettingsSync.syncedKeys`).
- Paesi italiani: storefront ITA/SMR/VAT, regione IT/SM/VA.
- Utenti esistenti (tutorial fatto prima della 2.2) → italiano.

## Review Focus

1. Cambio lingua con un foglio aperto → nessun crash, foglio chiuso o tradotto (verifica a schermo).
2. Testi con numeri (plurali, «%lld lezioni») corretti in inglese (test sul bundle).
3. Orari importati da PDF (giorni salvati in italiano) mostrati in inglese (test `DayId.displayName`).
4. Utente che aggiorna dalla 2.1.1 fuori Italia → resta italiano (test regola).
5. Nessuna chiave senza traduzione inglese (test completezza).

---

### Task 1: Infrastruttura lingua + prova tecnica cambio al volo

**Files:** Create `FMT II/Services/AppLanguage.swift`, `FMT II/Localizable.xcstrings` (poche chiavi di prova); Modify `FMT II.xcodeproj/project.pbxproj` (developmentRegion it, knownRegions it/en/Base), `FMT II/FMT_IIApp.swift` (locale da LanguageSettings); Test `FMT IITests/LanguageTests.swift`.

**Produces:** `enum AppLanguage { case italian, english; nativeName; locale(region:); bundle; static func initial(storefrontCountry:region:isExistingUser:) }`, `LanguageSettings.shared` (`@Published language`, `func choose(_:)`, `func refineFromStorefront() async`), `func L(_ key: String.LocalizationValue) -> String`.

- [ ] Test regola: existing → it; ITA/SMR/VAT → it; USA/CHE/GBR → en; nil storefront + region IT → it; nil + DE → en; nil/nil → en; locale(region:) it → it_IT, en con regione GB → en_GB, en con regione IT → en_US.
- [ ] RED → implementazione → GREEN.
- [ ] Prova: chiave «Orario» e «Diario» tradotte nel catalogo; avvio con `-appLanguage en` → screenshot: barra sezioni in inglese (Text con environment locale) e un testo via `L()`; poi cambio lingua al volo da codice di debug e screenshot. Esito nel ledger (Ruling se serve il ripiego riavvio).
- [ ] Commit.

### Task 2: Codice pronto per la traduzione

**Files:** Modify componenti con parametri testuali (Theme.swift `AuroraTitle`, `AuroraChip`; SettingsView `header`/`row`; MainScheduleView `StatPill`; ManualView `ManualEntry`; WhatsNewBanner `feature`; altri trovati con grep), modelli (`GradeType.label`, `NoteTaskType.label`, `PeriodSystem`, `CloudSyncManager.Status.label`, messaggi `ScheduleRejectReason`, `NotificationManager`), `Models.swift` (`DayId.displayName`), formatter con `it_IT` fisso → locale della lingua.

- [ ] Test: `DayId.monday.displayName(in: .english) == "Monday"`, `(.italian) == "Lunedì"`.
- [ ] Parametri `String` dei componenti → `LocalizedStringKey` (overload `String` per valori dinamici → `Text(verbatim:)`); etichette dei modelli → `L("…")`; viste che mostrano `day.label`/`lesson.dayLabel` → `displayName`.
- [ ] Suite verde, italiano identico (screenshot iPhone Orario/Diario/Voti/Impostazioni a confronto). Commit.

### Task 3: Estrazione e traduzione completa

**Files:** `FMT II/Localizable.xcstrings`; Test `FMT IITests/LocalizationCompletenessTests.swift`.

- [ ] `xcodebuild -exportLocalizations -project "FMT II.xcodeproj" -localizationPath <tmp> -exportLanguage en` → elenco chiavi (XLIFF).
- [ ] Traduzione inglese di tutte le chiavi secondo il glossario della spec (script che scrive il catalogo JSON con stato `translated`), plurali dove serve.
- [ ] Test completezza: per ogni chiave del catalogo copiato nel bundle di test (o letto dal bundle `en.lproj` compilato) esiste un valore inglese diverso dalla chiave, salvo nomi propri/simboli in una lista di eccezioni.
- [ ] Suite verde. Commit.

### Task 4: Riga Lingua + lingua iniziale

**Files:** Modify `SettingsView.swift` (sezione Aspetto), `ContentView.swift`/`FMT_IIApp.swift` (avvio), `SettingsSync` invariato.

- [ ] Riga «Lingua» Aurora con menu Italiano / English → `LanguageSettings.shared.choose`.
- [ ] Avvio: se `appLanguage` assente → `initial(storefrontCountry: nil, region:…, isExistingUser: hasSeenTutorial già true)`, poi `refineFromStorefront()` (solo primo avvio, solo se non scelta a mano).
- [ ] Test: `SettingsSync.syncedKeys` non contiene `appLanguage`.
- [ ] Suite verde; screenshot cambio lingua. Commit.

### Task 5: Banner, Novità, manuale

- [ ] Riga banner `globe` «Italiano e inglese» / «Scegli la lingua in Impostazioni → Aspetto.»; Novità IT/EN; voce manuale.
- [ ] Commit.

### Task 6: Verifica finale

- [ ] Screenshot inglese iPhone (Orario Adesso/Settimana, Diario, Voti, Impostazioni, editor nota, banner) e iPad (verticale/orizzontale via UI test con `-appLanguage en`); italiano invariato.
- [ ] Revisione finale indipendente, correzioni, push sulla PR.
