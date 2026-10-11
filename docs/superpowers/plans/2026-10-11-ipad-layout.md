# FMT 2.2 — Layout iPad — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Layout dedicato a iPad (verticale e orizzontale) per Orario, Diario e Voti, senza cambiare funzioni, stile o navigazione.

**Architecture:** Una funzione pura decide la modalità (`compact`/`regular`/`wide`) dalla size class e dalla larghezza della finestra; `ContentView` la calcola e la passa via Environment. Ogni sezione sceglie la disposizione in base alla modalità, riusando le stesse sottoviste. In `.compact` il codice esistente resta l'unico percorso.

**Tech Stack:** SwiftUI iOS 17, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-11-ipad-layout-design.md`

## Global Constraints

- Nessun cambio di funzionalità, stile Aurora o navigazione; iPhone identico.
- Soglie: compatta < 700 pt o size class compatta; regolare 700–999; larga ≥ 1000.
- Settimana iPad: righe 76 pt, colonna ore 60 pt, colonna giorno minima 88 pt.
- Colonna sinistra: Orario 340 pt, Voti 380 pt. Larghezza massima Adesso/Giorno in verticale: 760 pt.
- Testi in italiano.

## Review Focus

1. iPad in Split View/Slide Over (finestra stretta) → layout iPhone, nessun taglio (test `testNarrowIPadWindowIsCompact`).
2. Orario con 6 giorni (sabato) → colonne ancora senza scroll (test `testSixDaysFillWidth`).
3. Finestra appena sotto la larghezza utile → torna lo scroll orizzontale invece di colonne < 88 pt (test `testFallsBackToMinimumWidth`).
4. Diario su iPad: scroll alla data dalla striscia e selezione multipla funzionano nella griglia (verifica a schermo).
5. Rotazione mentre è aperto un foglio → nessun crash (verifica a schermo).

Comando test: `.superpowers/sdd/2026-10-11-ipad-layout/t.sh` (unit test, simulatore iPhone 18 Pro, senza parallelismo).

---

### Task 1: Modalità di layout + metriche settimana

**Files:** Create `FMT II/Models/DeviceLayout.swift`; Test `FMT IITests/IPadLayoutTests.swift`.

**Produces:** `enum DeviceLayout { case compact, regular, wide }`, `static func resolve(horizontalSizeClass: UserInterfaceSizeClass?, width: CGFloat) -> DeviceLayout`, `var isIPadLayout: Bool`, `EnvironmentValues.deviceLayout`; `enum WeekGridMetrics { static func dayColumnWidth(available: CGFloat, days: Int, timeColumn: CGFloat, minimum: CGFloat) -> CGFloat }`.

- [ ] Step 1 — test:
```swift
import XCTest
import SwiftUI
@testable import FMT_II

final class IPadLayoutTests: XCTestCase {
    func testIPhoneIsCompact() {
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .compact, width: 430), .compact)
    }
    func testNarrowIPadWindowIsCompact() {
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .compact, width: 375), .compact)
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .regular, width: 600), .compact)
    }
    func testIPadPortraitIsRegular() {
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .regular, width: 834), .regular)
    }
    func testIPadLandscapeIsWide() {
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .regular, width: 1194), .wide)
        XCTAssertEqual(DeviceLayout.resolve(horizontalSizeClass: .regular, width: 1000), .wide)
    }
    func testFiveDaysFillWidth() {
        XCTAssertEqual(WeekGridMetrics.dayColumnWidth(available: 860, days: 5, timeColumn: 60, minimum: 88), 160)
    }
    func testSixDaysFillWidth() {
        XCTAssertEqual(WeekGridMetrics.dayColumnWidth(available: 780, days: 6, timeColumn: 60, minimum: 88), 120)
    }
    func testFallsBackToMinimumWidth() {
        XCTAssertEqual(WeekGridMetrics.dayColumnWidth(available: 400, days: 5, timeColumn: 60, minimum: 88), 88)
        XCTAssertEqual(WeekGridMetrics.dayColumnWidth(available: 800, days: 0, timeColumn: 60, minimum: 88), 88)
    }
}
```
- [ ] Step 2 — run, expect build failure (types missing).
- [ ] Step 3 — implement:
```swift
import SwiftUI

/// Disposizione dell'interfaccia: iPhone (o iPad in finestra stretta),
/// iPad in verticale, iPad in orizzontale.
enum DeviceLayout: Equatable {
    case compact, regular, wide

    static func resolve(horizontalSizeClass: UserInterfaceSizeClass?, width: CGFloat) -> DeviceLayout {
        guard horizontalSizeClass == .regular, width >= 700 else { return .compact }
        return width >= 1000 ? .wide : .regular
    }

    var isIPadLayout: Bool { self != .compact }
}

private struct DeviceLayoutKey: EnvironmentKey {
    static let defaultValue: DeviceLayout = .compact
}

extension EnvironmentValues {
    var deviceLayout: DeviceLayout {
        get { self[DeviceLayoutKey.self] }
        set { self[DeviceLayoutKey.self] = newValue }
    }
}

/// Settimana su iPad: colonne dei giorni che riempiono la larghezza.
enum WeekGridMetrics {
    static func dayColumnWidth(available: CGFloat, days: Int, timeColumn: CGFloat, minimum: CGFloat) -> CGFloat {
        guard days > 0 else { return minimum }
        return max(minimum, ((available - timeColumn) / CGFloat(days)).rounded(.down))
    }
}
```
- [ ] Step 4 — run, expect PASS. Step 5 — commit `feat(ipad): modalità di layout e metriche settimana`.

### Task 2: Wiring in ContentView + hook orientamento DEBUG

**Files:** Modify `FMT II/ContentView.swift`.

- [ ] `@Environment(\.horizontalSizeClass) private var hSizeClass`, `@State private var windowWidth: CGFloat = 0`; sul `Group` del body: `.background(GeometryReader { g in Color.clear.onAppear { windowWidth = g.size.width }.onChange(of: g.size.width) { _, w in windowWidth = w } })` e `.environment(\.deviceLayout, DeviceLayout.resolve(horizontalSizeClass: hSizeClass, width: windowWidth))`.
- [ ] In `.onAppear` dentro `#if DEBUG`: argomento `-FMTOrientation landscape|portrait` →
```swift
if let i = dbgArgs.firstIndex(of: "-FMTOrientation"), i + 1 < dbgArgs.count,
   let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
    let mask: UIInterfaceOrientationMask = dbgArgs[i + 1] == "landscape" ? .landscapeRight : .portrait
    scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
}
```
- [ ] Suite verde; commit `feat(ipad): layout calcolato dalla finestra + hook orientamento (debug)`.

### Task 3: Settimana a tutta larghezza

**Files:** Modify `FMT II/Views/WeekView.swift`.

- [ ] `@Environment(\.deviceLayout) private var layout`. In iPad layout: `GeometryReader` attorno alla griglia (altezza = header + righe·76) che calcola `dayW = WeekGridMetrics.dayColumnWidth(available: g.size.width, days: schedule.days.count, timeColumn: 60, minimum: 88)`; se `dayW * days + 60 <= g.size.width` niente `ScrollView(.horizontal)`, altrimenti lo scroll di oggi. `rowHeight` 76, `timeColWidth` 60, header giorni font 11.
- [ ] `WeekCell`: nuovo parametro `large: Bool = false`; se `large` chip con titolo 12.5 bold + seconda riga 10.5 (classe: `lesson.classModeSubtitle`; docente: `lesson.subject` se diverso dal titolo) e padding verticale 7. Stessi tint, tap, contextMenu, «+N».
- [ ] Compact: valori e codice di oggi. Suite verde; screenshot iPad verticale; commit.

### Task 4: Orario a due colonne in orizzontale

**Files:** Modify `FMT II/Views/MainScheduleView.swift`.

- [ ] Estrarre `scheduleContent` (lo `switch viewMode`) in una `@ViewBuilder` property.
- [ ] `layout == .wide`: sotto il titolo fisso, `HStack(alignment: .top, spacing: 18)` con `ScrollView { VStack(spacing: 14) { statusStrip; controlPanel; if viewMode != .week { timeIndicator } } }.frame(width: 340)` e `ScrollView { scheduleContent }` (stessa mask e padding top `headerHeight + 6`).
- [ ] `layout == .regular`: struttura di oggi; `NowView`/`DayView` con `.frame(maxWidth: 760).frame(maxWidth: .infinity)`.
- [ ] `.compact`: invariato. Suite verde; screenshot orizzontale; commit.

### Task 5: Diario su 2 colonne

**Files:** Modify `FMT II/Views/NotesView.swift`.

- [ ] Estrarre la riga (NoteRowSelectable + tap + contextMenu) in `noteCell(_:)`; la `List` compact la usa con gli stessi `.swipeActions`/modificatori di oggi.
- [ ] `layout.isIPadLayout`: `ScrollViewReader { proxy in ScrollView { LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) { ForEach(notesByDate) { group in dayHeader(group).id(group.id); LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) { ForEach(group.notes) { noteCell($0) } } } ; Color.clear.frame(height: 80) }.padding(.horizontal, 16) } }` con lo stesso `.onChange(of: jumpToDate)`.
- [ ] Suite verde; screenshot; commit.

### Task 6: Voti

**Files:** Modify `FMT II/Views/GradesView.swift`.

- [ ] Estrarre `gradeRow(_:)` (GradeHomeRow + tap + contextMenu) e `gradesHeader` (titolo, summary, recent).
- [ ] `.wide`: `HStack(alignment: .top, spacing: 18) { ScrollView { gradesHeader }.frame(width: 380); ScrollView { LazyVStack(spacing: 12) { ForEach(sortedGrades) { gradeRow($0) } } } }`.
- [ ] `.regular`: `ScrollView { LazyVStack { gradesHeader; LazyVGrid(2 colonne) { ForEach(sortedGrades) { gradeRow($0) } } } }`.
- [ ] `.compact` invariato. Suite verde; screenshot; commit.

### Task 7: Banner, testi, verifica finale

**Files:** Modify `FMT II/Views/WhatsNewBanner.swift`, `AppStore/metadata/whats-new-2.2.md`, `FMT II/Views/ManualView.swift`.

- [ ] Banner: `if UIDevice.current.userInterfaceIdiom == .pad { feature(icon: "ipad.landscape", hex: "#F472B6", title: "Pensata per iPad", text: "Settimana a tutto schermo e schermate su due colonne in orizzontale.") }`.
- [ ] Novità IT «• Pensata per iPad: settimana a tutto schermo e schermate su due colonne in orizzontale.» / EN «• Designed for iPad: full-width week and two-column screens in landscape.»; voce nel manuale.
- [ ] Suite verde; screenshot iPad verticale+orizzontale per Orario (Adesso, Settimana), Diario, Voti, banner; iPhone 18 Pro regressione (Orario Settimana, Diario, Voti); commit; push sulla PR.
