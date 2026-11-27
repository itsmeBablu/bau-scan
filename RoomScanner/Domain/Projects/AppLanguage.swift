import Foundation

enum AppLanguage: String, CaseIterable {
    case system, english = "en", german = "de"
    static let preferenceKey = "renovation.language"
    static var selected: Self { Self(rawValue:UserDefaults.standard.string(forKey:preferenceKey) ?? "system") ?? .system }
    var locale: Locale { self == .system ? .current : Locale(identifier:self == .german ? "de_DE" : "en_GB") }
    static var locale: Locale { selected.locale }
    static func text(_ key: String, locale: Locale = AppLanguage.locale) -> String {
        let language = locale.language.languageCode?.identifier ?? "en"
        let bundle = Bundle.main.path(forResource:language,ofType:"lproj").flatMap(Bundle.init(path:)) ?? .main
        return String(localized:String.LocalizationValue(key),bundle:bundle,locale:locale)
    }
    static func format(_ key: String, _ values: [String], locale: Locale = AppLanguage.locale) -> String {
        String(format:text(key,locale:locale),locale:locale,arguments:values.map { $0 as CVarArg })
    }
}
