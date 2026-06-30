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
    var title: String {
        switch self {
        case .schedule: return "Orario"
        case .notes:    return "Diario"
        case .grades:   return "Voti"
        }
    }

    /// Per-section accent used to tint the sliding glass pill, so the colour
    /// gives an at-a-glance cue of which section you're on.
    var accent: Color {
        switch self {
        case .schedule: return .blue
        case .notes:    return .indigo
        case .grades:   return .purple
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

    private let segWidth: CGFloat = 62
    private let height: CGFloat = 32
    private let inset: CGFloat = 5

    private var tint: Color {
        guard !colors.isEmpty else { return .accentColor }
        let i = min(max(Int(progress.rounded()), 0), colors.count - 1)
        return colors[i]
    }

    var body: some View {
        let maxIdx = CGFloat(max(titles.count - 1, 0))
        let clamped = min(max(progress, 0), maxIdx)

        ZStack(alignment: .leading) {
            // Sliding Liquid Glass pill
            pill
                .frame(width: segWidth - inset * 2, height: height - inset * 2)
                .offset(x: clamped * segWidth + inset)
                .animation(.easeInOut(duration: 0.25), value: tint)

            // Labels
            HStack(spacing: 0) {
                ForEach(titles.indices, id: \.self) { i in
                    Text(titles[i])
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .opacity(labelOpacity(for: i, progress: clamped))
                        .frame(width: segWidth, height: height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                                index = i
                            }
                        }
                }
            }
        }
        .frame(width: segWidth * CGFloat(titles.count), height: height)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: index)
    }

    @ViewBuilder
    private var pill: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(tint.opacity(0.22))
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(tint.opacity(0.20)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
        }
    }

    /// Nearest segment is fully opaque; neighbours fade toward 0.5 as the pill
    /// slides away, giving a continuous feel rather than a hard snap.
    private func labelOpacity(for i: Int, progress: CGFloat) -> Double {
        let distance = min(abs(progress - CGFloat(i)), 1)
        return 0.5 + 0.5 * (1 - Double(distance))
    }
}
