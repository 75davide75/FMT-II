import SwiftUI

private struct TutorialSlide {
    let icon: String
    let iconColors: [Color]
    let title: String
    let description: String
    var iconOffset: CGSize = .zero
}

private let slides: [TutorialSlide] = [
    TutorialSlide(
        icon: "magnifyingglass",
        iconColors: [.blue, .purple],
        title: "FindMyTeacher",
        description: "L'orario della tua scuola, sempre in tasca. Trova dov'è ogni lezione in un attimo."
    ),
    TutorialSlide(
        icon: "arrow.up.doc.fill",
        iconColors: [.green, .teal],
        title: "Carica una volta",
        description: "Importa il PDF dell'orario: lo trasformiamo in un orario interattivo. Niente PDF? Puoi crearlo a mano in pochi tocchi."
    ),
    TutorialSlide(
        icon: "graduationcap.fill",
        iconColors: [.orange, .yellow],
        title: "Cerca come vuoi",
        description: "Per classe o per docente: vedi subito dov'è e cosa c'è adesso, oggi o in settimana."
    ),
    TutorialSlide(
        icon: "book.closed.fill",
        iconColors: [.indigo, .blue],
        title: "Il tuo Diario",
        description: "Tieni premuto su una lezione per annotare compiti e promemoria, ordinati per giorno e ora."
    ),
    TutorialSlide(
        icon: "chart.line.uptrend.xyaxis",
        iconColors: [.purple, .indigo],
        title: "Voti sotto controllo",
        description: "Segna i voti, scegli il peso e tieni d'occhio media, andamento e obiettivi."
    )
]

struct TutorialView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            // Sfondo aurora del design system (continuo con la Welcome).
            AuroraBackground(section: .neutral)

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(slides.indices, id: \.self) { index in
                        SlideContentView(slide: slides[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 14) {
                Button {
                    if currentPage < slides.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        handleFinish()
                    }
                } label: {
                    Text(currentPage < slides.count - 1 ? "Avanti" : "Inizia")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .auroraProminent(.neutral)
                }

                Button("Salta", action: handleFinish)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .opacity(currentPage < slides.count - 1 ? 1 : 0)
                    .allowsHitTesting(currentPage < slides.count - 1)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .padding(.top, 8)
            }
        }
        .navigationTitle("Tutorial")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func handleFinish() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}

private struct SlideContentView: View {
    let slide: TutorialSlide

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: slide.iconColors.map { $0.opacity(0.15) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 150, height: 150)

                Image(systemName: slide.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: slide.iconColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .offset(slide.iconOffset)
            }

            VStack(spacing: 14) {
                Text(slide.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(slide.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
        .padding(.bottom, 20)
    }
}
