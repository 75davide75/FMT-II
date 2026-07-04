import SwiftUI

struct WeekView: View {
    let schedule: ScheduleData
    let targetLessons: [Lesson]
    let targetMode: TargetMode
    let targetName: String
    let onOpenCounterpart: (Lesson) -> Void
    let onAddNote: (DayId?, String?, String?, String?, String?) -> Void

    private let timeColWidth: CGFloat = 52
    private let dayColWidth: CGFloat = 88
    private let rowHeight: CGFloat = 56

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

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Column headers
                    HStack(spacing: 0) {
                        Text("Ora")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: timeColWidth, height: 36)
                        ForEach(schedule.days) { day in
                            Text(shortLabel(day.label).uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .kerning(0.4)
                                .foregroundStyle(.secondary)
                                .frame(width: dayColWidth, height: 36)
                        }
                    }

                    Divider()

                    // Period rows
                    ForEach(schedule.periods) { period in
                        HStack(spacing: 0) {
                            // Time cell
                            VStack(spacing: 1) {
                                Text(period.startTime)
                                    .font(.caption.monospacedDigit().weight(.medium))
                                Text(period.endTime)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: timeColWidth, height: rowHeight)

                            // Day cells
                            ForEach(schedule.days) { day in
                                let lessons = targetLessons
                                    .filter { $0.day == day.id && $0.startTime == period.startTime }
                                    .sorted { $0.className.compare($1.className, locale: Locale(identifier: "it")) == .orderedAscending }

                                WeekCell(
                                    lessons: lessons,
                                    targetMode: targetMode,
                                    width: dayColWidth,
                                    height: rowHeight,
                                    onTap: onOpenCounterpart,
                                    onAddNote: onAddNote
                                )
                            }
                        }

                        Divider().padding(.leading, timeColWidth)
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .auroraCard(radius: 18)
    }

    private func shortLabel(_ label: String) -> String {
        let map = ["Lunedì": "Lun", "Martedì": "Mar", "Mercoledì": "Mer", "Giovedì": "Gio", "Venerdì": "Ven"]
        return map[label] ?? String(label.prefix(3))
    }
}

struct WeekCell: View {
    let lessons: [Lesson]
    let targetMode: TargetMode
    let width: CGFloat
    let height: CGFloat
    let onTap: (Lesson) -> Void
    let onAddNote: (DayId?, String?, String?, String?, String?) -> Void
    @Environment(\.colorScheme) private var scheme

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
                            Text(label)
                                .font(.system(size: 9.5, weight: .bold))
                                .kerning(0.2)
                                .lineLimit(1)
                                .foregroundStyle(entityLabelColor(tint, scheme))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
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
