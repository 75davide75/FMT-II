import SwiftUI

// MARK: - Manuale

private struct ManualEntry: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

private struct ManualSection: Identifiable {
    let id = UUID()
    let screen: String
    let icon: String
    let entries: [ManualEntry]
}

struct ManualView: View {
    @State private var query = ""

    private let sections: [ManualSection] = [
        ManualSection(screen: "Per iniziare", icon: "hand.wave", entries: [
            ManualEntry(title: "Cambiare sezione",
                        detail: "In alto c'è la barra Orario · Diario · Voti. Tocca un nome o scorri orizzontalmente per passare da una sezione all'altra."),
            ManualEntry(title: "Importare l'orario",
                        detail: "Alla prima apertura importi il PDF dell'orario della scuola. Senza orario restano comunque attive le sezioni Diario e Voti."),
            ManualEntry(title: "Creare l'orario a mano",
                        detail: "Se non hai un PDF, scegli \"Crea il mio orario\": imposti la classe, le ore (inizio + durata) e i giorni, poi tocchi le celle della griglia settimanale per inserire le materie. Il docente è facoltativo e viene auto-completato — una volta abbinato a una materia, l'app lo ricompila da solo. Puoi creare l'orario anche per più classi."),
            ManualEntry(title: "Tema e personalizzazione",
                        detail: "Dalle Impostazioni scegli tema chiaro/scuro/automatico; nei Voti ogni materia ha un colore personalizzabile.")
        ]),
        ManualSection(screen: "Orario", icon: "calendar", entries: [
            ManualEntry(title: "Cambiare vista",
                        detail: "In alto scegli Adesso, Giorno o Settimana per vedere la lezione corrente, l'intera giornata o tutta la settimana."),
            ManualEntry(title: "Classe o Docente",
                        detail: "Con il selettore Classe/Docente cerchi per classe oppure per cognome del docente."),
            ManualEntry(title: "Cercare un docente",
                        detail: "Digita il cognome: compare un elenco scorrevole. Premi Invio per scegliere il primo risultato. La X arancione cancella la ricerca."),
            ManualEntry(title: "Ora manuale",
                        detail: "Dalle Impostazioni puoi disattivare \"Usa ora corrente\" e fissare un giorno e un'ora specifici da consultare."),
            ManualEntry(title: "Vedere la controparte",
                        detail: "Tocca una lezione per passare alla sua controparte: dalla classe vedi dov'è quel docente, e viceversa."),
            ManualEntry(title: "Creare una nota da una lezione",
                        detail: "Tieni premuto su una lezione (l'elemento blu) e scegli \"Crea nota\": la voce di diario nasce già con giorno, ora e docente/classe."),
            ManualEntry(title: "Condividere l'orario",
                        detail: "Dall'icona di condivisione esporti l'orario in un file da inviare o salvare.")
        ]),
        ManualSection(screen: "Diario", icon: "book.closed", entries: [
            ManualEntry(title: "Nuova voce",
                        detail: "Tocca la matita in alto a destra. Puoi formattare il testo: Titolo, Intestazione, Sottotitolo, Corpo e grassetto, corsivo, sottolineato, barrato."),
            ManualEntry(title: "Dettagli",
                        detail: "Tocca \"Dettagli\" (in fondo all'editor) per aprire un pannello con tipo, giorno, ora (24h), materia, docente, classe e promemoria — così il testo resta sempre visibile mentre scrivi."),
            ManualEntry(title: "Promemoria multipli",
                        detail: "Puoi aggiungere più promemoria a una voce, ciascuno con giorno e ora scelti (ricorrenti ogni settimana): utile per un avviso il giorno prima e uno il giorno stesso."),
            ManualEntry(title: "Tipi speciali (compiti, verifiche, interrogazioni)",
                        detail: "Assegna un tipo alla voce: Compito (giallo), Verifica (rosso), Interrogazione (arancione). La voce cambia leggermente colore e puoi filtrarla per tipo, anche insieme agli altri tag."),
            ManualEntry(title: "Cercare nel testo",
                        detail: "Menu ••• → Cerca: trova qualsiasi parola contenuta nel testo delle note, come un \"trova\" di un documento."),
            ManualEntry(title: "Filtrare per tag",
                        detail: "Menu ••• → Filtra per tag: mostri solo le voci con un certo tag (materia, docente o classe)."),
            ManualEntry(title: "Selezione multipla",
                        detail: "Menu ••• → Seleziona. Tocca le voci (ovunque sulla riga), usa \"Seleziona tutto\", poi elimina o archivia in blocco."),
            ManualEntry(title: "Azioni rapide",
                        detail: "Tieni premuto su una voce per Modifica, Archivia o Elimina. Puoi anche scorrerla verso sinistra."),
            ManualEntry(title: "Archivio",
                        detail: "Menu ••• → Mostra l'archivio per vedere le voci archiviate e ripristinarle.")
        ]),
        ManualSection(screen: "Voti", icon: "chart.line.uptrend.xyaxis", entries: [
            ManualEntry(title: "Aggiungere un voto",
                        detail: "Col + inserisci materia (con suggerimenti: Invio sceglie il primo), docente, voto, tipo, data, peso e se fa media."),
            ManualEntry(title: "Peso e media",
                        detail: "Il peso (0–100%) determina quanto il voto incide nella media. Disattivando \"Fa media\" il voto diventa blu e non viene conteggiato."),
            ManualEntry(title: "Grafico andamento",
                        detail: "Nella materia tocca un punto del grafico per vedere voto e data. Le frecce ↑ ↓ indicano se ogni voto ha alzato o abbassato la media."),
            ManualEntry(title: "Obiettivo media",
                        detail: "Imposta la media obiettivo: l'app calcola quale o quanti voti ti servono. La frase motivazionale cambia a ogni nuovo obiettivo."),
            ManualEntry(title: "Colore della materia",
                        detail: "Nella scheda materia, dal selettore colore in alto a destra, personalizzi il colore: anche lo sfondo e il grafico si adattano."),
            ManualEntry(title: "Elenco materie",
                        detail: "L'icona elenco apre tutte le materie con la rispettiva media."),
            ManualEntry(title: "Azioni rapide",
                        detail: "Tieni premuto su un voto per Modifica, Apri materia o Elimina.")
        ]),
        ManualSection(screen: "Impostazioni", icon: "gearshape", entries: [
            ManualEntry(title: "Aspetto",
                        detail: "Scegli tema chiaro, scuro o automatico."),
            ManualEntry(title: "Dimensione testo",
                        detail: "In Accessibilità puoi ingrandire tutti i testi dell'app (Automatica, Grande, Molto grande, Enorme), impostazioni e menu compresi."),
            ManualEntry(title: "Scala dei voti",
                        detail: "In Valutazione imposti il voto sufficiente (non per forza 6) e il voto massimo (di default 10): i colori dei voti, la sufficienza sul grafico e gli obiettivi si adattano di conseguenza."),
            ManualEntry(title: "Periodi scolastici",
                        detail: "Imposta quadrimestri oppure trimestre + pentamestre e la fine del primo periodo (solo giorno e mese, l'anno è automatico). Passando a trimestre la fine è impostata al 23 dicembre."),
            ManualEntry(title: "Backup",
                        detail: "Esporti diario, voti e orario in un unico file e li reimporti quando vuoi (anche su un altro dispositivo)."),
            ManualEntry(title: "Crea o modifica l'orario",
                        detail: "Senza orario trovi \"Crea il mio orario\"; se l'hai creato a mano, \"Modifica orario\" riapre la griglia. Puoi sempre importare un PDF: se hai un orario tuo ti avvisiamo prima di sostituirlo, e lo sostituiamo solo se il PDF viene letto correttamente."),
            ManualEntry(title: "Modifica database",
                        detail: "Correggi o aggiungi docenti e classi, regola le fasce orarie (inizio + durata) e modifica le singole lezioni. C'è un avviso prima di entrare."),
            ManualEntry(title: "Zona di rischio",
                        detail: "Cambia o rimuovi l'orario, cancella tutto il diario o tutti i voti. Ogni azione chiede conferma."),
            ManualEntry(title: "Segnala un problema",
                        detail: "Apre l'app Mail con un messaggio pronto da inviare allo sviluppatore.")
        ])
    ]

    private var filteredSections: [ManualSection] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sections }
        return sections.compactMap { section in
            let entries = section.entries.filter {
                $0.title.lowercased().contains(q) || $0.detail.lowercased().contains(q)
            }
            return entries.isEmpty ? nil : ManualSection(screen: section.screen, icon: section.icon, entries: entries)
        }
    }

    var body: some View {
        List {
            if filteredSections.isEmpty {
                ContentUnavailableView("Nessun risultato", systemImage: "magnifyingglass",
                                       description: Text("Nessuna funzione corrisponde a «\(query)»."))
            }
            ForEach(filteredSections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.callout.weight(.semibold))
                            Text(entry.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Label(section.screen, systemImage: section.icon)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .navigationTitle("Manuale")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Cerca una funzione")
    }
}
