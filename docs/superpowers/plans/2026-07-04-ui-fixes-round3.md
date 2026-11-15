# UI/UX Round 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementare il round 3 di rifiniture UI/UX di FMT II: tema automatico live, builder orario zoomabile stile 3d, diario con date reali e barra giorni infinita, sezione Voti con FAB, menu «tre pallini» uniforme, fix bordi context-menu, zona di rischio ridisegnata, versione 2.1.0.

**Architecture:** App SwiftUI iOS 17+ a file-per-vista (`FMT II/Views/*.swift`), stores ObservableObject (`Models/*.swift`), design system in `Views/Theme.swift`. Le modifiche sono per lo più chirurgiche alle viste esistenti; le uniche novità strutturali sono `Note.date` (con migrazione), un `UIScrollView` representable per lo zoom del builder e l'applicazione del tema via `UIWindow.overrideUserInterfaceStyle`.

**Tech Stack:** SwiftUI, UIKit bridge, XCTest. Build/test: `xcodebuild -project "FMT II.xcodeproj" -scheme "FMT II" -destination 'platform=iOS Simulator,name=iPhone 15 Pro'`.

## Global Constraints

- Target iOS 17: niente API iOS 18+ (`Color.mix`, `onScrollPhaseChange`…). `glassEffect` solo dietro `#available(iOS 26.0, *)` già esistente.
- Design token Aurora Glass (Theme.swift + README handoff): gradiente Orario `#38BDF8→#4E7CF6`, Diario `#4E7CF6→#8B5CF6`, Voti `#8B5CF6→#F472B6→#F8A87E`.
- Testi UI in italiano.
- Commit frequenti; mai committare file non correlati già modificati nel working tree (usare `git add` mirato sui file toccati dal task).
- Comando test unit: `xcodebuild test -project "FMT II.xcodeproj" -scheme "FMT II" -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:"FMT IITests" 2>&1 | tail -20`.

---

### Task 1: Tema automatico applicato alla finestra

**Files:**
- Modify: `FMT II/ContentView.swift` (righe 38–44, 79)
- Modify: `FMT II/Views/SettingsView.swift` (righe 49–55, 178)

**Interfaces:**
- Produces: `func applyAppearanceMode(_ mode: String)` (globale, in ContentView.swift) — usata solo internamente.

- [ ] **Step 1: helper + hook**

In `ContentView.swift`, sostituire la computed `preferredColorScheme` (righe 38–44) con:

```swift
/// Applica il tema a livello di finestra: a differenza di
/// `preferredColorScheme(nil)`, tornare ad «Automatico» segue subito il
/// sistema anche negli sheet già aperti.
func applyAppearanceMode(_ mode: String) {
    let style: UIUserInterfaceStyle = switch mode {
    case "light": .light
    case "dark": .dark
    default: .unspecified
    }
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
        for window in scene.windows { window.overrideUserInterfaceStyle = style }
    }
}
```

Rimuovere `.preferredColorScheme(preferredColorScheme)` (riga 79) e aggiungere al `Group` principale:

```swift
.onAppear { applyAppearanceMode(appearanceMode) }
.onChange(of: appearanceMode) { _, mode in applyAppearanceMode(mode) }
```

In `SettingsView.swift`: eliminare la computed `preferredColorScheme` (49–55) e `.preferredColorScheme(preferredColorScheme)` (riga 178).

- [ ] **Step 2: build**

Run: `xcodebuild build -project "FMT II.xcodeproj" -scheme "FMT II" -destination 'platform=iOS Simulator,name=iPhone 15 Pro' 2>&1 | tail -3` → `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit** `git add "FMT II/ContentView.swift" "FMT II/Views/SettingsView.swift" && git commit -m "fix: tema Automatico applicato subito via overrideUserInterfaceStyle"`

### Task 2: Versione 2.1.0

**Files:**
- Modify: `FMT II.xcodeproj/project.pbxproj` (righe 413, 443: `MARKETING_VERSION = 1.2;`)

- [ ] Sostituire le **due** occorrenze `MARKETING_VERSION = 1.2;` con `MARKETING_VERSION = 2.1.0;` (lasciare le 1.0 dei target di test). Build ok, commit `chore: versione 2.1.0`.

### Task 3: Bordi non tagliati nelle preview dei context menu

**Files:**
- Modify: `FMT II/Views/DayView.swift` (bottone lezione, riga ~150)
- Modify: `FMT II/Views/NotesView.swift` (riga nota, prima di `.contextMenu` riga ~392)
- Modify: `FMT II/Views/GradesView.swift` (riga voto, prima di `.contextMenu` riga ~171)

- [ ] In ciascun punto, subito **prima** del `.contextMenu`, aggiungere il contentShape della preview con lo stesso raggio della card:

```swift
// DayView (raggio 10):
.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10, style: .continuous))
// NotesView (le card nota hanno raggio 22):
.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
// GradesView (auroraCard radius 14):
.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
```

- [ ] Build ok, commit `fix: la preview del context menu segue gli angoli arrotondati delle card`.

### Task 4: Zona di rischio in stile Aurora

**Files:**
- Modify: `FMT II/Views/SettingsView.swift` (`dangerZoneSection` righe 422–444, `DangerZoneView` righe 542–608, `header` riga 183)

- [ ] **Step 1**: dare a `header` un colore parametrico:

```swift
static func header(_ text: String, tint: Color = Color(hex: "#A5B4FC")!) -> some View {
    Text(text.uppercased())
        .font(.system(size: 10.5, weight: .heavy))
        .kerning(1)
        .foregroundStyle(tint)
        .textCase(nil)
}
```

- [ ] **Step 2**: eliminare `DangerZoneView` e riscrivere `dangerZoneSection` come Section di righe standard (stesse card delle altre sezioni, icone a badge gradiente rosso, testo rosso):

```swift
@ViewBuilder
private var dangerZoneSection: some View {
    if store.schedule != nil || notesStore != nil || gradesStore != nil {
        Section {
            if store.schedule != nil {
                Button {
                    if store.schedule?.edited == true { showOverwriteWarn = true }
                    else {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showFilePicker = true }
                    }
                } label: {
                    Self.row("Cambia PDF", icon: "arrow.triangle.2.circlepath", "#FB923C")
                        .foregroundStyle(.primary)
                }
                Button(role: .destructive) { showClearConfirmation = true } label: {
                    Self.row("Rimuovi orario", icon: "trash.fill", "#FB7185")
                        .foregroundStyle(Color(hex: "#FDA4AF")!)
                }
            }
            if notesStore != nil {
                Button(role: .destructive) { showDeleteNotesConfirm = true } label: {
                    Self.row("Cancella tutto il diario", icon: "trash.fill", "#F43F5E")
                        .foregroundStyle(Color(hex: "#FDA4AF")!)
                }
            }
            if gradesStore != nil {
                Button(role: .destructive) { showDeleteGradesConfirm = true } label: {
                    Self.row("Cancella tutti i voti", icon: "trash.fill", "#E11D48")
                        .foregroundStyle(Color(hex: "#FDA4AF")!)
                }
            }
        } header: {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "#FB7185")!)
                Self.header("Zona di rischio", tint: Color(hex: "#FB7185")!)
            }
        } footer: {
            Text("Azioni definitive: prima di procedere viene sempre chiesta conferma.")
        }
        .listRowBackground(Color.sectionCard)
    }
}
```

- [ ] Build ok, commit `restyle: zona di rischio coerente con il resto delle impostazioni`.

### Task 5: Menu «tre pallini» uniforme in Orario e Voti + FAB Voti

**Files:**
- Modify: `FMT II/Views/MainScheduleView.swift` (`toolbarContent` righe 204–222)
- Modify: `FMT II/Views/GradesView.swift` (toolbar righe 57–87, body 42–54, `showAllSubjects` già esistente)

**Interfaces:**
- Consumes: `SettingsView`, `SubjectsListView`, `GradeEntrySheet` esistenti.

- [ ] **Step 1 — Orario**: sostituire i due ToolbarItem con un solo menu:

```swift
@ToolbarContentBuilder
var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
        Menu {
            if let url = exportURL {
                ShareLink(item: url,
                          preview: SharePreview("Orario \(schedule.sourceName)",
                                                image: Image(systemName: "calendar.badge.clock"))) {
                    Label("Condividi orario", systemImage: "square.and.arrow.up")
                }
            }
            Button { dbEditTarget = nil; showDBDisclaimer = true } label: {
                Label("Dati orario", systemImage: "slider.horizontal.3")
            }
            Button { showSettings = true } label: {
                Label("Impostazioni", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Altre azioni")
    }
}
```

- [ ] **Step 2 — Voti**: nella toolbar di `GradesView` rimuovere i ToolbarItem con `plus`, `list.bullet.below.rectangle` e `gearshape`; lasciare un solo item:

```swift
ToolbarItem(placement: .topBarTrailing) {
    Menu {
        if !store.grades.isEmpty {
            Button { showAllSubjects = true } label: {
                Label("Materie", systemImage: "list.bullet.below.rectangle")
            }
        }
        Button { showSettings = true } label: {
            Label("Impostazioni", systemImage: "gearshape")
        }
    } label: {
        Image(systemName: "ellipsis.circle")
    }
    .accessibilityLabel("Altre azioni")
}
```

(rimuovere la condizione `scheduleStore.schedule == nil` intorno a Impostazioni: sempre visibile.)

- [ ] **Step 3 — FAB Voti**: aggiungere al `ZStack` principale di `GradesView` (dopo la Group), stesso overlay del Diario ma con gradiente Voti:

```swift
.overlay(alignment: .bottomTrailing) {
    if isActive {
        Button { showGradeEntry = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(
                    LinearGradient(colors: [Color(hex: "#8B5CF6")!, Color(hex: "#F472B6")!, Color(hex: "#F8A87E")!],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: Color(hex: "#C4459E")!.opacity(0.55), radius: 15, y: 7)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 26)
        .accessibilityLabel("Aggiungi voto")
    }
}
```

L'empty state «Tocca +…» resta valido (il + ora è il FAB).

- [ ] Build ok, commit `feat: menu ⋯ uniforme in Orario e Voti, FAB + per i voti`.

### Task 6: Orario — header fisso + fix selettore a testo enorme

**Files:**
- Modify: `FMT II/Views/MainScheduleView.swift` (body righe 112–160)
- Modify: `FMT II/Views/SectionNavigation.swift` (`GlassSectionBar`, righe 161–241)

- [ ] **Step 1 — header fisso**: nel body, estrarre il titolo dalla ScrollView; il contenuto scivola sotto:

```swift
var body: some View {
    ZStack(alignment: .top) {
        ScrollView {
            VStack(spacing: 14) {
                statusStrip
                controlPanel
                if viewMode != .week { timeIndicator }
                // … switch viewMode invariato …
            }
            .padding(.horizontal, 16)
            .padding(.top, headerHeight + 6)
            .padding(.bottom, 32)
        }

        AuroraTitle(title: "Orario", subtitle: orarioSubtitle)
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 10)
            .background {
                // Il contenuto scorre SOTTO il titolo: velo sfumato per leggibilità.
                LinearGradient(colors: [Color(hex: "#05060D")!.opacity(0.92),
                                        Color(hex: "#05060D")!.opacity(0.55), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            }
            .background {
                GeometryReader { g in
                    Color.clear.onAppear { headerHeight = g.size.height }
                        .onChange(of: g.size.height) { _, h in headerHeight = h }
                }
            }
    }
    // … modificatori esistenti invariati …
}
```

con `@State private var headerHeight: CGFloat = 64`. In light mode il velo usa `Color(.systemGroupedBackground)` al posto di `#05060D` (usare `@Environment(\.colorScheme)`).

- [ ] **Step 2 — selettore che non copre i bottoni**: in `GlassSectionBar` limitare la larghezza scalata: dopo il calcolo di `segWidth` usare una larghezza effettiva

```swift
private var effectiveSegWidth: CGFloat {
    // A «Enorme» il selettore sfonda e copre i bottoni a destra: cap alla
    // larghezza che lascia sempre ~120pt liberi nella barra di navigazione.
    let available = UIScreen.main.bounds.width - 120
    return min(segWidth, available / CGFloat(max(titles.count, 1)))
}
```

e sostituire ogni uso di `segWidth` nel body/pill con `effectiveSegWidth`.

- [ ] Build ok; smoke test manuale (testo Enorme → il menu ⋯ resta toccabile). Commit `fix: header Orario fisso e selettore sezioni che non copre più la toolbar`.

### Task 7: Diario — modello con data reale + migrazione (TDD)

**Files:**
- Modify: `FMT II/Models/NoteModel.swift`
- Create: `FMT IITests/NoteDateTests.swift`

**Interfaces:**
- Produces: `Note.date: Date?`; `func nextOccurrence(of day: DayId, from now: Date) -> Date` (globale); `NoteCreationContext.date: Date?`; migrazione in `NotesStore.load()`.

- [ ] **Step 1: test che falliscono**

```swift
import XCTest
@testable import FMT_II

final class NoteDateTests: XCTestCase {
    // 2026-07-04 è un sabato.
    private let saturday = ISO8601DateFormatter().date(from: "2026-07-04T10:00:00Z")!

    func testNextOccurrenceSameDayIsToday() {
        let d = nextOccurrence(of: .saturday, from: saturday)
        XCTAssertTrue(Calendar.current.isDate(d, inSameDayAs: saturday))
    }

    func testNextOccurrenceForward() {
        let d = nextOccurrence(of: .monday, from: saturday)   // lunedì 6 luglio
        XCTAssertEqual(Calendar.current.component(.day, from: d), 6)
        XCTAssertEqual(Calendar.current.component(.weekday, from: d), 2)
    }

    func testDateRoundTripCodable() throws {
        var n = Note(); n.date = saturday
        let decoded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(decoded.date?.timeIntervalSince1970 ?? 0,
                       saturday.timeIntervalSince1970, accuracy: 1)
    }

    func testLegacyNoteMigratesToNextOccurrence() {
        var n = Note(); n.day = DayId.friday.rawValue; n.date = nil
        let migrated = n.migratingDate(from: saturday)        // venerdì 10 luglio
        XCTAssertNotNil(migrated.date)
        XCTAssertEqual(Calendar.current.component(.day, from: migrated.date!), 10)
    }
}
```

- [ ] **Step 2**: run → FAIL (`date`/`nextOccurrence` non definiti).

- [ ] **Step 3: implementazione**

In `NoteModel.swift`:

```swift
/// Prossima occorrenza (oggi inclusa) del giorno settimanale a partire da `now`.
func nextOccurrence(of day: DayId, from now: Date = Date()) -> Date {
    let cal = Calendar.current
    let targetIdx = weekOrder.firstIndex(of: day) ?? 0
    let todayIdx = weekOrder.firstIndex(of: todayDayId(now)) ?? 0
    let delta = (targetIdx - todayIdx + 7) % 7
    return cal.startOfDay(for: cal.date(byAdding: .day, value: delta, to: now) ?? now)
}
```

In `Note`: proprietà `var date: Date? = nil`, decodifica `date = try c.decodeIfPresent(Date.self, forKey: .date)` nel decoder custom, e:

```swift
/// Migrazione: nota vecchia con solo giorno settimanale → prossima occorrenza.
func migratingDate(from now: Date = Date()) -> Note {
    guard date == nil, let d = dayId else { return self }
    var n = self
    n.date = nextOccurrence(of: d, from: now)
    return n
}
```

In `NoteCreationContext`: aggiungere `var date: Date?`; init nuovo `date: Date? = nil` e, per l'init da nota esistente, `self.date = existingNote.date`. In `NotesStore.load()`:

```swift
notes = decoded.map { $0.migratingDate() }
if decoded.contains(where: { $0.date == nil && $0.dayId != nil }) { save() }
```

- [ ] **Step 4**: run test → PASS. Commit `feat: le note del diario hanno una data di calendario (con migrazione)`.

### Task 8: Diario — editor con data completa, raggruppamento per data, niente swipe-elimina, empty state contestuali

**Files:**
- Modify: `FMT II/Views/NotesView.swift`
- Modify: `FMT II/Views/MainScheduleView.swift` (`addNoteContext`), `FMT II/Views/DayView.swift`/`NowView.swift`/`WeekView.swift` non cambiano firma (il contesto converte lui).

**Interfaces:**
- Consumes: `Note.date`, `nextOccurrence(of:from:)` dal Task 7.
- Produces: raggruppamento `notesByDate: [(id: String, label: String, date: Date?, notes: [Note])]`.

- [ ] **Step 1 — editor**: in `NoteEditorSheet` sostituire lo state `day: String?` con `noteDate: Date?` (mantenendo `day` derivato al salvataggio). Riga «Giorno» dei `metadataFields`:

```swift
HStack {
    Label("Giorno", systemImage: "calendar").font(.callout)
    Spacer()
    if let binding = Binding($noteDate) {
        DatePicker("", selection: binding, displayedComponents: .date)
            .labelsHidden()
        Button { noteDate = nil } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    } else {
        Button("Aggiungi") { noteDate = Calendar.current.startOfDay(for: Date()) }
            .font(.callout).foregroundStyle(.tint)
    }
}
```

`setupInitialState`: `noteDate = note.date` (nota esistente) / `noteDate = context.date ?? context.day.map { nextOccurrence(of: $0) }` (nuova). `save()`: `note.date = noteDate; note.day = noteDate.map { dayRaw(of: $0) } ?? day` dove

```swift
private func dayRaw(of date: Date) -> String { todayDayId(date).rawValue }
```

- [ ] **Step 2 — raggruppamento per data**: sostituire `notesByDay` con:

```swift
private var notesByDate: [(id: String, label: String, date: Date?, notes: [Note])] {
    let cal = Calendar.current
    var groups: [Date: [Note]] = [:]
    var noDate: [Note] = []
    for note in displayNotes {
        if let d = note.date { groups[cal.startOfDay(for: d), default: []].append(note) }
        else { noDate.append(note) }
    }
    var result = groups.keys.sorted().map { day in
        (id: "d-\(day.timeIntervalSince1970)", label: dateGroupLabel(day), date: Optional(day),
         notes: groups[day]!.sorted { ($0.time ?? "") < ($1.time ?? "") })
    }
    if !noDate.isEmpty { result.append((id: "nodate", label: "Senza data", date: nil, notes: noDate)) }
    return result
}

private func dateGroupLabel(_ day: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(day) { return "Oggi" }
    if cal.isDateInTomorrow(day) { return "Domani" }
    if cal.isDateInYesterday(day) { return "Ieri" }
    let f = DateFormatter(); f.locale = Locale(identifier: "it_IT")
    f.dateFormat = cal.component(.year, from: day) == cal.component(.year, from: Date())
        ? "EEEE d MMMM" : "EEEE d MMMM yyyy"
    return f.string(from: day).capitalized
}
```

Adattare `ForEach(notesByDate, id: \.id)`, `dayHeader` (pill OGGI quando `cal.isDateInToday(group.date)`), `jumpToDay: Date?` e `nextGroup(after:)` che ora cercano per data (primo gruppo con `date >= target`, altrimenti l'ultimo precedente), e il `proxy.scrollTo(target.id …)`.

- [ ] **Step 3 — niente swipe-elimina**: nelle `swipeActions` della riga rimuovere il `Button(role: .destructive)` Elimina e `allowsFullSwipe: true` → `false` (resta Archivia/Ripristina); l'eliminazione resta nel context menu e nella selezione multipla.

- [ ] **Step 4 — empty state contestuali**: in `emptyState`, prima del ramo ricerca:

```swift
} else if let t = taskFilter {
    Image(systemName: t.icon).font(.system(size: 56)).foregroundStyle(.quaternary)
    Text(t == .verifica ? "Nessuna verifica in programma"
         : t == .compito ? "Nessun compito in programma"
         : "Nessuna interrogazione in programma")
        .font(.title3.bold())
    Text("Le note con questa etichetta compariranno qui.")
        .font(.callout).foregroundStyle(.secondary)
        .multilineTextAlignment(.center).padding(.horizontal, 40)
} else if let f = tagFilter {
    Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 56)).foregroundStyle(.quaternary)
    Text("Nessuna corrispondenza").font(.title3.bold())
    Text("Non ci sono note per «\(f.value)».")
        .font(.callout).foregroundStyle(.secondary)
        .multilineTextAlignment(.center).padding(.horizontal, 40)
}
```

- [ ] Build ok, commit `feat: diario con data completa, gruppi per data, empty state contestuali, niente swipe-elimina`.

### Task 9: Diario — barra dei giorni infinita (e fix conflitto col pager)

**Files:**
- Modify: `FMT II/Views/NotesView.swift` (`diarioHeader`, `weekTile`, `dayDots`)

**Interfaces:**
- Consumes: `notesByDate` (Task 8).

- [ ] **Step 1**: sostituire la striscia LUN–DOM con una striscia di **date reali** infinita (finestra ±730 giorni, LazyHStack → mai un bordo da cui il pan «scappa» verso il pager, che era la causa del doppio scorrimento):

```swift
@State private var selectedStripDate: Date? = nil
private let stripSpan = 730   // giorni prima/dopo oggi

private var stripDates: [Date] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    return (-stripSpan...stripSpan).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
}

private func dayDots(_ date: Date) -> [Color] {
    let cal = Calendar.current
    var seen = Set<String>(); var colors: [Color] = []
    for n in visibleBase where n.date.map({ cal.isDate($0, inSameDayAs: date) }) == true {
        let key = n.taskType ?? "nota"
        guard seen.insert(key).inserted else { continue }
        colors.append(n.taskType.flatMap(NoteTaskType.init(rawValue:))?.auroraColor ?? plainNoteColor)
    }
    return Array(colors.prefix(3))
}
```

`weekTile(day:)` diventa `dayTile(_ date: Date)` (stesso stile: etichetta = prime 3 lettere del giorno; numero = giorno del mese; evidenziata `selectedStripDate ?? oggi`; bordo violetto se `isDateInToday`). Tocco: `selectedStripDate = date; jumpToDay = date`.

La ScrollView della striscia va inizializzata **centrata su oggi**: `ScrollViewReader` + `.onAppear { stripProxy.scrollTo(startOfToday, anchor: .center) }` e ogni tile con `.id(date)`. Usare `LazyHStack` dentro la ScrollView.

- [ ] **Step 2**: `onChange(of: isActive)` azzera `selectedStripDate = nil` (già fa per gli altri filtri).

- [ ] **Step 3**: smoke test manuale: la barra scorre di anni in entrambe le direzioni senza trascinare il pager; tocco su una data salta al gruppo giusto.

- [ ] Commit `feat: barra dei giorni del diario infinita e senza conflitto col pager`.

### Task 10: Completamento orario — autocomplete + propagazione per docente (TDD sulla logica)

**Files:**
- Modify: `FMT II/Views/ImportReviewView.swift`
- Create: `FMT IITests/SubjectPropagationTests.swift`

**Interfaces:**
- Produces: `func propagateSubject(edits: [String: String], autoFilled: Set<String>, lessons: [Lesson], teacher: String, subject: String, sourceId: String) -> (edits: [String: String], autoFilled: Set<String>)` (globale, in ImportReviewView.swift).

- [ ] **Step 1: test**

```swift
import XCTest
@testable import FMT_II

final class SubjectPropagationTests: XCTestCase {
    private func lesson(_ id: String, teacher: String) -> Lesson {
        Lesson(id: id, className: "5G", teacher: teacher, day: .monday, dayLabel: "Lunedì",
               period: 1, startTime: "08:00", endTime: "09:00", sourcePage: 0, subject: "")
    }

    func testPropagatesToEmptyFieldsOfSameTeacher() {
        let lessons = [lesson("a", teacher: "ROSSI"), lesson("b", teacher: "ROSSI"), lesson("c", teacher: "NERI")]
        let out = propagateSubject(edits: ["a": "Matematica"], autoFilled: [],
                                   lessons: lessons, teacher: "ROSSI", subject: "Matematica", sourceId: "a")
        XCTAssertEqual(out.edits["b"], "Matematica")
        XCTAssertNil(out.edits["c"])
        XCTAssertTrue(out.autoFilled.contains("b"))
        XCTAssertFalse(out.autoFilled.contains("a"))
    }

    func testDoesNotOverwriteManualEdits() {
        let lessons = [lesson("a", teacher: "ROSSI"), lesson("b", teacher: "ROSSI")]
        let out = propagateSubject(edits: ["a": "Matematica", "b": "Fisica"], autoFilled: [],
                                   lessons: lessons, teacher: "ROSSI", subject: "Matematica", sourceId: "a")
        XCTAssertEqual(out.edits["b"], "Fisica")
    }

    func testRefreshesPreviouslyAutoFilled() {
        let lessons = [lesson("a", teacher: "ROSSI"), lesson("b", teacher: "ROSSI")]
        let out = propagateSubject(edits: ["a": "Fisica", "b": "Matematica"], autoFilled: ["b"],
                                   lessons: lessons, teacher: "ROSSI", subject: "Fisica", sourceId: "a")
        XCTAssertEqual(out.edits["b"], "Fisica")
    }
}
```

- [ ] **Step 2**: run → FAIL. **Step 3: implementazione** in ImportReviewView.swift:

```swift
/// Propaga la materia inserita per una lezione a tutte le altre lezioni dello
/// stesso docente, senza toccare i campi modificati a mano dall'utente.
func propagateSubject(edits: [String: String], autoFilled: Set<String>, lessons: [Lesson],
                      teacher: String, subject: String, sourceId: String)
    -> (edits: [String: String], autoFilled: Set<String>) {
    var edits = edits, auto = autoFilled
    for l in lessons where l.teacher == teacher && l.id != sourceId {
        let current = edits[l.id] ?? ""
        if current.isEmpty || auto.contains(l.id) {
            edits[l.id] = subject
            auto.insert(l.id)
        }
    }
    auto.remove(sourceId)
    return (edits, auto)
}
```

- [ ] **Step 4**: run → PASS.

- [ ] **Step 5 — UI**: nel `completionEditor` (ramo `missing == .subject`):
  - state: `@State private var autoFilled: Set<String> = []`, `@State private var multiSubjectTeachers: Set<String> = []`, `@State private var pendingEdit: (lessonId: String, teacher: String, oldValue: String)? = nil`, `@FocusState private var focusedLesson: String?`.
  - Al TextField materia aggiungere `.focused($focusedLesson, equals: lesson.id)`, `.submitLabel(.done)` e:

```swift
.onSubmit {
    var value = edits[lesson.id] ?? ""
    if let first = subjectSuggestions(for: value).first { value = first; edits[lesson.id] = first }
    commitSubject(value, for: lesson)
}
.onChange(of: edits[lesson.id] ?? "") { old, new in
    guard autoFilled.contains(lesson.id), new != old, focusedLesson == lesson.id,
          !multiSubjectTeachers.contains(lesson.teacher), pendingEdit == nil else { return }
    pendingEdit = (lesson.id, lesson.teacher, old)
}
```

  - Sotto il campo con focus, riga di suggerimenti (stile chip come `suggestionsRow` di NotesView) con `subjectSuggestions(for:)` basata su materie comuni + già inserite:

```swift
private static let commonSubjects = [
    "Italiano", "Matematica", "Storia", "Geografia", "Geostoria",
    "Inglese", "Francese", "Spagnolo", "Tedesco", "Latino", "Greco",
    "Scienze", "Scienze naturali", "Biologia", "Chimica", "Fisica",
    "Filosofia", "Storia dell'arte", "Disegno e storia dell'arte",
    "Diritto", "Economia", "Informatica", "Tecnologia",
    "Scienze motorie", "Educazione fisica", "Educazione civica",
    "Religione", "Musica", "Arte e immagine"
]

private func subjectSuggestions(for text: String) -> [String] {
    let q = text.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return [] }
    var seen = Set<String>(); var pool: [String] = []
    for s in edits.values + Self.commonSubjects where !s.isEmpty && seen.insert(s.lowercased()).inserted { pool.append(s) }
    return pool.filter { $0.lowercased().contains(q) && $0.lowercased() != q }.prefix(6).map { $0 }
}

private func commitSubject(_ value: String, for lesson: Lesson) {
    let v = value.trimmingCharacters(in: .whitespaces)
    guard !v.isEmpty else { return }
    autoFilled.remove(lesson.id)
    guard !lesson.teacher.isEmpty else { return }
    let out = propagateSubject(edits: edits, autoFilled: autoFilled, lessons: schedule.lessons,
                               teacher: lesson.teacher, subject: v, sourceId: lesson.id)
    edits = out.edits; autoFilled = out.autoFilled
}
```

  - Alert «più materie»:

```swift
.alert("\(pendingEdit?.teacher ?? "") insegna più di una materia?",
       isPresented: Binding(get: { pendingEdit != nil }, set: { if !$0 { pendingEdit = nil } }),
       presenting: pendingEdit) { p in
    Button("Sì") {
        multiSubjectTeachers.insert(p.teacher)
        autoFilled.remove(p.lessonId)
        pendingEdit = nil
    }
    Button("No", role: .cancel) {
        edits[p.lessonId] = p.oldValue
        pendingEdit = nil
    }
} message: { _ in
    Text("Se sì, puoi assegnare a questa ora una materia diversa; le altre ore restano invariate.")
}
```

  (rendere `pendingEdit` `Identifiable`-friendly con una piccola struct `PendingSubjectEdit: Identifiable` se serve per `presenting`.)
  - Campo evidenziato: testo dei campi `autoFilled` in `.secondary` finché non confermati.

- [ ] Build + test → PASS. Commit `feat: completamento materie con suggerimenti, invio-per-accettare e propagazione per docente`.

### Task 11: Builder — nome classe obbligatorio robusto + rinomina nelle impostazioni

**Files:**
- Modify: `FMT II/Views/ScheduleBuilderView.swift`

- [ ] **Step 1**: nell'alert «Nome della classe» aggiungere un tasto d'uscita esplicito (l'OK con campo vuoto continua a ripresentarlo):

```swift
.alert("Nome della classe", isPresented: $showClassPrompt) {
    TextField("Es. 5GSA", text: $classNameDraft)
    Button("Annulla", role: .cancel) { dismiss() }   // esce dal builder
    Button("OK") {
        commitClassName()
        if selectedClass.isEmpty { DispatchQueue.main.async { showClassPrompt = true } }
    }
} message: {
    Text("Per quale classe stai creando l'orario? (obbligatorio)")
}
```

- [ ] **Step 2**: nel `setupSheet`, aggiungere la sezione Classe con il tasto rinomina:

```swift
Section("Classe") {
    LabeledContent("Classe selezionata", value: selectedClass.isEmpty ? "—" : selectedClass)
    Button {
        renameDraft = selectedClass
        showSetupSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { renamingClass = true }
    } label: {
        Label("Rinomina classe", systemImage: "pencil")
    }
    .disabled(selectedClass.isEmpty)
}
```

- [ ] Build ok, commit `feat: rinomina classe dalle impostazioni orario; nome classe sempre obbligatorio`.

### Task 12: Builder — foglio zoomabile stile 3d (zoom, minimappa, salva a gradiente)

**Files:**
- Create: `FMT II/Views/ZoomableSheetView.swift`
- Modify: `FMT II/Views/ScheduleBuilderView.swift`

**Interfaces:**
- Produces: `ZoomableSheetView<Content: View>` con `init(zoom: Binding<CGFloat>, visibleRect: Binding<CGRect>, minZoom: CGFloat = 0.5, maxZoom: CGFloat = 2, @ViewBuilder content: () -> Content)`; `visibleRect` in coordinate unitarie (0–1) del contenuto.

- [ ] **Step 1 — representable**:

```swift
import SwiftUI
import UIKit

/// UIScrollView con pinch-zoom e pan per contenuto SwiftUI ("foglio" del
/// builder, design 3d). Espone zoom e rettangolo visibile (unitario) per
/// pilotare il controllo zoom e la minimappa.
struct ZoomableSheetView<Content: View>: UIViewRepresentable {
    @Binding var zoom: CGFloat
    @Binding var visibleRect: CGRect
    var minZoom: CGFloat = 0.5
    var maxZoom: CGFloat = 2
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = minZoom
        scroll.maximumZoomScale = maxZoom
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.delegate = context.coordinator

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        context.coordinator.host = host
        scroll.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor)
        ])
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.host?.rootView = content()
        if abs(scroll.zoomScale - zoom) > 0.01, !context.coordinator.isInteracting {
            scroll.setZoomScale(zoom, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableSheetView
        var host: UIHostingController<Content>?
        var isInteracting = false

        init(_ parent: ZoomableSheetView) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host?.view }

        func scrollViewWillBeginZooming(_ s: UIScrollView, with view: UIView?) { isInteracting = true }
        func scrollViewDidEndZooming(_ s: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            isInteracting = false
            DispatchQueue.main.async { self.parent.zoom = scale }
        }
        func scrollViewDidZoom(_ s: UIScrollView) { publish(s) }
        func scrollViewDidScroll(_ s: UIScrollView) { publish(s) }

        private func publish(_ s: UIScrollView) {
            let size = s.contentSize
            guard size.width > 0, size.height > 0 else { return }
            let r = CGRect(x: s.contentOffset.x / size.width,
                           y: s.contentOffset.y / size.height,
                           width: min(s.bounds.width / size.width, 1),
                           height: min(s.bounds.height / size.height, 1))
            DispatchQueue.main.async {
                self.parent.visibleRect = r
                if !self.isInteracting { self.parent.zoom = s.zoomScale }
            }
        }
    }
}
```

- [ ] **Step 2 — ScheduleBuilderView**: sostituire `grid`'s `ScrollView([.horizontal, .vertical])` con il foglio zoomabile dentro una card glass, e aggiungere overlay:

```swift
@State private var zoom: CGFloat = 1
@State private var visibleRect = CGRect(x: 0, y: 0, width: 1, height: 1)

private var sheetGrid: some View {
    ZStack {
        ZoomableSheetView(zoom: $zoom, visibleRect: $visibleRect) {
            gridContent.padding(18)     // l'attuale VStack della griglia
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .auroraCard(radius: 22)

        // Zoom in basso a sinistra
        .overlay(alignment: .bottomLeading) { zoomControl.padding(12) }
        // Minimappa in basso a destra, solo quando il foglio è zoomato
        .overlay(alignment: .bottomTrailing) {
            if zoom > 1.02 { minimap.padding(12) }
        }
    }
    .padding(.horizontal, 14)
    .padding(.bottom, 12)
}

private var zoomControl: some View {
    HStack(spacing: 10) {
        Button { withAnimation { zoom = max(0.5, zoom - 0.25) } } label: {
            Image(systemName: "minus").font(.system(size: 11, weight: .heavy))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.08), in: Circle())
        }
        Text("\(Int((zoom * 100).rounded()))%")
            .font(.system(size: 12.5, weight: .bold)).monospacedDigit()
        Button { withAnimation { zoom = min(2, zoom + 0.25) } } label: {
            Image(systemName: "plus").font(.system(size: 11, weight: .heavy))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.08), in: Circle())
        }
    }
    .foregroundStyle(Color(hex: "#DCE7FF")!)
    .padding(.horizontal, 7).padding(.vertical, 5)
    .background(Color(hex: "#0A0E1C")!.opacity(0.72), in: Capsule())
    .overlay(Capsule().strokeBorder(.white.opacity(0.13), lineWidth: 1))
    .shadow(color: .black.opacity(0.45), radius: 13, y: 5)
    .buttonStyle(.plain)
}

private var minimap: some View {
    GeometryReader { _ in EmptyView() } // placeholder per tenere l'aspect
        .frame(width: 82, height: 60)
        .background(Color(hex: "#0A0E1C")!.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.13), lineWidth: 1))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(hex: "#7DD3FC")!, lineWidth: 1.6)
                .shadow(color: Color(hex: "#7DD3FC")!.opacity(0.45), radius: 6)
                .frame(width: max(14, 82 * visibleRect.width),
                       height: max(10, 60 * visibleRect.height))
                .offset(x: 82 * visibleRect.minX - (82 - 82 * visibleRect.width) / 2,
                        y: 60 * visibleRect.minY - (60 - 60 * visibleRect.height) / 2)
                .animation(.linear(duration: 0.05), value: visibleRect)
        }
        .shadow(color: .black.opacity(0.45), radius: 13, y: 5)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
}
```

(nella minimappa dentro l'overlay disegnare anche la texture a celle: `Grid` 6×3 di rettangolini `white.opacity(0.08/0.14)` come nel design.)

- [ ] **Step 3 — chrome 3d**: nella `setupBar`: pill classe con bordo gradiente (`overlay(Capsule().strokeBorder(LinearGradient(colors: [Color(hex:"#38BDF8")!.opacity(0.7), Color(hex:"#4E7CF6")!.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))`), hint a destra:

```swift
HStack(spacing: 6) {
    Image(systemName: "arrow.up.left.and.arrow.down.right")
        .font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: "#7DD3FC")!)
    Text("Pizzica per lo zoom").font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
}
.padding(.horizontal, 12).padding(.vertical, 6)
.background(.white.opacity(0.06), in: Capsule())
.overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1))
```

Toolbar Salva a gradiente:

```swift
ToolbarItem(placement: .topBarTrailing) {
    Button {
        onSave(applyManualEdits(draft))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    } label: {
        Text("Salva")
            .font(.system(size: 13.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(LinearGradient(colors: [Color(hex: "#38BDF8")!, Color(hex: "#4E7CF6")!],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule())
            .shadow(color: Color(hex: "#3884F6")!.opacity(0.45), radius: 9, y: 4)
    }
    .buttonStyle(.plain)
    .disabled(!canSave)
    .opacity(canSave ? 1 : 0.4)
}
```

Sfondo builder = aurora Orario (`AuroraBackground(section: .orario)` al posto del gradiente attuale su `secondarySystemGroupedBackground`); intestazioni giorno in pill scure `white.opacity(0.07)` bordo `white.opacity(0.10)` testo `#DCE7FF` (in chiaro: `black.opacity(0.05)` / testo `.primary`); colonna orari testo `.secondary` weight 650.

- [ ] Build + smoke test (pinch, zoom control, minimappa che appare solo da zoom > 1). Commit `feat: builder orario come foglio zoomabile con minimappa e salva a gradiente (design 3d)`.

### Task 13: Verifica finale

- [ ] `xcodebuild test … -only-testing:"FMT IITests"` → tutti PASS.
- [ ] Build app + walkthrough manuale su simulatore delle aree toccate (tema, builder, import parziale, diario, voti, orario header, dimensione testo Enorme).
- [ ] Aggiornare i checkbox del piano; commit finale di eventuali ritocchi.
