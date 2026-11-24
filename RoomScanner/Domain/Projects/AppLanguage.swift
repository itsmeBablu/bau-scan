import Foundation

enum AppLanguage: String, CaseIterable {
    case system, english = "en", german = "de"
    static let preferenceKey = "renovation.language"
    static var selected: Self { Self(rawValue:UserDefaults.standard.string(forKey:preferenceKey) ?? "system") ?? .system }
    var locale: Locale { self == .system ? .current : Locale(identifier:self == .german ? "de_DE" : "en_GB") }
    static var locale: Locale { selected.locale }
    static func text(_ key: String, locale: Locale = AppLanguage.locale) -> String {
        String(localized:String.LocalizationValue(key),locale:locale)
    }
}
