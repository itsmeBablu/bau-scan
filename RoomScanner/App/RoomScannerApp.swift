import SwiftUI

/// Entry point: navigation stack library on iPhone, sidebar window on
/// File menus on macOS (`MacUI/`).
@main
struct RoomScannerApp: App {
    #if os(macOS)
    @State private var store = RoomStore(location: RootView.initialLocation(), allowsCloud: !RootView.hasForcedRoot)
    @State private var updater = UpdaterController()
    #endif

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MacRootView()
                .environment(store)
                .environment(updater)
        }
        .commands { MacMenuCommands(updater: updater) }
        Settings {
            SettingsView()
                .environment(store)
                .environment(updater)
        }
        #else
        WindowGroup {
            RootView()
        }
        #endif
    }
}
