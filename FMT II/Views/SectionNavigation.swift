import SwiftUI
import UIKit

// MARK: - Pop-on-long-press (note creation)

/// Shrinks the element while held, then springs back with a haptic when the
/// long press fires — syncing what the finger feels with what the eye sees.
struct PopOnLongPress: ViewModifier {
    let action: () -> Void
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: pressed)
            // simultaneousGesture so a normal tap on the underlying button still
            // works (navigation), while a long press creates the note.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in
                        pressed = false
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        action()
                    }
            )
    }
}

extension View {
    func popAddNote(perform: @escaping () -> Void) -> some View {
        modifier(PopOnLongPress(action: perform))
    }
}

// MARK: - Section titles

extension AppSection {
    var aurora: AuroraSection {
        switch self {
        case .schedule: return .orario
        case .notes:    return .diario
        case .grades:   return .voti
        }
    }

    var title: String {
        switch self {
        case .schedule: return L("Orario")
        case .notes:    return L("Diario")
        case .grades:   return L("Voti")
        }
    }

    /// Per-section accent used to tint the sliding glass pill, so the colour
    /// gives an at-a-glance cue of which section you're on.
    var accent: Color {
        switch self {
        case .schedule: return AuroraSection.orario.accent
        case .notes:    return AuroraSection.diario.accent
        case .grades:   return AuroraSection.voti.accent
        }
    }
}

// MARK: - Liquid Glass helper

extension View {
    /// Applies the real iOS 26 Liquid Glass effect when available, otherwise a
    /// faithful translucent-material fallback for iOS 17–25.
    @ViewBuilder
    func liquidGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        }
    }
}

// MARK: - Horizontal paging container

/// Tracks the live horizontal scroll offset so external chrome (the glass bar)
/// can follow the pages continuously, even mid-swipe.
private struct PagerOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {}
}

/// A horizontally paged container built on a native paging `ScrollView`, so it
/// coexists cleanly with inner vertical lists and horizontal carousels. Exposes
/// a continuous `progress` (0...count-1) for syncing the section bar.
struct SectionPager<Page: View>: View {
    let count: Int
    @Binding var index: Int
    @Binding var progress: CGFloat
    @ViewBuilder let page: (Int) -> Page

    @State private var scrolledID: Int?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { i in
                        page(i)
                            .frame(width: w)
                            .id(i)
                    }
                }
                .scrollTargetLayout()
                .background(
                    GeometryReader { inner in
                        Color.clear.preference(
                            key: PagerOffsetKey.self,
                            value: inner.frame(in: .named("pager")).minX
                        )
                    }
                )
            }
            .coordinateSpace(name: "pager")
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledID)
            .scrollIndicators(.hidden)
            .onPreferenceChange(PagerOffsetKey.self) { minX in
                guard w > 0 else { return }
                progress = -minX / w
            }
            .onChange(of: scrolledID) { _, new in
                if let new, new != index { index = new }
            }
            .onChange(of: index) { _, new in
                if scrolledID != new {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                        scrolledID = new
                    }
                }
            }
            .onChange(of: count) { _, _ in
                let clamped = min(max(index, 0), count - 1)
                if index != clamped { index = clamped }
                scrolledID = clamped
                progress = CGFloat(clamped)
            }
            .onAppear { scrolledID = index }
            // Rotazione / ridimensionamento: le pagine cambiano larghezza ma lo
            // ScrollView conserva lo scostamento vecchio (due sezioni a metà,
            // sovrapposte). Riallinea alla pagina corrente, senza animazione.
            .onChange(of: w) { _, _ in
                let target = index
                var noAnimation = Transaction()
                noAnimation.disablesAnimations = true
                withTransaction(noAnimation) { scrolledID = nil }
                DispatchQueue.main.async {
                    withTransaction(noAnimation) { scrolledID = target }
                    progress = CGFloat(target)
                }
            }
        }
    }
}

// MARK: - Liquid Glass section bar

/// A compact segmented control designed to live in the navigation bar's leading
/// slot. Its highlight pill is a real Liquid Glass lozenge (iOS 26) that follows
/// the pager `progress` in real time, so the control and the pages move together.
/// Sitting inside the native (already-glass) toolbar keeps the trailing buttons
/// and any pushed back button in the same bar — nothing slides underneath it.
struct GlassSectionBar: View {
    let titles: [String]
    var colors: [Color] = []
    @Binding var index: Int
    let progress: CGFloat

    // Scaled so the top menu grows with the app's text-size setting instead of
    // clipping the labels inside a fixed-width pill.
    @ScaledMetric(relativeTo: .footnote) private var rawSegWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = 32
    @ScaledMetric(relativeTo: .footnote) private var inset: CGFloat = 5

    /// A «Enorme» il selettore sfondava la barra e copriva i bottoni trailing
    /// (che smettevano di ricevere i tocchi): la larghezza dei segmenti è
    /// limitata così da lasciare sempre spazio al resto della toolbar.
    private var segWidth: CGFloat {
        let available = UIScreen.main.bounds.width - 120
        return min(rawSegWidth, available / CGFloat(max(titles.count, 1)))
    }

    private var tint: Color {
        guard !colors.isEmpty else { return .accentColor }
        let i = min(max(Int(progress.rounded()), 0), colors.count - 1)
        return colors[i]
    }

    var body: some View {
        let maxIdx = CGFloat(max(titles.count - 1, 0))
        let clamped = min(max(progress, 0), maxIdx)

        ZStack(alignment: .leading) {
            // Pill che scivola, con lo spettro che scorre (3a)
            pill(clamped: clamped, maxIdx: maxIdx)
                .frame(width: segWidth - inset * 2, height: height - inset * 2)
                .offset(x: clamped * segWidth + inset)

            // Labels
            HStack(spacing: 0) {
                ForEach(titles.indices, id: \.self) { i in
                    let active = abs(clamped - CGFloat(i)) < 0.5
                    Text(titles[i])
                        .font(.footnote.weight(active ? .bold : .semibold))
                        // «Timetable» è più lungo di «Orario»: si riduce appena invece di troncarsi.
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(active ? Color.white : .primary)
                        .opacity(labelOpacity(for: i, progress: clamped))
                        .frame(width: segWidth, height: height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.9)) {
                                index = i
                            }
                        }
                }
            }
        }
        .frame(width: segWidth * CGFloat(titles.count), height: height)
        .padding(4)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(.white.opacity(0.11), lineWidth: 1))
        .animation(.spring(response: 0.52, dampingFraction: 0.9), value: index)
    }

    /// Pill con il gradiente-spettro completo che scorre con il progresso:
    /// "il pill del selettore scivola e il suo gradiente scorre lungo lo
    /// spettro" (design 3a).
    @ViewBuilder
    private func pill(clamped: CGFloat, maxIdx: CGFloat) -> some View {
        let pillW = segWidth - inset * 2
        let windowFraction = maxIdx > 0 ? clamped / maxIdx : 0
        let gradientW = pillW * 3
        Capsule()
            .fill(.clear)
            .overlay(
                LinearGradient(colors: auroraSpectrum, startPoint: .leading, endPoint: .trailing)
                    .frame(width: gradientW)
                    .offset(x: -windowFraction * (gradientW - pillW) + (gradientW - pillW) / 2)
            )
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.30), lineWidth: 0.8))
            .shadow(color: Color(hex: "#6960F6")!.opacity(0.5), radius: 9, y: 3)
    }

    /// Nearest segment is fully opaque; neighbours fade toward 0.5 as the pill
    /// slides away, giving a continuous feel rather than a hard snap.
    private func labelOpacity(for i: Int, progress: CGFloat) -> Double {
        let distance = min(abs(progress - CGFloat(i)), 1)
        return 0.5 + 0.5 * (1 - Double(distance))
    }
}
