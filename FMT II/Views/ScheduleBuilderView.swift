import SwiftUI

// MARK: - Manual schedule builder (weekly grid)

/// Create or edit a schedule by hand: pick the class(es), the time slots, then
/// tap cells in a weekly grid to fill them. Subjects are required, teachers are
/// optional and auto-filled from a learned subject→teacher map. Produces a
/// `ScheduleData` with `edited = true` (so custom times are preserved).
struct ScheduleBuilderView: View {
    let onSave: (ScheduleData) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduleData
    @State private var selectedClass: String
    @State private var firstStartDate: Date
    @State private var slotMinutes: Int
    @State private var periodCount: Int
    @State private var includeSaturday: Bool
    @State private var showSetupSheet = false
    @State private var classNameDraft = ""
    @State private var cell: CellTarget?
    @State private var addingClass = false
    @State private var newClassName = ""
    @State private var renamingClass = false
    @State private var renameDraft = ""
    // Zoom del foglio (design 3d): stato condiviso col controllo − / + e con
    // la minimappa.
    @State private var zoom: CGFloat = 1
    @State private var visibleRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var isPinching = false
    @Environment(\.colorScheme) private var scheme

    private let timeColWidth: CGFloat = 48
    private let dayColWidth: CGFloat = 96
    private let rowHeight: CGFloat = 58

    init(existing: ScheduleData?, onSave: @escaping (ScheduleData) -> Void) {
        self.onSave = onSave
        let base = existing ?? Self.blank()
        _draft = State(initialValue: base)
        _selectedClass = State(initialValue: base.classes.first ?? "")
        _includeSaturday = State(initialValue: base.days.contains { $0.id == .saturday })
        let periods = base.periods.sorted { $0.number < $1.number }
        _periodCount = State(initialValue: max(periods.count, 1))
        let firstStart = periods.first?.startTime ?? "08:00"
        var comp = DateComponents()
        let p = firstStart.split(separator: ":").compactMap { Int($0) }
        comp.hour = p.first ?? 8; comp.minute = p.count > 1 ? p[1] : 0
        _firstStartDate = State(initialValue: Calendar.current.date(from: comp) ?? Date())
        if periods.count >= 2 {
            _slotMinutes = State(initialValue: min(max(minutesFromMidnight(periods[1].startTime) - minutesFromMidnight(periods[0].startTime), 30), 90))
        } else {
            _slotMinutes = State(initialValue: 60)
        }
    }

    private var activeDays: [DayId] { includeSaturday ? dayOrder + [.saturday] : dayOrder }
    private var sortedPeriods: [Period] { draft.periods.sorted { $0.number < $1.number } }
    /// Fasce della classe in modifica (con l'eventuale inizio per classe).
    private var classPeriods: [Period] { draft.periods(forClass: selectedClass) }
    private var canSave: Bool { !selectedClass.trimmingCharacters(in: .whitespaces).isEmpty && !draft.lessons.isEmpty }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                builderHeader
                setupBar
                sheetGrid
            }
            // Nome classe obbligatorio: finché manca, un velo bloccante copre
            // il builder e non si può fare altro che dargli un nome o uscire.
            if selectedClass.isEmpty {
                classNameOverlay
            }
        }
        .background(AuroraBackground(section: .orario))
        // Header custom (design 3d): la toolbar di sistema aggiungerebbe la
        // sua capsula glass attorno a Salva, creando un doppio bordo.
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            rebuildPeriodsAndDays()
        }
        .sheet(isPresented: $showSetupSheet) { setupSheet }
        .sheet(item: $cell) { target in
            CellEditorSheet(
                subject: lesson(for: target)?.subject ?? "",
                teacher: lesson(for: target)?.teacher ?? "",
                subjectPool: subjectPool,
                teacherPool: draft.teachers,
                subjectTeachers: draft.subjectTeachers
            ) { subject, teacher in
                setCell(target, subject: subject, teacher: teacher)
            }
        }
        .alert("Aggiungi classe", isPresented: $addingClass) {
            TextField("Es. 5GSA", text: $newClassName)
            Button("Annulla", role: .cancel) { newClassName = "" }
            Button("Aggiungi") { addClass() }
        } message: {
            Text("Crea l'orario anche per un'altra classe.")
        }
        .alert("Rinomina classe", isPresented: $renamingClass) {
            TextField("Nome classe", text: $renameDraft)
            Button("Annulla", role: .cancel) {}
            Button("Rinomina") { renameSelectedClass() }
        } message: {
            Text("Cambia il nome della classe selezionata: si aggiorna anche in tutte le sue lezioni.")
        }
    }

    private func renameSelectedClass() {
        let name = renameDraft.trimmingCharacters(in: .whitespaces)
        let old = selectedClass
        guard !name.isEmpty, name != old else { return }
        draft.renameClass(from: old, to: name)
        selectedClass = name
        renameDraft = ""
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Setup bar (always visible)

    private var setupBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(draft.classes, id: \.self) { c in
                    Button { selectedClass = c } label: {
                        if c == selectedClass { Label(c.isEmpty ? L("(senza nome)") : c, systemImage: "checkmark") }
                        else { Text(c.isEmpty ? L("(senza nome)") : c) }
                    }
                }
                Divider()
                if !selectedClass.isEmpty {
                    Button { renameDraft = selectedClass; renamingClass = true } label: {
                        Label("Rinomina classe", systemImage: "pencil")
                    }
                }
                Button { addingClass = true } label: { Label("Aggiungi classe", systemImage: "plus") }
            } label: {
                // Pill classe con bordo a gradiente Orario (design 3d).
                HStack(spacing: 8) {
                    Image(systemName: "graduationcap.fill")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#7DD3FC")!)
                    Text(selectedClass.isEmpty ? L("Classe") : selectedClass)
                        .font(.system(size: 15, weight: .heavy))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(Color(hex: "#7DD3FC")!)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Color(hex: "#38BDF8")!.opacity(0.7),
                                                    Color(hex: "#4E7CF6")!.opacity(0.7)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.2
                        )
                )
                .foregroundStyle(selectedClass.isEmpty ? .secondary : .primary)
            }

            Spacer()

            // Hint d'uso del foglio (design 3d).
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "#7DD3FC")!)
                Text("Pizzica per lo zoom")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(.white.opacity(scheme == .dark ? 0.06 : 0.5), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(scheme == .dark ? 0.10 : 0.6), lineWidth: 1))

            Button { showSetupSheet = true } label: {
                Label("Impostazioni", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
                    .padding(9)
                    .background(.regularMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: Header (Annulla / titolo / Salva a gradiente, design 3d)

    private var builderHeader: some View {
        ZStack {
            Text("Crea orario")
                .font(.system(size: 16, weight: .bold))
            HStack {
                Button { dismiss() } label: {
                    Text("Annulla")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(scheme == .dark ? Color(hex: "#DCE4FF")! : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05), in: Capsule())
                        .overlay(Capsule().strokeBorder(scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onSave(applyManualEdits(draft))
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                } label: {
                    Text("Salva")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(orarioGradient, in: Capsule())
                        .shadow(color: Color(hex: "#3884F6")!.opacity(canSave ? 0.45 : 0), radius: 9, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.4), value: canSave)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    // MARK: Nome classe obbligatorio (overlay bloccante)

    private var classNameOverlay: some View {
        ZStack {
            // Sfondo sfocato + velo: la griglia dietro non deve trasparire
            // dentro la card.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            Color.black.opacity(scheme == .dark ? 0.35 : 0.15).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(colors: [Color(hex: "#38BDF8")!, Color(hex: "#4E7CF6")!],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                    .shadow(color: Color(hex: "#3884F6")!.opacity(0.45), radius: 10, y: 5)

                Text("Per quale classe è l'orario?")
                    .font(.system(size: 17, weight: .bold))
                Text("Il nome della classe è obbligatorio per iniziare; potrai rinominarla dalle Impostazioni orario.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Es. 5GSA", text: $classNameDraft)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 17, weight: .bold))
                    .padding(.vertical, 10)
                    .background(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.4), lineWidth: 1))
                    .submitLabel(.done)
                    .onSubmit { commitClassName() }

                HStack(spacing: 10) {
                    Button { dismiss() } label: {
                        Text("Annulla")
                            .font(.system(size: 13.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button { commitClassName() } label: {
                        Text("Inizia")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                LinearGradient(colors: [Color(hex: "#38BDF8")!, Color(hex: "#4E7CF6")!],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: Capsule()
                            )
                            .shadow(color: Color(hex: "#3884F6")!.opacity(0.4), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(classNameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(classNameDraft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                }
            }
            .padding(22)
            .background {
                // Card opaca: gradiente scuro pieno (bianco pieno in chiaro).
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(scheme == .dark
                          ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#1A1E36")!, Color(hex: "#111426")!],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white))
            }
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(scheme == .dark ? 0.14 : 0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
            .padding(.horizontal, 28)
        }
    }

    // MARK: Impostazioni orario (foglio in stile Aurora)

    private let orarioGradient = LinearGradient(colors: [Color(hex: "#38BDF8")!, Color(hex: "#4E7CF6")!],
                                                startPoint: .topLeading, endPoint: .bottomTrailing)

    private var setupSheet: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Impostazioni orario")
                    .font(.system(size: 16, weight: .bold))
                HStack {
                    Spacer()
                    Button { showSetupSheet = false } label: {
                        Text("Fine")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background(orarioGradient, in: Capsule())
                            .shadow(color: Color(hex: "#3884F6")!.opacity(0.45), radius: 7, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Classe: nome attuale + rinomina inline.
                    settingsCard {
                        settingsRow(icon: "graduationcap.fill", tint: Color(hex: "#6EE7B7")!, label: L("Classe")) {
                            Text(selectedClass.isEmpty ? "—" : selectedClass)
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(entityLabelColor(Color(hex: "#6EE7B7")!, scheme))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color(hex: "#6EE7B7")!.opacity(0.12), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color(hex: "#6EE7B7")!.opacity(0.26), lineWidth: 1))
                        }
                        settingsHairline
                        settingsRow(icon: "pencil", tint: Color(hex: "#93C5FD")!, label: L("Rinomina")) {
                            TextField("Nuovo nome", text: $renameDraft)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 13))
                                .frame(maxWidth: 130)
                                .submitLabel(.done)
                                .onSubmit { renameSelectedClass() }
                            Button {
                                renameSelectedClass()
                            } label: {
                                Text("OK")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(orarioGradient, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(renameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                            .opacity(renameDraft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                        }
                    }

                    // Ore: inizio, numero e durata.
                    settingsCard {
                        settingsRow(icon: "clock", tint: Color(hex: "#7DD3FC")!, label: L("Inizio 1ª ora")) {
                            DatePicker("", selection: $firstStartDate, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        settingsHairline
                        settingsRow(icon: "number", tint: Color(hex: "#93C5FD")!, label: L("Ore al giorno")) {
                            stepperPill(value: "\(periodCount)",
                                        minus: { periodCount = max(1, periodCount - 1) },
                                        plus: { periodCount = min(12, periodCount + 1) })
                        }
                        settingsHairline
                        settingsRow(icon: "timer", tint: Color(hex: "#C4B5FD")!, label: L("Durata ora")) {
                            stepperPill(value: "\(slotMinutes) min",
                                        minus: { slotMinutes = max(30, slotMinutes - 5) },
                                        plus: { slotMinutes = min(90, slotMinutes + 5) })
                        }
                    }

                    // Giorni.
                    settingsCard {
                        settingsRow(icon: "calendar", tint: Color(hex: "#F0ABFC")!, label: L("Includi sabato")) {
                            Toggle("", isOn: $includeSaturday)
                                .labelsHidden()
                                .tint(Color(hex: "#4E7CF6")!)
                        }
                    }

                    Text("Le fasce orarie si ricalcolano da inizio e durata; rinominando la classe si aggiornano anche tutte le sue lezioni.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 26)
            }
        }
        .background {
            if scheme == .dark {
                LinearGradient(colors: [Color(hex: "#14172A")!, Color(hex: "#0C0E1A")!],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            } else {
                Color(.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
        .onAppear { renameDraft = "" }
        .onChange(of: firstStartDate) { _, _ in rebuildPeriodsAndDays() }
        .onChange(of: periodCount) { _, _ in rebuildPeriodsAndDays() }
        .onChange(of: slotMinutes) { _, _ in rebuildPeriodsAndDays() }
        .onChange(of: includeSaturday) { _, _ in rebuildPeriodsAndDays() }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.75),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07), lineWidth: 1))
    }

    private func settingsRow<Content: View>(icon: String, tint: Color, label: String,
                                            @ViewBuilder trailing: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 1))
            Text(label).font(.system(size: 14, weight: .semibold))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }

    private var settingsHairline: some View {
        Rectangle()
            .fill(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 51)
    }

    private func stepperPill(value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: minus) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .heavy))
                    .frame(width: 24, height: 24)
                    .background(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), in: Circle())
            }
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Color(hex: "#7CB3FF")!)
                .frame(minWidth: 30)
                .contentTransition(.numericText())
            Button(action: plus) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .heavy))
                    .frame(width: 24, height: 24)
                    .background(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), in: Circle())
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08), lineWidth: 1))
    }

    private func commitClassName() {
        let name = classNameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let old = selectedClass
        selectedClass = name
        draft.renameClass(from: old, to: name)
    }

    // MARK: Grid (foglio zoomabile, design 3d)

    /// Il "foglio": griglia dentro una card glass, con pinch-zoom e pan.
    /// In basso a sinistra il controllo zoom; in basso a destra la minimappa
    /// per orientarsi, visibile solo quando il foglio è zoomato.
    private var sheetGrid: some View {
        ZoomableSheetView(zoom: $zoom, visibleRect: $visibleRect, isPinching: $isPinching) {
            gridContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .auroraCard(radius: 22)
        .overlay(alignment: .bottomLeading) {
            zoomControl.padding(12)
        }
        .overlay(alignment: .bottomTrailing) {
            if zoom > 1.02 {
                minimap.padding(12)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: zoom > 1.02)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var gridContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Color.clear.frame(width: timeColWidth, height: 30)
                ForEach(activeDays, id: \.self) { day in
                    Text(shortLabel(day).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.4)
                        .foregroundStyle(scheme == .dark ? Color(hex: "#DCE7FF")! : .primary)
                        .frame(width: dayColWidth, height: 30)
                        .background(
                            scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(scheme == .dark ? 0.10 : 0.4), lineWidth: 1))
                }
            }
            ForEach(classPeriods) { period in
                HStack(spacing: 6) {
                    VStack(spacing: 1) {
                        Text(period.startTime)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(period.endTime)
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: timeColWidth, height: rowHeight)

                    ForEach(activeDays, id: \.self) { day in
                        cellView(day: day, period: period)
                    }
                }
            }
        }
        .padding(18)
    }

    /// Controllo zoom «− 100% +» in pill glass scura.
    private var zoomControl: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation { zoom = max(0.5, ((zoom - 0.25) * 4).rounded() / 4) }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .heavy))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.08), in: Circle())
            }
            Text("\(Int((zoom * 100).rounded()))%")
                .font(.system(size: 12.5, weight: .bold))
                .monospacedDigit()
            Button {
                withAnimation { zoom = min(2, ((zoom + 0.25) * 4).rounded() / 4) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .heavy))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.08), in: Circle())
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(hex: "#DCE7FF")!)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(Color(hex: "#0A0E1C")!.opacity(0.72), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.13), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 13, y: 5)
    }

    /// Minimappa: proporzioni del foglio con la finestra visibile evidenziata,
    /// per orientarsi quando si è zoomati.
    private var minimap: some View {
        let mapW: CGFloat = 82, mapH: CGFloat = 60
        let clamped = CGRect(x: min(max(visibleRect.minX, 0), 1),
                             y: min(max(visibleRect.minY, 0), 1),
                             width: visibleRect.width,
                             height: visibleRect.height)
        return ZStack(alignment: .topLeading) {
            // Texture a cellette del foglio.
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(0..<3, id: \.self) { r in
                    GridRow {
                        ForEach(0..<6, id: \.self) { c in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity((r + c).isMultiple(of: 3) ? 0.14 : 0.08))
                        }
                    }
                }
            }
            .padding(6)

            // Finestra visibile.
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(hex: "#7DD3FC")!, lineWidth: 1.6)
                .shadow(color: Color(hex: "#7DD3FC")!.opacity(0.45), radius: 6)
                .frame(width: max(14, mapW * clamped.width),
                       height: max(10, mapH * clamped.height))
                .offset(x: min(mapW * clamped.minX, mapW - max(14, mapW * clamped.width)),
                        y: min(mapH * clamped.minY, mapH - max(10, mapH * clamped.height)))
                .animation(.linear(duration: 0.08), value: clamped)
        }
        .frame(width: mapW, height: mapH)
        .background(Color(hex: "#0A0E1C")!.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.white.opacity(0.13), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 13, y: 5)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func cellView(day: DayId, period: Period) -> some View {
        let target = CellTarget(day: day, period: period.number)
        let l = lesson(for: target)
        let filled = (l?.subject.isEmpty == false)
        return Button {
            // Anti-pinch: se stanno arrivando due dita, il "tap" della prima
            // non deve aprire la cella. Piccola attesa e verifica.
            guard !isPinching else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                guard !isPinching else { return }
                cell = target
            }
        } label: {
            VStack(spacing: 2) {
                if let l, filled {
                    let tint = entityTint(l.subject)
                    Text(l.subject)
                        .font(.system(size: 10.5, weight: .heavy))
                        .kerning(0.3)
                        .foregroundStyle(entityLabelColor(tint, scheme))
                        .lineLimit(2).multilineTextAlignment(.center)
                    if !l.teacher.isEmpty {
                        Text(l.teacher).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Image(systemName: "plus")
                        .font(.callout)
                        .foregroundStyle(Color(hex: "#94B7FF")!.opacity(0.5))
                }
            }
            .frame(width: dayColWidth, height: rowHeight)
            .background(
                filled ? entityTint(l?.subject ?? "").opacity(0.16) : Color.white.opacity(0.02),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                if filled {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(entityTint(l?.subject ?? "").opacity(0.32), lineWidth: 1)
                } else {
                    // Cella libera: bordo tratteggiato (design 3d)
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color(hex: "#94B7FF")!.opacity(0.24),
                                      style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortLabel(_ day: DayId) -> String {
        day.shortName
    }

    // MARK: Data helpers

    private static var commonSubjects: [String] { SubjectSuggestions.all }

    private var subjectPool: [String] {
        var seen = Set<String>(); var out: [String] = []
        for l in draft.lessons where !l.subject.isEmpty && seen.insert(l.subject.lowercased()).inserted { out.append(l.subject) }
        for s in Self.commonSubjects where seen.insert(s.lowercased()).inserted { out.append(s) }
        return out
    }

    private func lesson(for t: CellTarget) -> Lesson? {
        draft.lessons.first { $0.className == selectedClass && $0.day == t.day && $0.period == t.period }
    }

    private func setCell(_ t: CellTarget, subject: String, teacher: String) {
        let subj = subject.trimmingCharacters(in: .whitespaces)
        let teach = teacher.trimmingCharacters(in: .whitespaces)
        // Remove any existing lesson in this cell.
        draft.lessons.removeAll { $0.className == selectedClass && $0.day == t.day && $0.period == t.period }
        guard !subj.isEmpty else { return }

        let p = classPeriods.first { $0.number == t.period }
        draft.lessons.append(Lesson(
            id: UUID().uuidString,
            className: selectedClass,
            teacher: teach,
            day: t.day,
            dayLabel: dayLabels[t.day] ?? t.day.rawValue,
            period: t.period,
            startTime: p?.startTime ?? "08:00",
            endTime: p?.endTime ?? "09:00",
            sourcePage: 0,
            subject: subj
        ))
        if !teach.isEmpty {
            if !draft.teachers.contains(teach) { draft.teachers.append(teach) }
            draft.subjectTeachers[subj] = teach   // learn the pairing
        }
    }

    private func addClass() {
        let name = newClassName.trimmingCharacters(in: .whitespaces)
        newClassName = ""
        guard !name.isEmpty, !draft.classes.contains(name) else { return }
        draft.classes.append(name)
        selectedClass = name
    }

    private func rebuildPeriodsAndDays() {
        let cal = Calendar.current
        let firstMins = cal.component(.hour, from: firstStartDate) * 60 + cal.component(.minute, from: firstStartDate)
        draft.periods = (1...periodCount).map { n in
            let start = firstMins + (n - 1) * slotMinutes
            return Period(number: n, startTime: hhmm(start), endTime: hhmm(start + slotMinutes))
        }
        draft.days = activeDays.map { DayInfo(id: $0, label: dayLabels[$0] ?? $0.rawValue) }
        // Drop lessons whose period no longer exists.
        let valid = Set(1...periodCount)
        draft.lessons.removeAll { !valid.contains($0.period) }
    }

    private func hhmm(_ mins: Int) -> String {
        String(format: "%02d:%02d", (mins / 60) % 24, mins % 60)
    }

    static func blank() -> ScheduleData {
        ScheduleData(
            id: UUID().uuidString,
            sourceName: L("Orario personale"),
            importedAt: ISO8601DateFormatter().string(from: Date()),
            startsFrom: nil,
            days: dayOrder.map { DayInfo(id: $0, label: dayLabels[$0] ?? $0.rawValue) },
            periods: (1...6).map { Period(number: $0, startTime: hhmmStatic(480 + ($0 - 1) * 60), endTime: hhmmStatic(480 + $0 * 60)) },
            classes: [""],
            teachers: [],
            lessons: [],
            warnings: [],
            edited: true,
            subjectTeachers: [:]
        )
    }

    private static func hhmmStatic(_ mins: Int) -> String {
        String(format: "%02d:%02d", (mins / 60) % 24, mins % 60)
    }
}

private struct CellTarget: Identifiable {
    let day: DayId
    let period: Int
    var id: String { "\(day.rawValue)-\(period)" }
}

// MARK: - Cell editor

private struct CellEditorSheet: View {
    @State var subject: String
    @State var teacher: String
    let subjectPool: [String]
    let teacherPool: [String]
    let subjectTeachers: [String: String]
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var subjectFocused: Bool

    private func suggest(_ text: String, from pool: [String]) -> [String] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return pool.filter { $0.lowercased().contains(q) && $0.lowercased() != q }.prefix(6).map { $0 }
    }

    /// Subjects already associated with the entered teacher (a teacher may teach several).
    private var teacherSubjects: [String] {
        let t = teacher.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return [] }
        return subjectTeachers
            .filter { $0.value.lowercased() == t && $0.key.lowercased() != subject.trimmingCharacters(in: .whitespaces).lowercased() }
            .map(\.key)
            .sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Materia") {
                    TextField("Es. Matematica", text: $subject)
                        .autocorrectionDisabled()
                        .focused($subjectFocused)
                        .submitLabel(.done)
                        .onSubmit { autocompleteSubject() }
                        .onChange(of: subject) { _, newValue in
                            // Auto-fill the teacher when the subject is already known.
                            if teacher.isEmpty, let t = subjectTeachers[newValue] { teacher = t }
                        }
                    ForEach(suggest(subject, from: subjectPool), id: \.self) { s in
                        Button {
                            subject = s
                            if teacher.isEmpty, let t = subjectTeachers[s] { teacher = t }
                        } label: {
                            Label(s, systemImage: "arrow.turn.down.right").font(.callout)
                        }
                        .buttonStyle(.plain)
                    }
                    // If a teacher was entered first, offer the subjects they teach.
                    ForEach(teacherSubjects, id: \.self) { s in
                        Button { subject = s } label: {
                            Label("\(s) · \(teacher)", systemImage: "person.fill")
                                .font(.callout)
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Docente (facoltativo)") {
                    TextField("Cognome", text: $teacher)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .submitLabel(.done)
                        .onSubmit { if let f = suggest(teacher, from: teacherPool).first { teacher = f } }
                    ForEach(suggest(teacher, from: teacherPool), id: \.self) { t in
                        Button { teacher = t } label: {
                            Label(t, systemImage: "arrow.turn.down.right").font(.callout)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !subject.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        Button(role: .destructive) {
                            onSave("", "")
                            dismiss()
                        } label: {
                            Label("Svuota cella", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Lezione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") { onSave(subject, teacher); dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { subjectFocused = true }
        }
    }

    private func autocompleteSubject() {
        if let f = suggest(subject, from: subjectPool).first {
            subject = f
            if teacher.isEmpty, let t = subjectTeachers[f] { teacher = t }
        }
    }
}
