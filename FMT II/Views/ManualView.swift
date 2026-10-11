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
        ManualSection(screen: L("Per iniziare"), icon: "hand.wave.fill", tintHex: "#34D399", entries: [
            ManualEntry(title: L("Cambiare sezione"),
                        detail: L("In alto c'è il selettore Orario · Diario · Voti: la pillola colorata scivola con te. Tocca un nome oppure scorri orizzontalmente la pagina: lo sfondo sfuma verso la tinta della sezione."),
                        icon: "rectangle.3.group.fill"),
            ManualEntry(title: L("Importare l'orario da PDF"),
                        detail: L("Alla prima apertura importi il PDF dell'orario della scuola. Se il PDF è completo l'import è immediato; se manca un solo elemento (per esempio i docenti) l'app importa il resto e ti fa scegliere per quali classi completare i dati a mano; se il file non è leggibile o contiene conflitti viene rifiutato e ti viene proposta la creazione manuale."),
                        icon: "square.and.arrow.down.fill"),
            ManualEntry(title: L("Creare l'orario a mano"),
                        detail: L("Senza PDF scegli \"Crea il mio orario\": il nome della classe è obbligatorio all'inizio (si può rinominare dopo, dalle Impostazioni orario), imposti ore (inizio + durata) e giorni, poi tocchi le celle della griglia per inserire le materie. La griglia è un foglio: pizzichi per zoomare e trascini per muoverti; in basso a sinistra c'è il controllo dello zoom e, quando sei zoomato, in basso a destra compare la minimappa per orientarti. Le celle libere sono tratteggiate; il docente è facoltativo e viene ricompilato da solo una volta abbinato a una materia."),
                        icon: "square.and.pencil"),
            ManualEntry(title: L("Tema e colori"),
                        detail: L("Dalle Impostazioni scegli tema chiaro/scuro/automatico e assegni un colore personale a ogni classe, docente o materia: lo ritrovi in tutte le viste dell'orario."),
                        icon: "paintpalette.fill")
        ]),
        ManualSection(screen: L("Orario"), icon: "calendar", tintHex: "#38BDF8", entries: [
            ManualEntry(title: L("Le tre viste"),
                        detail: L("Adesso mostra l'ora corrente con la barra di avanzamento e la prossima ora; Giorno l'intera giornata; Settimana la griglia completa con le etichette colorate."),
                        icon: "clock.fill"),
            ManualEntry(title: L("Classe, Docente o Materia"),
                        detail: L("Col selettore scegli se consultare per classe o per docente. Se l'orario importato contiene solo le materie (senza docenti), il filtro diventa automaticamente Classe/Materia."),
                        icon: "person.2.fill"),
            ManualEntry(title: L("Cercare"),
                        detail: L("Digita il cognome (o la materia): compare l'elenco dei suggerimenti, Invio sceglie il primo. La ✕ cancella la ricerca."),
                        icon: "magnifyingglass"),
            ManualEntry(title: L("Vedere la controparte"),
                        detail: L("Tocca una lezione per saltare alla sua controparte: dalla classe vedi l'orario di quel docente, e viceversa. Il passaggio è animato."),
                        icon: "arrow.triangle.2.circlepath"),
            ManualEntry(title: L("Creare una nota da una lezione"),
                        detail: L("Tieni premuto su una lezione e scegli \"Crea nota\": la voce di diario nasce già con giorno, ora, docente/classe e materia compilati."),
                        icon: "note.text.badge.plus"),
            ManualEntry(title: L("Ora manuale"),
                        detail: L("Tocca il badge Live (o dalle Impostazioni) per fissare un giorno e un'ora specifici da consultare al posto dell'ora corrente."),
                        icon: "clock.badge.questionmark"),
            ManualEntry(title: L("Condividere l'orario"),
                        detail: L("Dal menu ••• in alto a destra scegli \"Condividi orario\": esporti un file da inviare o salvare; chi lo riceve lo importa senza rifare nulla."),
                        icon: "square.and.arrow.up"),
            ManualEntry(title: L("Materie per classe (Dati orario)"),
                        detail: L("Menu ••• → Dati orario → \"Materie per classe\": qui modifichi le corrispondenze docente ↔ materia. Primo passo: scegli le classi da sistemare (o \"Tutte\"). Secondo passo: per ogni ora vedi giorno, orario e docente, e scrivi la materia nel campo a destra. Mentre digiti compaiono i suggerimenti delle materie più diffuse: Invio inserisce il primo. Appena confermi una materia per un docente, la stessa materia si precompila in tutte le sue altre ore (in grigio finché non le confermi); se cambi una di quelle ore, l'app ti chiede se il docente insegna più di una materia — con Sì quella singola ora può essere diversa, con No torna il valore proposto. Alla fine tocca \"Applica\" e poi \"Salva\" nei Dati orario."),
                        icon: "book.closed.fill"),
            ManualEntry(title: L("Ora d'inizio per classe"),
                        detail: L("Menu ••• → Dati orario → Fasce orarie: attiva \"Inizio diverso per classe\" e scegli per ogni classe a che ora inizia la 1ª ora (es. 1C alle 8:10, 3C alle 9:10). La durata delle lezioni resta uguale per tutte. In vista Docente le righe seguono gli orari reali di tutte le classi."),
                        icon: "clock.fill")
        ]),
        ManualSection(screen: L("Diario"), icon: "book.closed.fill", tintHex: "#4E7CF6", entries: [
            ManualEntry(title: L("Nuova voce"),
                        detail: L("Tocca il pulsante + in basso a destra. Nel testo puoi usare Titolo, Intestazione, Sottotitolo, Corpo e grassetto, corsivo, sottolineato, barrato."),
                        icon: "plus.circle.fill"),
            ManualEntry(title: L("La striscia dei giorni"),
                        detail: L("Le date in alto scorrono senza limite, avanti e indietro nel calendario: toccandone una, l'elenco salta alle note di quel giorno e il + crea una nota già datata su quel giorno. I puntini colorati indicano i tipi di impegno presenti (rosa verifica, ambra compito, viola interrogazione, azzurro nota)."),
                        icon: "calendar.day.timeline.left"),
            ManualEntry(title: L("Filtri rapidi"),
                        detail: L("Sotto le date trovi Tutti / Compiti / Verifiche / Interrogazioni, sempre visibili. Le verifiche hanno la card rosata con il bordo sfumato."),
                        icon: "line.3.horizontal.decrease.circle.fill"),
            ManualEntry(title: L("Dettagli della voce"),
                        detail: L("Nel pannello \"Dettagli\" assegni tipo, data completa (giorno, mese e anno), ora, materia, docente, classe e promemoria — il testo resta visibile mentre scrivi. Se non scegli una data, la voce resta sotto il giorno in cui è stata creata."),
                        icon: "tag.fill"),
            ManualEntry(title: L("Promemoria multipli"),
                        detail: L("Più avvisi per la stessa voce, ciascuno con giorno e ora (ricorrenti ogni settimana): uno il giorno prima e uno il giorno stesso, per esempio."),
                        icon: "bell.fill"),
            ManualEntry(title: L("Cercare e filtrare"),
                        detail: L("Menu ••• → Cerca trova qualsiasi parola nel testo; Filtra mostra solo le voci con un certo tag (materia, docente o classe) o tipo."),
                        icon: "magnifyingglass"),
            ManualEntry(title: L("Selezione multipla e archivio"),
                        detail: L("Menu ••• → Seleziona per eliminare o archiviare in blocco; Mostra l'archivio per rivedere e ripristinare le voci archiviate."),
                        icon: "checklist"),
            ManualEntry(title: L("Azioni rapide"),
                        detail: L("Tieni premuto su una voce per Modifica, Archivia o Elimina. Lo scorrimento verso sinistra archivia soltanto: per eliminare usa la pressione prolungata o la selezione multipla."),
                        icon: "hand.tap.fill")
        ]),
        ManualSection(screen: L("Voti"), icon: "chart.line.uptrend.xyaxis", tintHex: "#8B5CF6", entries: [
            ManualEntry(title: L("Aggiungere un voto"),
                        detail: L("Col + in basso a destra inserisci materia (con suggerimenti), docente, voto, tipo, data, peso e se fa media. L'anello in alto mostra la media generale con le barre dei periodi."),
                        icon: "plus.circle.fill"),
            ManualEntry(title: L("Peso e media"),
                        detail: L("Il peso (0–100%) determina quanto il voto incide nella media ponderata. Disattivando \"Fa media\" il voto diventa blu e non viene conteggiato."),
                        icon: "scalemass.fill"),
            ManualEntry(title: L("Grafico andamento"),
                        detail: L("Nella scheda materia, la card Andamento mostra la curva dei voti col colore della materia: la linea rosa tratteggiata è la sufficienza, i punti insufficienti sono rosa col valore sotto. Tocca un punto per il dettaglio (alone viola)."),
                        icon: "chart.xyaxis.line"),
            ManualEntry(title: L("Obiettivo media"),
                        detail: L("Imposta la media obiettivo: l'app calcola quale o quanti voti ti servono per raggiungerla."),
                        icon: "target"),
            ManualEntry(title: L("Colore della materia"),
                        detail: L("Dal cerchio colorato in alto a destra nella scheda materia personalizzi il colore: righe, grafico e sfondo si adattano."),
                        icon: "paintbrush.fill"),
            ManualEntry(title: L("Ultimi voti ed elenco materie"),
                        detail: L("Le bolle \"Ultimi voti\" scorrono in orizzontale; \"Vedi tutti ›\" oppure menu ••• → Materie apre tutte le materie con la rispettiva media."),
                        icon: "list.bullet.circle.fill"),
            ManualEntry(title: L("Soglia personalizzata"),
                        detail: L("Cambiando voto sufficiente o massimo nelle Impostazioni, i colori di tutti i voti (verde/arancio/rosso) si aggiornano immediatamente."),
                        icon: "slider.horizontal.3")
        ]),
        ManualSection(screen: L("Impostazioni"), icon: "gearshape.fill", tintHex: "#F472B6", entries: [
            ManualEntry(title: L("Aspetto"),
                        detail: L("Tema chiaro/scuro/automatico, dimensione del testo (fino a Enorme) e colori personalizzati per classi, docenti e materie."),
                        icon: "circle.lefthalf.filled"),
            ManualEntry(title: L("Orario"),
                        detail: L("Sorgente e contenuto dell'orario caricato, ora corrente o manuale, PDF originale, modifica dell'orario creato a mano e Dati orario (docenti, classi, fasce, lezioni e materie per classe con le corrispondenze docente ↔ materia)."),
                        icon: "calendar"),
            ManualEntry(title: L("Voti"),
                        detail: L("Scala dei voti (sufficienza e massimo) e periodi: quadrimestri oppure trimestre + pentamestre, con la fine del primo periodo (solo giorno e mese)."),
                        icon: "chart.bar.fill"),
            ManualEntry(title: L("Lingua"),
                        detail: L("In Impostazioni → Aspetto → Lingua scegli Italiano o English: l'app cambia lingua subito. Alla prima apertura la lingua dipende dal paese del tuo App Store: italiano in Italia, San Marino e Vaticano, inglese altrove."),
                        icon: "globe"),
            ManualEntry(title: L("Su iPad"),
                        detail: L("Su iPad la Settimana occupa tutto lo schermo, con materia e docente in ogni ora. Il Diario mostra le date su due colonne e, in verticale, i voti stanno su due colonne. In orizzontale l'Orario e i Voti si dividono in due colonne (controlli o riepilogo a sinistra, contenuto a destra). Su iPad le voci del diario si archiviano tenendo premuto."),
                        icon: "ipad.landscape"),
            ManualEntry(title: L("Sincronizzazione iCloud"),
                        detail: L("Con lo stesso Apple ID, voti, diario, orario e impostazioni di scuola (scala dei voti, periodi, colori) si aggiornano da soli su iPhone e iPad. In Impostazioni → Sincronizzazione iCloud vedi lo stato e puoi forzare un aggiornamento con \"Sincronizza ora\". Tema e dimensione del testo restano propri di ogni dispositivo."),
                        icon: "icloud.fill"),
            ManualEntry(title: L("Dati e backup"),
                        detail: L("Esporti orario, diario e voti in un unico file e li reimporti quando vuoi, anche su un altro dispositivo."),
                        icon: "externaldrive.fill"),
            ManualEntry(title: L("Zona di rischio"),
                        detail: L("Cambia o rimuovi l'orario, cancella tutto il diario o tutti i voti. Ogni azione chiede conferma e non è reversibile."),
                        icon: "exclamationmark.triangle.fill"),
            ManualEntry(title: L("Segnala un problema"),
                        detail: L("Apre l'app Mail con un messaggio già pronto da inviare allo sviluppatore."),
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
                AuroraTitle(title: L("Manuale"),
                            subtitle: L("Tutte le funzioni, sezione per sezione"))
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
        let tint = Color(hex: section.tintHex) ?? .gray
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
