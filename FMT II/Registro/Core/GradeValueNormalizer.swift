import Foundation

/// Converte la stringa del voto così come la scrive il registro in un numero
/// usato SOLO per le medie. La stringa originale si conserva altrove per la
/// visualizzazione. `nil` = non numerico (escluso dalle medie): non si
/// inventa mai un valore.
///
/// Regole:
/// - se il registro fornisce già un numero, vince quello, ma solo se rientra
///   in `0...maxGrade`; altrimenti `nil` (non si ricade sulla stringa);
/// - `7`, `7.5`, `7,25` (virgola decimale);
/// - `+` / `-` valgono ±0,25 ciascuno (`7+` = 7,25, `7--` = 6,5);
/// - `7½`, `7 ½`, `7 1/2` = 7,5;
/// - coppie di voti interi adiacenti `6/7`, `6-7` = media (6,5); rapporti
///   come `3/10` o `6/8` NON sono coppie e restano non numerici;
/// - giudizi: vedi `judgments`;
/// - tutto il resto (vuoto, `N.C.`, `ass.`, testo libero) e ogni valore fuori
///   da `0...maxGrade` (anche dopo i modificatori: `10+`) = `nil`.
enum GradeValueNormalizer {
    /// Tabella unica dei giudizi -> valore numerico (scala in decimi).
    /// Le chiavi sono già normalizzate: minuscole, senza accenti né punti,
    /// spazi singoli. "non classificato" non compare di proposito: non è
    /// un voto e resta `nil`.
    static let judgments: [String: Double] = [
        "ottimo": 10,
        "distinto": 9,
        "buono": 8,
        "discreto": 7,
        "sufficiente": 6,
        "insufficiente": 5,
        "gravemente insufficiente": 4
    ]

    /// Valore di ogni segno `+` / `-` accanto al voto.
    private static let modifierStep = 0.25

    static func normalize(_ raw: String, providedNumeric: Double?, maxGrade: Double) -> Double? {
        if let provided = providedNumeric {
            return inScale(provided, maxGrade)
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let value = parseNumeric(text) { return inScale(value, maxGrade) }
        if let value = judgments[normalizedWord(text)] { return inScale(value, maxGrade) }
        return nil
    }

    private static func inScale(_ value: Double, _ maxGrade: Double) -> Double? {
        guard value.isFinite, value >= 0, value <= maxGrade else { return nil }
        return value
    }

    /// Minuscolo, senza accenti, senza punti, spazi collassati.
    private static func normalizedWord(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
        let noDots = folded.replacingOccurrences(of: ".", with: "")
        return noDots.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func parseNumeric(_ text: String) -> Double? {
        // "7½" / "7 ½" -> "7 1/2"; virgola decimale -> punto.
        var s = text
        s = s.replacingOccurrences(of: #"(\d)\s*½"#, with: "$1 1/2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d),(\d)"#, with: "$1.$2", options: .regularExpression)

        // Numero con modificatori: 7, 7.5, 7+, 7--
        if let m = s.wholeMatch(of: /(\d+(?:\.\d+)?)\s*(\++|-+)?/) {
            guard let base = Double(m.1) else { return nil }
            guard let mods = m.2 else { return base }
            let sign: Double = mods.first == "+" ? 1 : -1
            return base + sign * modifierStep * Double(mods.count)
        }
        // Voto con frazione: "7 1/2"
        if let m = s.wholeMatch(of: /(\d+)\s+(\d+)\/(\d+)/) {
            guard let whole = Double(m.1), let num = Double(m.2), let den = Double(m.3),
                  den > 0, num < den else { return nil }
            return whole + num / den
        }
        // Coppia di voti interi adiacenti: "6/7", "6-7"
        if let m = s.wholeMatch(of: /(\d+)\s*[\/-]\s*(\d+)/) {
            guard let a = Int(m.1), let b = Int(m.2), b == a + 1 else { return nil }
            return (Double(a) + Double(b)) / 2
        }
        return nil
    }
}
