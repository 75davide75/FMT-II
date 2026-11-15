# FMT 2.2 — App in inglese + scelta della lingua — design

Data: 2026-10-11. Fonte: richiesta utente («tradurre l'intera app in inglese,
nelle impostazioni scegliere tra italiano e inglese; in base al paese in cui
viene scaricata avviarla in italiano (Italia) o in inglese (altri paesi)») +
risposte: chi aggiorna dalla 2.1.1 resta in italiano; paesi italiani = Italia,
San Marino, Vaticano. Parte della 2.2 (banner Novità).

## Vincoli

- Italiano identico a oggi (testi e formati).
- Nessun cambio di funzionalità, stile o navigazione oltre alla riga Lingua.
- La lingua è una preferenza del dispositivo: non sincronizzata con iCloud.

## Catalogo

- `FMT II/Localizable.xcstrings` (String Catalog). Lingua sorgente: italiano
  (`developmentRegion = it`, `knownRegions = (it, en, Base)`); le chiavi sono i
  testi italiani attuali. Ogni chiave ha la traduzione inglese.
- Estrazione completa con `xcodebuild -exportLocalizations`, traduzione,
  reimport. Interpolazioni come formati (`%lld lezioni`).
- Componenti con parametri testuali (header/row Impostazioni, AuroraTitle,
  StatPill, AuroraChip, ManualEntry, voci banner…) accettano
  `LocalizedStringKey` per i letterali.
- Stringhe fuori da `Text` (etichette dei modelli, stato iCloud, messaggi
  dell'import, notifiche, titoli calcolati) passano da `L("…")`
  (`String(localized:bundle:)` col bundle della lingua scelta).
- Giorni: la visualizzazione usa `DayId.displayName` tradotto; i `dayLabel`
  salvati (italiano) restano invariati nei dati.

### Glossario

Orario/Diario/Voti → Timetable/Planner/Grades; Adesso/Giorno/Settimana →
Now/Day/Week; Docente/Classe/Materia → Teacher/Class/Subject;
Compito/Verifica/Interrogazione → Homework/Test/Oral test; Giustifica →
Excused; Quadrimestre/Trimestre → Semester/Trimester; Voto sufficiente →
Passing grade; Orale/Scritto/Pratico → Oral/Written/Practical; Media →
Average; Impostazioni → Settings; Dati orario → Timetable data.

## Lingua dell'app

- `AppLanguage` (`.italian` "it", `.english` "en") con `nativeName`,
  `locale(region:)` (it_IT; en_<regione del dispositivo, US se italiana o
  assente>) e `bundle` (lproj).
- `LanguageSettings` (ObservableObject, @MainActor): lingua corrente salvata in
  `appLanguage` (UserDefaults, locale). Alla radice:
  `.environment(\.locale, language.locale)` e `.id(language)` → cambio
  immediato di tutte le viste. Si aggiorna anche `AppleLanguages` così i
  componenti di sistema seguono dal prossimo avvio.
- Regola iniziale (pura, `AppLanguage.initial(storefrontCountry:region:isExistingUser:)`):
  utente esistente (tutorial già fatto prima della 2.2) → italiano; paese
  App Store (StoreKit `Storefront`, ISO alpha-3) ITA/SMR/VAT → italiano, altro
  → inglese; senza storefront si usa la regione del dispositivo (IT/SM/VA);
  nessun dato → inglese. La scelta manuale vince sempre.
- All'avvio: regione subito (sincrona), poi lo storefront asincrono può
  correggere la lingua solo al primo avvio e solo se l'utente non l'ha scelta.

## Impostazioni

Sezione «Aspetto»: riga Aurora «Lingua» con selettore Italiano / English.

## Banner Novità

Nuova riga (icona `globe`): «Italiano e inglese» — «Scegli la lingua in
Impostazioni → Aspetto.» (EN: «Italian and English» — «Choose the language in
Settings → Appearance.»). Novità App Store IT/EN aggiornate.

## Verifica

- XCTest: regola iniziale, locale per lingua, completezza del catalogo
  (ogni chiave tradotta in inglese, controllato sul bundle `en.lproj`).
- Prova tecnica iniziale: cambio lingua al volo su `Text` e su `L()`.
  Ripiego se `Text` non segue l'environment: riavvio richiesto dopo il cambio.
- Screenshot inglese iPhone e iPad delle schermate principali; italiano
  invariato.
