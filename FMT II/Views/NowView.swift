import SwiftUI

struct NowView: View {
    let currentLesson: Lesson?
    let nextLesson: Lesson?
    let targetMode: TargetMode
    let activeDay: DayId?
    let activeTime: String
    let schoolTimes: [String]
    let onOpenWeek: () -> Void
    let onJumpToLesson: (DayId, String) -> Void
    let onAddNote: ((DayId?, String?, String?, String?) -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            LessonCard(
                title: "Ora corrente",
                icon: "clock.fill",
                accentColor: currentLesson != nil ? .green : .secondary,
                lesson: currentLesson,
                targetMode: targetMode,
                fallback: weekendText(day: activeDay, time: activeTime),
                schoolTimes: schoolTimes,
                showWeekButton: false,
                isNextCard: false,
                onOpenWeek: nil,
                onJumpToLesson: onJumpToLesson,
                onAddNote: onAddNote
            )
            LessonCard(
                title: "Prossima ora",
                icon: "arrow.right.circle.fill",
                accentColor: nextLesson != nil ? .blue : .secondary,
                lesson: nextLesson,
                targetMode: targetMode,
                fallback: "Nessuna lezione successiva oggi",
                schoolTimes: schoolTimes,
                showWeekButton: true,
                isNextCard: true,
                onOpenWeek: onOpenWeek,
                onJumpToLesson: onJumpToLesson,
                onAddNote: onAddNote
            )
        }
    }
}

struct LessonCard: View {
    let title: String
    let icon: String
    let accentColor: Color
    let lesson: Lesson?
    let targetMode: TargetMode
    let fallback: String
    let schoolTimes: [String]
    let showWeekButton: Bool
    let isNextCard: Bool
    let onOpenWeek: (() -> Void)?
    let onJumpToLesson: (DayId, String) -> Void
    let onAddNote: ((DayId?, String?, String?, String?) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(accentColor)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if showWeekButton {
                    Button(action: { onOpenWeek?() }) {
                        HStack(spacing: 4) {
                            Text("Settimana")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                    }
                }
            }

            if let lesson {
                // Main content
                VStack(alignment: .leading, spacing: 6) {
                    Text(targetMode == .class_ ? lesson.classModeTitle : lesson.className)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .contextMenu {
                            Button {
                                onAddNote?(lesson.day, lesson.startTime,
                                           targetMode == .class_ ? lesson.teacher : nil,
                                           targetMode == .teacher ? lesson.className : nil)
                            } label: {
                                Label("Crea nota", systemImage: "note.text.badge.plus")
                            }
                        }

                    HStack(spacing: 8) {
                        // Start time button
                        timeButton(lesson.startTime, boundary: "start", lesson: lesson)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        // End time button
                        timeButton(lesson.endTime, boundary: "end", lesson: lesson)

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text(targetMode == .class_ ? lesson.dayLabel : lesson.teacher)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                // Accent bar
                Rectangle()
                    .fill(accentColor.opacity(0.25))
                    .frame(height: 3)
                    .clipShape(Capsule())
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nessuna lezione")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    Text(fallback)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(accentColor.opacity(0.2), lineWidth: 1.5)
        )
        .shadow(color: accentColor.opacity(0.06), radius: 10, y: 4)
    }

    private func timeButton(_ time: String, boundary: String, lesson: Lesson) -> some View {
        let idx = schoolTimes.firstIndex(of: time) ?? 0
        let targetIdx: Int
        if boundary == "start" {
            // "Prossima ora" needs to step back 2 slots so the previous lesson becomes the new "prossima"
            targetIdx = isNextCard ? max(0, idx - 2) : max(0, idx - 1)
        } else {
            targetIdx = idx
        }
        let targetTime = schoolTimes.indices.contains(targetIdx) ? schoolTimes[targetIdx] : time

        return Button {
            onJumpToLesson(lesson.day, targetTime)
        } label: {
            Text(time)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
