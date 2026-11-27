import SwiftUI

private struct ProjectPreferencesKey:EnvironmentKey { static let defaultValue:ProjectPreferences? = nil }
extension EnvironmentValues {
    var projectPreferences:ProjectPreferences? {
        get { self[ProjectPreferencesKey.self] }
        set { self[ProjectPreferencesKey.self] = newValue }
    }
}
private struct ProjectPreferenceScope:ViewModifier {
    let preferences:ProjectPreferences?
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.system.rawValue
    private var appLocale:Locale { (AppLanguage(rawValue:language) ?? .system).locale }
    func body(content:Content) -> some View {
        content.environment(\.projectPreferences,preferences)
            .environment(\.locale,ProjectPreferenceResolution.locale(preferences,appDefault:appLocale))
    }
}
extension View {
    func projectPreferenceScope(_ preferences:ProjectPreferences?) -> some View { modifier(ProjectPreferenceScope(preferences:preferences)) }
}
