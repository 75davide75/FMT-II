# FMT 2.2 — iCloud sync + inizio per classe — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rilasciare FMT 2.2: sync iCloud di voti/note/orario/impostazioni scuola, ora d'inizio per classe con toggle, banner «Novità» solo per chi aggiorna.

**Architecture:** Gli store JSON/UserDefaults esistenti restano la fonte di verità locale. `CloudSyncManager` (CKSyncEngine, zona privata `FMTZone`) accoda le modifiche locali e applica quelle remote con last-writer-wins su `modifiedAt` (logica pura in `SyncMerge`). Le impostazioni scuola passano da `NSUbiquitousKeyValueStore` (`SettingsSync`). Gli orari per classe sono funzioni pure su `ScheduleData` (`ClassTimes.swift`) usate da editor e viste.

**Tech Stack:** Swift 5 / SwiftUI, iOS 17+, CloudKit (CKSyncEngine), NSUbiquitousKeyValueStore, XCTest. Progetto Xcode con cartelle sincronizzate (i nuovi file in `FMT II/` e `FMT IITests/` entrano nel target da soli).

**Spec:** `docs/superpowers/specs/2026-10-11-icloud-sync-v2.2-design.md`

## Global Constraints

- Deployment target iOS 17.0; nessuna libreria di terze parti.
- Container CloudKit: `iCloud.com.davide.fmtII`; zona `FMTZone`; record type `Grade`, `Note`, `Schedule`.
- Bundle `com.davide.fmtII`; `MARKETING_VERSION = 2.2.0`, `CURRENT_PROJECT_VERSION = 2`.
- Testi UI in italiano; stile Aurora (`auroraCard`, `auroraProminent`, `SettingsView.header/row`, `Color.sectionCard`).
- Ogni nuovo campo Codable si decodifica con `decodeIfPresent` + default: i dati della 2.1.1 devono caricarsi.
- Chiavi sincronizzate: `sufficientGrade`, `maxGrade`, `periodSystem`, `period1EndTimestamp`, `fmt_subject_colors`, `fmt_entity_colors`. Mai: `appearanceMode`, `dynamicTypeLevel`, `useLiveTime`, `manualDayRaw`, `manualTime`, `appSectionRaw`, `hasSeenTutorial`, `hasCompletedOnboarding`, `lastSeenWhatsNew`.
- Sync disattivata sotto XCTest e con `-FMTSeedDemo`.
- Nessun upload/invio App Store e nessun push senza i passaggi di conferma previsti nel Task 11.

## Review Focus

1. Due dispositivi con dati 2.1.1 che aggiornano insieme → unione per id, nessuna perdita (test `testApplyUnionKeepsBothSides`, Task 4).
2. Ora d'inizio per classe **prima** di quella globale (delta negativo) → fasce corrette (test `testEarlierClassStartShiftsBackwards`, Task 1).
3. Classe rinominata con toggle attivo → l'ora personalizzata la segue (test `testRenameMovesCustomStart`, Task 1).
4. Voto modificato su due dispositivi con lo stesso timestamp → entrambi convergono sul remoto (test `testTieGoesToRemote`, Task 4).
5. Utente che aggiorna ma ha già visto il banner, o installa una versione futura → banner non mostrato (test `testFutureVersionSeenDoesNotShow`, Task 9).

Comando test (usato in tutti i task):
```bash
xcodebuild test -project "FMT II.xcodeproj" -scheme "FMT II" -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:"FMT IITests" 2>&1 | grep -E "Test Case|error:|TEST (SUCCEEDED|FAILED)" | tail -40
```

---

### Task 1: Modello orari per classe

**Files:**
- Modify: `FMT II/Models/Models.swift` (struct `ScheduleData`, decoder, `applyManualEdits`)
- Create: `FMT II/Models/ClassTimes.swift`
- Test: `FMT IITests/ClassTimesTests.swift`

**Interfaces:**
- Produces: `ScheduleData.perClassStartTimes: Bool`, `ScheduleData.classStartTimes: [String: String]`, `sortedPeriods`, `customStart(forClass:) -> String?`, `periods(forClass:) -> [Period]`, `displayPeriods(forClass: String?) -> [Period]`, `timeSlots(forClass: String?) -> [String]`, `mutating renameClassStartTime(from:to:)`.

- [ ] **Step 1: Test che falliscono** — `FMT IITests/ClassTimesTests.swift`:

```swift
import XCTest
@testable import FMT_II

final class ClassTimesTests: XCTestCase {
    private func lesson(_ id: String, _ cls: String, period: Int) -> Lesson {
        Lesson(id: id, className: cls, teacher: "ROSSI", day: .monday, dayLabel: "Lunedì",
               period: period, startTime: "08:10", endTime: "09:10", sourcePage: 0)
    }

    private func sample(perClass: Bool, starts: [String: String] = [:]) -> ScheduleData {
        var s = ScheduleData(
            id: "t", sourceName: "t", importedAt: "", startsFrom: nil,
            days: [DayInfo(id: .monday, label: "Lunedì")],
            periods: [Period(number: 1, startTime: "08:10", endTime: "09:10"),
                      Period(number: 2, startTime: "09:10", endTime: "10:10")],
            classes: ["1C", "3C"], teachers: ["ROSSI"],
            lessons: [lesson("a", "1C", period: 1), lesson("b", "3C", period: 1)],
            warnings: [])
        s.perClassStartTimes = perClass
        s.classStartTimes = starts
        return s
    }

    func testToggleOffIgnoresCustomStarts() {
        let s = sample(perClass: false, starts: ["3C": "09:10"])
        XCTAssertEqual(s.periods(forClass: "3C").map(\.startTime), ["08:10", "09:10"])
    }

    func testClassStartShiftsAllPeriods() {
        let s = sample(perClass: true, starts: ["3C": "09:10"])
        let p = s.periods(forClass: "3C")
        XCTAssertEqual(p.map(\.startTime), ["09:10", "10:10"])
        XCTAssertEqual(p.map(\.endTime), ["10:10", "11:10"])
        XCTAssertEqual(p.map(\.number), [1, 2])
    }

    func testClassWithoutCustomStartUsesGlobal() {
        let s = sample(perClass: true, starts: ["3C": "09:10"])
        XCTAssertEqual(s.periods(forClass: "1C").map(\.startTime), ["08:10", "09:10"])
    }

    func testEarlierClassStartShiftsBackwards() {
        let s = sample(perClass: true, starts: ["1C": "07:40"])
        XCTAssertEqual(s.periods(forClass: "1C").map(\.startTime), ["07:40", "08:40"])
        XCTAssertEqual(s.periods(forClass: "1C").last?.endTime, "09:40")
    }

    func testApplyManualEditsAlignsLessonsToTheirClass() {
        let s = applyManualEdits(sample(perClass: true, starts: ["3C": "09:10"]))
        let c1 = s.lessons.first { $0.className == "1C" }!
        let c3 = s.lessons.first { $0.className == "3C" }!
        XCTAssertEqual(c1.startTime, "08:10")
        XCTAssertEqual(c3.startTime, "09:10")
        XCTAssertEqual(c3.endTime, "10:10")
        XCTAssertNotEqual(c1.id, c3.id)
        XCTAssertTrue(s.edited)
    }

    func testTeacherViewUsesUnionOfStarts() {
        let s = sample(perClass: true, starts: ["3C": "09:10"])
        let rows = s.displayPeriods(forClass: nil)
        XCTAssertEqual(rows.map(\.startTime), ["08:10", "09:10", "10:10"])
        XCTAssertEqual(rows.map(\.number), [1, 2, 3])
    }

    func testTeacherViewWithToggleOffIsGlobal() {
        let s = sample(perClass: false, starts: ["3C": "09:10"])
        XCTAssertEqual(s.displayPeriods(forClass: nil).map(\.startTime), ["08:10", "09:10"])
    }

    func testTimeSlotsIncludeLastEnd() {
        let s = sample(perClass: true, starts: ["3C": "09:10"])
        XCTAssertEqual(s.timeSlots(forClass: "3C"), ["09:10", "10:10", "11:10"])
        XCTAssertEqual(s.timeSlots(forClass: nil), ["08:10", "09:10", "10:10", "11:10"])
    }

    func testRenameMovesCustomStart() {
        var s = sample(perClass: true, starts: ["3C": "09:10"])
        s.renameClassStartTime(from: "3C", to: "3D")
        XCTAssertNil(s.classStartTimes["3C"])
        XCTAssertEqual(s.classStartTimes["3D"], "09:10")
    }

    func testScheduleFrom211DecodesWithDefaults() throws {
        let json = """
        {"id":"x","sourceName":"a.pdf","importedAt":"","days":[],"periods":[],
         "classes":["1C"],"teachers":[],"lessons":[],"warnings":[],"edited":true}
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(ScheduleData.self, from: json)
        XCTAssertFalse(s.perClassStartTimes)
        XCTAssertTrue(s.classStartTimes.isEmpty)
    }
}
```

- [ ] **Step 2: Esegui i test** — atteso: build FAILED («value of type 'ScheduleData' has no member 'perClassStartTimes'»).

- [ ] **Step 3: Campi in `ScheduleData`** (`Models.swift`), dopo `subjectTeachers`:

```swift
    /// v2.2: ogni classe può avere la sua ora d'inizio (durata e numero di ore restano globali).
    var perClassStartTimes: Bool = false
    /// Classe → "HH:mm" d'inizio della 1ª ora (usato solo con `perClassStartTimes`).
    var classStartTimes: [String: String] = [:]
```

Nel decoder, dopo `subjectTeachers = …`:

```swift
        perClassStartTimes = try c.decodeIfPresent(Bool.self, forKey: .perClassStartTimes) ?? false
        classStartTimes = try c.decodeIfPresent([String: String].self, forKey: .classStartTimes) ?? [:]
```

- [ ] **Step 4: `FMT II/Models/ClassTimes.swift`:**

```swift
import Foundation

// Ora d'inizio per classe (v2.2): la durata e il numero di ore restano quelli
// globali di `periods`; una classe può solo traslare l'inizio della giornata.
extension ScheduleData {
    var sortedPeriods: [Period] { periods.sorted { $0.number < $1.number } }

    /// Inizio personalizzato della 1ª ora per la classe, se il toggle è attivo.
    func customStart(forClass className: String) -> String? {
        guard perClassStartTimes, let t = classStartTimes[className], !t.isEmpty else { return nil }
        return t
    }

    /// Fasce della classe: quelle globali traslate al suo inizio.
    func periods(forClass className: String) -> [Period] {
        let base = sortedPeriods
        guard let custom = customStart(forClass: className), let first = base.first else { return base }
        let delta = minutesFromMidnight(custom) - minutesFromMidnight(first.startTime)
        guard delta != 0 else { return base }
        return base.map {
            Period(number: $0.number,
                   startTime: addMinutes($0.startTime, delta),
                   endTime: addMinutes($0.endTime, delta))
        }
    }

    /// Righe da mostrare: le fasce della classe (vista classe) oppure, con
    /// `nil` (vista docente), l'unione ordinata degli inizi di tutte le classi.
    func displayPeriods(forClass className: String?) -> [Period] {
        if let className { return periods(forClass: className) }
        guard perClassStartTimes, classes.contains(where: { customStart(forClass: $0) != nil }) else {
            return sortedPeriods
        }
        var seen = Set<String>()
        let union = classes.flatMap { periods(forClass: $0) }
            .sorted { minutesFromMidnight($0.startTime) < minutesFromMidnight($1.startTime) }
            .filter { seen.insert($0.startTime).inserted }
        return union.enumerated().map {
            Period(number: $0.offset + 1, startTime: $0.element.startTime, endTime: $0.element.endTime)
        }
    }

    /// Orari selezionabili: gli inizi delle fasce + la fine dell'ultima.
    func timeSlots(forClass className: String?) -> [String] {
        let ps = displayPeriods(forClass: className)
        guard let lastEnd = ps.map(\.endTime).max(by: { minutesFromMidnight($0) < minutesFromMidnight($1) }) else {
            return []
        }
        var out = ps.map(\.startTime)
        if !out.contains(lastEnd) { out.append(lastEnd) }
        return out
    }

    /// Una classe rinominata si porta dietro la sua ora d'inizio.
    mutating func renameClassStartTime(from old: String, to new: String) {
        guard let t = classStartTimes.removeValue(forKey: old) else { return }
        classStartTimes[new] = t
    }
}
```

- [ ] **Step 5: `applyManualEdits` usa le fasce della classe** — in `Models.swift` sostituisci le prime righe della funzione:

```swift
func applyManualEdits(_ s: ScheduleData) -> ScheduleData {
    var periodsByClass: [String: [Int: Period]] = [:]
    func period(_ number: Int, of className: String) -> Period? {
        if periodsByClass[className] == nil {
            var map: [Int: Period] = [:]
            for p in s.periods(forClass: className) { map[p.number] = p }
            periodsByClass[className] = map
        }
        return periodsByClass[className]?[number]
    }

    let lessons = s.lessons.map { lesson -> Lesson in
        let p = period(lesson.period, of: lesson.className)
```
(il resto della closure invariato: usa `p?.startTime ?? lesson.startTime` ecc.)

- [ ] **Step 6: Esegui i test** — atteso: `ClassTimesTests` tutti PASS, nessuna regressione.

- [ ] **Step 7: Commit** — `git add -A "FMT II/Models" "FMT IITests/ClassTimesTests.swift" && git commit -m "feat(orario): modello ora d'inizio per classe"`

---

### Task 2: Viste che usano le fasce per classe

**Files:**
- Modify: `FMT II/Views/MainScheduleView.swift` (`schoolTimes`, `dayPlan`, chiamata `WeekView`, `QuickTimePickerSheet.schoolTimes`)
- Modify: `FMT II/Views/WeekView.swift` (nuovo parametro `periods`)
- Modify: `FMT II/Views/SettingsView.swift:56-59`, `FMT II/Views/NotesView.swift:957-960`

**Interfaces:**
- Consumes: `displayPeriods(forClass:)`, `timeSlots(forClass:)` (Task 1).
- Produces: `WeekView(schedule:periods:targetLessons:…)`.

- [ ] **Step 1: MainScheduleView** — aggiungi sotto `targetLessons`:

```swift
    /// Classe di cui mostrare le fasce: quella selezionata in vista classe,
    /// nil in vista docente (unione degli orari di tutte le classi).
    var periodClass: String? { targetMode == .class_ ? selectedClass : nil }
```
Sostituisci il corpo di `schoolTimes` con `schedule.timeSlots(forClass: periodClass)`; in `dayPlan` sostituisci `schedule.periods.map` con `schedule.displayPeriods(forClass: periodClass).map`; nella chiamata `WeekView(` aggiungi `periods: schedule.displayPeriods(forClass: periodClass),` dopo `schedule: schedule,`; in `QuickTimePickerSheet` il corpo di `schoolTimes` diventa `schedule.timeSlots(forClass: nil)`.

- [ ] **Step 2: WeekView** — aggiungi `let periods: [Period]` dopo `let schedule: ScheduleData` e sostituisci `ForEach(schedule.periods) { period in` con `ForEach(periods) { period in`.

- [ ] **Step 3: SettingsView / NotesView** — `SettingsView.schoolTimes` diventa `store.schedule?.timeSlots(forClass: nil) ?? []`; `NotesView.schoolTimes` diventa `schedule?.timeSlots(forClass: classTag.isEmpty ? nil : classTag) ?? []`.

- [ ] **Step 4: Build + test** — comando test; atteso PASS (le viste non hanno test unitari: la verifica visiva è nel Task 10).

- [ ] **Step 5: Commit** — `git commit -am "feat(orario): viste Ora/Giorno/Settimana con le fasce della classe"`

---

### Task 3: Editor «Fasce orarie» con toggle per classe

**Files:**
- Modify: `FMT II/Views/DatabaseEditorView.swift` (`timeSlotsSection`, `applyRename`)

**Interfaces:**
- Consumes: `perClassStartTimes`, `classStartTimes`, `periods(forClass:)`, `renameClassStartTime` (Task 1); helper esistenti `hhmm(_:)`, `dateFrom(_:)`, `entityTint`, `entityLabelColor`.

- [ ] **Step 1: Binding** — aggiungi alla view:

```swift
    private var perClassBinding: Binding<Bool> {
        Binding(
            get: { draft.perClassStartTimes },
            set: { on in
                draft.perClassStartTimes = on
                // Le classi senza orario partono dall'inizio globale.
                if on, let first = sortedPeriods.first {
                    for cls in draft.classes where draft.classStartTimes[cls] == nil {
                        draft.classStartTimes[cls] = first.startTime
                    }
                }
            }
        )
    }

    private func classStartBinding(_ cls: String) -> Binding<Date> {
        Binding(
            get: { dateFrom(draft.classStartTimes[cls] ?? sortedPeriods.first?.startTime ?? "08:00") },
            set: { d in
                let cal = Calendar.current
                draft.classStartTimes[cls] = hhmm(cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d))
            }
        )
    }
```

- [ ] **Step 2: UI** — in `timeSlotsSection`, il testo «Inizio 1ª ora» diventa `Text(draft.perClassStartTimes ? "Inizio predefinito" : "Inizio 1ª ora")`; dopo lo `Stepper` della durata inserisci:

```swift
            Toggle(isOn: perClassBinding.animation(.easeInOut(duration: 0.25))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inizio diverso per classe").font(.system(size: 14.5, weight: .semibold))
                    Text("Es. 1C alle 8:10, 3C alle 9:10")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .tint(AuroraSection.orario.tintB)
            if draft.perClassStartTimes {
                ForEach(draft.classes, id: \.self) { cls in
                    classStartRow(cls)
                }
            }
```
e la funzione:

```swift
    private func classStartRow(_ cls: String) -> some View {
        let ps = draft.periods(forClass: cls)
        return HStack(spacing: 10) {
            Text(cls)
                .font(.system(size: 11.5, weight: .bold))
                .kerning(0.3)
                .foregroundStyle(entityLabelColor(entityTint(cls), scheme))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(entityTint(cls).opacity(0.13), in: Capsule())
                .overlay(Capsule().strokeBorder(entityTint(cls).opacity(0.28), lineWidth: 1))
            if let f = ps.first, let l = ps.last {
                Text("\(f.startTime)–\(l.endTime)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DatePicker("", selection: classStartBinding(cls), displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }
```
Nel footer: `Text(draft.perClassStartTimes ? "La durata delle lezioni resta uguale per tutte le classi." : "Calcolate da inizio e durata — nessun inserimento manuale.")`. Il `ChipFlowLayout` delle fasce resta, ma solo quando il toggle è spento (`if !draft.perClassStartTimes { ChipFlowLayout … }`).

- [ ] **Step 3: Rinomina** — in `applyRename`, ramo `.class_`, dentro l'`else` dopo il ciclo sulle lezioni: `draft.renameClassStartTime(from: target.current, to: new)`.

- [ ] **Step 4: Build + test** — atteso PASS.

- [ ] **Step 5: Commit** — `git commit -am "feat(orario): toggle «Inizio diverso per classe» nelle fasce orarie"`

---

### Task 4: `modifiedAt` + logica di merge pura

**Files:**
- Modify: `FMT II/Models/GradeModel.swift` (struct `Grade` + decoder), `FMT II/Models/NoteModel.swift` (struct `Note` + decoder), `FMT II/Models/Models.swift` (`ScheduleData` + decoder)
- Create: `FMT II/Services/SyncMerge.swift`
- Test: `FMT IITests/SyncMergeTests.swift`

**Interfaces:**
- Produces: `Grade.modifiedAt`, `Note.modifiedAt`, `ScheduleData.modifiedAt: Date`; `enum SyncItem { case grade(UUID), note(UUID), schedule }` con `recordName`, `recordType`, `init?(recordName:)`; `SyncMerge.remoteWins(local: Date?, remote: Date) -> Bool`; `SyncMerge.apply(upserts:deletions:to:modifiedAt:) -> [T]`.

- [ ] **Step 1: Test** — `FMT IITests/SyncMergeTests.swift`:

```swift
import XCTest
@testable import FMT_II

final class SyncMergeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    private func grade(_ id: UUID, _ value: Double, _ at: Date) -> Grade {
        var g = Grade(); g.id = id; g.value = value; g.modifiedAt = at; return g
    }

    func testRecordNamesRoundTrip() {
        let id = UUID()
        XCTAssertEqual(SyncItem(recordName: SyncItem.grade(id).recordName), .grade(id))
        XCTAssertEqual(SyncItem(recordName: SyncItem.note(id).recordName), .note(id))
        XCTAssertEqual(SyncItem(recordName: "schedule-current"), .schedule)
        XCTAssertNil(SyncItem(recordName: "grade-not-a-uuid"))
        XCTAssertNil(SyncItem(recordName: "photo-\(id.uuidString)"))
        XCTAssertEqual(SyncItem.grade(id).recordType, "Grade")
    }

    func testNewerLocalIsKept() {
        let id = UUID()
        let out = SyncMerge.apply(upserts: [grade(id, 4, t0)], deletions: [], to: [grade(id, 8, t1)], modifiedAt: \.modifiedAt)
        XCTAssertEqual(out.first?.value, 8)
    }

    func testNewerRemoteWins() {
        let id = UUID()
        let out = SyncMerge.apply(upserts: [grade(id, 9, t1)], deletions: [], to: [grade(id, 5, t0)], modifiedAt: \.modifiedAt)
        XCTAssertEqual(out.first?.value, 9)
    }

    func testTieGoesToRemote() {
        let id = UUID()
        let out = SyncMerge.apply(upserts: [grade(id, 7, t0)], deletions: [], to: [grade(id, 6, t0)], modifiedAt: \.modifiedAt)
        XCTAssertEqual(out.first?.value, 7)
    }

    func testApplyUnionKeepsBothSides() {
        let a = UUID(), b = UUID()
        let out = SyncMerge.apply(upserts: [grade(b, 7, t0)], deletions: [], to: [grade(a, 6, t0)], modifiedAt: \.modifiedAt)
        XCTAssertEqual(Set(out.map(\.id)), [a, b])
    }

    func testDeletionRemovesAndUnknownDeletionIsNoop() {
        let a = UUID(), b = UUID()
        let out = SyncMerge.apply(upserts: [], deletions: [a, UUID()], to: [grade(a, 6, t0), grade(b, 7, t0)], modifiedAt: \.modifiedAt)
        XCTAssertEqual(out.map(\.id), [b])
    }

    func testRemoteWinsWithoutLocal() {
        XCTAssertTrue(SyncMerge.remoteWins(local: nil, remote: .distantPast))
    }

    func testLegacyGradeDecodesModifiedAtFromDate() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","subject":"Mat","value":7,"date":1000}"#
        let g = try JSONDecoder().decode(Grade.self, from: Data(json.utf8))
        XCTAssertEqual(g.modifiedAt, g.date)
    }
}
```

- [ ] **Step 2: Esegui** — atteso build FAILED (`modifiedAt`/`SyncItem` mancanti).

- [ ] **Step 3: Campi** —
  - `Grade`: `var modifiedAt: Date = Date()`; decoder dopo `countsForAverage`: `modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? date`.
  - `Note`: `var modifiedAt: Date = Date()`; decoder dopo `reminders`: `modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt`.
  - `ScheduleData`: `var modifiedAt: Date = .distantPast` (dopo `classStartTimes`); decoder: `modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast`.

- [ ] **Step 4: `FMT II/Services/SyncMerge.swift`:**

```swift
import Foundation

/// Elemento sincronizzato. Il nome del record CloudKit è "<tipo>-<id>", così
/// il tipo si ricava dal nome senza consultare gli store.
enum SyncItem: Equatable, Hashable {
    case grade(UUID)
    case note(UUID)
    case schedule

    static let scheduleRecordName = "schedule-current"

    var recordName: String {
        switch self {
        case .grade(let id): return "grade-\(id.uuidString)"
        case .note(let id):  return "note-\(id.uuidString)"
        case .schedule:      return Self.scheduleRecordName
        }
    }

    var recordType: String {
        switch self {
        case .grade:    return "Grade"
        case .note:     return "Note"
        case .schedule: return "Schedule"
        }
    }

    init?(recordName: String) {
        if recordName == Self.scheduleRecordName { self = .schedule; return }
        let parts = recordName.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "grade": self = .grade(id)
        case "note":  self = .note(id)
        default:      return nil
        }
    }
}

/// Regole di merge (pure, testate): last-writer-wins su `modifiedAt`; a parità
/// vince il remoto, così tutti i dispositivi convergono sullo stesso valore.
enum SyncMerge {
    static func remoteWins(local: Date?, remote: Date) -> Bool {
        guard let local else { return true }
        return remote >= local
    }

    /// Applica modifiche remote a una lista locale: unione per id, mai
    /// sostituzione totale.
    static func apply<T: Identifiable>(upserts: [T], deletions: Set<T.ID>, to local: [T],
                                       modifiedAt: (T) -> Date) -> [T] {
        var result = local.filter { !deletions.contains($0.id) }
        for item in upserts {
            if let idx = result.firstIndex(where: { $0.id == item.id }) {
                if remoteWins(local: modifiedAt(result[idx]), remote: modifiedAt(item)) {
                    result[idx] = item
                }
            } else {
                result.insert(item, at: 0)
            }
        }
        return result
    }
}
```

- [ ] **Step 5: Esegui** — atteso PASS (anche i test 2.1.1 esistenti).

- [ ] **Step 6: Commit** — `git commit -am "feat(sync): modifiedAt sui modelli e regole di merge"` (con `git add` dei nuovi file).

---

### Task 5: Store collegati alla sync

**Files:**
- Create: `FMT II/Services/CloudSyncManager.swift` (solo API pubblica: engine ancora assente)
- Modify: `FMT II/Models/GradeModel.swift` (`GradesStore`), `FMT II/Models/NoteModel.swift` (`NotesStore`), `FMT II/Services/ScheduleStore.swift`

**Interfaces:**
- Consumes: `SyncItem`, `SyncMerge` (Task 4).
- Produces: `CloudSyncManager.shared.enqueueSave(_: [SyncItem])`, `enqueueDelete(_: [SyncItem])`; `GradesStore.applyRemote(upserts:deletions:)`, `NotesStore.applyRemote(upserts:deletions:)`, `ScheduleStore.applyRemote(schedule:remoteModifiedAt:deleted:)`, `ScheduleStore.clearedAt: Date?`.

- [ ] **Step 1: Scheletro manager** — `CloudSyncManager.swift`:

```swift
import Foundation
import CloudKit
import os

/// Sincronizzazione iCloud (CloudKit, database privato) di voti, note e orario.
/// Gli store restano la fonte di verità locale: il manager accoda le modifiche
/// locali e applica quelle remote (vedi `SyncMerge`).
@MainActor
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    static let containerIdentifier = "iCloud.com.davide.fmtII"
    static let zoneID = CKRecordZone.ID(zoneName: "FMTZone", ownerName: CKCurrentUserDefaultName)

    private var engine: CKSyncEngine?

    private init() {}

    func enqueueSave(_ items: [SyncItem]) {
        guard let engine, !items.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: items.map { .saveRecord(recordID(for: $0)) })
    }

    func enqueueDelete(_ items: [SyncItem]) {
        guard let engine, !items.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: items.map { .deleteRecord(recordID(for: $0)) })
    }

    private func recordID(for item: SyncItem) -> CKRecord.ID {
        CKRecord.ID(recordName: item.recordName, zoneID: Self.zoneID)
    }
}
```

- [ ] **Step 2: GradesStore** — sostituisci i metodi di mutazione:

```swift
    private var sync: CloudSyncManager { .shared }

    func add(_ grade: Grade) {
        var g = grade; g.modifiedAt = Date()
        grades.insert(g, at: 0); save()
        sync.enqueueSave([.grade(g.id)])
    }

    func update(_ grade: Grade) {
        if let idx = grades.firstIndex(where: { $0.id == grade.id }) {
            var g = grade; g.modifiedAt = Date()
            grades[idx] = g; save()
            sync.enqueueSave([.grade(g.id)])
        }
    }

    func delete(ids: Set<UUID>) {
        grades.removeAll { ids.contains($0.id) }; save()
        sync.enqueueDelete(ids.map { .grade($0) })
    }

    func deleteAll() {
        let ids = grades.map(\.id)
        grades.removeAll(); save()
        sync.enqueueDelete(ids.map { .grade($0) })
    }

    func replaceAll(_ newGrades: [Grade]) {
        let removed = Set(grades.map(\.id)).subtracting(newGrades.map(\.id))
        let now = Date()
        grades = newGrades.map { var g = $0; g.modifiedAt = now; return g }
        save()
        sync.enqueueDelete(removed.map { .grade($0) })
        sync.enqueueSave(grades.map { .grade($0.id) })
    }

    /// Modifiche arrivate da iCloud: non vengono rinviate (niente loop).
    func applyRemote(upserts: [Grade], deletions: Set<UUID>) {
        grades = SyncMerge.apply(upserts: upserts, deletions: deletions, to: grades, modifiedAt: \.modifiedAt)
        save()
    }
```

- [ ] **Step 3: NotesStore** — stesso schema (`.note(id)`), più `archive`/`unarchive` che impostano `notes[idx].modifiedAt = Date()` e accodano i salvataggi; `delete`/`deleteAll` mantengono `NotificationManager.shared.cancel`; `replaceAll` mantiene `reschedule`. `applyRemote`:

```swift
    func applyRemote(upserts: [Note], deletions: Set<UUID>) {
        notes = SyncMerge.apply(upserts: upserts.map { $0.migratingDate() }, deletions: deletions,
                                to: notes, modifiedAt: \.modifiedAt)
        save()
        NotificationManager.shared.cancel(ids: deletions)
        let changed = Set(upserts.map(\.id))
        for n in notes where changed.contains(n.id) {
            if n.reminders.isEmpty { NotificationManager.shared.cancel(ids: [n.id]) }
            else { NotificationManager.shared.schedule(note: n) }
        }
    }
```

- [ ] **Step 4: ScheduleStore** — aggiungi:

```swift
    private let clearedAtKey = "findmyteacher.scheduleClearedAt"
    /// Quando l'orario è stato rimosso (tombstone per gli altri dispositivi).
    var clearedAt: Date? { UserDefaults.standard.object(forKey: clearedAtKey) as? Date }

    /// Salva un orario modificato localmente e lo accoda per iCloud.
    private func commit(_ s: ScheduleData) {
        var stamped = s
        stamped.modifiedAt = Date()
        schedule = stamped
        persist(stamped)
        UserDefaults.standard.removeObject(forKey: clearedAtKey)
        CloudSyncManager.shared.enqueueSave([.schedule])
    }

    /// Orario arrivato da iCloud (o rimosso altrove).
    func applyRemote(schedule remote: ScheduleData?, remoteModifiedAt: Date, deleted: Bool) {
        let localModified = schedule?.modifiedAt ?? clearedAt
        guard SyncMerge.remoteWins(local: localModified, remote: remoteModifiedAt) else { return }
        if deleted {
            schedule = nil
            UserDefaults.standard.removeObject(forKey: storageKey)
            UserDefaults.standard.set(remoteModifiedAt, forKey: clearedAtKey)
        } else if let remote {
            let s = remote.edited ? remote : normalizeScheduleTimes(remote)
            schedule = s
            persist(s)
            UserDefaults.standard.removeObject(forKey: clearedAtKey)
        }
    }
```
Sostituisci `schedule = X; persist(X)` con `commit(X)` in: `_importPDF` (entrambi i casi), `_importJSON`, `update`, `restore`. In `clearSchedule` aggiungi in fondo:
```swift
        UserDefaults.standard.set(Date(), forKey: clearedAtKey)
        CloudSyncManager.shared.enqueueSave([.schedule])
```

- [ ] **Step 5: Build + test** — atteso PASS (engine nil → gli enqueue non fanno nulla).

- [ ] **Step 6: Commit** — `git commit -am "feat(sync): store collegati (enqueue locale, applyRemote)"`

---

### Task 6: CKSyncEngine, entitlements, avvio

**Files:**
- Modify: `FMT II/Services/CloudSyncManager.swift`
- Create: `FMT II/FMT II.entitlements`
- Modify: `FMT II.xcodeproj/project.pbxproj` (config Debug e Release del target app)
- Modify: `FMT II/FMT_IIApp.swift` (registerForRemoteNotifications), `FMT II/ContentView.swift` (`.onAppear`)
- Test: `FMT IITests/SyncStatusTests.swift`

**Interfaces:**
- Consumes: store `applyRemote`, `clearedAt`, `SyncItem`, `SyncMerge` (Task 4-5).
- Produces: `CloudSyncManager.start(grades:notes:schedule:)`, `syncNow() async`, `@Published status: CloudSyncManager.Status` con `label: String` e `isProblem: Bool`, `lastSync: Date?`.

- [ ] **Step 1: Test stato** — `FMT IITests/SyncStatusTests.swift`:

```swift
import XCTest
@testable import FMT_II

final class SyncStatusTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(CloudSyncManager.Status.noAccount.label, "Accedi a iCloud")
        XCTAssertEqual(CloudSyncManager.Status.quotaExceeded.label, "Spazio iCloud esaurito")
        XCTAssertEqual(CloudSyncManager.Status.syncing.label, "In corso…")
        XCTAssertEqual(CloudSyncManager.Status.upToDate(nil).label, "Attiva")
        XCTAssertTrue(CloudSyncManager.Status.noAccount.isProblem)
        XCTAssertFalse(CloudSyncManager.Status.upToDate(nil).isProblem)
    }

    @MainActor func testSyncIsOffUnderTests() {
        XCTAssertEqual(CloudSyncManager.shared.status, .off)
    }
}
```

- [ ] **Step 2: Esegui** — atteso build FAILED (`Status` mancante).

- [ ] **Step 3: Manager completo** — in `CloudSyncManager.swift` aggiungi dentro la classe:

```swift
    enum Status: Equatable {
        case off, checking, syncing, upToDate(Date?), noAccount, quotaExceeded, failed(String)

        var label: String {
            switch self {
            case .off:            return "Non attiva"
            case .checking:       return "Verifica…"
            case .syncing:        return "In corso…"
            case .upToDate(let d):
                guard let d else { return "Attiva" }
                return "Aggiornata alle " + d.formatted(date: .omitted, time: .shortened)
            case .noAccount:      return "Accedi a iCloud"
            case .quotaExceeded:  return "Spazio iCloud esaurito"
            case .failed:         return "Errore"
            }
        }

        var isProblem: Bool {
            switch self {
            case .noAccount, .quotaExceeded, .failed: return true
            default: return false
            }
        }
    }

    @Published private(set) var status: Status = .off

    private weak var grades: GradesStore?
    private weak var notes: NotesStore?
    private weak var scheduleStore: ScheduleStore?
    private let log = Logger(subsystem: "com.davide.fmtII", category: "sync")
    /// Campi di sistema (change tag) dell'ultimo record noto, per nome record.
    private var systemFields: [String: Data] = [:]
    private let lastSyncKey = "fmt_lastCloudSync"

    var lastSync: Date? { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }

    private static var isDisabledForProcess: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        return ProcessInfo.processInfo.arguments.contains("-FMTSeedDemo") || env["FMT_SEED_DEMO"] == "1"
    }

    func start(grades: GradesStore, notes: NotesStore, schedule: ScheduleStore) {
        guard engine == nil, !Self.isDisabledForProcess else { return }
        self.grades = grades
        self.notes = notes
        self.scheduleStore = schedule
        systemFields = loadSystemFields()
        status = .checking
        NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccountStatus() }
        }
        startEngine(state: loadState())
        Task { await refreshAccountStatus() }
    }

    func syncNow() async {
        guard let engine else { return }
        status = .syncing
        do {
            try await engine.sendChanges()
            try await engine.fetchChanges()
            markSynced()
        } catch {
            handle(error)
        }
    }

    private func startEngine(state: CKSyncEngine.State.Serialization?) {
        let container = CKContainer(identifier: Self.containerIdentifier)
        var config = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                stateSerialization: state, delegate: self)
        config.automaticallySync = true
        let engine = CKSyncEngine(config)
        self.engine = engine
        if state == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            enqueueAllLocal()
        }
    }

    private func refreshAccountStatus() async {
        let account = try? await CKContainer(identifier: Self.containerIdentifier).accountStatus()
        if account != .available {
            status = .noAccount
        } else if status == .noAccount || status == .checking {
            status = .upToDate(lastSync)
        }
    }

    private func enqueueAllLocal() {
        var items: [SyncItem] = []
        items += (grades?.grades ?? []).map { .grade($0.id) }
        items += (notes?.notes ?? []).map { .note($0.id) }
        if scheduleStore?.schedule != nil || scheduleStore?.clearedAt != nil { items.append(.schedule) }
        enqueueSave(items)
    }

    private func markSynced() {
        let now = Date()
        UserDefaults.standard.set(now, forKey: lastSyncKey)
        if !status.isProblem || status == .failed("") { status = .upToDate(now) }
        if case .failed = status { status = .upToDate(now) }
    }

    private func handle(_ error: Error) {
        switch (error as? CKError)?.code {
        case .notAuthenticated?: status = .noAccount
        case .quotaExceeded?:    status = .quotaExceeded
        default:                 status = .failed(error.localizedDescription)
        }
        log.error("sync: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: Record ⇄ modelli

    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let item = SyncItem(recordName: recordID.recordName) else { return nil }
        let enc = JSONEncoder()
        let record = existingRecord(recordID, type: item.recordType)
        switch item {
        case .grade(let id):
            guard let g = grades?.grades.first(where: { $0.id == id }),
                  let data = try? enc.encode(g) else { return nil }
            record["payload"] = data as NSData
            record["modifiedAt"] = g.modifiedAt as NSDate
        case .note(let id):
            guard let n = notes?.notes.first(where: { $0.id == id }),
                  let data = try? enc.encode(n) else { return nil }
            record["payload"] = data as NSData
            record["modifiedAt"] = n.modifiedAt as NSDate
        case .schedule:
            if let s = scheduleStore?.schedule, let data = try? enc.encode(s) {
                let url = assetsDirectory.appendingPathComponent("schedule.json")
                guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
                record["payloadAsset"] = CKAsset(fileURL: url)
                record["modifiedAt"] = s.modifiedAt as NSDate
                record["deleted"] = 0 as NSNumber
            } else if let cleared = scheduleStore?.clearedAt {
                record["payloadAsset"] = nil
                record["modifiedAt"] = cleared as NSDate
                record["deleted"] = 1 as NSNumber
            } else {
                return nil
            }
        }
        return record
    }

    private func existingRecord(_ id: CKRecord.ID, type: String) -> CKRecord {
        if let data = systemFields[id.recordName],
           let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            coder.requiresSecureCoding = true
            let record = CKRecord(coder: coder)
            coder.finishDecoding()
            if let record { return record }
        }
        return CKRecord(recordType: type, recordID: id)
    }

    private func remember(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        systemFields[record.recordID.recordName] = coder.encodedData
    }

    private func apply(modified records: [CKRecord], deleted ids: [CKRecord.ID]) {
        let dec = JSONDecoder()
        var gradeUps: [Grade] = [], noteUps: [Note] = []
        var gradeDels = Set<UUID>(), noteDels = Set<UUID>()
        for record in records {
            remember(record)
            switch SyncItem(recordName: record.recordID.recordName) {
            case .grade?:
                if let d = record["payload"] as? Data, let g = try? dec.decode(Grade.self, from: d) { gradeUps.append(g) }
            case .note?:
                if let d = record["payload"] as? Data, let n = try? dec.decode(Note.self, from: d) { noteUps.append(n) }
            case .schedule?:
                let deleted = (record["deleted"] as? Int ?? 0) == 1
                let modified = record["modifiedAt"] as? Date ?? .distantPast
                let data = (record["payloadAsset"] as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) }
                let s = data.flatMap { try? dec.decode(ScheduleData.self, from: $0) }
                scheduleStore?.applyRemote(schedule: s, remoteModifiedAt: modified, deleted: deleted)
            case nil:
                break
            }
        }
        for id in ids {
            systemFields[id.recordName] = nil
            switch SyncItem(recordName: id.recordName) {
            case .grade(let uuid)?: gradeDels.insert(uuid)
            case .note(let uuid)?:  noteDels.insert(uuid)
            default: break
            }
        }
        saveSystemFields()
        if !gradeUps.isEmpty || !gradeDels.isEmpty { grades?.applyRemote(upserts: gradeUps, deletions: gradeDels) }
        if !noteUps.isEmpty || !noteDels.isEmpty { notes?.applyRemote(upserts: noteUps, deletions: noteDels) }
    }

    private func handleSent(_ e: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
        for saved in e.savedRecords { remember(saved) }
        for id in e.deletedRecordIDs { systemFields[id.recordName] = nil }
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var serverWinners: [CKRecord] = []
        for failure in e.failedRecordSaves {
            let record = failure.record
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { continue }
                remember(server)
                let local = record["modifiedAt"] as? Date
                let remote = server["modifiedAt"] as? Date ?? .distantPast
                if SyncMerge.remoteWins(local: local, remote: remote) { serverWinners.append(server) }
                else { retry.append(.saveRecord(record.recordID)) }
            case .zoneNotFound:
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                systemFields[record.recordID.recordName] = nil
                retry.append(.saveRecord(record.recordID))
            case .unknownItem:
                systemFields[record.recordID.recordName] = nil
                retry.append(.saveRecord(record.recordID))
            case .quotaExceeded:
                status = .quotaExceeded
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled, .requestRateLimited:
                break   // CKSyncEngine riprova da solo
            default:
                log.error("save \(record.recordID.recordName, privacy: .public): \(failure.error.localizedDescription, privacy: .public)")
            }
        }
        saveSystemFields()
        if !serverWinners.isEmpty { apply(modified: serverWinners, deleted: []) }
        if !retry.isEmpty { engine.state.add(pendingRecordZoneChanges: retry) }
    }

    private func handleAccountChange(_ e: CKSyncEngine.Event.AccountChange) {
        switch e.changeType {
        case .signIn:
            enqueueAllLocal()
            status = .syncing
        case .signOut, .switchAccounts:
            // I dati locali restano sul dispositivo; si riparte da zero col nuovo account.
            systemFields = [:]
            saveSystemFields()
            try? FileManager.default.removeItem(at: stateURL)
            engine = nil
            startEngine(state: nil)
            Task { await refreshAccountStatus() }
        @unknown default:
            break
        }
    }

    // MARK: Persistenza dello stato

    private var supportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private var stateURL: URL { supportDirectory.appendingPathComponent("engine_state.json") }
    private var systemFieldsURL: URL { supportDirectory.appendingPathComponent("system_fields.plist") }
    private var assetsDirectory: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudSyncAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        try? JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    }

    private func loadSystemFields() -> [String: Data] {
        guard let data = try? Data(contentsOf: systemFieldsURL) else { return [:] }
        return (try? PropertyListDecoder().decode([String: Data].self, from: data)) ?? [:]
    }

    private func saveSystemFields() {
        try? PropertyListEncoder().encode(systemFields).write(to: systemFieldsURL, options: .atomic)
    }
```
(Correggi `markSynced` così: `UserDefaults…set(now…)`; `switch status { case .noAccount, .quotaExceeded: break; default: status = .upToDate(now) }`.)

E il delegate in fondo al file:

```swift
extension CloudSyncManager: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let e):
            saveState(e.stateSerialization)
        case .accountChange(let e):
            handleAccountChange(e)
        case .fetchedDatabaseChanges(let e):
            // Zona cancellata (es. dati iCloud rimossi): la ricreiamo coi dati locali.
            if e.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
                systemFields = [:]
                saveSystemFields()
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                enqueueAllLocal()
            }
        case .fetchedRecordZoneChanges(let e):
            apply(modified: e.modifications.map(\.record), deleted: e.deletions.map(\.recordID))
        case .sentRecordZoneChanges(let e):
            handleSent(e, engine: syncEngine)
        case .willFetchChanges, .willSendChanges:
            if !status.isProblem { status = .syncing }
        case .didFetchChanges, .didSendChanges:
            markSynced()
        case .sentDatabaseChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await self.recordForSending(recordID, engine: syncEngine)
        }
    }

    private func recordForSending(_ id: CKRecord.ID, engine: CKSyncEngine) -> CKRecord? {
        if let record = record(for: id) { return record }
        // L'elemento non esiste più in locale: togliamo il salvataggio in coda.
        engine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
        return nil
    }
}
```

- [ ] **Step 4: Entitlements** — `FMT II/FMT II.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.com.davide.fmtII</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
	<key>com.apple.developer.ubiquity-kvstore-identifier</key>
	<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
</dict>
</plist>
```
In `project.pbxproj`, nelle due configurazioni del target app (quelle con `PRODUCT_BUNDLE_IDENTIFIER = com.davide.fmtII`) aggiungi:
```
				CODE_SIGN_ENTITLEMENTS = "FMT II/FMT II.entitlements";
				INFOPLIST_KEY_UIBackgroundModes = "remote-notification";
```

- [ ] **Step 5: Avvio** — in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` prima del `return true`: `application.registerForRemoteNotifications()`. In `ContentView.onAppear`, dopo il blocco `#if DEBUG … #endif` del seed:

```swift
            CloudSyncManager.shared.start(grades: gradesStore, notes: notesStore, schedule: store)
            SettingsSync.shared.start()
```
(`SettingsSync` arriva nel Task 7: se esegui i task in ordine, aggiungi la seconda riga nel Task 7.)

- [ ] **Step 6: Build + test** — atteso PASS; poi build Debug per simulatore:
```bash
xcodebuild build -project "FMT II.xcodeproj" -scheme "FMT II" -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -allowProvisioningUpdates 2>&1 | grep -E "error:|warning: .*CloudSync|BUILD" | tail -20
```
Atteso `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit** — `git add -A && git commit -m "feat(sync): CKSyncEngine, entitlements iCloud e avvio"`

---

### Task 7: Impostazioni scuola via iCloud key-value

**Files:**
- Create: `FMT II/Services/SettingsSync.swift`
- Modify: `FMT II/Models/GradeModel.swift` (`GradesStore.init`, nuovo `reloadColors()`), `FMT II/ContentView.swift`
- Test: `FMT IITests/SettingsSyncTests.swift`

**Interfaces:**
- Produces: `SettingsSync.shared.start()`, `SettingsSync.syncedKeys: [String]`, `SettingsSync.same(_:_:) -> Bool`, `Notification.Name.fmtSyncedSettingsChanged`.

- [ ] **Step 1: Test**:

```swift
import XCTest
@testable import FMT_II

final class SettingsSyncTests: XCTestCase {
    func testDevicePreferencesAreNotSynced() {
        for local in ["appearanceMode", "dynamicTypeLevel", "useLiveTime", "manualDayRaw", "manualTime",
                      "appSectionRaw", "hasSeenTutorial", "hasCompletedOnboarding", "lastSeenWhatsNew"] {
            XCTAssertFalse(SettingsSync.syncedKeys.contains(local), local)
        }
    }

    func testSchoolSettingsAreSynced() {
        XCTAssertEqual(Set(SettingsSync.syncedKeys),
                       ["sufficientGrade", "maxGrade", "periodSystem", "period1EndTimestamp",
                        "fmt_subject_colors", "fmt_entity_colors"])
    }

    func testSameComparesValues() {
        XCTAssertTrue(SettingsSync.same(6.0, 6.0))
        XCTAssertFalse(SettingsSync.same(6.0, 5.5))
        XCTAssertTrue(SettingsSync.same(Data([1, 2]), Data([1, 2])))
        XCTAssertFalse(SettingsSync.same(nil, 1))
        XCTAssertTrue(SettingsSync.same(nil, nil))
    }
}
```

- [ ] **Step 2: Esegui** — atteso FAILED (`SettingsSync` mancante).

- [ ] **Step 3: `SettingsSync.swift`:**

```swift
import Foundation

extension Notification.Name {
    /// Impostazioni scuola cambiate da un altro dispositivo.
    static let fmtSyncedSettingsChanged = Notification.Name("fmtSyncedSettingsChanged")
}

/// Impostazioni "di scuola" condivise via iCloud key-value store. Le preferenze
/// del dispositivo (tema, testo, tutorial…) restano locali.
@MainActor
final class SettingsSync {
    static let shared = SettingsSync()
    static let syncedKeys = ["sufficientGrade", "maxGrade", "periodSystem", "period1EndTimestamp",
                             "fmt_subject_colors", "fmt_entity_colors"]

    private let kvs = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private var applyingRemote = false
    private var started = false

    private init() {}

    func start() {
        guard !started, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        started = true
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: kvs, queue: .main) { [weak self] note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? SettingsSync.syncedKeys
            MainActor.assumeIsolated { self?.pull(keys: keys) }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.push() }
        }
        kvs.synchronize()
        // Primo avvio: i valori già in iCloud vincono, quelli solo locali salgono.
        pull(keys: Self.syncedKeys.filter { kvs.object(forKey: $0) != nil })
        push()
    }

    private func push() {
        guard !applyingRemote else { return }
        for key in Self.syncedKeys {
            guard let local = defaults.object(forKey: key) else { continue }
            if !Self.same(local, kvs.object(forKey: key)) { kvs.set(local, forKey: key) }
        }
    }

    private func pull(keys: [String]) {
        let relevant = keys.filter { Self.syncedKeys.contains($0) }
        guard !relevant.isEmpty else { return }
        applyingRemote = true
        defer { applyingRemote = false }
        var changed = false
        for key in relevant {
            guard let remote = kvs.object(forKey: key) else { continue }
            if !Self.same(remote, defaults.object(forKey: key)) {
                defaults.set(remote, forKey: key)
                changed = true
            }
        }
        guard changed else { return }
        // Forza il refresh delle tinte docenti/classi nelle viste.
        defaults.set(defaults.integer(forKey: "entityColorsVersion") + 1, forKey: "entityColorsVersion")
        NotificationCenter.default.post(name: .fmtSyncedSettingsChanged, object: nil)
    }

    nonisolated static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil):        return true
        case let (a?, b?):      return (a as AnyObject).isEqual(b)
        default:                return false
        }
    }
}
```

- [ ] **Step 4: GradesStore** — sposta il caricamento dei colori in `func reloadColors()` (stesso codice di oggi in `init`) e in `init` aggiungi:

```swift
        reloadColors()
        NotificationCenter.default.addObserver(forName: .fmtSyncedSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadColors() }
        }
```
In `ContentView.onAppear` aggiungi `SettingsSync.shared.start()` dopo `CloudSyncManager.shared.start(…)`.

- [ ] **Step 5: Esegui** — atteso PASS.

- [ ] **Step 6: Commit** — `git commit -am "feat(sync): impostazioni scuola su iCloud key-value"` (+ `git add` del nuovo file e del test).

---

### Task 8: Sezione «Sincronizzazione iCloud» in Impostazioni

**Files:**
- Modify: `FMT II/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `CloudSyncManager.shared.status`, `.label`, `.isProblem`, `syncNow()`.

- [ ] **Step 1: Sezione** — proprietà `@ObservedObject private var sync = CloudSyncManager.shared`; nel `Form` inserisci `iCloudSection` dopo `valutazioneSection`:

```swift
    private var iCloudSection: some View {
        Section {
            HStack {
                Self.row("iCloud", icon: "icloud.fill", "#38BDF8")
                Spacer()
                Text(sync.status.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(sync.status.isProblem ? Color(hex: "#FB923C")! : .secondary)
            }
            Button {
                Task { await sync.syncNow() }
            } label: {
                Self.row("Sincronizza ora", icon: "arrow.triangle.2.circlepath", "#4E7CF6")
                    .foregroundStyle(.primary)
            }
            .disabled(sync.status == .off || sync.status == .syncing || sync.status == .noAccount)
        } header: {
            Self.header("Sincronizzazione iCloud")
        } footer: {
            Text(sync.status == .noAccount
                 ? "Accedi a iCloud nelle Impostazioni di iOS per avere voti, diario e orario su tutti i tuoi dispositivi."
                 : "Voti, diario, orario e impostazioni di scuola si aggiornano su tutti i dispositivi con lo stesso Apple ID.")
        }
        .listRowBackground(Color.sectionCard)
    }
```

- [ ] **Step 2: Build + test** — atteso PASS.
- [ ] **Step 3: Commit** — `git commit -am "feat(sync): stato iCloud e «Sincronizza ora» in Impostazioni"`

---

### Task 9: Banner «Novità 2.2»

**Files:**
- Create: `FMT II/Views/WhatsNewBanner.swift`
- Modify: `FMT II/ContentView.swift`, `FMT II/DemoSeed.swift`
- Test: `FMT IITests/WhatsNewTests.swift`

**Interfaces:**
- Produces: `WhatsNew.version = "2.2"`, `WhatsNew.storageKey = "lastSeenWhatsNew"`, `WhatsNew.shouldShow(tutorialDoneAtLaunch:lastSeen:) -> Bool`, `WhatsNewBanner(onDismiss:)`.

- [ ] **Step 1: Test**:

```swift
import XCTest
@testable import FMT_II

final class WhatsNewTests: XCTestCase {
    func testUpdatingUserSeesBanner() {
        XCTAssertTrue(WhatsNew.shouldShow(tutorialDoneAtLaunch: true, lastSeen: ""))
    }
    func testNewInstallDoesNotSeeBanner() {
        XCTAssertFalse(WhatsNew.shouldShow(tutorialDoneAtLaunch: false, lastSeen: ""))
    }
    func testAlreadySeenDoesNotShow() {
        XCTAssertFalse(WhatsNew.shouldShow(tutorialDoneAtLaunch: true, lastSeen: "2.2"))
    }
    func testFutureVersionSeenDoesNotShow() {
        XCTAssertFalse(WhatsNew.shouldShow(tutorialDoneAtLaunch: true, lastSeen: "2.10"))
    }
}
```

- [ ] **Step 2: Esegui** — atteso FAILED.

- [ ] **Step 3: `WhatsNewBanner.swift`:**

```swift
import SwiftUI

/// Banner «Novità» mostrato una sola volta a chi aggiorna l'app (tutorial già
/// completato prima di questo avvio), mai a chi la installa da zero.
enum WhatsNew {
    static let version = "2.2"
    static let storageKey = "lastSeenWhatsNew"

    static func shouldShow(tutorialDoneAtLaunch: Bool, lastSeen: String) -> Bool {
        tutorialDoneAtLaunch && lastSeen.compare(version, options: .numeric) == .orderedAscending
    }
}

struct WhatsNewBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(AuroraSection.neutral.gradient,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("NOVITÀ · \(WhatsNew.version)")
                        .font(.system(size: 10.5, weight: .heavy))
                        .kerning(1)
                        .foregroundStyle(Color(hex: "#A5B4FC")!)
                    Text("Novità di FMT \(WhatsNew.version)")
                        .font(.system(size: 18, weight: .bold))
                }
                Spacer(minLength: 0)
            }
            feature(icon: "icloud.fill", hex: "#38BDF8",
                    title: "Sincronizzazione iCloud",
                    text: "Voti, diario e orario uguali su iPhone e iPad con lo stesso Apple ID.")
            feature(icon: "clock.fill", hex: "#8B5CF6",
                    title: "Ora d'inizio per classe",
                    text: "Ogni classe può entrare a un orario diverso: Impostazioni → Dati orario.")
            Button(action: onDismiss) {
                Text("Ho capito")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .auroraProminent(.neutral, radius: 13)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .auroraCard(radius: 22)
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
    }

    private func feature(icon: String, hex: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: hex)!)
                .frame(width: 28, height: 28)
                .background(Color(hex: hex)!.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5, weight: .semibold))
                Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
```

- [ ] **Step 4: ContentView** —
```swift
    @AppStorage(WhatsNew.storageKey) private var lastSeenWhatsNew = ""
    /// Valutato una volta all'avvio: il tutorial era già stato fatto (= aggiornamento)?
    @State private var showWhatsNew = WhatsNew.shouldShow(
        tutorialDoneAtLaunch: UserDefaults.standard.bool(forKey: "hasSeenTutorial"),
        lastSeen: UserDefaults.standard.string(forKey: WhatsNew.storageKey) ?? "")
```
Nella prima `TutorialView(onDismiss:)` (quella del `body`), dentro la closure: `lastSeenWhatsNew = WhatsNew.version`. In `pagedSectionContent`, sullo `ZStack` dentro `NavigationStack` aggiungi:
```swift
            .overlay(alignment: .top) {
                if showWhatsNew {
                    WhatsNewBanner {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showWhatsNew = false }
                        lastSeenWhatsNew = WhatsNew.version
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
```
In `DemoSeed.seedIfRequested` aggiungi `UserDefaults.standard.set(WhatsNew.version, forKey: WhatsNew.storageKey)` (gli screenshot App Store non devono mostrare il banner) — ma solo se non è passato `-FMTShowWhatsNew`.

- [ ] **Step 5: Esegui** — atteso PASS.
- [ ] **Step 6: Commit** — `git commit -am "feat: banner Novità 2.2 solo per chi aggiorna"` (+ add nuovi file).

---

### Task 10: Versione, metadati, verifica completa

**Files:**
- Modify: `FMT II.xcodeproj/project.pbxproj` (`MARKETING_VERSION = 2.2.0`, `CURRENT_PROJECT_VERSION = 2` nelle config app)
- Create: `AppStore/metadata/whats-new-2.2.md`
- Modify: `AppStore/metadata/privacy-policy.md`, `FMT II/Views/ManualView.swift` (paragrafo sync + orari per classe), `docs/superpowers/specs/2026-10-11-icloud-sync-v2.2-design.md` (Note: payload sempre Bytes, Schedule sempre CKAsset)

- [ ] **Step 1:** Versioni nel pbxproj (`sed` su `MARKETING_VERSION = 2.1.1` → `2.2.0` e `CURRENT_PROJECT_VERSION = 1` → `2` solo nelle due config con bundle `com.davide.fmtII`).
- [ ] **Step 2:** `whats-new-2.2.md`:
  - IT: «Novità della versione 2.2 • Sincronizzazione iCloud: voti, diario, orario e impostazioni di scuola sempre aggiornati su iPhone e iPad con lo stesso Apple ID. • Ora d'inizio per classe: ogni classe può entrare a un orario diverso (Impostazioni → Dati orario → Inizio diverso per classe). • Piccoli miglioramenti e correzioni.»
  - EN: «What's new in 2.2 • iCloud sync: grades, diary, timetable and school settings stay up to date on iPhone and iPad with the same Apple ID. • Per-class start time: each class can start at a different time (Settings → Timetable data → Different start per class). • Minor improvements and fixes.»
- [ ] **Step 3:** Privacy policy: paragrafo «I dati restano sul dispositivo e, se iCloud è attivo, nel tuo account iCloud privato (CloudKit). Lo sviluppatore non ha accesso a questi dati e non usa server propri.»
- [ ] **Step 4:** Test completi (`xcodebuild test` senza `-only-testing` per gli unit test) → atteso `TEST SUCCEEDED`.
- [ ] **Step 5:** Avvio su iPhone 15 Pro e iPad Pro 11'' con dati demo e banner forzato (`-FMTSeedDemo -FMTShowWhatsNew`), screenshot di: banner, Impostazioni → iCloud, Dati orario con toggle on (1C 08:10, 3ªB 09:10), vista settimana in modalità classe e docente.
- [ ] **Step 6: Commit** — `git commit -am "chore(release): 2.2.0 — metadati, privacy, manuale"`

---

### Task 11: Rilascio (con conferme)

- [ ] **Step 1: GitHub** — `git push -u origin feature/ui-round-3`, `git push -u origin feature/icloud-sync-v2.2`, `gh pr create --base main --head feature/icloud-sync-v2.2` (titolo «FMT 2.2 — sync iCloud, inizio per classe», corpo con riepilogo + nota che la PR include anche i 29 commit della 2.1.1). Poi `ccd_pr` get_status/bind.
- [ ] **Step 2: CloudKit** — eseguire l'app Debug con un account iCloud (simulatore/dispositivo dell'utente) e aggiungere un voto, una nota e un orario così lo schema Development contiene `Grade`, `Note`, `Schedule` con `payload`, `payloadAsset`, `modifiedAt`, `deleted`; nella CloudKit Console: indici `recordName` queryable non servono (CKSyncEngine usa i change token). **Deploy Schema Changes to Production** — azione sull'account: chiedere conferma all'utente.
- [ ] **Step 3: Archive + upload** —
```bash
xcodebuild archive -project "FMT II.xcodeproj" -scheme "FMT II" -configuration Release -destination 'generic/platform=iOS' -archivePath build/FMT-2.2.0.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/FMT-2.2.0.xcarchive -exportOptionsPlist build/ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
```
con `ExportOptions.plist` = `method: app-store-connect`, `destination: upload`, `teamID: ZR86H7JQD2`. **Chiedere conferma prima dell'upload.**
- [ ] **Step 4: App Store Connect** — nuova versione 2.2.0, «Novità» IT/EN da `whats-new-2.2.md`, selezionare la build. **Chiedere conferma esplicita prima di «Invia per la revisione».**
