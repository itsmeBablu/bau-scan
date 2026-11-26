import SwiftUI

/// Entry point: navigation stack library on iPhone, sidebar window on
/// File menus on macOS (`MacUI/`).
@main
struct RoomScannerApp: App {
    init() {
        AppLaunchTrace.start()
        #if os(iOS)
        _ = PerformanceMetrics.shared
        #endif
    }
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.system.rawValue
    #if os(macOS)
    @NSApplicationDelegateAdaptor(StudioTerminationDelegate.self) private var termination
    @State private var store = RoomStore(location: RootView.initialLocation(), allowsCloud: !RootView.hasForcedRoot)
    @State private var updater = UpdaterController()
    #endif

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MacRootView()
                .onAppear { AppLaunchTrace.firstRootAppeared() }
                .dsAppTheme()
                .environment(\.locale,(AppLanguage(rawValue:language) ?? .system).locale)
                .environment(store)
                .environment(updater)
        }
        .commands { MacMenuCommands(updater: updater) }
        WindowGroup("Design Studio", for: UUID.self) { $designID in
            if let id = designID {
                MacStudioWindow(designID: id)
                    .dsAppTheme()
                    .environment(\.locale,(AppLanguage(rawValue:language) ?? .system).locale)
                    .environment(store)
                    .environment(updater)
            }
        }
        Settings {
            SettingsView()
                .dsAppTheme()
                .environment(\.locale,(AppLanguage(rawValue:language) ?? .system).locale)
                .environment(store)
                .environment(updater)
        }
        #else
        WindowGroup {
            RootView()
                .onAppear { AppLaunchTrace.firstRootAppeared() }
                .dsAppTheme()
        }
        #endif
    }
}
