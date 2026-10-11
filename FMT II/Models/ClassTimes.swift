import Foundation

// Ora d'inizio per classe (v2.2): la durata e il numero di ore restano quelli
// globali di `periods`; una classe può solo traslare l'inizio della giornata.
extension ScheduleData {
    var sortedPeriods: [Period] { periods.sorted { $0.number < $1.number } }

    /// Inizio personalizzato della 1ª ora per la classe, se il toggle è attivo.
    func customStart(forClass className: String) -> String? {
        guard perClassStartTimes, let t = classStartTimes[className], !t.isEmpty else { return nil }
        return t
    }

    /// Fasce della classe: quelle globali traslate al suo inizio.
    func periods(forClass className: String) -> [Period] {
        let base = sortedPeriods
        guard let custom = customStart(forClass: className), let first = base.first else { return base }
        let delta = minutesFromMidnight(custom) - minutesFromMidnight(first.startTime)
        guard delta != 0 else { return base }
        return base.map {
            Period(number: $0.number,
                   startTime: addMinutes($0.startTime, delta),
                   endTime: addMinutes($0.endTime, delta))
        }
    }

    /// Righe da mostrare: le fasce della classe (vista classe) oppure, con
    /// `nil` (vista docente), l'unione ordinata degli inizi di tutte le classi.
    func displayPeriods(forClass className: String?) -> [Period] {
        if let className { return periods(forClass: className) }
        guard perClassStartTimes, classes.contains(where: { customStart(forClass: $0) != nil }) else {
            return sortedPeriods
        }
        var seen = Set<String>()
        let union = classes.flatMap { periods(forClass: $0) }
            .sorted { minutesFromMidnight($0.startTime) < minutesFromMidnight($1.startTime) }
            .filter { seen.insert($0.startTime).inserted }
        return union.enumerated().map {
            Period(number: $0.offset + 1, startTime: $0.element.startTime, endTime: $0.element.endTime)
        }
    }

    /// Orari selezionabili: gli inizi delle fasce + la fine dell'ultima.
    func timeSlots(forClass className: String?) -> [String] {
        let ps = displayPeriods(forClass: className)
        guard let lastEnd = ps.map(\.endTime).max(by: { minutesFromMidnight($0) < minutesFromMidnight($1) }) else {
            return []
        }
        var out = ps.map(\.startTime)
        if !out.contains(lastEnd) { out.append(lastEnd) }
        return out
    }

    /// Una classe rinominata si porta dietro la sua ora d'inizio.
    mutating func renameClassStartTime(from old: String, to new: String) {
        guard let t = classStartTimes.removeValue(forKey: old) else { return }
        classStartTimes[new] = t
    }

    /// Rinomina una classe ovunque: elenco, lezioni e ora d'inizio.
    mutating func renameClass(from old: String, to new: String) {
        guard !new.isEmpty, new != old else { return }
        if let idx = classes.firstIndex(of: old) { classes[idx] = new }
        else if !classes.contains(new) { classes.append(new) }
        for i in lessons.indices where lessons[i].className == old {
            lessons[i].className = new
        }
        renameClassStartTime(from: old, to: new)
    }

    /// Imposta l'inizio di una classe; uguale all'inizio predefinito = nessuna
    /// personalizzazione (la classe seguirà il predefinito se cambia).
    mutating func setClassStart(_ time: String, forClass className: String) {
        if time == sortedPeriods.first?.startTime {
            classStartTimes.removeValue(forKey: className)
        } else {
            classStartTimes[className] = time
        }
    }
}
