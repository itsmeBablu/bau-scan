import Foundation

/// Read-only resolution. Never writes UserDefaults or changes library/session state.
enum ProjectPreferenceResolution {
    static func locale(_ preferences:ProjectPreferences?,appDefault:Locale) -> Locale {
        guard let raw = preferences?.language,let language = AppLanguage(rawValue:raw) else { return appDefault }
        return language.locale
    }
    static func unit(_ preferences:ProjectPreferences?,appDefault:MeasurementUnit) -> MeasurementUnit {
        preferences?.units.flatMap(MeasurementUnit.init(rawValue:)) ?? appDefault
    }
    static func photos(_ preferences:ProjectPreferences?,appDefault:Bool) -> Bool { preferences?.photos ?? appDefault }
}
