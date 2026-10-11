import SwiftUI

struct WeekView: View {
    let schedule: ScheduleData
    /// Righe orarie: fasce della classe o unione (vista docente).
    let periods: [Period]
    let targetLessons: [Lesson]
    let targetMode: TargetMode
    let targetName: String
    let onOpenCounterpart: (Lesson) -> Void
    let onAddNote: (DayId?, String?, String?, String?, String?) -> Void

    private let timeColWidth: CGFloat = 52
    private let dayColWidth: CGFloat = 88
    private let rowHeight: CGFloat = 56
    @Environment(\.deviceLayout) private var layout
    @State private var gridWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settimana")
                        .font(.title3.bold())
                    Text(targetName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        onAddNote(nil, nil, nil, nil, nil)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.title3)
                            .foregroundStyle(.tint.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(.tint.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            Group {
                if layout.isIPadLayout {
                    // iPad: i giorni riempiono la larghezza, niente scroll laterale
                    // (torna solo se la finestra è troppo stretta).
                    let dayW = WeekGridMetrics.dayColumnWidth(available: gridWidth, days: schedule.days.count,
                                                              timeColumn: 60, minimum: dayColWidth)
                    if dayW * CGFloat(schedule.days.count) + 60 <= gridWidth {
                        grid(timeW: 60, dayW: dayW, rowH: 76, large: true)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            grid(timeW: 60, dayW: dayW, rowH: 76, large: true)
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        grid(timeW: timeColWidth, dayW: dayColWidth, rowH: rowHeight, large: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { gridWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in gridWidth = w }
                }
            }
            .padding(.bottom, 4)
        }
        .auroraCard(radius: 18)
    }

    /// Griglia ore × giorni (stessa per iPhone e iPad, cambiano le misure).
    private func grid(timeW: CGFloat, dayW: CGFloat, rowH: CGFloat, large: Bool) -> some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("Ora")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: timeW, height: 36)
                ForEach(schedule.days) { day in
                    Text(day.id.shortName.uppercased())
                        .font(.system(size: large ? 11.5 : 10, weight: .bold))
                        .kerning(0.4)
                        .foregroundStyle(.secondary)
                        .frame(width: dayW, height: 36)
                }
            }

            Divider()

            // Period rows
            ForEach(periods) { period in
                HStack(spacing: 0) {
                    // Time cell
                    VStack(spacing: 1) {
                        Text(period.startTime)
                            .font(.caption.monospacedDigit().weight(.medium))
                        Text(period.endTime)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: timeW, height: rowH)

                    // Day cells
                    ForEach(schedule.days) { day in
                        let lessons = targetLessons
                            .filter { $0.day == day.id && $0.startTime == period.startTime }
                            .sorted { $0.className.compare($1.className, locale: Locale(identifier: "it")) == .orderedAscending }

                        WeekCell(
                            lessons: lessons,
                            targetMode: targetMode,
                            width: dayW,
                            height: rowH,
                            onTap: onOpenCounterpart,
                            onAddNote: onAddNote,
                            large: large
                        )
                    }
                }

                Divider().padding(.leading, timeW)
            }
        }
    }

}

struct WeekCell: View {
    let lessons: [Lesson]
    let targetMode: TargetMode
    let width: CGFloat
    let height: CGFloat
    let onTap: (Lesson) -> Void
    let onAddNote: (DayId?, String?, String?, String?, String?) -> Void
    /// iPad: chip più grandi con una seconda riga (docente o materia).
    var large: Bool = false
    @Environment(\.colorScheme) private var scheme

    /// Seconda riga del chip su iPad: docente sotto la materia (vista classe),
    /// materia sotto la classe (vista docente). Solo se la cella ha una lezione.
    private func detail(_ lesson: Lesson) -> String? {
        guard large, lessons.count == 1 else { return nil }
        if targetMode == .class_ { return lesson.classModeSubtitle }
        return lesson.subject.isEmpty ? nil : lesson.subject
    }

    var body: some View {
        ZStack {
            if lessons.isEmpty {
                Text("—").font(.caption2).foregroundStyle(.quaternary)
            } else {
                VStack(spacing: 3) {
                    ForEach(lessons.prefix(2)) { lesson in
                        let label = targetMode == .class_ ? lesson.classModeTitle : lesson.className
                        let tint = entityTint(label)
                        Button { onTap(lesson) } label: {
                            VStack(spacing: 2) {
                                Text(label)
                                    .font(.system(size: large ? 12.5 : 9.5, weight: .bold))
                                    .kerning(0.2)
                                    .lineLimit(1)
                                if let detail = detail(lesson) {
                                    Text(detail)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .lineLimit(1)
                                        .opacity(0.8)
                                }
                            }
                                .foregroundStyle(entityLabelColor(tint, scheme))
                                .padding(.horizontal, large ? 8 : 6)
                                .padding(.vertical, large ? 7 : 5)
                                .frame(maxWidth: .infinity)
                                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(tint.opacity(0.30), lineWidth: 1))
                                .padding(.horizontal, 3)
                        }
                        .buttonStyle(.plain)
                        // La preview del context menu segue gli angoli della
                        // cella: senza, il bordo viene tagliato agli angoli.
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contextMenu {
                            Button {
                                onAddNote(lesson.day, lesson.startTime,
                                          targetMode == .class_ ? lesson.teacher : nil,
                                          targetMode == .teacher ? lesson.className : nil,
                                          targetMode == .class_ && !lesson.subject.isEmpty ? lesson.subject : nil)
                            } label: {
                                Label("Crea nota", systemImage: "note.text.badge.plus")
                            }
                        }
                    }
                    if lessons.count > 2 {
                        Text("+\(lessons.count - 2)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(.separator)).frame(width: 0.5)
        }
    }
}
