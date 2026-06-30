import Foundation
import CoreGraphics
import PDFKit

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
        case .noTextFound: return "Il PDF non contiene testo selezionabile."
        case .noLessonsFound: return "Nessuna lezione trovata nel PDF."
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
