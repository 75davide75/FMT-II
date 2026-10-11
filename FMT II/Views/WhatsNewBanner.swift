import SwiftUI

/// Banner «Novità» mostrato una sola volta a chi aggiorna l'app (tutorial già
/// completato prima di questo avvio), mai a chi la installa da zero.
enum WhatsNew {
    static let version = "2.2"
    static let storageKey = "lastSeenWhatsNew"

    static func shouldShow(tutorialDoneAtLaunch: Bool, lastSeen: String) -> Bool {
        tutorialDoneAtLaunch && lastSeen.compare(version, options: .numeric) == .orderedAscending
    }
}

struct WhatsNewBanner: View {
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            // Sfondo sfocato + velo (come il popup nome classe del builder):
            // il contenuto dietro non deve trasparire dentro la card.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            Color.black.opacity(scheme == .dark ? 0.35 : 0.15).ignoresSafeArea()
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(AuroraSection.neutral.gradient,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("NOVITÀ · \(WhatsNew.version)")
                        .font(.system(size: 10.5, weight: .heavy))
                        .kerning(1)
                        .foregroundStyle(Color(hex: "#A5B4FC")!)
                    Text("Novità di FMT \(WhatsNew.version)")
                        .font(.system(size: 18, weight: .bold))
                }
                Spacer(minLength: 0)
            }
            feature(icon: "icloud.fill", hex: "#38BDF8",
                    title: L("Sincronizzazione iCloud"),
                    text: L("Voti, diario e orario uguali su iPhone e iPad con lo stesso Apple ID."))
            feature(icon: "clock.fill", hex: "#8B5CF6",
                    title: L("Ora d'inizio per classe"),
                    text: L("Ogni classe può entrare a un orario diverso: Impostazioni → Dati orario."))
            if UIDevice.current.userInterfaceIdiom == .pad {
                feature(icon: "ipad.landscape", hex: "#F472B6",
                        title: L("Pensata per iPad"),
                        text: L("Settimana a tutto schermo e schermate su due colonne in orizzontale."))
            }
            feature(icon: "globe", hex: "#34D399",
                    title: L("Italiano e inglese"),
                    text: L("Scegli la lingua in Impostazioni → Aspetto."))
            Button(action: onDismiss) {
                Text("Ho capito")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .auroraProminent(.neutral, radius: 13)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
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
        .frame(maxWidth: 460)
        .padding(.horizontal, 24)
    }

    private func feature(icon: String, hex: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: hex)!)
                .frame(width: 28, height: 28)
                .background(Color(hex: hex)!.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5, weight: .semibold))
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
