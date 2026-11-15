# App Store Connect — checklist di compilazione

Dati pronti da inserire creando l'app su App Store Connect. Bundle ID: **com.davide.fmtII** · versione **2.1.1** (build 1) · categoria **Education**.

## Informazioni generali
- **Nome:** FindMyTeacher — **Sottotitolo:** Orario, diario e voti
- **Categoria primaria:** Istruzione (Education) · secondaria: Produttività (facoltativa)
- **Lingua principale:** Italiano · aggiungere Inglese come lingua secondaria (testi in `listing-en.md`)
- **Prezzo:** Gratis (consigliato) — impostare fascia di prezzo e territori (tutti)
- Testi lunghi in `listing-it.md` / `listing-en.md`.

## Privacy dell'app ("nutrition label")
Rispondere al questionario **App Privacy** così:
- **"Raccogli dati da questa app?" → No.**
  L'app non raccoglie alcun dato (nessuna rete, nessun analytics, nessun SDK di terze parti). Risultato mostrato: **"Dati non raccolti" (Data Not Collected)**.
- **URL della Privacy Policy (obbligatorio):** https://75davide75.github.io/FMT_support_marketing/privacy/
- Il file `PrivacyInfo.xcprivacy` è già incluso nel bundle e coerente (dichiara solo l'uso di UserDefaults, motivo CA92.1; nessun tracciamento).

## Export compliance (crittografia)
- Già risolto nel progetto: `ITSAppUsesNonExemptEncryption = NO` è nell'Info.plist generato.
- Alla domanda su App Store Connect rispondere: **"No, l'app non usa crittografia"** (o "solo crittografia esente"). Non verrà chiesto altro.

## Fascia d'età (Age Rating)
- Nessun contenuto sensibile → tutte le domande "Nessuno/No" → risultato atteso **4+**.

## Screenshot da caricare
Cartelle già pronte nel progetto (`AppStore/screenshots/`):
- **iPhone 6.9"** (`iphone-6.9/`, 1320×2868): 01-orario-settimana, 02-orario-giorno, 03-diario, 04-voti
- **iPad 13"** (`ipad-13/`, 2064×2752): stessi quattro
Questi due formati coprono, per scala, gli altri dispositivi.

## URL scheda
- **Assistenza (obbligatorio):** https://75davide75.github.io/FMT_support_marketing/support/
- **Marketing (facoltativo):** https://75davide75.github.io/FMT_support_marketing/
- **Privacy Policy:** https://75davide75.github.io/FMT_support_marketing/privacy/

## Caricamento build
1. In Xcode: *Product ▸ Archive* (schema "FMT II", configurazione Release).
2. *Distribute App ▸ App Store Connect ▸ Upload* (la firma automatica gestisce certificato e provisioning).
3. Selezionare la build 2.1.1 (1) nella versione, completare i campi sopra e inviare alla revisione.

> Nota: registrare l'App ID **com.davide.fmtII** sul Developer Portal (Xcode può farlo in fase di Distribute) e verificare che l'iscrizione all'Apple Developer Program a pagamento sia attiva.
