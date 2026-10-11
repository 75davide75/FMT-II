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
    let onAddNote: ((DayId?, String?, String?, String?, String?) -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            CurrentLessonCard(
                lesson: currentLesson,
                targetMode: targetMode,
                activeTime: activeTime,
                fallback: weekendText(day: activeDay, time: activeTime),
                schoolTimes: schoolTimes,
                onJumpToLesson: onJumpToLesson,
                onAddNote: onAddNote
            )
            NextLessonCard(
                lesson: nextLesson,
                targetMode: targetMode,
                schoolTimes: schoolTimes,
                onOpenWeek: onOpenWeek,
                onJumpToLesson: onJumpToLesson,
                onAddNote: onAddNote
            )
        }
    }
}

private let greenA = Color(hex: "#34D399")!
private let greenB = Color(hex: "#A3E635")!
private let greenText = Color(hex: "#6EE7B7")!
private let skyA = Color(hex: "#38BDF8")!
private let skyText = Color(hex: "#7DD3FC")!

/// Card "ORA CORRENTE" (design 3a): vetro tinto di verde, nome grande,
/// barra di avanzamento con bagliore, "termina tra N min".
private struct CurrentLessonCard: View {
    let lesson: Lesson?
    let targetMode: TargetMode
    let activeTime: String
    let fallback: String
    let schoolTimes: [String]
    let onJumpToLesson: (DayId, String) -> Void
    let onAddNote: ((DayId?, String?, String?, String?, String?) -> Void)?
    @Environment(\.colorScheme) private var scheme

    private var progress: Double {
        guard let l = lesson else { return 0 }
        let start = Double(minutesFromMidnight(l.startTime))
        let end = Double(minutesFromMidnight(l.endTime))
        let now = Double(minutesFromMidnight(activeTime))
        guard end > start else { return 0 }
        return min(1, max(0, (now - start) / (end - start)))
    }

    private var remainingText: String {
        guard let l = lesson else { return "" }
        let mins = minutesFromMidnight(l.endTime) - minutesFromMidnight(activeTime)
        return mins > 0 ? L("termina tra \(mins) min") : L("in chiusura")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(lesson != nil ? greenA : Color.secondary)
                    .frame(width: 7, height: 7)
                    .shadow(color: lesson != nil ? greenA.opacity(0.9) : .clear, radius: 4)
                Text("ORA CORRENTE")
                    .font(.system(size: 10.5, weight: .heavy))
                    .kerning(1)
                    .foregroundStyle(lesson != nil ? (scheme == .dark ? greenText : greenA.blended(with: .black, by: 0.25)) : .secondary)
                Spacer()
                if let l = lesson {
                    Text("\(l.period)ª ora")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let l = lesson {
                Text(targetMode == .class_ ? l.classModeTitle : l.className)
                    .font(.system(size: 24, weight: .heavy))
                    .kerning(-0.3)
                    .foregroundStyle(.primary)
                    .padding(.top, 8)
                    .contextMenu {
                        Button {
                            onAddNote?(l.day, l.startTime,
                                       targetMode == .class_ ? l.teacher : nil,
                                       targetMode == .teacher ? l.className : nil,
                                       targetMode == .class_ && !l.subject.isEmpty ? l.subject : nil)
                        } label: {
                            Label("Crea nota", systemImage: "note.text.badge.plus")
                        }
                    }
                if targetMode == .class_, let sub = l.classModeSubtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(scheme == .dark ? 0.08 : 0.5)).frame(height: 6)
                        Capsule()
                            .fill(LinearGradient(colors: [greenA, greenB], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * progress), height: 6)
                            .shadow(color: greenA.opacity(0.55), radius: 5)
                    }
                }
                .frame(height: 6)
                .padding(.top, 12)

                HStack(spacing: 4) {
                    timeJump(l.startTime, target: earlierTime(of: l.startTime, back: 1), day: l.day)
                    Text("– ")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    timeJump(l.endTime, target: l.endTime, day: l.day)
                    Text("· \(remainingText)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(targetMode == .class_ ? l.day.displayName : (l.teacher.isEmpty ? l.subject : l.teacher))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 6)
            } else {
                Text("Nessuna lezione")
                    .font(.system(size: 24, weight: .heavy))
                    .kerning(-0.3)
                    .padding(.top, 8)
                Text(fallback)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: scheme == .dark
                        ? [greenA.opacity(lesson != nil ? 0.13 : 0.0), .white.opacity(0.045)]
                        : [greenA.opacity(lesson != nil ? 0.18 : 0.03), .white.opacity(0.75)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(lesson != nil ? greenA.opacity(0.32) : .white.opacity(0.13), lineWidth: 1)
        )
        .shadow(color: (lesson != nil ? Color(red: 0.04, green: 0.31, blue: 0.22) : .black).opacity(scheme == .dark ? 0.25 : 0.08), radius: 14, y: 6)
    }

    private func earlierTime(of time: String, back: Int) -> String {
        let idx = schoolTimes.firstIndex(of: time) ?? 0
        let target = max(0, idx - back)
        return schoolTimes.indices.contains(target) ? schoolTimes[target] : time
    }

    private func timeJump(_ label: String, target: String, day: DayId) -> some View {
        Button { onJumpToLesson(day, target) } label: {
            Text(label)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(scheme == .dark ? greenText : greenA.blended(with: .black, by: 0.25))
        }
        .buttonStyle(.plain)
    }
}

/// Card "PROSSIMA ORA" (design 3a): vetro tinto cilestino.
private struct NextLessonCard: View {
    let lesson: Lesson?
    let targetMode: TargetMode
    let schoolTimes: [String]
    let onOpenWeek: () -> Void
    let onJumpToLesson: (DayId, String) -> Void
    let onAddNote: ((DayId?, String?, String?, String?, String?) -> Void)?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(lesson != nil ? skyA : Color.secondary).frame(width: 7, height: 7)
                Text("PROSSIMA ORA")
                    .font(.system(size: 10.5, weight: .heavy))
                    .kerning(1)
                    .foregroundStyle(lesson != nil ? (scheme == .dark ? skyText : skyA.blended(with: .black, by: 0.3)) : .secondary)
                Spacer()
                if let l = lesson {
                    Button {
                        // Salta all'orario della prossima lezione (comportamento invariato).
                        let idx = schoolTimes.firstIndex(of: l.startTime) ?? 0
                        let target = max(0, idx - 2)
                        onJumpToLesson(l.day, schoolTimes.indices.contains(target) ? schoolTimes[target] : l.startTime)
                    } label: {
                        Text("\(l.startTime) – \(l.endTime)")
                            .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onOpenWeek) {
                        HStack(spacing: 3) {
                            Text("Settimana")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(scheme == .dark ? skyText : skyA.blended(with: .black, by: 0.3))
                    }
                }
            }

            if let l = lesson {
                HStack {
                    Text(targetMode == .class_ ? l.classModeTitle : l.className)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.primary)
                        .contextMenu {
                            Button {
                                onAddNote?(l.day, l.startTime,
                                           targetMode == .class_ ? l.teacher : nil,
                                           targetMode == .teacher ? l.className : nil,
                                           targetMode == .class_ && !l.subject.isEmpty ? l.subject : nil)
                            } label: {
                                Label("Crea nota", systemImage: "note.text.badge.plus")
                            }
                        }
                    Spacer()
                    Button(action: onOpenWeek) {
                        HStack(spacing: 3) {
                            Text("Settimana")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(scheme == .dark ? skyText : skyA.blended(with: .black, by: 0.3))
                    }
                }
                .padding(.top, 6)
            } else {
                Text("Nessuna lezione")
                    .font(.system(size: 18, weight: .heavy))
                    .padding(.top, 6)
                Text("Nessuna lezione successiva oggi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: scheme == .dark
                        ? [skyA.opacity(lesson != nil ? 0.11 : 0.0), .white.opacity(0.04)]
                        : [skyA.opacity(lesson != nil ? 0.16 : 0.03), .white.opacity(0.75)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(lesson != nil ? skyA.opacity(0.28) : .white.opacity(0.13), lineWidth: 1)
        )
    }
}
