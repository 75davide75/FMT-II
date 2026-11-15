import Foundation
import CoreGraphics
import CoreText

// Programmatic PDF fixtures for the parser test-suite: each function draws a
// small timetable (or intentionally broken document) with CoreGraphics, so the
// tests don't depend on binary resources.

enum SyntheticPDF {

    private static func makePDF(pageSize: CGSize = CGSize(width: 842, height: 595),
                                draw: (CGContext, CGSize) -> Void) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        ctx.beginPDFPage(nil)
        draw(ctx, pageSize)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    private static func drawText(_ ctx: CGContext, _ text: String, x: CGFloat, yTop: CGFloat,
                                 pageHeight: CGFloat, size: CGFloat = 10) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attr = NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0, alpha: 1)
        ])
        let line = CTLineCreateWithAttributedString(attr as CFAttributedString)
        ctx.textPosition = CGPoint(x: x, y: pageHeight - yTop)
        CTLineDraw(line, ctx)
    }

    /// Columns = classes, rows = periods grouped in day bands, cells = `values`.
    /// `values[day][period][classIndex]` (nil -> empty cell).
    private static func gridPDF(classes: [String],
                                days: [String],
                                periods: [(label: String, time: String?)],
                                cell: (Int, Int, Int) -> String?) -> Data {
        makePDF { ctx, size in
            let h = size.height
            let colWidth: CGFloat = 90
            let colStart: CGFloat = 220
            var y: CGFloat = 40
            drawText(ctx, "ORARIO SCOLASTICO", x: 40, yTop: y, pageHeight: h, size: 14)
            y += 30
            for (c, name) in classes.enumerated() {
                drawText(ctx, name, x: colStart + CGFloat(c) * colWidth, yTop: y, pageHeight: h, size: 11)
            }
            y += 24
            for (d, day) in days.enumerated() {
                drawText(ctx, day, x: 30, yTop: y + 20, pageHeight: h, size: 10)
                for (p, period) in periods.enumerated() {
                    drawText(ctx, period.label, x: 100, yTop: y, pageHeight: h)
                    if let t = period.time {
                        drawText(ctx, t, x: 130, yTop: y, pageHeight: h)
                    }
                    for c in classes.indices {
                        if let value = cell(d, p, c) {
                            drawText(ctx, value, x: colStart + CGFloat(c) * colWidth, yTop: y, pageHeight: h)
                        }
                    }
                    y += 18
                }
                y += 8
            }
        }
    }

    private static let subjectsPool = ["MATEMATICA", "ITALIANO", "INGLESE", "STORIA", "SCIENZE", "FISICA"]
    private static let teachersPool = ["ROSSI", "BIANCHI", "VERDI", "NERI", "GALLO", "FERRARI"]

    /// Classes + days/hours + subjects, no teachers -> partial import (.teacher).
    static func missingTeacher() -> Data {
        gridPDF(classes: ["1A", "2A", "3A"],
                days: ["LUNEDI'", "MARTEDI'", "MERCOLEDI'"],
                periods: (1...4).map { ("\($0)a", nil) },
                cell: { d, p, c in subjectsPool[(d + p * 2 + c * 3) % subjectsPool.count] })
    }

    /// Classes + days/hours + teachers, no subjects (like the legacy class PDF).
    static func missingSubject() -> Data {
        gridPDF(classes: ["1A", "2A", "3A"],
                days: ["LUNEDI'", "MARTEDI'"],
                periods: (1...4).map { ("\($0)a", nil) },
                cell: { d, p, c in teachersPool[(d + p + c * 2 + (p + c) % 2) % teachersPool.count] })
    }

    /// Days/hours + subjects + teachers but no class names -> partial (.classes).
    static func missingClasses() -> Data {
        makePDF { ctx, size in
            let h = size.height
            let days = ["LUNEDI'", "MARTEDI'", "MERCOLEDI'", "GIOVEDI'", "VENERDI'"]
            var y: CGFloat = 40
            drawText(ctx, "IL MIO ORARIO", x: 40, yTop: y, pageHeight: h, size: 14)
            y += 30
            for (d, day) in days.enumerated() {
                drawText(ctx, day, x: 150 + CGFloat(d) * 130, yTop: y, pageHeight: h, size: 11)
            }
            y += 24
            for p in 0..<5 {
                drawText(ctx, String(format: "%02d:10", 8 + p), x: 60, yTop: y, pageHeight: h)
                for d in 0..<days.count {
                    let text = "\(subjectsPool[(d + p) % subjectsPool.count]) \(teachersPool[(d * 2 + p) % teachersPool.count])"
                    drawText(ctx, text, x: 150 + CGFloat(d) * 130, yTop: y, pageHeight: h, size: 8)
                }
                y += 20
            }
        }
    }

    /// Roster (classe/materia/docente) with no day-hour grid -> partial (.dayTime).
    static func missingDayTime() -> Data {
        makePDF { ctx, size in
            let h = size.height
            var y: CGFloat = 40
            drawText(ctx, "ASSEGNAZIONE DOCENTI", x: 40, yTop: y, pageHeight: h, size: 14)
            y += 30
            drawText(ctx, "CLASSE", x: 60, yTop: y, pageHeight: h, size: 11)
            drawText(ctx, "MATERIA", x: 220, yTop: y, pageHeight: h, size: 11)
            drawText(ctx, "DOCENTE", x: 420, yTop: y, pageHeight: h, size: 11)
            y += 22
            for (i, cls) in ["1A", "2A", "3A", "4A"].enumerated() {
                for j in 0..<3 {
                    drawText(ctx, cls, x: 60, yTop: y, pageHeight: h)
                    drawText(ctx, subjectsPool[(i + j * 2) % subjectsPool.count], x: 220, yTop: y, pageHeight: h)
                    drawText(ctx, teachersPool[(i * 3 + j) % teachersPool.count], x: 420, yTop: y, pageHeight: h)
                    y += 18
                }
            }
        }
    }

    /// Only days/hours + subjects: no classes AND no teachers -> rejected (2 missing).
    static func missingTwoElements() -> Data {
        makePDF { ctx, size in
            let h = size.height
            let days = ["LUNEDI'", "MARTEDI'", "MERCOLEDI'", "GIOVEDI'"]
            var y: CGFloat = 40
            drawText(ctx, "ORARIO", x: 40, yTop: y, pageHeight: h, size: 14)
            y += 30
            for (d, day) in days.enumerated() {
                drawText(ctx, day, x: 150 + CGFloat(d) * 130, yTop: y, pageHeight: h, size: 11)
            }
            y += 24
            for p in 0..<4 {
                drawText(ctx, String(format: "%02d:10", 8 + p), x: 60, yTop: y, pageHeight: h)
                for d in 0..<days.count {
                    drawText(ctx, subjectsPool[(d * 2 + p) % subjectsPool.count], x: 150 + CGFloat(d) * 130, yTop: y, pageHeight: h)
                }
                y += 20
            }
        }
    }

    /// Free text with no table structure -> rejected.
    static func unstructured() -> Data {
        makePDF { ctx, size in
            let h = size.height
            let lines = [
                "Relazione di fine anno scolastico.",
                "Il consiglio si riunisce per discutere le attivita' della scuola",
                "e l'organizzazione delle prossime iniziative culturali.",
                "Si ringraziano le famiglie per la collaborazione.",
                "Il dirigente scolastico."
            ]
            for (i, line) in lines.enumerated() {
                drawText(ctx, line, x: 60, yTop: 60 + CGFloat(i) * 24, pageHeight: h, size: 12)
            }
        }
    }

    /// Same teacher in two classes in the same day/hour -> rejected.
    static func teacherConflict() -> Data {
        gridPDF(classes: ["1A", "2A", "3A"],
                days: ["LUNEDI'", "MARTEDI'"],
                periods: (1...3).map { ("\($0)a", nil) },
                cell: { d, p, c in
                    if d == 0 && p == 0 && (c == 0 || c == 1) { return "ROSSI" } // conflict
                    return teachersPool[(d + p * 2 + c * 3 + 2) % teachersPool.count]
                })
    }

    /// Same class with two subjects in the same day/hour -> rejected.
    static func subjectConflict() -> Data {
        makePDF { ctx, size in
            let h = size.height
            var y: CGFloat = 40
            drawText(ctx, "ORARIO CLASSI", x: 40, yTop: y, pageHeight: h, size: 14)
            y += 30
            for (c, name) in ["1A", "2A", "3A"].enumerated() {
                drawText(ctx, name, x: 220 + CGFloat(c) * 110, yTop: y, pageHeight: h, size: 11)
            }
            y += 24
            drawText(ctx, "LUNEDI'", x: 30, yTop: y + 20, pageHeight: h, size: 10)
            // Two rows both marked as first period: 1A gets two subjects at LUN/1.
            for (p, label) in ["1a", "1a", "2a"].enumerated() {
                drawText(ctx, label, x: 100, yTop: y, pageHeight: h)
                for c in 0..<3 {
                    let subj = p == 0 ? subjectsPool[c] : subjectsPool[(c + 3) % subjectsPool.count]
                    drawText(ctx, subj, x: 220 + CGFloat(c) * 110, yTop: y, pageHeight: h)
                }
                y += 18
            }
        }
    }

    /// A "DOMENICA" band with lessons -> rejected (day outside Mon-Sat).
    static func implausibleDay() -> Data {
        gridPDF(classes: ["1A", "2A", "3A"],
                days: ["SABATO", "DOMENICA"],
                periods: (1...3).map { ("\($0)a", nil) },
                cell: { d, p, c in subjectsPool[(d + p + c) % subjectsPool.count] })
    }

    /// Lessons at 20:00 -> rejected (time outside 07:00-19:00).
    static func implausibleTime() -> Data {
        gridPDF(classes: ["1A", "2A", "3A"],
                days: ["LUNEDI'", "MARTEDI'"],
                periods: [("1", "20:00"), ("2", "21:00"), ("3", "22:00")],
                cell: { d, p, c in subjectsPool[(d + p + c * 2) % subjectsPool.count] })
    }

    /// Legacy "global teacher" layout (rows = teachers, day x period columns),
    /// one of the two formats supported before the parser generalization.
    static func legacyTeacherGlobal() -> Data {
        makePDF(pageSize: CGSize(width: 1000, height: 700)) { ctx, size in
            let h = size.height
            let days = ["lun", "mar", "mer", "gio", "ven"]
            let colStart: CGFloat = 320
            let colWidth: CGFloat = 21
            var y: CGFloat = 40
            drawText(ctx, "DOCENTE", x: 40, yTop: y, pageHeight: h, size: 9)
            for d in 0..<5 {
                for p in 0..<6 {
                    drawText(ctx, days[d], x: colStart + CGFloat(d * 6 + p) * colWidth, yTop: y, pageHeight: h, size: 6)
                }
            }
            y += 14
            for i in 0..<30 {
                drawText(ctx, "\(i + 1)", x: colStart + CGFloat(i) * colWidth, yTop: y, pageHeight: h, size: 7)
            }
            y += 14
            let classesPool = ["1A", "2A", "3A", "4A", "5A"]
            for (t, teacher) in teachersPool.enumerated() {
                drawText(ctx, teacher, x: 40, yTop: y, pageHeight: h, size: 8)
                for slot in 0..<30 where (slot + t) % 3 != 0 {
                    // Ogni docente in una sola classe per slot, senza conflitti:
                    // la classe dipende solo dal docente.
                    let cls = classesPool[t % classesPool.count]
                    drawText(ctx, cls, x: colStart + CGFloat(slot) * colWidth, yTop: y, pageHeight: h, size: 7)
                }
                y += 16
            }
        }
    }

    /// Not a PDF at all.
    static func notAPDF() -> Data {
        Data("questo non e' un pdf".utf8)
    }
}
