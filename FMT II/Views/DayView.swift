import SwiftUI

struct DayView: View {
    let dayPlan: [(period: Period, lessons: [Lesson])]
    let dayLabel: String
    let targetName: String
    let targetMode: TargetMode
    let dayId: DayId
    let onOpenCounterpart: (Lesson) -> Void
    let onJumpToLesson: (DayId, String) -> Void
    let onAddNote: (DayId?, String?, String?, String?, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayLabel)
                        .font(.title3.bold())
                    Text(targetName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        onAddNote(dayId, nil, nil, nil, nil)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.title3)
                            .foregroundStyle(.tint.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    Image(systemName: "calendar.day.timeline.left")
                        .font(.title3)
                        .foregroundStyle(.tint.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            ForEach(dayPlan, id: \.period.number) { item in
                TimelineRow(
                    period: item.period,
                    lessons: item.lessons,
                    targetMode: targetMode,
                    isLast: item.period.number == dayPlan.last?.period.number,
                    onOpenCounterpart: onOpenCounterpart,
                    onAddNote: onAddNote
                )
            }
        }
        .auroraCard(radius: 18)
    }
}

struct TimelineRow: View {
    let period: Period
    let lessons: [Lesson]
    let targetMode: TargetMode
    let isLast: Bool
    let onOpenCounterpart: (Lesson) -> Void
    let onAddNote: (DayId?, String?, String?, String?, String?) -> Void

    var hasLessons: Bool { !lessons.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Period number + time column
            VStack(spacing: 2) {
                Text("№\(period.number)")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
                Text(period.startTime)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.primary)
                Text(period.endTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56)
            .padding(.top, 12)

            // Vertical line
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Circle()
                        .fill(hasLessons ? AuroraSection.orario.tintB : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .padding(.top, 14)
                    if !isLast {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 1.5)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 20)
            }

            // Lessons
            VStack(alignment: .leading, spacing: 6) {
                if lessons.isEmpty {
                    Text("Libero")
                        .font(.callout)
                        .foregroundStyle(.quaternary)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                } else {
                    ForEach(lessons) { lesson in
                        let label = targetMode == .class_ ? lesson.classModeTitle : lesson.className
                        let tint = entityTint(label)
                        Button {
                            onOpenCounterpart(lesson)
                        } label: {
                            HStack(spacing: 8) {
                                // Stessa etichetta-colore della settimana, con
                                // effetto gradiente.
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(entityGradient(label))
                                    .frame(width: 3)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(label)
                                        .font(.callout.bold())
                                        .foregroundStyle(tint.blended(with: .white, by: 0.45))
                                    if targetMode == .class_, let sub = lesson.classModeSubtitle {
                                        Text(sub)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(tint.opacity(0.7))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.08)],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.28), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        // La preview del context menu deve seguire gli angoli
                        // arrotondati della cella, altrimenti il bordo viene
                        // tagliato agli angoli.
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, isLast ? 10 : 0)

        if !isLast {
            Divider().padding(.leading, 76)
        }
    }
}
