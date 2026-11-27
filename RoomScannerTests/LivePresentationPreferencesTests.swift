#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import RoomScanner

@MainActor final class LivePresentationPreferencesTests:XCTestCase {
    private final class Reading {
        var language = ""
        var scheme:ColorScheme?
        var identity:UUID?
    }
    private struct Probe:View {
        let reading:Reading
        @Environment(\.locale) private var locale
        @Environment(\.colorScheme) private var scheme
        @State private var identity = UUID()
        var body:some View {
            Text("Settings")
                .onAppear { record() }
                .onChange(of:locale.identifier) { _,_ in record() }
                .onChange(of:scheme) { _,_ in record() }
        }
        private func record() {
            reading.language = locale.language.languageCode?.identifier ?? ""
            reading.scheme = scheme; reading.identity = identity
        }
    }
    private func waitFor(_ condition:() -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTFail("The already presented view did not receive the preference change")
    }
    func testOpenScopeUpdatesWithoutReplacingViewAndPreservesProjectLanguage() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("A hosted iOS scene is required")
        }
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.object(forKey:AppLanguage.preferenceKey)
        let previousAppearance = defaults.object(forKey:"ui.appearance")
        defer {
            if let previousLanguage { defaults.set(previousLanguage,forKey:AppLanguage.preferenceKey) }
            else { defaults.removeObject(forKey:AppLanguage.preferenceKey) }
            if let previousAppearance { defaults.set(previousAppearance,forKey:"ui.appearance") }
            else { defaults.removeObject(forKey:"ui.appearance") }
        }
        for projectLanguage in [nil,"de"] as [String?] {
            defaults.set("en",forKey:AppLanguage.preferenceKey); defaults.set("dark",forKey:"ui.appearance")
            let reading = Reading(),window = UIWindow(windowScene:scene)
            let host = UIHostingController(rootView:Probe(reading:reading)
                .projectPreferenceScope(projectLanguage.map { ProjectPreferences(language:$0) }).dsAppTheme())
            window.frame = scene.coordinateSpace.bounds
            window.rootViewController = host; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await waitFor { reading.language == (projectLanguage ?? "en") && reading.scheme == .dark }
            let identity = try XCTUnwrap(reading.identity)
            defaults.set("light",forKey:"ui.appearance"); defaults.set("de",forKey:AppLanguage.preferenceKey)
            try await waitFor { reading.scheme == .light && reading.language == "de" }
            defaults.set("en",forKey:AppLanguage.preferenceKey)
            try await waitFor { reading.language == (projectLanguage ?? "en") }
            XCTAssertEqual(reading.identity,identity,"A preference change must not discard navigation or unsaved view state")
        }
    }
}
#endif
