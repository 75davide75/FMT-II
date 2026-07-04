import SwiftUI

// Aurora Glass design system — dal canvas "Riprogettazione interfaccia app
// stile Apple" (direzione 1a): ogni sezione ha la sua coppia di tinte sullo
// stesso spettro (Orario cilestino→blu, Diario blu→violetto, Voti
// violetto→rosa→pesca), sfondo scuro con "aurore" radiali, card in vetro.

enum AuroraSection {
    case orario, diario, voti, neutral

    var tintA: Color {
        switch self {
        case .orario:  return Color(hex: "#38BDF8")!
        case .diario:  return Color(hex: "#4E7CF6")!
        case .voti:    return Color(hex: "#8B5CF6")!
        case .neutral: return Color(hex: "#4E7CF6")!
        }
    }

    var tintB: Color {
        switch self {
        case .orario:  return Color(hex: "#4E7CF6")!
        case .diario:  return Color(hex: "#8B5CF6")!
        case .voti:    return Color(hex: "#F472B6")!
        case .neutral: return Color(hex: "#8B5CF6")!
        }
    }

    var tintC: Color? {
        self == .voti ? Color(hex: "#F8A87E") : nil
    }

    /// Accent usato per testi/icone della sezione.
    var accent: Color { tintB }

    /// Il gradiente firma della sezione (135°).
    var gradient: LinearGradient {
        var colors = [tintA, tintB]
        if let c = tintC { colors.append(c) }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Sfondo aurora

struct AuroraBackground: View {
    var section: AuroraSection = .neutral
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if scheme == .dark {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#070A15")!, location: 0),
                        .init(color: Color(hex: "#05060D")!, location: 0.45),
                        .init(color: Color(hex: "#04050A")!, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(colors: [section.tintA.opacity(0.32), .clear],
                               center: UnitPoint(x: 0.12, y: -0.02),
                               startRadius: 10, endRadius: 420)
                RadialGradient(colors: [section.tintB.opacity(0.27), .clear],
                               center: UnitPoint(x: 0.95, y: 0.02),
                               startRadius: 10, endRadius: 400)
                RadialGradient(colors: [Color(hex: "#7DD3FC")!.opacity(0.10), .clear],
                               center: UnitPoint(x: 0.6, y: -0.06),
                               startRadius: 10, endRadius: 320)
            } else {
                Color(.systemGroupedBackground)
                RadialGradient(colors: [section.tintA.opacity(0.30), .clear],
                               center: UnitPoint(x: 0.12, y: -0.02),
                               startRadius: 10, endRadius: 460)
                RadialGradient(colors: [section.tintB.opacity(0.24), .clear],
                               center: UnitPoint(x: 0.95, y: 0.02),
                               startRadius: 10, endRadius: 430)
                LinearGradient(colors: [.clear, section.tintB.opacity(0.08)],
                               startPoint: .center, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Card in vetro

private struct AuroraCardModifier: ViewModifier {
    var radius: CGFloat
    var strokeTint: Color?
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if scheme == .dark {
                    shape.fill(
                        LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.045)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                } else {
                    shape.fill(
                        LinearGradient(colors: [.white.opacity(0.92), .white.opacity(0.65)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                }
            }
            .overlay(
                shape.strokeBorder(
                    (strokeTint ?? .white).opacity(scheme == .dark ? 0.13 : 0.65),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.07), radius: 12, y: 5)
    }
}

extension View {
    /// Card glass del design Aurora (raggio 22 di default, come nel canvas).
    func auroraCard(radius: CGFloat = 22, strokeTint: Color? = nil) -> some View {
        modifier(AuroraCardModifier(radius: radius, strokeTint: strokeTint))
    }

    /// CTA primaria con il gradiente firma della sezione.
    func auroraProminent(_ section: AuroraSection, radius: CGFloat = 14) -> some View {
        self
            .background(section.gradient, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .foregroundStyle(.white)
            .shadow(color: section.tintB.opacity(0.35), radius: 10, y: 4)
    }
}

// MARK: - Riquadro colore per le celle lezione

extension AuroraSection {
    /// Riempimento dei chip lezione (settimana/giorno) con il gradiente sezione.
    var chipGradient: LinearGradient {
        LinearGradient(colors: [tintA, tintB], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Aurore esatte per sezione (opzione 3a del canvas)

private struct AuroraSpec {
    var r1: (Color, Double)   // radial 15%,-4%
    var r2: (Color, Double)   // radial 95%,2%
    var r3: (Color, Double)   // radial 60-65%,-8%
    var baseTop: String
    var baseMid: String
}

private func spec(for section: AuroraSection) -> AuroraSpec {
    switch section {
    case .orario:
        return AuroraSpec(r1: (Color(hex: "#38BDF8")!, 0.36), r2: (Color(hex: "#4E7CF6")!, 0.36),
                          r3: (Color(hex: "#5EEAD4")!, 0.14), baseTop: "#060B15", baseMid: "#05070D")
    case .voti:
        return AuroraSpec(r1: (Color(hex: "#8B5CF6")!, 0.36), r2: (Color(hex: "#F472B6")!, 0.28),
                          r3: (Color(hex: "#FB923C")!, 0.20), baseTop: "#0B0812", baseMid: "#07060D")
    default:
        return AuroraSpec(r1: (Color(hex: "#4E7CF6")!, 0.40), r2: (Color(hex: "#8B5CF6")!, 0.34),
                          r3: (Color(hex: "#7DD3FC")!, 0.16), baseTop: "#070A15", baseMid: "#05060D")
    }
}

/// Un singolo strato aurora, fedele ai radial-gradient del canvas.
struct AuroraLayer: View {
    let section: AuroraSection
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = spec(for: section)
        ZStack {
            if scheme == .dark {
                LinearGradient(stops: [
                    .init(color: Color(hex: s.baseTop)!, location: 0),
                    .init(color: Color(hex: s.baseMid)!, location: 0.45),
                    .init(color: Color(hex: "#04050A")!, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [s.r1.0.opacity(s.r1.1), .clear],
                               center: UnitPoint(x: 0.15, y: -0.04), startRadius: 8, endRadius: 400)
                RadialGradient(colors: [s.r2.0.opacity(s.r2.1), .clear],
                               center: UnitPoint(x: 0.95, y: 0.02), startRadius: 8, endRadius: 380)
                RadialGradient(colors: [s.r3.0.opacity(s.r3.1), .clear],
                               center: UnitPoint(x: 0.62, y: -0.08), startRadius: 8, endRadius: 320)
            } else {
                Color(.systemGroupedBackground)
                RadialGradient(colors: [s.r1.0.opacity(0.30), .clear],
                               center: UnitPoint(x: 0.15, y: -0.04), startRadius: 8, endRadius: 440)
                RadialGradient(colors: [s.r2.0.opacity(0.24), .clear],
                               center: UnitPoint(x: 0.95, y: 0.02), startRadius: 8, endRadius: 410)
                LinearGradient(colors: [.clear, s.r2.0.opacity(0.08)],
                               startPoint: .center, endPoint: .bottom)
            }
        }
    }
}

/// Sfondo unico dell'app: dissolve tra le aurore delle sezioni seguendo il
/// progresso del pager (750 ms al tocco, continuo durante lo swipe) — come
/// nell'opzione 3a: "l'aurora di sfondo dissolve verso la tinta della scheda".
struct AuroraCrossfadeBackground: View {
    let sections: [AuroraSection]
    let progress: CGFloat

    var body: some View {
        ZStack {
            Color(hex: "#04050A")!
            ForEach(sections.indices, id: \.self) { i in
                AuroraLayer(section: sections[i])
                    .opacity(1 - min(1, Double(abs(progress - CGFloat(i)))))
            }
        }
        .ignoresSafeArea()
    }
}

/// Ingresso del contenuto di sezione: fade + leggera salita + scala (3a),
/// pilotato in continuo dal progresso del pager.
struct SectionEntrance: ViewModifier {
    let distance: CGFloat   // i - pagerProgress

    func body(content: Content) -> some View {
        let d = min(1, abs(distance))
        return content
            .opacity(1 - 0.6 * Double(d))
            .scaleEffect(1 - 0.015 * d)
            .offset(y: 14 * d)
    }
}

// MARK: - Spettro completo (pill del selettore)

let auroraSpectrum: [Color] = ["#38BDF8", "#4E7CF6", "#8B5CF6", "#F472B6", "#F8A87E"].compactMap { Color(hex: $0) }

// MARK: - Chip colorati (design 1a)

/// Chip pillola con puntino colorato, come le etichette del Diario.
struct AuroraChip: View {
    let text: String
    var color: Color = Color(hex: "#60A5FA")!
    var icon: String? = nil
    var showDot: Bool = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
            } else if showDot {
                Circle().fill(color).frame(width: 5, height: 5)
            }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(scheme == .dark ? color.blended(with: .white, by: 0.35) : color.blended(with: .black, by: 0.25))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
    }
}

// MARK: - Tipi di nota: gradienti e colori (1a)

extension NoteTaskType {
    var auroraColor: Color {
        switch self {
        case .verifica:       return Color(hex: "#FB7185")!
        case .compito:        return Color(hex: "#F59E0B")!
        case .interrogazione: return Color(hex: "#A78BFA")!
        }
    }
    var auroraGradient: LinearGradient {
        switch self {
        case .verifica:       return LinearGradient(colors: [Color(hex: "#FB7185")!, Color(hex: "#F472B6")!], startPoint: .top, endPoint: .bottom)
        case .compito:        return LinearGradient(colors: [Color(hex: "#FBBF24")!, Color(hex: "#F59E0B")!], startPoint: .top, endPoint: .bottom)
        case .interrogazione: return LinearGradient(colors: [Color(hex: "#C4B5FD")!, Color(hex: "#A78BFA")!], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Barra/colore per note senza tipo ("Nota" azzurra nel canvas).
let plainNoteColor = Color(hex: "#38BDF8")!
let plainNoteGradient = LinearGradient(colors: [Color(hex: "#7DD3FC")!, Color(hex: "#38BDF8")!], startPoint: .top, endPoint: .bottom)

// MARK: - Titolo grande di sezione (32/800 + sottotitolo)

struct AuroraTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 32, weight: .heavy))
                .kerning(-0.6)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Segmentato in vetro con segmento attivo a gradiente (2a/2b)

struct AuroraSegmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var gradient: LinearGradient = LinearGradient(colors: [Color(hex: "#4E7CF6")!, Color(hex: "#8B5CF6")!],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing)
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { opt in
                let active = opt.value == selection
                Text(opt.label)
                    .font(.system(size: 12.5, weight: active ? .bold : .semibold))
                    .foregroundStyle(active ? .white : (scheme == .dark ? Color(hex: "#E6ECFF")!.opacity(0.55) : Color.secondary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(gradient)
                                .shadow(color: Color(hex: "#6960F6")!.opacity(0.45), radius: 7, y: 3)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { selection = opt.value } }
            }
        }
        .padding(3)
        .background(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(scheme == .dark ? 0.09 : 0.4), lineWidth: 1))
    }
}

// MARK: - Tinta stabile per nome (celle docente della settimana, 2b)

private let namePalette: [Color] = ["#F59E0B", "#F472B6", "#38BDF8", "#2DD4BF", "#60A5FA",
                                    "#E879F9", "#A3E635", "#A78BFA", "#FB923C", "#34D399",
                                    "#7DD3FC", "#FBBF24"].compactMap { Color(hex: $0) }

func nameTint(_ name: String) -> Color {
    let key = name.trimmingCharacters(in: .whitespaces).lowercased()
    guard !key.isEmpty else { return .gray }
    var hash = 5381
    for u in key.unicodeScalars { hash = (hash &* 33) &+ Int(u.value) }
    return namePalette[abs(hash) % namePalette.count]
}

// MARK: - Layout a bandiera per i chip delle card

struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

/// DayId di oggi, weekend incluso (il Diario copre lun-dom).
func todayDayId(_ date: Date = Date()) -> DayId {
    switch Calendar.current.component(.weekday, from: date) {
    case 2: return .monday
    case 3: return .tuesday
    case 4: return .wednesday
    case 5: return .thursday
    case 6: return .friday
    case 7: return .saturday
    default: return .sunday
    }
}

// MARK: - Miscela colori compatibile iOS 17 (Color.mix è iOS 18+)

extension Color {
    /// Interpola questo colore verso `other` in spazio sRGB.
    func blended(with other: Color, by fraction: Double) -> Color {
        let f = min(max(fraction, 0), 1)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(.sRGB,
                     red: Double(r1 + (r2 - r1) * f),
                     green: Double(g1 + (g2 - g1) * f),
                     blue: Double(b1 + (b2 - b1) * f),
                     opacity: Double(a1 + (a2 - a1) * f))
    }
}

// MARK: - Colori personalizzati per docente/materia/classe

/// Palette proposta per la personalizzazione (nomi + materie).
let entityPalette: [Color] = [
    "#F59E0B", "#F472B6", "#38BDF8", "#2DD4BF", "#60A5FA", "#E879F9",
    "#A3E635", "#A78BFA", "#FB923C", "#34D399", "#7DD3FC", "#FBBF24",
    "#FB7185", "#4E7CF6", "#8B5CF6", "#F8A87E", "#BEF264", "#6EE7B7",
    "#C4B5FD", "#FDA4AF", "#93C5FD", "#0D9488", "#CA8A04", "#E11D48"
].compactMap { Color(hex: $0) }

private let entityColorsKey = "fmt_entity_colors"

private func entityOverrides() -> [String: String] {
    guard let data = UserDefaults.standard.data(forKey: entityColorsKey),
          let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return dict
}

/// Colore di un docente/materia/classe: la scelta dell'utente se presente,
/// altrimenti la tinta stabile derivata dal nome.
func entityTint(_ name: String) -> Color {
    let key = name.trimmingCharacters(in: .whitespaces).lowercased()
    if let hex = entityOverrides()[key], let c = Color(hex: hex) { return c }
    return nameTint(name)
}

/// Salva (o azzera, con nil) il colore scelto per un nome e notifica le viste
/// tramite il contatore `entityColorsVersion`.
func setEntityColor(_ color: Color?, for name: String) {
    let key = name.trimmingCharacters(in: .whitespaces).lowercased()
    var dict = entityOverrides()
    if let hex = color?.hexString { dict[key] = hex } else { dict.removeValue(forKey: key) }
    if let data = try? JSONEncoder().encode(dict) {
        UserDefaults.standard.set(data, forKey: entityColorsKey)
    }
    UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "entityColorsVersion") + 1,
                              forKey: "entityColorsVersion")
}

func hasEntityColorOverride(_ name: String) -> Bool {
    entityOverrides()[name.trimmingCharacters(in: .whitespaces).lowercased()] != nil
}

/// Testo leggibile per un'etichetta colorata su fondo tinta al ~16%:
/// schiarita in scuro, scurita in chiaro — così il nome del docente/classe
/// resta contrastato in entrambi i temi.
func entityLabelColor(_ tint: Color, _ scheme: ColorScheme) -> Color {
    scheme == .dark ? tint.blended(with: .white, by: 0.45)
                    : tint.blended(with: .black, by: 0.5)
}

/// Gradiente-etichetta di un'entità (per la vista giornaliera).
func entityGradient(_ name: String) -> LinearGradient {
    let c = entityTint(name)
    return LinearGradient(colors: [c.blended(with: .white, by: 0.25), c],
                          startPoint: .top, endPoint: .bottom)
}
