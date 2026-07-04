import SwiftUI

// MARK: - Manuale (stile Aurora Glass)

private struct ManualEntry: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    var icon: String = "circle.fill"
}

private struct ManualSection: Identifiable {
    let id = UUID()
    let screen: String
    let icon: String
    let tintHex: String
    let entries: [ManualEntry]
}

struct ManualView: View {
    @State private var query = ""
    @Environment(\.colorScheme) private var scheme

    private let sections: [ManualSection] = [
        ManualSection(screen: "Per iniziare", icon: "hand.wave.fill", tintHex: "#34D399", entries: [
            ManualEntry(title: "Cambiare sezione",
                        detail: "In alto c'è il selettore Orario · Diario · Voti: la pillola colorata scivola con te. Tocca un nome oppure scorri orizzontalmente la pagina: lo sfondo sfuma verso la tinta della sezione.",
                        icon: "rectangle.3.group.fill"),
            ManualEntry(title: "Importare l'orario da PDF",
                        detail: "Alla prima apertura importi il PDF dell'orario della scuola. Se il PDF è completo l'import è immediato; se manca un solo elemento (per esempio i docenti) l'app importa il resto e ti fa scegliere per quali classi completare i dati a mano; se il file non è leggibile o contiene conflitti viene rifiutato e ti viene proposta la creazione manuale.",
                        icon: "square.and.arrow.down.fill"),
            ManualEntry(title: "Creare l'orario a mano",
                        detail: "Senza PDF scegli \"Crea il mio orario\": imposti classe, ore (inizio + durata) e giorni, poi tocchi le celle della griglia per inserire le materie. Le celle libere sono tratteggiate; il docente è facoltativo e viene ricompilato da solo una volta abbinato a una materia.",
                        icon: "square.and.pencil"),
            ManualEntry(title: "Tema e colori",
                        detail: "Dalle Impostazioni scegli tema chiaro/scuro/automatico e assegni un colore personale a ogni classe, docente o materia: lo ritrovi in tutte le viste dell'orario.",
                        icon: "paintpalette.fill")
        ]),
        ManualSection(screen: "Orario", icon: "calendar", tintHex: "#38BDF8", entries: [
            ManualEntry(title: "Le tre viste",
                        detail: "Adesso mostra l'ora corrente con la barra di avanzamento e la prossima ora; Giorno l'intera giornata; Settimana la griglia completa con le etichette colorate.",
                        icon: "clock.fill"),
            ManualEntry(title: "Classe, Docente o Materia",
                        detail: "Col selettore scegli se consultare per classe o per docente. Se l'orario importato contiene solo le materie (senza docenti), il filtro diventa automaticamente Classe/Materia.",
                        icon: "person.2.fill"),
            ManualEntry(title: "Cercare",
                        detail: "Digita il cognome (o la materia): compare l'elenco dei suggerimenti, Invio sceglie il primo. La ✕ cancella la ricerca.",
                        icon: "magnifyingglass"),
            ManualEntry(title: "Vedere la controparte",
                        detail: "Tocca una lezione per saltare alla sua controparte: dalla classe vedi l'orario di quel docente, e viceversa. Il passaggio è animato.",
                        icon: "arrow.triangle.2.circlepath"),
            ManualEntry(title: "Creare una nota da una lezione",
                        detail: "Tieni premuto su una lezione e scegli \"Crea nota\": la voce di diario nasce già con giorno, ora, docente/classe e materia compilati.",
                        icon: "note.text.badge.plus"),
            ManualEntry(title: "Ora manuale",
                        detail: "Tocca il badge Live (o dalle Impostazioni) per fissare un giorno e un'ora specifici da consultare al posto dell'ora corrente.",
                        icon: "clock.badge.questionmark"),
            ManualEntry(title: "Condividere l'orario",
                        detail: "Dall'icona di condivisione esporti l'orario in un file da inviare o salvare; chi lo riceve lo importa senza rifare nulla.",
                        icon: "square.and.arrow.up")
        ]),
        ManualSection(screen: "Diario", icon: "book.closed.fill", tintHex: "#4E7CF6", entries: [
            ManualEntry(title: "Nuova voce",
                        detail: "Tocca il pulsante + in basso a destra. Nel testo puoi usare Titolo, Intestazione, Sottotitolo, Corpo e grassetto, corsivo, sottolineato, barrato.",
                        icon: "plus.circle.fill"),
            ManualEntry(title: "La striscia della settimana",
                        detail: "Le date in alto scorrono e si toccano: toccandone una, l'elenco salta alle note di quel giorno. I puntini colorati indicano i tipi di impegno presenti (rosa verifica, ambra compito, viola interrogazione, azzurro nota).",
                        icon: "calendar.day.timeline.left"),
            ManualEntry(title: "Filtri rapidi",
                        detail: "Sotto le date trovi Tutti / Compiti / Verifiche / Interrogazioni, sempre visibili. Le verifiche hanno la card rosata con il bordo sfumato.",
                        icon: "line.3.horizontal.decrease.circle.fill"),
            ManualEntry(title: "Dettagli della voce",
                        detail: "Nel pannello \"Dettagli\" assegni tipo, giorno, ora, materia, docente, classe e promemoria — il testo resta visibile mentre scrivi.",
                        icon: "tag.fill"),
            ManualEntry(title: "Promemoria multipli",
                        detail: "Più avvisi per la stessa voce, ciascuno con giorno e ora (ricorrenti ogni settimana): uno il giorno prima e uno il giorno stesso, per esempio.",
                        icon: "bell.fill"),
            ManualEntry(title: "Cercare e filtrare",
                        detail: "Menu ••• → Cerca trova qualsiasi parola nel testo; Filtra mostra solo le voci con un certo tag (materia, docente o classe) o tipo.",
                        icon: "magnifyingglass"),
            ManualEntry(title: "Selezione multipla e archivio",
                        detail: "Menu ••• → Seleziona per eliminare o archiviare in blocco; Mostra l'archivio per rivedere e ripristinare le voci archiviate.",
                        icon: "checklist"),
            ManualEntry(title: "Azioni rapide",
                        detail: "Tieni premuto su una voce per Modifica, Archivia o Elimina; oppure scorrila verso sinistra.",
                        icon: "hand.tap.fill")
        ]),
        ManualSection(screen: "Voti", icon: "chart.line.uptrend.xyaxis", tintHex: "#8B5CF6", entries: [
            ManualEntry(title: "Aggiungere un voto",
                        detail: "Col + inserisci materia (con suggerimenti), docente, voto, tipo, data, peso e se fa media. Il ring in alto mostra la media generale con le barre dei periodi.",
                        icon: "plus.circle.fill"),
            ManualEntry(title: "Peso e media",
                        detail: "Il peso (0–100%) determina quanto il voto incide nella media ponderata. Disattivando \"Fa media\" il voto diventa blu e non viene conteggiato.",
                        icon: "scalemass.fill"),
            ManualEntry(title: "Grafico andamento",
                        detail: "Nella scheda materia, la card Andamento mostra la curva dei voti col colore della materia: la linea rosa tratteggiata è la sufficienza, i punti insufficienti sono rosa col valore sotto. Tocca un punto per il dettaglio (alone viola).",
                        icon: "chart.xyaxis.line"),
            ManualEntry(title: "Obiettivo media",
                        detail: "Imposta la media obiettivo: l'app calcola quale o quanti voti ti servono per raggiungerla.",
                        icon: "target"),
            ManualEntry(title: "Colore della materia",
                        detail: "Dal cerchio colorato in alto a destra nella scheda materia personalizzi il colore: righe, grafico e sfondo si adattano.",
                        icon: "paintbrush.fill"),
            ManualEntry(title: "Ultimi voti ed elenco materie",
                        detail: "Le bolle \"Ultimi voti\" scorrono in orizzontale; \"Vedi tutti ›\" (o l'icona elenco) apre tutte le materie con la rispettiva media.",
                        icon: "list.bullet.circle.fill"),
            ManualEntry(title: "Soglia personalizzata",
                        detail: "Cambiando voto sufficiente o massimo nelle Impostazioni, i colori di tutti i voti (verde/arancio/rosso) si aggiornano immediatamente.",
                        icon: "slider.horizontal.3")
        ]),
        ManualSection(screen: "Impostazioni", icon: "gearshape.fill", tintHex: "#F472B6", entries: [
            ManualEntry(title: "Aspetto",
                        detail: "Tema chiaro/scuro/automatico, dimensione del testo (fino a Enorme) e colori personalizzati per classi, docenti e materie.",
                        icon: "circle.lefthalf.filled"),
            ManualEntry(title: "Orario",
                        detail: "Sorgente e contenuto dell'orario caricato, ora corrente o manuale, PDF originale, modifica dell'orario creato a mano e Dati orario (docenti, classi, fasce, lezioni).",
                        icon: "calendar"),
            ManualEntry(title: "Voti",
                        detail: "Scala dei voti (sufficienza e massimo) e periodi: quadrimestri oppure trimestre + pentamestre, con la fine del primo periodo (solo giorno e mese).",
                        icon: "chart.bar.fill"),
            ManualEntry(title: "Dati e backup",
                        detail: "Esporti orario, diario e voti in un unico file e li reimporti quando vuoi, anche su un altro dispositivo.",
                        icon: "externaldrive.fill"),
            ManualEntry(title: "Zona di rischio",
                        detail: "Cambia o rimuovi l'orario, cancella tutto il diario o tutti i voti. Ogni azione chiede conferma e non è reversibile.",
                        icon: "exclamationmark.triangle.fill"),
            ManualEntry(title: "Segnala un problema",
                        detail: "Apre l'app Mail con un messaggio già pronto da inviare allo sviluppatore.",
                        icon: "exclamationmark.bubble.fill")
        ])
    ]

    private var filteredSections: [ManualSection] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sections }
        return sections.compactMap { section in
            let entries = section.entries.filter {
                $0.title.lowercased().contains(q) || $0.detail.lowercased().contains(q)
            }
            return entries.isEmpty ? nil
                : ManualSection(screen: section.screen, icon: section.icon, tintHex: section.tintHex, entries: entries)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AuroraTitle(title: "Manuale",
                            subtitle: "Tutte le funzioni, sezione per sezione")
                    .padding(.top, 2)

                // Campo di ricerca in vetro
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Cerca una funzione", text: $query)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white.opacity(scheme == .dark ? 0.06 : 0.7),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(scheme == .dark ? 0.10 : 0.5), lineWidth: 1))

                if filteredSections.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(.quaternary)
                        Text("Nessun risultato per «\(query)»")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }

                ForEach(filteredSections) { section in
                    sectionCard(section)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background { AuroraBackground(section: .neutral) }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionCard(_ section: ManualSection) -> some View {
        let tint = Color(hex: section.tintHex)!
        return VStack(alignment: .leading, spacing: 0) {
            // Intestazione della sezione: badge sfumato + nome in maiuscoletto
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        LinearGradient(colors: [tint.blended(with: .white, by: 0.18), tint],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .shadow(color: tint.opacity(0.4), radius: 6, y: 3)
                Text(section.screen.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .kerning(1)
                    .foregroundStyle(scheme == .dark ? tint.blended(with: .white, by: 0.35) : tint.blended(with: .black, by: 0.2))
                Spacer()
                Text("\(section.entries.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.07), in: Capsule())
            }
            .padding(14)

            // Voci con hairline tra le righe (come le card del canvas)
            ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Rectangle()
                        .fill(.white.opacity(scheme == .dark ? 0.07 : 0.35))
                        .frame(height: 1)
                        .padding(.leading, 46)
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: entry.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.system(size: 15, weight: .semibold))
                        Text(entry.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            Spacer().frame(height: 6)
        }
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: scheme == .dark
                        ? [.white.opacity(0.08), .white.opacity(0.035)]
                        : [.white.opacity(0.92), .white.opacity(0.65)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.6), lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.06), radius: 14, y: 6)
    }
}
