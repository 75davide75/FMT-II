import SwiftUI

/// Badge discreto dei voti importati dal registro.
struct RegistroOriginBadge: View {
    var body: some View {
        Image(systemName: "building.columns.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel(L("Dal registro"))
    }
}

/// "Rimosso dal registro" con le due scelte: elimina (percorso di cancellazione
/// normale, che ricorda di ignorare il voto nelle sync future) o tieni.
struct RemovedGradeBar: View {
    let label: String
    var onKeep: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
            HStack(spacing: 16) {
                if let onKeep {
                    Button(L("Tieni"), action: onKeep)
                        .accessibilityIdentifier("grade.removed.keep")
                }
                if let onDelete {
                    // Elimina è irreversibile (il voto non viene più reimportato): si conferma.
                    Button(L("Elimina"), role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("grade.removed.delete")
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
            .padding(.vertical, 4)
        }
        .confirmationDialog(L("Eliminare questo voto?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Elimina"), role: .destructive) { onDelete?() }
            Button(L("Annulla"), role: .cancel) {}
        } message: {
            Text("Il voto verrà eliminato e non sarà più importato dal registro.")
        }
    }
}

extension View {
    /// Valore del voto nel badge a larghezza fissa: i giudizi lunghi del registro
    /// ("sufficiente") si riducono a vista; il testo completo resta nell'etichetta
    /// di accessibilità e nel dettaglio.
    func gradeValueFit(maxWidth: CGFloat? = nil) -> some View {
        self.lineLimit(1).minimumScaleFactor(0.4).frame(maxWidth: maxWidth, alignment: .trailing)
    }
}
