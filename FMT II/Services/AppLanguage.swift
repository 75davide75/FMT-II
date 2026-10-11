import Foundation
import StoreKit

/// Lingue dell'app. L'italiano è la lingua sorgente (le chiavi del catalogo
/// sono i testi italiani), l'inglese è la traduzione.
enum AppLanguage: String, CaseIterable, Identifiable {
    case italian = "it"
    case english = "en"

    var id: String { rawValue }

    /// Nome nella lingua stessa (come nei selettori di lingua di iOS).
    var nativeName: String {
        switch self {
        case .italian: return "Italiano"
        case .english: return "English"
        }
    }

    private static let italianStorefronts: Set<String> = ["ITA", "SMR", "VAT"]
    private static let italianRegions: Set<String> = ["IT", "SM", "VA"]

    /// Locale per testi e date: italiano d'Italia; inglese con la regione del
    /// dispositivo (US se la regione è italiana o assente).
    func locale(region: String?) -> Locale {
        switch self {
        case .italian:
            return Locale(identifier: "it_IT")
        case .english:
            guard let region, !Self.italianRegions.contains(region.uppercased()) else {
                return Locale(identifier: "en_US")
            }
            return Locale(identifier: "en_\(region.uppercased())")
        }
    }

    /// Lingua iniziale: chi aggiorna dalla 2.1.1 resta in italiano; altrimenti
    /// conta il paese dell'App Store (Italia, San Marino, Vaticano → italiano),
    /// poi la regione del dispositivo; senza dati → inglese.
    static func initial(storefrontCountry: String?, region: String?, isExistingUser: Bool) -> AppLanguage {
        if isExistingUser { return .italian }
        if let storefrontCountry {
            return italianStorefronts.contains(storefrontCountry.uppercased()) ? .italian : .english
        }
        if let region {
            return italianRegions.contains(region.uppercased()) ? .italian : .english
        }
        return .english
    }

    /// Bundle `.lproj` della lingua, per le stringhe fuori da `Text`.
    var bundle: Bundle {
        Bundle.main.path(forResource: rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}

/// Lingua scelta per l'app (preferenza del dispositivo, non sincronizzata).
@MainActor
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    static let storageKey = "appLanguage"
    private static let manualKey = "appLanguageChosenManually"

    /// Lingua corrente, letta da `L()` anche fuori dal MainActor.
    nonisolated(unsafe) static var current: AppLanguage = .italian

    @Published private(set) var language: AppLanguage
    /// Primo avvio senza lingua salvata: il paese dell'App Store può ancora correggerla.
    private var needsStorefrontCheck = false

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.storageKey), let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            let existingUser = defaults.bool(forKey: "hasSeenTutorial")
            language = AppLanguage.initial(storefrontCountry: nil,
                                           region: Locale.current.region?.identifier,
                                           isExistingUser: existingUser)
            defaults.set(language.rawValue, forKey: Self.storageKey)
            needsStorefrontCheck = !existingUser
        }
        Self.current = language
        defaults.set([language.rawValue], forKey: "AppleLanguages")
    }

    var locale: Locale { language.locale(region: Locale.current.region?.identifier) }

    /// Scelta dalle Impostazioni: vince su ogni regola automatica.
    func choose(_ newLanguage: AppLanguage) {
        UserDefaults.standard.set(true, forKey: Self.manualKey)
        apply(newLanguage)
    }

    /// Primo avvio: il paese dell'account App Store decide la lingua (se
    /// l'utente non l'ha già scelta a mano).
    func refineFromStorefront() async {
        guard needsStorefrontCheck else { return }
        needsStorefrontCheck = false
        guard let country = await Storefront.current?.countryCode,
              !UserDefaults.standard.bool(forKey: Self.manualKey) else { return }
        let fromStore = AppLanguage.initial(storefrontCountry: country, region: nil, isExistingUser: false)
        if fromStore != language { apply(fromStore) }
    }

    private func apply(_ newLanguage: AppLanguage) {
        Self.current = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: Self.storageKey)
        // Anche i componenti di sistema seguono la lingua, dal prossimo avvio.
        UserDefaults.standard.set([newLanguage.rawValue], forKey: "AppleLanguages")
        language = newLanguage
    }
}

extension LanguageSettings {
    /// Locale della lingua corrente, utilizzabile fuori dal MainActor.
    nonisolated static var currentLocale: Locale {
        current.locale(region: Locale.current.region?.identifier)
    }
}

extension Date {
    /// Data/ora nella lingua dell'app (non in quella del dispositivo).
    func appFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(LanguageSettings.currentLocale))
    }
}

/// Cose che si contano nei riepiloghi dell'orario.
enum CountedNoun { case lessons, classes, teachers, subjects }

/// «1 classe» / «3 classi» nella lingua dell'app.
func counted(_ n: Int, _ noun: CountedNoun) -> String {
    switch noun {
    case .lessons:  return n == 1 ? L("1 lezione") : L("\(n) lezioni")
    case .classes:  return n == 1 ? L("1 classe")  : L("\(n) classi")
    case .teachers: return n == 1 ? L("1 docente") : L("\(n) docenti")
    case .subjects: return n == 1 ? L("1 materia") : L("\(n) materie")
    }
}

/// Testo tradotto nella lingua dell'app, per le stringhe fuori da `Text`
/// (etichette dei modelli, messaggi, notifiche).
func L(_ key: String.LocalizationValue) -> String {
    switch LanguageSettings.current {
    case .italian:
        // L'italiano è la lingua sorgente: nessun .lproj da consultare (una
        // tabella inesistente restituisce il testo sorgente, interpolato).
        return String(localized: key, table: "SorgenteItaliana", bundle: .main)
    case .english:
        return String(localized: key, bundle: AppLanguage.english.bundle)
    }
}
