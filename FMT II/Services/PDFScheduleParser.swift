import Foundation
import CoreGraphics
import PDFKit
import Vision

// MARK: - Internal types

private struct TextItem {
    var str: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var page: Int
}

private struct TextRow {
    var page: Int
    var y: Double
    var items: [TextItem]
}

// MARK: - Public entry point

enum PDFParseError: LocalizedError {
    case noTextFound
    case noLessonsFound

    var errorDescription: String? {
        switch self {
        case .noTextFound: return L("Il PDF non contiene testo selezionabile.")
        case .noLessonsFound: return L("Nessuna lezione trovata nel PDF.")
        }
    }
}

func parseSchedulePDF(data: Data, sourceName: String) throws -> ScheduleData {
    guard let pdfDoc = PDFDocument(data: data) else {
        throw PDFParseError.noTextFound
    }

    var allItems: [TextItem] = []

    for pageIndex in 0..<pdfDoc.pageCount {
        guard let page = pdfDoc.page(at: pageIndex) else { continue }
        let pageItems = extractTextItems(from: page, pageNumber: pageIndex + 1)
        allItems.append(contentsOf: pageItems)
    }

    guard !allItems.isEmpty else { throw PDFParseError.noTextFound }

    var warnings: [String] = []
    let rows = groupRows(allItems)
    let startsFrom = detectStartDate(rows)
    let columnStarts = detectColumnStarts(rows)
    let fallback: [Double] = [127.43, 263.85, 400.5, 536.92, 673.55]
    let usedColumns = columnStarts.count == dayOrder.count ? columnStarts : fallback

    let classLessons = extractClassLessons(rows, columns: usedColumns)
    let teacherLessons = extractGlobalTeacherLessons(rows)
    let useTeacherLayout = teacherLessons.count > classLessons.count
    let rawLessons = useTeacherLayout ? teacherLessons : classLessons

    if !useTeacherLayout && columnStarts.count < dayOrder.count {
        warnings.append("Colonne non riconosciute automaticamente: usato il layout standard del PDF.")
    }

    let periods = buildPeriods(rawLessons.map { $0.startTime })
    let periodByNumber = Dictionary(uniqueKeysWithValues: periods.map { ($0.number, $0) })

    let lessons = rawLessons.map { lesson -> Lesson in
        let period = periodByNumber[lesson.period]
        let startTime = period?.startTime ?? lesson.startTime
        let endTime = period?.endTime ?? addMinutes(startTime, 60)
        return Lesson(
            id: lessonId(lesson.className, lesson.day, startTime, lesson.teacher),
            className: lesson.className,
            teacher: lesson.teacher,
            day: lesson.day,
            dayLabel: lesson.dayLabel,
            period: lesson.period,
            startTime: startTime,
            endTime: endTime,
            sourcePage: lesson.sourcePage
        )
    }

    if lessons.isEmpty {
        warnings.append("Non sono state trovate lezioni nel PDF.")
    }

    let classes = uniqueSorted(lessons.map { $0.className }, compare: compareClassNames)
    let teachers = uniqueSorted(lessons.map { $0.teacher }) { $0.compare($1, locale: Locale(identifier: "it")) == .orderedAscending }

    return ScheduleData(
        id: UUID().uuidString,
        sourceName: sourceName,
        importedAt: ISO8601DateFormatter().string(from: Date()),
        startsFrom: startsFrom,
        days: dayOrder.map { DayInfo(id: $0, label: dayLabels[$0]!) },
        periods: periods,
        classes: classes,
        teachers: teachers,
        lessons: lessons,
        warnings: warnings
    )
}

// MARK: - Text extraction

private func extractTextItems(from page: PDFPage, pageNumber: Int) -> [TextItem] {
    guard page.pageRef != nil else { return [] }
    var items: [TextItem] = []
    let mediaBox = page.bounds(for: .mediaBox)
    let pageHeight = mediaBox.height

    // Use PDFKit selection-based extraction for reliability
    guard let fullString = page.string, !fullString.isEmpty else { return [] }

    // Extract character-by-character bounding boxes by word
    // Group into "words" using PDFKit selections
    let nsString = fullString as NSString
    let totalLength = nsString.length

    var wordStart = 0
    var inWord = false

    var wordRanges: [NSRange] = []
    for i in 0..<totalLength {
        let char = nsString.character(at: i)
        let isSpace = char == 32 || char == 9 || char == 10 || char == 13
        if !isSpace && !inWord {
            wordStart = i
            inWord = true
        } else if isSpace && inWord {
            wordRanges.append(NSRange(location: wordStart, length: i - wordStart))
            inWord = false
        }
    }
    if inWord {
        wordRanges.append(NSRange(location: wordStart, length: totalLength - wordStart))
    }

    for range in wordRanges {
        guard let selection = page.selection(for: range) else { continue }
        let bounds = selection.bounds(for: page)
        guard bounds != .zero, bounds != .null else { continue }
        let word = nsString.substring(with: range).trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { continue }

        let x = Double(bounds.minX)
        let y = Double(pageHeight - bounds.maxY) // flip Y to match PDF coordinate style
        items.append(TextItem(str: word, x: x, y: y, width: Double(bounds.width), height: Double(bounds.height), page: pageNumber))
    }

    return items
}

// MARK: - Row grouping

private func groupRows(_ items: [TextItem]) -> [TextRow] {
    var rows: [TextRow] = []
    let sorted = items.sorted { a, b in
        if a.page != b.page { return a.page < b.page }
        if abs(a.y - b.y) > 1.2 { return a.y < b.y }
        return a.x < b.x
    }

    for item in sorted {
        if let idx = rows.firstIndex(where: { $0.page == item.page && abs($0.y - item.y) <= 1.2 }) {
            rows[idx].items.append(item)
        } else {
            rows.append(TextRow(page: item.page, y: item.y, items: [item]))
        }
    }

    return rows.map { row in
        TextRow(page: row.page, y: row.y, items: row.items.sorted { $0.x < $1.x })
    }.sorted { a, b in
        if a.page != b.page { return a.page < b.page }
        return a.y < b.y
    }
}

// MARK: - Column detection

private let timePattern = /^\d{1,2}:\d{2}$/

private func detectColumnStarts(_ rows: [TextRow]) -> [Double] {
    var counts: [Double: Int] = [:]

    for row in rows {
        let hasTimeItem = row.items.contains { item in
            item.x >= 70 && item.x <= 125 && (try? timePattern.wholeMatch(in: item.str)) != nil
        }
        guard hasTimeItem else { continue }

        for item in row.items {
            if item.x < 120 || item.str == "CLASSE" || item.str == "Ora" { continue }
            let rounded = (item.x * 2).rounded() / 2
            counts[rounded, default: 0] += 1
        }
    }

    return counts
        .sorted { $0.value > $1.value }
        .prefix(dayOrder.count)
        .map { $0.key }
        .sorted()
}

private func detectStartDate(_ rows: [TextRow]) -> String? {
    let text = rows.prefix(10).flatMap { $0.items.map { $0.str } }.joined(separator: " ")
    guard let match = text.range(of: #"\bDAL\s+(\d{2})/(\d{2})/(\d{4})\b"#, options: .regularExpression) else { return nil }
    let matched = String(text[match])
    let parts = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
    guard parts.count >= 3 else { return nil }
    return "\(parts[2])-\(parts[1])-\(parts[0])"
}

// MARK: - Class-based layout extraction

private func extractClassLessons(_ rows: [TextRow], columns: [Double]) -> [Lesson] {
    var lessons: [Lesson] = []
    var currentClass = ""

    for row in rows {
        if let classItem = row.items.first(where: { $0.x < 70 && isClassName($0.str) }) {
            currentClass = normalizeClassName(classItem.str)
        }

        guard let timeItem = row.items.first(where: { $0.x >= 70 && $0.x <= 125 && (try? timePattern.wholeMatch(in: $0.str)) != nil }),
              !currentClass.isEmpty else { continue }

        let parsedStart = normalizeTime(timeItem.str)
        let hour = Int(parsedStart.prefix(2)) ?? 8
        let period = max(1, hour - 7)
        let startTime = periodToStartTime(period)

        var columnWords: [Int: [String]] = [:]
        for item in row.items {
            guard item.str != timeItem.str && item.x >= 120 else { continue }
            let dayIndex = nearestColumnIndex(item.x, columns: columns)
            guard dayIndex >= 0, dayIndex < dayOrder.count else { continue }
            columnWords[dayIndex, default: []].append(item.str)
        }
        for (dayIndex, words) in columnWords {
            let teacher = normalizeTeacherName(words.joined(separator: " "))
            guard !teacher.isEmpty else { continue }
            let day = dayOrder[dayIndex]
            lessons.append(Lesson(
                id: "", className: currentClass, teacher: teacher,
                day: day, dayLabel: dayLabels[day]!,
                period: period, startTime: startTime,
                endTime: addMinutes(startTime, 60), sourcePage: row.page
            ))
        }
    }

    return lessons
}

// MARK: - Global teacher layout extraction

private func extractGlobalTeacherLessons(_ rows: [TextRow]) -> [Lesson] {
    let columnStarts = detectGlobalColumnStarts(rows)
    guard columnStarts.count >= 12 else { return [] }

    let teacherBoundary = (columnStarts.min() ?? 0) - 15
    var lessons: [Lesson] = []

    for row in rows {
        let teacherStr = row.items.filter { $0.x < teacherBoundary }.map { $0.str }.joined(separator: " ")
        let teacher = normalizeTeacherName(teacherStr)
        guard !teacher.isEmpty, teacher != "DOCENTE" else { continue }

        for item in row.items {
            guard item.x >= teacherBoundary, isClassName(item.str) else { continue }
            let colIndex = nearestColumnIndex(item.x, columns: columnStarts)
            guard colIndex >= 0 else { continue }
            let dayIndex = colIndex / 6
            guard dayIndex < dayOrder.count else { continue }
            let day = dayOrder[dayIndex]
            let period = (colIndex % 6) + 1
            let startTime = periodToStartTime(period)
            lessons.append(Lesson(
                id: "", className: normalizeClassName(item.str), teacher: teacher,
                day: day, dayLabel: dayLabels[day]!,
                period: period, startTime: startTime,
                endTime: addMinutes(startTime, 60), sourcePage: row.page
            ))
        }
    }

    return lessons
}

private func detectGlobalColumnStarts(_ rows: [TextRow]) -> [Double] {
    if let headerRow = rows.first(where: { row in
        let dayTokens = row.items.filter { $0.x > 300 && isShortDayToken($0.str) }.count
        return row.items.contains { $0.str.lowercased() == "docente" } && dayTokens >= 12
    }) {
        return headerRow.items.filter { $0.x > 300 && isShortDayToken($0.str) }.map { $0.x }.sorted()
    }

    if let periodRow = rows.first(where: { row in
        row.items.filter { $0.x > 300 && $0.str.range(of: "^[1-6]$", options: .regularExpression) != nil }.count >= 12
    }) {
        return periodRow.items.filter { $0.x > 300 && $0.str.range(of: "^[1-6]$", options: .regularExpression) != nil }.map { $0.x }.sorted()
    }

    return []
}

// MARK: - Helpers

private func isShortDayToken(_ value: String) -> Bool {
    value.range(of: "^(lun|mar|mer|gio|ven)$", options: [.regularExpression, .caseInsensitive]) != nil
}

private func nearestColumnIndex(_ x: Double, columns: [Double]) -> Int {
    var nearest = -1
    var distance = Double.infinity
    for (index, col) in columns.enumerated() {
        let d = abs(x - col)
        if d < distance { distance = d; nearest = index }
    }
    return distance <= 18 ? nearest : -1
}

private func isClassName(_ value: String) -> Bool {
    value.range(of: #"^\d{1,2}\s*[A-Z](?:[\s\-]*[A-Z]){0,3}$"#, options: [.regularExpression, .caseInsensitive]) != nil
}

private func normalizeClassName(_ value: String) -> String {
    value.components(separatedBy: .whitespaces).joined().uppercased()
}

private func normalizeTeacherName(_ value: String) -> String {
    value.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ").uppercased()
}

private func normalizeTime(_ value: String) -> String {
    let parts = value.split(separator: ":")
    guard parts.count == 2 else { return value }
    return String(format: "%02d:%@", Int(parts[0]) ?? 0, String(parts[1]))
}

private func buildPeriods(_ times: [String]) -> [Period] {
    let unique = uniqueSorted(times) { minutesFromMidnight($0) < minutesFromMidnight($1) }
    return unique.enumerated().map { index, startTime in
        let endTime = index + 1 < unique.count ? unique[index + 1] : addMinutes(startTime, 60)
        return Period(number: index + 1, startTime: startTime, endTime: endTime)
    }
}

private func uniqueSorted<T: Hashable>(_ values: [T], compare: (T, T) -> Bool) -> [T] {
    Array(Set(values)).sorted(by: compare)
}

func compareClassNames(_ a: String, _ b: String) -> Bool {
    let pattern = /^(\d+)([A-Z]+)$/
    if let ma = try? pattern.wholeMatch(in: a), let mb = try? pattern.wholeMatch(in: b) {
        let secCompare = String(ma.2).compare(String(mb.2), locale: Locale(identifier: "it"))
        if secCompare != .orderedSame { return secCompare == .orderedAscending }
        return Int(ma.1)! < Int(mb.1)!
    }
    return a.compare(b, locale: Locale(identifier: "it")) == .orderedAscending
}

// MARK: - Generalized import (outcome-based)
//
// The legacy `parseSchedulePDF` above handles the two historical layouts and is
// kept byte-for-byte unchanged; `importSchedulePDF` tries it first, so those
// formats keep producing identical data. New layouts go through a structural
// grid detector based on the four elements: classe, giorno/ora, materia, docente.

enum ScheduleField: String, CaseIterable, Equatable {
    case classes, dayTime, subject, teacher

    var label: String {
        switch self {
        case .classes: return L("classi")
        case .dayTime: return L("giorni e ore")
        case .subject: return L("materie")
        case .teacher: return L("docenti")
        }
    }
}

enum ScheduleRejectReason: Equatable {
    case invalidPDF
    case unrecognizedStructure
    case missingElements([ScheduleField])
    case teacherConflict(teacher: String, day: DayId, time: String)
    case subjectConflict(className: String, day: DayId, time: String)
    case implausibleDay(DayId)
    case implausibleTime(String)

    var message: String {
        switch self {
        case .invalidPDF:
            return L("Il file non è un PDF valido.")
        case .unrecognizedStructure:
            return L("La struttura dell'orario non è riconoscibile.")
        case .missingElements(let fields):
            let list = fields.map { $0.label }.joined(separator: ", ")
            return L("Nel PDF mancano troppi elementi (\(list)).")
        case .teacherConflict(let teacher, let day, let time):
            return L("Conflitto: il docente \(teacher) risulta in due classi diverse (\(day.displayName) \(time)).")
        case .subjectConflict(let className, let day, let time):
            return L("Conflitto: la classe \(className) ha due materie nella stessa ora (\(day.displayName) \(time)).")
        case .implausibleDay(let day):
            return L("Orario non plausibile: contiene il giorno \(day.displayName).")
        case .implausibleTime(let time):
            return L("Orario non plausibile: lezioni alle \(time).")
        }
    }
}

enum ScheduleImportOutcome {
    case complete(ScheduleData)
    case partial(ScheduleData, missing: ScheduleField)
    case rejected(ScheduleRejectReason)
}

func importSchedulePDF(data: Data, sourceName: String) -> ScheduleImportOutcome {
    guard let pdfDoc = PDFDocument(data: data) else { return .rejected(.invalidPDF) }

    var allItems: [TextItem] = []
    for pageIndex in 0..<pdfDoc.pageCount {
        guard let page = pdfDoc.page(at: pageIndex) else { continue }
        allItems.append(contentsOf: extractTextItems(from: page, pageNumber: pageIndex + 1))
    }

    var usedOCR = false
    if allItems.isEmpty {
        allItems = ocrTextItems(from: pdfDoc)
        usedOCR = true
    }
    guard !allItems.isEmpty else { return .rejected(.unrecognizedStructure) }

    // 1) Legacy layouts, exactly as today.
    if !usedOCR, let legacy = try? parseSchedulePDF(data: data, sourceName: sourceName), !legacy.lessons.isEmpty {
        return finalizeImport(legacy, missingClasses: false)
    }

    // 2) General grid layouts (per page, merged).
    let pageNumbers = Set(allItems.map { $0.page }).sorted()
    var gridLessons: [Lesson] = []
    var gridTimes: [Int: String] = [:]           // period -> start time (when printed)
    var detectedDays = Set<DayId>()
    var cellValues: [String] = []                // for subject/teacher classification
    var anyGrid = false
    var missingClasses = false

    for pageNo in pageNumbers {
        let pageItems = allItems.filter { $0.page == pageNo }
        let tol = rowTolerance(for: pageItems, usedOCR: usedOCR)
        let rows = groupRowsTol(pageItems, tolerance: tol)
        guard let grid = extractGrid(rows: rows, page: pageNo, usedOCR: usedOCR) else { continue }
        anyGrid = true
        missingClasses = missingClasses || grid.missingClasses
        detectedDays.formUnion(grid.days)
        for (p, t) in grid.periodTimes { gridTimes[p] = t }
        gridLessons.append(contentsOf: grid.lessons)
        cellValues.append(contentsOf: grid.cellTexts)
    }

    if anyGrid && !gridLessons.isEmpty {
        // Canonicalize OCR noise, then decide whether cells are subjects or teachers.
        if usedOCR {
            let canonical = canonicalizeValues(gridLessons.map { $0.teacher })
            gridLessons = gridLessons.enumerated().map { i, l in
                var l = l; l.teacher = canonical[i]; return l
            }
        }
        let distinct = Array(Set(gridLessons.map { $0.teacher }))
        let splits = distinct.map { splitSubjectTeacher($0) }
        let mixedCount = splits.filter { !$0.subject.isEmpty && !$0.teacher.isEmpty }.count
        let cellsAreMixed = !distinct.isEmpty && Double(mixedCount) / Double(distinct.count) >= 0.5
        let subjectish = distinct.filter { looksLikeSubject($0) }.count
        let cellsAreSubjects = !cellsAreMixed && !distinct.isEmpty
            && (Double(subjectish) / Double(distinct.count) >= 0.5)

        var lessons: [Lesson] = gridLessons.map { raw in
            var l = raw
            if cellsAreMixed {
                // Cells carry both ("Matematica ROSSI").
                let (subj, teach) = splitSubjectTeacher(raw.teacher)
                l.subject = subj
                l.teacher = teach
            } else if cellsAreSubjects {
                l.subject = raw.teacher
                l.teacher = ""
            }
            return l
        }

        // Rebuild coherent periods and times.
        let periodsUsed = Set(lessons.map { $0.period }).sorted()
        var periods: [Period] = []
        for (idx, p) in periodsUsed.enumerated() {
            let start = gridTimes[p] ?? periodToStartTime(p)
            let nextStart = idx + 1 < periodsUsed.count
                ? (gridTimes[periodsUsed[idx + 1]] ?? periodToStartTime(periodsUsed[idx + 1]))
                : addMinutes(start, 60)
            periods.append(Period(number: p, startTime: start, endTime: nextStart))
        }
        var periodByNumber: [Int: Period] = [:]
        for p in periods { periodByNumber[p.number] = p }

        lessons = lessons.map { l in
            var l = l
            let p = periodByNumber[l.period]
            l.startTime = p?.startTime ?? periodToStartTime(l.period)
            l.endTime = p?.endTime ?? addMinutes(l.startTime, 60)
            l.id = lessonId(l.className, l.day, l.startTime, l.teacher.isEmpty ? l.subject : l.teacher)
            return l
        }

        let days = weekOrder.filter { detectedDays.contains($0) }
        let classes = uniqueSorted(lessons.map { $0.className }, compare: compareClassNames)
        let teachers = uniqueSorted(lessons.map { $0.teacher }.filter { !$0.isEmpty }) {
            $0.compare($1, locale: Locale(identifier: "it")) == .orderedAscending
        }
        var subjectTeachers: [String: String] = [:]
        for l in lessons where !l.subject.isEmpty && !l.teacher.isEmpty {
            subjectTeachers[l.subject] = l.teacher
        }

        var schedule = ScheduleData(
            id: UUID().uuidString,
            sourceName: sourceName,
            importedAt: ISO8601DateFormatter().string(from: Date()),
            startsFrom: nil,
            days: days.map { DayInfo(id: $0, label: dayLabels[$0]!) },
            periods: periods,
            classes: classes,
            teachers: teachers,
            lessons: lessons,
            warnings: []
        )
        schedule.subjectTeachers = subjectTeachers
        return finalizeImport(schedule, missingClasses: missingClasses)
    }

    // 3) Roster table (classe / materia / docente without day-hour grid).
    for pageNo in pageNumbers {
        let pageItems = allItems.filter { $0.page == pageNo }
        let tol = rowTolerance(for: pageItems, usedOCR: usedOCR)
        let rows = groupRowsTol(pageItems, tolerance: tol)
        if let roster = extractRoster(rows: rows) {
            return .partial(roster.withSource(sourceName), missing: .dayTime)
        }
    }

    return .rejected(.unrecognizedStructure)
}

// MARK: Validation + missing-field policy

private func finalizeImport(_ schedule: ScheduleData, missingClasses: Bool) -> ScheduleImportOutcome {
    let lessons = schedule.lessons

    // Plausibility: days within Mon-Sat.
    let allowedDays: Set<DayId> = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    if let bad = lessons.first(where: { !allowedDays.contains($0.day) }) {
        return .rejected(.implausibleDay(bad.day))
    }
    // Plausibility: times within 07:00-19:00.
    for l in lessons {
        let start = minutesFromMidnight(l.startTime)
        let end = minutesFromMidnight(l.endTime)
        if start < 7 * 60 || end > 19 * 60 || start >= end {
            return .rejected(.implausibleTime("\(l.startTime)–\(l.endTime)"))
        }
    }
    // Conflict: same teacher in two classes at the same day/hour.
    var teacherSlots: [String: String] = [:]
    for l in lessons where !l.teacher.isEmpty {
        let key = "\(l.teacher)|\(l.day.rawValue)|\(l.period)"
        if let other = teacherSlots[key], other != l.className {
            return .rejected(.teacherConflict(teacher: l.teacher, day: l.day, time: l.startTime))
        }
        teacherSlots[key] = l.className
    }
    // Conflict: same class with two subjects at the same day/hour.
    var subjectSlots: [String: String] = [:]
    for l in lessons where !l.subject.isEmpty {
        let key = "\(l.className)|\(l.day.rawValue)|\(l.period)"
        if let other = subjectSlots[key], other != l.subject {
            if ProcessInfo.processInfo.environment["PARSER_DEBUG"] != nil {
                print("DEBUG subject conflict: \(key) '\(other)' vs '\(l.subject)'")
            }
            return .rejected(.subjectConflict(className: l.className, day: l.day, time: l.startTime))
        }
        subjectSlots[key] = l.subject
    }

    var missing: [ScheduleField] = []
    if missingClasses { missing.append(.classes) }
    if lessons.isEmpty { missing.append(.dayTime) }
    if !lessons.contains(where: { !$0.subject.isEmpty }) { missing.append(.subject) }
    if !lessons.contains(where: { !$0.teacher.isEmpty }) { missing.append(.teacher) }

    switch missing.count {
    case 0: return .complete(schedule)
    case 1: return .partial(schedule, missing: missing[0])
    default: return .rejected(.missingElements(missing))
    }
}

// MARK: Grid detection (columns = classes or days, bands = days, rows = periods)

private struct GridResult {
    var lessons: [Lesson]        // teacher field temporarily holds the raw cell text
    var cellTexts: [String]
    var days: Set<DayId>
    var periodTimes: [Int: String]
    var missingClasses: Bool
}

private func rowTolerance(for items: [TextItem], usedOCR: Bool) -> Double {
    guard usedOCR else { return 1.2 }
    let maxY = items.map { $0.y }.max() ?? 800
    return max(4.0, maxY * 0.007)
}

private func groupRowsTol(_ items: [TextItem], tolerance: Double) -> [TextRow] {
    var rows: [TextRow] = []
    let sorted = items.sorted { a, b in
        if abs(a.y - b.y) > tolerance { return a.y < b.y }
        return a.x < b.x
    }
    for item in sorted {
        if let idx = rows.lastIndex(where: { abs($0.y - item.y) <= tolerance }) {
            rows[idx].items.append(item)
        } else {
            rows.append(TextRow(page: item.page, y: item.y, items: [item]))
        }
    }
    return rows.map { row in
        TextRow(page: row.page, y: row.y, items: row.items.sorted { $0.x < $1.x })
    }
}

private let periodTokenPattern = /^(\d{1,2})[aª^°]?$/
private let anyTimePattern = /^(\d{1,2})[.:hH](\d{2})$/

private func extractGrid(rows: [TextRow], page: Int, usedOCR: Bool) -> GridResult? {
    if ProcessInfo.processInfo.environment["PARSER_DEBUG_ROWS"] != nil {
        for row in rows.prefix(14) {
            print("ROW y=\(Int(row.y)) | " + row.items.map { "[\(Int($0.x))+\(Int($0.width))]\($0.str)" }.joined(separator: " "))
        }
    }
    // --- Mode A: columns are classes ---
    if let headerIdx = rows.firstIndex(where: { classHeaderTokens($0).count >= 3 }) {
        // Scan skew can split one printed header line into adjacent rows:
        // merge class tokens from the neighbouring rows too.
        var headerTokens = classHeaderTokens(rows[headerIdx])
        let headerY = rows[headerIdx].y
        let tol = rowTolerance(for: rows.flatMap { $0.items }, usedOCR: usedOCR)
        var lastHeaderIdx = headerIdx
        for (i, row) in rows.enumerated() where i != headerIdx && abs(row.y - headerY) <= tol * 3 {
            headerTokens.append(contentsOf: classHeaderTokens(row))
            lastHeaderIdx = max(lastHeaderIdx, i)
        }
        let columns = dedupeColumns(headerTokens)
        if columns.count >= 3 {
            if ProcessInfo.processInfo.environment["PARSER_DEBUG"] != nil {
                print("DEBUG page \(page) columns: \(columns.map { "\($0.name)@\(Int($0.x))" }.joined(separator: " "))")
            }
            return extractClassColumnsGrid(rows: rows, headerIdx: lastHeaderIdx, columns: columns, page: page, usedOCR: usedOCR)
        }
    }
    // --- Mode B: columns are days (single unnamed class) ---
    if let headerIdx = rows.firstIndex(where: { dayHeaderTokens($0).count >= 3 }) {
        let columns = dayHeaderTokens(rows[headerIdx])
        if columns.count >= 3 {
            return extractDayColumnsGrid(rows: rows, headerIdx: headerIdx, columns: columns, page: page)
        }
    }
    return nil
}

private func extractClassColumnsGrid(rows: [TextRow], headerIdx: Int, columns: [(name: String, x: Double)], page: Int, usedOCR: Bool) -> GridResult? {
    let colXs = columns.map { $0.x }
    let spacing = medianGap(colXs)
    guard spacing > 0 else { return nil }
    let leftBoundary = colXs[0] - spacing * 0.6
    let headerY = rows[headerIdx].y

    // Day anchors: names in the left margin (or, failing that, the right margin).
    var anchors: [(day: DayId, y: Double)] = []
    for row in rows {
        for item in row.items where item.x < leftBoundary {
            if let day = dayFromToken(item.str) { anchors.append((day, item.y + item.height / 2)) }
        }
    }
    if anchors.isEmpty {
        let rightBoundary = (colXs.last ?? 0) + spacing * 0.6
        for row in rows {
            for item in row.items where item.x > rightBoundary {
                if let day = dayFromToken(item.str) { anchors.append((day, item.y + item.height / 2)) }
            }
        }
    }
    anchors.sort { $0.y < $1.y }
    guard !anchors.isEmpty else { return nil }

    // Band boundaries at midpoints between consecutive day anchors.
    var bandStarts: [Double] = [headerY + 0.1]
    for i in 1..<anchors.count {
        bandStarts.append((anchors[i - 1].y + anchors[i].y) / 2)
    }

    struct DataRow { var y: Double; var period: Int?; var time: String?; var cells: [Int: String] }
    var dataRows: [DataRow] = []

    for row in rows.dropFirst(headerIdx + 1) {
        if isNoiseRow(row) { continue }
        var period: Int? = nil
        var time: String? = nil
        for item in row.items where item.x < leftBoundary {
            if let m = try? periodTokenPattern.wholeMatch(in: item.str), let v = Int(m.1), (1...12).contains(v) {
                period = v
            } else if let m = try? anyTimePattern.wholeMatch(in: item.str), let h = Int(m.1), h <= 23 {
                time = String(format: "%02d:%@", h, String(m.2))
            }
        }
        var cells: [Int: String] = [:]
        var cellWords: [Int: [TextItem]] = [:]
        for rawItem in row.items where rawItem.x >= leftBoundary {
            if dayFromToken(rawItem.str) != nil { continue }   // repeated day label on the right
            if (try? periodTokenPattern.wholeMatch(in: rawItem.str)) != nil && rawItem.x > (colXs.last ?? 0) + spacing * 0.55 { continue }
            // OCR can glue neighbouring cells into one observation: split
            // wide multi-word items back into words with interpolated x.
            var fragments: [TextItem] = [rawItem]
            if usedOCR, rawItem.width > spacing * 1.15, rawItem.str.contains(" ") {
                let words = rawItem.str.components(separatedBy: " ").filter { !$0.isEmpty }
                let totalChars = Double(words.reduce(0) { $0 + $1.count } + words.count - 1)
                var offset = 0.0
                fragments = words.map { w in
                    let frac = Double(w.count) / totalChars
                    let item = TextItem(str: w, x: rawItem.x + offset * rawItem.width,
                                        y: rawItem.y, width: rawItem.width * frac,
                                        height: rawItem.height, page: rawItem.page)
                    offset += frac + 1.0 / totalChars
                    return item
                }
            }
            for item in fragments {
                let center = item.x + item.width / 2
                let col = nearestIndex(center, in: colXs, tolerance: spacing * 0.55)
                guard col >= 0 else { continue }
                cellWords[col, default: []].append(item)
            }
        }
        for (col, words) in cellWords {
            let sorted = words.sorted { $0.x < $1.x }
            var kept: [String] = []
            for w in sorted {
                // Drop OCR near-duplicates from overlapping tiles.
                let lw = w.str.lowercased()
                if kept.contains(where: { k in
                    let lk = k.lowercased()
                    return lk.hasPrefix(lw) || lw.hasPrefix(lk)
                        || (usedOCR && lk.commonPrefix(with: lw).count >= 3)
                        || levenshtein(lk, lw) <= 1
                }) { continue }
                kept.append(w.str)
            }
            // Drop stray digit/punctuation fragments next to real words.
            if kept.contains(where: { $0.rangeOfCharacter(from: .letters) != nil }) {
                kept = kept.filter { $0.rangeOfCharacter(from: .letters) != nil }
            }
            let text = kept.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { cells[col] = text }
        }
        guard !cells.isEmpty else { continue }
        dataRows.append(DataRow(y: row.y, period: period, time: time, cells: cells))
    }
    guard !dataRows.isEmpty else { return nil }

    // If most rows carry a printed period/time, require it (filters footers).
    let withToken = dataRows.filter { $0.period != nil || $0.time != nil }
    let useLeftTokens = Double(withToken.count) >= Double(dataRows.count) * 0.6
    if useLeftTokens { dataRows = withToken }

    func bandIndex(for y: Double) -> Int {
        var idx = 0
        for (i, start) in bandStarts.enumerated() where y >= start { idx = i }
        return idx
    }

    var lessons: [Lesson] = []
    var cellTexts: [String] = []
    var periodTimes: [Int: String] = [:]
    var daysUsed = Set<DayId>()

    if useLeftTokens {
        // Period comes from the printed token (or from the time order).
        var timeToPeriod: [String: Int] = [:]
        let allTimes = uniqueSorted(dataRows.compactMap { $0.time }) { minutesFromMidnight($0) < minutesFromMidnight($1) }
        for (i, t) in allTimes.enumerated() { timeToPeriod[t] = i + 1 }

        // Day bands: the period sequence restarting (…5, 6, 1…) marks a new day.
        // This is robust to labels printed at the top, middle or bottom of the
        // band; if the band count disagrees with the day labels, fall back to
        // y-midpoint assignment.
        let ordered = dataRows.sorted { $0.y < $1.y }
        var bandOfRow: [Int] = []
        var band = 0
        var prevSlot = Int.min
        for rowData in ordered {
            let slot = rowData.period ?? rowData.time.flatMap { timeToPeriod[$0] } ?? (prevSlot + 1)
            if slot <= prevSlot { band += 1 }
            prevSlot = slot
            bandOfRow.append(band)
        }
        let useSequenceBands = band + 1 == anchors.count

        for (i, rowData) in ordered.enumerated() {
            guard let period = rowData.period ?? rowData.time.flatMap({ timeToPeriod[$0] }) else { continue }
            let day = useSequenceBands ? anchors[bandOfRow[i]].day : anchors[bandIndex(for: rowData.y)].day
            daysUsed.insert(day)
            if let t = rowData.time { periodTimes[period] = t }
            for (col, text) in rowData.cells {
                cellTexts.append(text)
                lessons.append(Lesson(
                    id: "", className: columns[col].name, teacher: text,
                    day: day, dayLabel: dayLabels[day]!,
                    period: period, startTime: "", endTime: "", sourcePage: page
                ))
            }
        }
    } else {
        // No printed periods (scanned "tabellone"): within each band, each
        // column's cells become consecutive periods ordered by y.
        var perBandColumn: [String: [(y: Double, col: Int, text: String)]] = [:]
        for rowData in dataRows {
            let b = bandIndex(for: rowData.y)
            for (col, text) in rowData.cells {
                perBandColumn["\(b)|\(col)", default: []].append((rowData.y, col, text))
            }
        }
        for (key, entries) in perBandColumn {
            let b = Int(key.split(separator: "|")[0])!
            let day = anchors[b].day
            daysUsed.insert(day)
            let sorted = entries.sorted { $0.y < $1.y }
            for (i, entry) in sorted.enumerated() {
                cellTexts.append(entry.text)
                lessons.append(Lesson(
                    id: "", className: columns[entry.col].name, teacher: entry.text,
                    day: day, dayLabel: dayLabels[day]!,
                    period: i + 1, startTime: "", endTime: "", sourcePage: page
                ))
            }
        }
    }

    guard !lessons.isEmpty else { return nil }
    return GridResult(lessons: lessons, cellTexts: cellTexts, days: daysUsed, periodTimes: periodTimes, missingClasses: false)
}

private func extractDayColumnsGrid(rows: [TextRow], headerIdx: Int, columns: [(day: DayId, x: Double)], page: Int) -> GridResult? {
    let colXs = columns.map { $0.x }
    let spacing = medianGap(colXs)
    guard spacing > 0 else { return nil }
    let leftBoundary = colXs[0] - spacing * 0.6

    var lessons: [Lesson] = []
    var cellTexts: [String] = []
    var periodTimes: [Int: String] = [:]
    var daysUsed = Set<DayId>()
    var rowTimes: [String] = []

    struct DataRow { var period: Int?; var time: String?; var cells: [Int: String] }
    var dataRows: [DataRow] = []

    for row in rows.dropFirst(headerIdx + 1) {
        if isNoiseRow(row) { continue }
        var period: Int? = nil
        var time: String? = nil
        for item in row.items where item.x < leftBoundary {
            if let m = try? periodTokenPattern.wholeMatch(in: item.str), let v = Int(m.1), (1...12).contains(v) {
                period = v
            } else if let m = try? anyTimePattern.wholeMatch(in: item.str), let h = Int(m.1), h <= 23 {
                time = String(format: "%02d:%@", h, String(m.2))
            }
        }
        var cellWords: [Int: [String]] = [:]
        for item in row.items where item.x >= leftBoundary {
            let center = item.x + item.width / 2
            let col = nearestIndex(center, in: colXs, tolerance: spacing * 0.55)
            guard col >= 0 else { continue }
            cellWords[col, default: []].append(item.str)
        }
        let cells = cellWords.mapValues { $0.joined(separator: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.value.isEmpty }
        guard !cells.isEmpty, period != nil || time != nil else { continue }
        if let t = time { rowTimes.append(t) }
        dataRows.append(DataRow(period: period, time: time, cells: cells))
    }
    guard dataRows.count >= 2 else { return nil }

    let allTimes = uniqueSorted(rowTimes) { minutesFromMidnight($0) < minutesFromMidnight($1) }
    var timeToPeriod: [String: Int] = [:]
    for (i, t) in allTimes.enumerated() { timeToPeriod[t] = i + 1 }

    for (rowIdx, rowData) in dataRows.enumerated() {
        let period = rowData.period ?? rowData.time.flatMap { timeToPeriod[$0] } ?? (rowIdx + 1)
        if let t = rowData.time { periodTimes[period] = t }
        for (col, text) in rowData.cells {
            let day = columns[col].day
            daysUsed.insert(day)
            cellTexts.append(text)
            lessons.append(Lesson(
                id: "", className: "CLASSE", teacher: text,
                day: day, dayLabel: dayLabels[day]!,
                period: period, startTime: "", endTime: "", sourcePage: page
            ))
        }
    }

    guard !lessons.isEmpty else { return nil }
    return GridResult(lessons: lessons, cellTexts: cellTexts, days: daysUsed, periodTimes: periodTimes, missingClasses: true)
}

// MARK: Roster table (no day/hour grid)

private struct RosterResult {
    var schedule: ScheduleData
    func withSource(_ name: String) -> ScheduleData {
        var s = schedule; s.sourceName = name; return s
    }
}

private func extractRoster(rows: [TextRow]) -> RosterResult? {
    func headerKind(_ s: String) -> ScheduleField? {
        let n = normalizedToken(s)
        if n.hasPrefix("class") { return .classes }
        if n.hasPrefix("materi") || n.hasPrefix("disciplin") { return .subject }
        if n.hasPrefix("docent") || n.hasPrefix("prof") || n.hasPrefix("insegnant") { return .teacher }
        return nil
    }
    guard let headerIdx = rows.firstIndex(where: { row in
        row.items.compactMap { headerKind($0.str) }.count >= 2
    }) else { return nil }

    var columns: [(field: ScheduleField, x: Double)] = []
    for item in rows[headerIdx].items {
        if let kind = headerKind(item.str) { columns.append((kind, item.x)) }
    }
    guard columns.count >= 2, columns.contains(where: { $0.field == .classes }) else { return nil }
    let colXs = columns.map { $0.x }
    let spacing = medianGap(colXs)

    var classes: [String] = []
    var teachers: [String] = []
    var subjectTeachers: [String: String] = [:]
    for row in rows.dropFirst(headerIdx + 1) {
        var values: [ScheduleField: String] = [:]
        for item in row.items {
            let col = nearestIndex(item.x, in: colXs, tolerance: max(spacing * 0.7, 40))
            guard col >= 0 else { continue }
            let field = columns[col].field
            values[field] = ((values[field] ?? "") + " " + item.str).trimmingCharacters(in: .whitespaces)
        }
        guard let cls = values[.classes], isClassName(cls.replacingOccurrences(of: "^", with: "")) else { continue }
        let name = normalizeClassName(cls.replacingOccurrences(of: "^", with: ""))
        if !classes.contains(name) { classes.append(name) }
        if let t = values[.teacher] {
            let teacher = normalizeTeacherName(t)
            if !teachers.contains(teacher) { teachers.append(teacher) }
            if let s = values[.subject] { subjectTeachers[s] = teacher }
        }
    }
    guard classes.count >= 2 else { return nil }

    var schedule = ScheduleData(
        id: UUID().uuidString,
        sourceName: "",
        importedAt: ISO8601DateFormatter().string(from: Date()),
        startsFrom: nil,
        days: [],
        periods: [],
        classes: classes.sorted(by: compareClassNames),
        teachers: teachers.sorted { $0.compare($1, locale: Locale(identifier: "it")) == .orderedAscending },
        lessons: [],
        warnings: []
    )
    schedule.subjectTeachers = subjectTeachers
    return RosterResult(schedule: schedule)
}

// MARK: Token helpers

private func normalizedToken(_ s: String) -> String {
    (s.applyingTransform(.stripDiacritics, reverse: false) ?? s)
        .lowercased()
        .components(separatedBy: CharacterSet.letters.inverted)
        .joined()
}

private let cyrillicFixes: [Character: Character] = [
    "А": "A", "В": "B", "С": "C", "Е": "E", "З": "3", "Н": "H", "К": "K",
    "М": "M", "О": "O", "Р": "P", "Т": "T", "У": "Y", "Х": "X", "І": "I"
]

private func fixOCRGlyphs(_ s: String) -> String {
    String(s.map { cyrillicFixes[$0] ?? $0 })
}

/// "1^ A" / "1BL" / "5GSA" -> normalized class name, or nil.
private func classToken(_ raw: String) -> String? {
    let fixed = fixOCRGlyphs(raw).uppercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    guard fixed.range(of: #"^\d{1,2}[A-Z]{1,4}$"#, options: .regularExpression) != nil else { return nil }
    return fixed
}

private func classHeaderTokens(_ row: TextRow) -> [(name: String, x: Double)] {
    var result: [(String, Double)] = []
    var i = 0
    let items = row.items
    while i < items.count {
        let item = items[i]
        // Merge "1^" + "A" split across two words.
        if i + 1 < items.count,
           fixOCRGlyphs(item.str).range(of: #"^\d{1,2}\^?$"#, options: .regularExpression) != nil,
           let merged = classToken(item.str + items[i + 1].str),
           items[i + 1].x - (item.x + item.width) < item.height * 2 {
            result.append((merged, item.x + (items[i + 1].x + items[i + 1].width - item.x) / 2))
            i += 2
            continue
        }
        if let name = classToken(item.str) {
            result.append((name, item.x + item.width / 2))
        }
        i += 1
    }
    return result
}

private func dedupeColumns(_ tokens: [(name: String, x: Double)]) -> [(name: String, x: Double)] {
    let sorted = tokens.sorted { $0.x < $1.x }
    guard sorted.count > 1 else { return sorted }
    let spacing = medianGap(sorted.map { $0.x })
    var result: [(String, Double)] = []
    for t in sorted {
        if let last = result.last, t.x - last.1 < max(spacing * 0.4, 8) { continue }
        result.append(t)
    }
    return result
}

private func dayFromToken(_ raw: String) -> DayId? {
    let n = normalizedToken(raw)
    guard n.count >= 3 else { return nil }
    let prefixes: [(String, DayId)] = [
        ("luned", .monday), ("marted", .tuesday), ("mercoled", .wednesday),
        ("gioved", .thursday), ("venerd", .friday), ("sabat", .saturday), ("domenic", .sunday)
    ]
    for (p, d) in prefixes where n.hasPrefix(p) || p.hasPrefix(n) { return d }
    let shorts: [String: DayId] = [
        "lun": .monday, "mar": .tuesday, "mer": .wednesday,
        "gio": .thursday, "ven": .friday, "sab": .saturday, "dom": .sunday
    ]
    return shorts[n]
}

private func dayHeaderTokens(_ row: TextRow) -> [(day: DayId, x: Double)] {
    var seen = Set<DayId>()
    var result: [(DayId, Double)] = []
    for item in row.items {
        if let d = dayFromToken(item.str), !seen.contains(d) {
            seen.insert(d)
            result.append((d, item.x + item.width / 2))
        }
    }
    return result
}

private func nearestIndex(_ x: Double, in xs: [Double], tolerance: Double) -> Int {
    var best = -1
    var dist = Double.infinity
    for (i, cx) in xs.enumerated() {
        let d = abs(x - cx)
        if d < dist { dist = d; best = i }
    }
    return dist <= tolerance ? best : -1
}

private func medianGap(_ xs: [Double]) -> Double {
    guard xs.count > 1 else { return 0 }
    let gaps = zip(xs.dropFirst(), xs).map { $0 - $1 }.sorted()
    return gaps[gaps.count / 2]
}

private func isNoiseRow(_ row: TextRow) -> Bool {
    let joined = row.items.map { $0.str.lowercased() }.joined(separator: " ")
    return joined.contains("copyright") || joined.contains("www.") || joined.contains("©")
        || joined.contains("pag.") || joined.contains("n.b.")
}

// MARK: Subject vs teacher classification

private let subjectSigle: Set<String> = [
    "it", "ita", "ital", "mat", "mate", "fis", "sci", "scien", "sto", "st", "geo",
    "fil", "filo", "filos", "ing", "ingl", "lat", "gst", "rel", "irc", "dis",
    "spa", "fra", "ted", "mus", "inf", "tec", "dir", "eco", "art", "mot", "gin",
    "ed", "sc", "chim", "bio", "nat", "gr", "grec"
]

private let subjectNames: [String] = [
    "italiano", "matematica", "fisica", "scienze", "scienza", "storia", "geografia",
    "geostoria", "filosofia", "inglese", "latino", "greco", "arte", "disegno",
    "religione", "motorie", "motoria", "spagnolo", "francese", "tedesco", "diritto",
    "economia", "informatica", "tecnologia", "musica", "chimica", "biologia",
    "naturali", "conversazione", "potenziamento", "cambridge", "educazione",
    "civica", "fisiche", "laboratorio", "ginnastica", "attivita", "alternativa",
    "sostegno", "lettere", "lingua", "letteratura", "elettronica", "meccanica",
    "sistemi", "telecomunicazioni", "topografia", "estimo", "costruzioni", "epica"
]

func looksLikeSubject(_ value: String) -> Bool {
    let cleaned = value.components(separatedBy: CharacterSet.decimalDigits).joined()
    let tokens = cleaned
        .components(separatedBy: CharacterSet.letters.inverted)
        .map { normalizedToken($0) }
        .filter { $0.count >= 2 }
    guard !tokens.isEmpty else { return false }
    var matched = 0
    for t in tokens {
        if subjectSigle.contains(t) { matched += 1; continue }
        if subjectNames.contains(where: { $0.hasPrefix(t) || t.hasPrefix($0) }) { matched += 1 }
    }
    return Double(matched) / Double(tokens.count) >= 0.5
}

/// Splits a mixed cell ("Matematica ROSSI") into subject and teacher parts.
private func splitSubjectTeacher(_ value: String) -> (subject: String, teacher: String) {
    let words = value.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    var subjectWords: [String] = []
    var teacherWords: [String] = []
    for w in words {
        if looksLikeSubject(w) { subjectWords.append(w) } else { teacherWords.append(w) }
    }
    guard !subjectWords.isEmpty else { return ("", value) }
    return (subjectWords.joined(separator: " "), normalizeTeacherName(teacherWords.joined(separator: " ")))
}

// MARK: OCR noise canonicalization

func levenshtein(_ a: String, _ b: String) -> Int {
    let aa = Array(a), bb = Array(b)
    if aa.isEmpty { return bb.count }
    if bb.isEmpty { return aa.count }
    var prev = Array(0...bb.count)
    var cur = [Int](repeating: 0, count: bb.count + 1)
    for i in 1...aa.count {
        cur[0] = i
        for j in 1...bb.count {
            let cost = aa[i - 1] == bb[j - 1] ? 0 : 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &cur)
    }
    return prev[bb.count]
}

/// Snaps rare OCR readings to the closest frequent value ("Inal" -> "Ingl",
/// "Ingl/Cambridge /Cambridgel" -> "Ingl/Cambridge").
private func canonicalizeValues(_ values: [String]) -> [String] {
    var freq: [String: Int] = [:]
    for v in values { freq[v, default: 0] += 1 }
    let frequent = freq.filter { $0.value >= 3 }.keys.sorted { freq[$0]! > freq[$1]! }
    return values.map { v in
        let vFreq = freq[v]!
        // A frequent value that contains a much more frequent one is that value
        // plus OCR debris.
        for f in frequent where freq[f]! >= vFreq * 6 && v.count > f.count
            && v.lowercased().contains(f.lowercased()) {
            return f
        }
        if vFreq >= 3 { return v }
        let maxDist = min(3, max(1, v.count / 4))
        for f in frequent where abs(f.count - v.count) <= maxDist && levenshtein(f.lowercased(), v.lowercased()) <= maxDist {
            return f
        }
        return v
    }
}

// MARK: OCR extraction (scanned PDFs)

private func ocrTextItems(from doc: PDFDocument) -> [TextItem] {
    var items: [TextItem] = []
    for pageIndex in 0..<doc.pageCount {
        guard let page = doc.page(at: pageIndex) else { continue }
        guard let upright = renderPage(page, scale: 3.0) else { continue }
        let orientation = bestTextOrientation(upright)
        guard let image = rotatedImage(upright, quarterTurns: orientation) else { continue }
        items.append(contentsOf: ocrWords(in: image, page: pageIndex + 1))
    }
    return items
}

private func renderPage(_ page: PDFPage, scale: CGFloat) -> CGImage? {
    let bounds = page.bounds(for: .mediaBox)
    // page.draw honours /Rotate, so the canvas must use the displayed size.
    let rotated = ((page.rotation % 360) + 360) % 360 % 180 != 0
    let width = Int((rotated ? bounds.height : bounds.width) * scale)
    let height = Int((rotated ? bounds.width : bounds.height) * scale)
    guard width > 0, height > 0,
          let ctx = CGContext(data: nil, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
    page.draw(with: .mediaBox, to: ctx)
    return ctx.makeImage()
}

private func rotatedImage(_ image: CGImage, quarterTurns: Int) -> CGImage? {
    guard quarterTurns % 4 != 0 else { return image }
    let w = image.width, h = image.height
    let swap = quarterTurns % 2 != 0
    let nw = swap ? h : w, nh = swap ? w : h
    guard let ctx = CGContext(data: nil, width: nw, height: nh,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.translateBy(x: CGFloat(nw) / 2, y: CGFloat(nh) / 2)
    ctx.rotate(by: CGFloat(quarterTurns) * .pi / 2)
    ctx.draw(image, in: CGRect(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2, width: CGFloat(w), height: CGFloat(h)))
    return ctx.makeImage()
}

/// Scores 0-3 quarter turns with a fast pass and returns the best one.
private func bestTextOrientation(_ image: CGImage) -> Int {
    var best = 0
    var bestCount = -1
    for turns in 0..<4 {
        guard let rotated = rotatedImage(image, quarterTurns: turns) else { continue }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: rotated, options: [:]).perform([request])
        let count = request.results?.count ?? 0
        if count > bestCount { bestCount = count; best = turns }
    }
    return best
}

/// Tiled accurate OCR (Vision misses most of a dense table on a full big scan).
private func ocrWords(in image: CGImage, page: Int) -> [TextItem] {
    let W = Double(image.width), H = Double(image.height)
    let cols = 3, rowsN = 3
    let overlap = 0.12
    var items: [TextItem] = []

    for ti in 0..<cols {
        for tj in 0..<rowsN {
            let tw = W / Double(cols), th = H / Double(rowsN)
            let x0 = max(0, tw * Double(ti) - tw * overlap)
            let y0 = max(0, th * Double(tj) - th * overlap)
            let x1 = min(W, tw * Double(ti + 1) + tw * overlap)
            let y1 = min(H, th * Double(tj + 1) + th * overlap)
            guard let tile = image.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["it-IT", "en-US"]
            try? VNImageRequestHandler(cgImage: tile, options: [:]).perform([request])
            for obs in request.results ?? [] {
                guard let cand = obs.topCandidates(1).first, !cand.string.isEmpty else { continue }
                let b = obs.boundingBox // normalized in tile, origin bottom-left
                // Scale to a 0-1000 logical page space, y growing downward.
                let px = (x0 + Double(b.minX) * (x1 - x0)) / W * 1000
                let py = (y0 + (1 - Double(b.maxY)) * (y1 - y0)) / H * 1000
                let pw = Double(b.width) * (x1 - x0) / W * 1000
                let ph = Double(b.height) * (y1 - y0) / H * 1000
                items.append(TextItem(str: cand.string, x: px, y: py, width: pw, height: ph, page: page))
            }
        }
    }

    // Merge duplicates from overlapping tiles: keep the longer reading.
    var merged: [TextItem] = []
    for item in items.sorted(by: { $0.str.count > $1.str.count }) {
        let isDup = merged.contains { m in
            abs(m.x - item.x) < 10 && abs(m.y - item.y) < 8 &&
            (m.str.contains(item.str) || item.str.contains(m.str)
             || levenshtein(m.str, item.str) <= max(2, min(item.str.count, m.str.count) / 4))
        }
        if !isDup { merged.append(item) }
    }
    return merged
}
